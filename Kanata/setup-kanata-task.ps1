<#
.SYNOPSIS
    Register / update the "Kanata" auto-start task in Windows Task Scheduler.

.DESCRIPTION
    Follows the "Best practice to launch Kanata with Windows" guide:
      https://rpnfan.github.io/keyboard-heaven/how-to/kanata-autostart-windows/

    What gets created:
      Trigger   : At log on of the current user, delayed by -DelaySeconds
      Action    : <ExePath> -c "<ConfigPath>"   (working dir = folder of ExePath)
      Principal : current user, interactive logon, RunLevel = Highest
      Settings  : allowed to start / keep running on battery, no execution time
                  limit, never starts a second instance while one is running

    Why RunLevel = Highest:
      Kanata installs a low-level keyboard hook (LLHOOK). Without administrator
      rights the remapping silently does not work inside elevated windows
      (Task Manager, admin terminals, some games/launchers).

    Why the logon delay:
      Starting before the shell and the input stack are ready can make Kanata
      miss remaps or fail to show its tray icon. The guide uses ~15s on ARM64
      and ~45s on x86/x64; lower it only after testing.

    Registering a task with RunLevel = Highest needs administrator rights, so
    the script re-launches itself elevated (one UAC prompt).

.PARAMETER ExePath
    Full path of the kanata binary to run. Use the gui build so that Kanata
    lives in the system tray instead of a console window.

.PARAMETER ConfigPath
    Full path of the .kbd configuration file.

.PARAMETER TaskName
    Name of the scheduled task (default: Kanata).

.PARAMETER DelaySeconds
    Delay after logon before Kanata starts (default: 45).

.PARAMETER StartNow
    Also start the task immediately after registering it.

.EXAMPLE
    pwsh -File .\setup-kanata-task.ps1 -StartNow

.EXAMPLE
    pwsh -File .\setup-kanata-task.ps1 -DelaySeconds 20

.EXAMPLE
    # inspect / remove afterwards
    Get-ScheduledTask -TaskName Kanata | Get-ScheduledTaskInfo
    Unregister-ScheduledTask -TaskName Kanata -Confirm:$false
#>
[CmdletBinding()]
param(
    [string] $ExePath      = 'D:\Daily\Kanata\kanata_windows_gui_winIOv2_cmd_allowed_x64.exe',
    [string] $ConfigPath   = 'D:\Sync\config-hub\Kanata\kanata.kbd',
    [string] $TaskName     = 'Kanata',
    [int]    $DelaySeconds = 45,
    [switch] $StartNow,
    # internal: used by the elevated re-launch to mirror output to a log file
    [string] $LogPath      = ''
)

$ErrorActionPreference = 'Stop'

function Write-Both {
    param([string] $Message)
    Write-Host $Message
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $Message -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# 0. Make sure we are elevated; if not, re-launch this script via UAC
# ---------------------------------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin   = ([Security.Principal.WindowsPrincipal] $identity).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $shellExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $shellExe) { $shellExe = (Get-Command powershell).Source }

    $tempLog = Join-Path $env:TEMP 'kanata-task-setup.log'
    Remove-Item -LiteralPath $tempLog -ErrorAction SilentlyContinue

    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-ExePath', "`"$ExePath`"",
        '-ConfigPath', "`"$ConfigPath`"",
        '-TaskName', "`"$TaskName`"",
        '-DelaySeconds', $DelaySeconds,
        '-LogPath', "`"$tempLog`""
    )
    if ($StartNow) { $argList += '-StartNow' }

    Write-Host 'Requesting administrator rights (UAC prompt) ...'
    try {
        Start-Process -FilePath $shellExe -Verb RunAs -ArgumentList $argList -Wait
    }
    catch {
        Write-Host "Elevation was cancelled or failed: $($_.Exception.Message)"
        Write-Host 'Nothing was changed. Re-run this script and accept the UAC prompt.'
        exit 1
    }

    if (Test-Path -LiteralPath $tempLog) {
        Write-Host ''
        Write-Host '--- output of the elevated run ---'
        Get-Content -LiteralPath $tempLog
    }
    exit 0
}

$script:LogPath = $LogPath
if ($script:LogPath) { Set-Content -LiteralPath $script:LogPath -Value '' -Encoding UTF8 }

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
Write-Both "Running elevated as $($identity.Name)"

if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "kanata executable not found: $ExePath"
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "kanata config not found: $ConfigPath"
}

$exeDir = Split-Path -Parent $ExePath
$user   = "$env:USERDOMAIN\$env:USERNAME"

Write-Both "Task name    : $TaskName"
Write-Both "Executable   : $ExePath"
Write-Both "Configuration: $ConfigPath"
Write-Both "Working dir  : $exeDir"
Write-Both "Run as       : $user (interactive, highest privileges)"
Write-Both "Logon delay  : $DelaySeconds s"

# ---------------------------------------------------------------------------
# 2. Build trigger / action / principal / settings
# ---------------------------------------------------------------------------
$action = New-ScheduledTaskAction `
            -Execute $ExePath `
            -Argument ('-c "{0}"' -f $ConfigPath) `
            -WorkingDirectory $exeDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT{0}S' -f $DelaySeconds

$principal = New-ScheduledTaskPrincipal `
                -UserId $user `
                -LogonType Interactive `
                -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -MultipleInstances IgnoreNew

# ---------------------------------------------------------------------------
# 3. Register (replacing any previous task of the same name)
# ---------------------------------------------------------------------------
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Both "Removing existing task '$TaskName' ..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Deleting a task does NOT stop the process it started. Without this cleanup a
# surviving instance keeps its keyboard hook while a new one is started, i.e.
# two LLHOOKs fighting over every keystroke.
$stale = Get-Process -Name 'kanata*' -ErrorAction SilentlyContinue
if ($stale) {
    Write-Both ("Stopping {0} already-running kanata process(es): {1}" -f `
                $stale.Count, (($stale | Select-Object -ExpandProperty Id) -join ', '))
    $stale | Stop-Process -Force
    Start-Sleep -Seconds 1
}

Register-ScheduledTask `
    -TaskName    $TaskName `
    -Action      $action `
    -Trigger     $trigger `
    -Principal   $principal `
    -Settings    $settings `
    -Description 'Kanata keyboard remapper - starts at logon, elevated, tray icon build.' | Out-Null

Write-Both "Task '$TaskName' registered."

$info = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
Write-Both ("Next run time: {0}" -f $info.NextRunTime)

# ---------------------------------------------------------------------------
# 4. Optionally start it right away
# ---------------------------------------------------------------------------
if ($StartNow) {
    Write-Both 'Starting the task now ...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    Get-Process -Name 'kanata*' -ErrorAction SilentlyContinue |
        Select-Object Id, ProcessName, StartTime |
        Format-Table -AutoSize |
        Out-String |
        ForEach-Object { Write-Both $_ }
}

Write-Both 'Done.'

-- System
vim.opt.clipboard = 'unnamedplus'

-- Searching
vim.opt.incsearch = true
vim.opt.smartcase = true
vim.opt.ignorecase = true

-- Tab
vim.opt.tabstop = 2                 -- number of visual spaces per TAB
vim.opt.softtabstop = 2             -- number of spacesin tab when editing
vim.opt.shiftwidth = 2              -- insert 4 spaces on a tab
vim.opt.expandtab = true            -- tabs are spaces, mainly because of python

-- UI
vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.cursorline = true


-- Keymap
local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- region Keybinding
keymap("n", "n", "nzz", opts) 
keymap("n", "N", "Nzz", opts)
keymap("n", "<leader>p", "viwpgy", opts)
keymap("n", "cp", "yyp", opts)

keymap("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
keymap("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })

keymap("v", "p", "pgvy", opts) -- 粘贴后保持选择内容
keymap("v", "y", "ygv<Esc>", opts) -- 复制后，光标保持在当前位置
keymap("v", "<", "<gv", opts) -- 缩进后保持选择
keymap("v", ">", ">gv", opts) -- 缩进后保持选择

keymap({'n','x'}, 'gu', 'viwgu', { desc = 'Lowercase Word' }) -- 小写当前单词
keymap({'n','x'}, 'gU', 'viwgU', { desc = 'Uppercase Word' }) -- 大写当前单词
-- endregion

-- region Leader
vim.g.mapleader = " "
vim.g.maplocalleader = " "
keymap("n", "<Space>", "", opts)
keymap('n', '<Leader>v', '<C-v>', { desc = 'Visual Block Mode' })
-- endregion


if vim.g.vscode then
local vscode = require('vscode')
keymap({ "n", "x" }, "<leader>i", function()
  vscode.action("editor.action.quickFix")
end)

vim.keymap.set({ "n", "x", "i" }, "<C-d>", function()
  vscode.action("editor.action.addSelectionToNextFindMatch")
end)

keymap("n", "<leader>s", function() -- save and format
  vscode.action("editor.action.formatDocument")
  vscode.action("workbench.action.files.save")
end, opts)

keymap("n", "<leader>w", function() -- save without formatting
  vscode.action("workbench.action.files.saveWithoutFormatting")
end, opts)

keymap("n", "<leader>b", function() -- toggle boolean
  vscode.action("extension.toggleBool")
end, opts)
end



vim.opt.foldmethod = "expr"
vim.opt.foldexpr = ""
vim.opt.foldenable = true
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99

keymap({'n', 'o'}, 'H', '^', { noremap = true, silent = true })
keymap({'n', 'o'}, 'L', 'g_', { noremap = true, silent = true })

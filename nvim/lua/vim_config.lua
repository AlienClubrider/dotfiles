vim.g.mapleader = " "

vim.opt.expandtab = true
vim.opt.shiftwidth = 2

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.clipboard = "unnamedplus"

vim.opt.scrolloff = 16

vim.opt.undofile = true

-- Vim doesn't watch files for external changes by default; poll on these
-- events so buffers refresh when something else edits the file on disk.
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  command = "if mode() != 'c' | checktime | endif",
})

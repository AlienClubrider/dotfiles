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

-- Vim doesn't watch files for external changes by default. FocusGained/BufEnter
-- only fire on focus or buffer switches, and CursorHold only fires once until
-- the next keypress rearms it - none of those catch "sitting idle in the same
-- buffer while something else edits the file on disk". Poll on a real timer
-- instead so changes show up without needing to leave and re-enter the buffer.
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  pattern = "*",
  command = "if mode() != 'c' | checktime | endif",
})

local checktime_timer = vim.uv.new_timer()
checktime_timer:start(1000, 1000, vim.schedule_wrap(function()
  if vim.fn.mode() ~= "c" then
    vim.cmd("checktime")
  end
end))

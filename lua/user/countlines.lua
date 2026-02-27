
-- -- -- vimscript
-- vim.cmd([[
-- function! CountLinesFromMark()
--   let l:start_line = line("'a")
--   let l:current_line = line(".")
--   echo abs(l:current_line - l:start_line + 1)
-- endfunction
-- ]])
--
-- vim.cmd([[
-- command! CountLines call CountLinesFromMark()
-- ]])


-- lua
function CountLinesFromMark()
  local top_line = vim.fn.line("'a")
  local current_line = vim.fn.line(".")
  print(math.abs(current_line - top_line))
end

vim.api.nvim_create_user_command('CountLines', CountLinesFromMark, {})

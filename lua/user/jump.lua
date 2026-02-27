
function FindVariableDefinition()
  local current_word = vim.fn.expand('<cword>')
  -- local pattern = "%" .. current_word .. "%s*=%s*"

  local pattern = "%" .. current_word
  -- 保存当前光标位置到临时标记
  vim.cmd('mark m')
  -- 获取当前光标位置
  local current_pos = vim.fn.getpos('.')

  -- 从文件开头开始查找
  -- vim.cmd('execute "normal! gg"')

  -- 搜索匹配的变量定义
  local result = vim.fn.search(pattern, 'bW')

  -- 如果找不到匹配项，给出提示
  if result == 0 then
    print("No definition found for variable: %" .. current_word)
    -- 返回到原来的位置
    vim.fn.setpos('.', current_pos)
  else
    -- 跳转到定义行并居中显示
    vim.cmd('execute "normal! zz"')
  end
end

function PreviewVariableDefinition()
  local current_word = vim.fn.expand('<cword>')
  local pattern = "%" .. current_word .. "\\>"
  local current_line = vim.fn.getline('.')
  print("line " .. current_line)
  local current_pos = vim.fn.getpos('.')
  vim.api.nvim_command("vimgrep /" .. pattern .. "/ %")
  vim.api.nvim_command("copen")
  vim.cmd('wincmd w')
  vim.fn.setpos('.', current_pos)
end

lvim.keys.normal_mode["<leader>jj"] = ":lua FindVariableDefinition()<CR>"
lvim.keys.normal_mode["<leader>kk"] = ":normal! `m<CR>"
-- lvim.keys.normal_mode["<leader>rr"] = ":lua PreviewVariableDefinition()<cr>"
lvim.keys.normal_mode["<leader>rr"] = PreviewVariableDefinition

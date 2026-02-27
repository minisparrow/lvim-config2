local M = {}

-- 打字机效果函数
function M.type_file(interval)
  interval = interval or 50 -- 每个字符的间隔时间（毫秒）

  -- 获取当前光标所在行
  local cursor_pos = vim.api.nvim_win_get_cursor(0) -- {line, col}
  local start_line = cursor_pos[1] - 1              -- 行号是从 0 开始的，所以需要减去 1

  -- 获取当前缓冲区的内容，从光标所在行到文件的末尾
  local lines = vim.api.nvim_buf_get_lines(0, start_line, -1, false)
  local content = table.concat(lines, "\n") -- 将所有行拼接为完整字符串

  -- 创建一个临时缓冲区
  local temp_buf = vim.api.nvim_create_buf(false, true) -- false: 非文件缓冲区, true: 无内容的缓冲区
  vim.api.nvim_set_current_buf(temp_buf)                -- 切换到临时缓冲区

  local total_length = #content
  local current_pos = 0
  local timer = vim.loop.new_timer()

  -- 使用计时器逐字符插入
  timer:start(0, interval, vim.schedule_wrap(function()
    if current_pos < total_length then
      current_pos = current_pos + 1
      local partial_content = content:sub(1, current_pos)               -- 截取当前内容
      local display_lines = vim.split(partial_content, "\n", true)      -- 按换行分割
      vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, display_lines) -- 更新临时缓冲区内容

      -- 播放打字音效
      -- vim.loop.spawn("/opt/homebrew/bin/sox", {
      --   env = vim.fn.environ(),                          -- 确保继承环境变量
      --   args = { "-n", "synth", "0.05", "sine", "500" }, -- 生成简短的打字音效
      --   stdio = { nil, vim.stdout, vim.stderr },
      --   detached = false,
      -- }, function(code)
      --   if code ~= 0 then
      --     print("sox failed " .. code)
      --   end
      -- end)
      -- vim.cmd("!sox  -n -d synth 0.05 sine 500 -t wav> /dev/null 2>&1 ")


      -- 移动光标到最后一行
      local last_line = #display_lines
      vim.api.nvim_win_set_cursor(0, { last_line, #display_lines[last_line] or 0 })

      -- 滚动屏幕：确保光标在屏幕可见范围
      vim.cmd("normal! zz")
    else
      timer:stop() -- 停止计时器
      timer:close()
    end
  end))
end

-- 绑定按键
lvim.keys.normal_mode["<leader>tp"] = function()
  M.type_file(100) -- 设置速度为每字符 100ms
end
return M

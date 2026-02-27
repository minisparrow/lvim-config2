local M = {}
local timer = nil

-- 自动滚动函数
function M.start(interval)
  -- 停止之前的滚动
  if timer then timer:stop() end

  -- 创建新的定时器
  timer = vim.loop.new_timer()
  timer:start(0, interval, vim.schedule_wrap(function()
    if vim.fn.line('.') >= vim.fn.line('$') then
      timer:stop()                                   -- 到达文件尾部停止
    else
      require("neoscroll").scroll(1, true, interval) -- 向下滚动 1 行
    end
  end))
end

-- 停止滚动
function M.stop()
  if timer then
    timer:stop()
    timer = nil
  end
end

return M

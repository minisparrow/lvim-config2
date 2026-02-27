local M = {}
function M.parse_file()
  --  local start_pos = vim.api.nvim_buf_get_mark(0, 'c')
  --  local end_pos = vim.api.nvim_buf_get_mark(0, 'd')
  --  -- lines 现在包含了从标记 a 到标记 b 之间的行
  --  local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)


  -- 获取 c 和 d 标记
  local start_pos = vim.api.nvim_buf_get_mark(0, 'c')
  local end_pos = vim.api.nvim_buf_get_mark(0, 'd')
  
  local buf = 0
  local line_count = vim.api.nvim_buf_line_count(buf)
  
  -- 如果没有标记，则设置为文件头和文件尾
  if start_pos[1] == 0 then
     start_pos = {1, 0}   -- 第一行开头
  end
  
  if end_pos[1] == 0 then
     end_pos = {line_count, 0}  -- 最后一行
  end
  
  -- 获取行：注意 start 需要 -1，因为 Lua 索引从 1 开始，API 从 0 开始
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)


  local definitions = {}

  -- 打印获取的行内容
  print("Lines between 'c' and 'd':")
  -- for _, line in ipairs(lines) do
  --   print(line)
  -- end
  for _, line in ipairs(lines) do
    local var, expr = line:match("^%s*(%%[%w_]+)%s*=%s*(.+)$")
    if var and expr then
      definitions[var] = expr
    end
  end
  return definitions
end

function M.parse_file_all()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local definitions = {}
  for _, line in ipairs(lines) do
    local var, expr = line:match("^%s*(%%[%w_]+)%s*=%s*(.+)$")
    if var and expr then
      definitions[var] = expr
    end
  end
  return definitions
end

function M.find_dependencies(var, definitions)
  local deps = {}
  local visited = {}

  local function dfs(current)
    if visited[current] then return end
    visited[current] = true

    local expr = definitions[current]
    if expr then
      deps[current] = expr
      for dep in expr:gmatch("%%[%w_]+") do
        if not visited[dep] then
          dfs(dep)
        end
      end
    else
      deps[current] = "Definition not found"
    end
  end

  dfs(var)
  return deps
end

function M.get_variable_at_cursor()
  local line = vim.fn.getline('.')
  local col = vim.fn.col('.') - 1
  local start_col = col

  while start_col > 0 and line:sub(start_col, start_col):match("[%%%w_]") do
    start_col = start_col - 1
  end

  if line:sub(start_col + 1, start_col + 1) == "%" then
    local end_col = col
    while end_col <= #line and line:sub(end_col + 1, end_col + 1):match("[%w_]") do
      end_col = end_col + 1
    end
    return line:sub(start_col + 1, end_col)
  else
    return nil
  end
end

function M.format_dependencies(deps, var)
  local output = {}
  local function add_dep(current, prefix, is_last)
    local expr = deps[current]
    if expr then
      table.insert(output, prefix .. (is_last and "└─ " or "├─ ") .. current .. " = " .. expr)
      local child_deps = {}
      for dep in expr:gmatch("%%[%w_]+") do
        if deps[dep] then
          table.insert(child_deps, dep)
        end
      end
      for i, dep in ipairs(child_deps) do
        local new_prefix = prefix .. (is_last and "   " or "│  ")
        add_dep(dep, new_prefix, i == #child_deps)
      end
    end
  end
  add_dep(var, "", true)
  return output
end

-- function M.show_dependencies()
--   local definitions = M.parse_file()
--   local var = M.get_variable_at_cursor()
--
--   if var and var:match("^%%[%w_]+$") then
--     local deps = M.find_dependencies(var, definitions)
--     local output = M.format_dependencies(deps, var)
--
--     vim.cmd("new")
--     vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
--     vim.bo.buftype = "nofile"
--     vim.bo.bufhidden = "wipe"
--     vim.bo.swapfile = false
--   else
--     print("No valid variable found at cursor position")
--   end
-- end
-- vim.api.nvim_create_user_command("ShowDependencies", M.show_dependencies, {})

function M.show_dependencies(opts)
  opts = opts or {}
  local definitions = M.parse_file()
  local var = M.get_variable_at_cursor()

  if var and var:match("^%%[%w_]+$") then
    local deps = M.find_dependencies(var, definitions)
    local output = M.format_dependencies(deps, var)

    -- 创建新的 buffer
    vim.cmd("new")

    -- 如果提供了名称，则设置 buffer 名称
    if opts.name then
      vim.api.nvim_buf_set_name(0, opts.name)
    else
      -- 如果没有提供名称，使用默认名称
      vim.api.nvim_buf_set_name(0, "Dependencies_" .. var)
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
  else
    print("No valid variable found at cursor position")
  end
end

-- 修改用户命令以支持可选的名称参数
vim.api.nvim_create_user_command("ShowDependencies", function(args)
  local opts = {}
  if args.args ~= "" then
    opts.name = args.args
  end
  M.show_dependencies(opts)
end, { nargs = '?' })


return M

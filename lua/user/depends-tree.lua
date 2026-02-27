local M = {}

function M.parse_file()
  -- 获取 c 和 d 标记
  local start_pos = vim.api.nvim_buf_get_mark(0, 'c')
  local end_pos = vim.api.nvim_buf_get_mark(0, 'd')
  
  local buf = 0
  local line_count = vim.api.nvim_buf_line_count(buf)
  
  -- 如果没有标记，则设置为文件头和文件尾
  if start_pos[1] == 0 then
     start_pos = {1, 0}
  end
  
  if end_pos[1] == 0 then
     end_pos = {line_count, 0}
  end
  
  -- 获取行
  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)

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

-- 修改后的格式化函数，包含去重逻辑
function M.format_dependencies(deps, var)
  local output = {}
  local printed_nodes = {} -- 记录已显示的节点

  local function add_dep(current, prefix, is_last)
    local expr = deps[current]
    if expr then
      local node_prefix = prefix .. (is_last and "└─ " or "├─ ")

      -- 如果已经显示过，加上标记并停止递归
      if printed_nodes[current] then
        table.insert(output, node_prefix .. current .. " (*)")
        return
      end

      -- 标记为已显示
      printed_nodes[current] = true
      
      table.insert(output, node_prefix .. current .. " = " .. expr)
      
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

function M.show_dependencies(opts)
  opts = opts or {}
  local definitions = M.parse_file()
  local var = M.get_variable_at_cursor()

  if var and var:match("^%%[%w_]+$") then
    local deps = M.find_dependencies(var, definitions)
    local output = M.format_dependencies(deps, var)

    vim.cmd("new")

    if opts.name then
      vim.api.nvim_buf_set_name(0, opts.name)
    else
      vim.api.nvim_buf_set_name(0, "Dependencies_" .. var)
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, output)
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    -- 设置一下 filetype 方便高亮（如果有 mlir 高亮支持的话）
    vim.bo.filetype = "mlir" 
  else
    print("No valid variable found at cursor position")
  end
end

vim.api.nvim_create_user_command("ShowDependencies", function(args)
  local opts = {}
  if args.args ~= "" then
    opts.name = args.args
  end
  M.show_dependencies(opts)
end, { nargs = '?' })

return M

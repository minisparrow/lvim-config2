
-- LLVM IR Expression Simplifier & Dependency Viewer for LunarVim
-- Adds a visual dependency tree and a concise simplified formula view for the %var under cursor
-- Author: minisparrow (enhanced)
-- Version: 2.4

local M = {}

M.debug = false
local function log(...) if M.debug then print("[LLVM-Simplifier] ", ...) end end

-- Node constructor
local function node(op, left, right, value, extra)
  return { op = op, left = left, right = right, value = value, extra = extra }
end

-- Utilities to get var under cursor
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = line:sub(1, col)
  local match = before:match(".*%%(%w+)[^%w]*$")
  if match then return match end
  local after = line:sub(col)
  match = after:match("^[^%w]*%%(%w+)")
  if match then return match end
  match = line:match("%%(%w+)")
  return match
end

-- Parse lines (targeting ops seen in your module)
local function parse_line(line)
  line = line:gsub("^[│├└─ ]+", "") -- strip tree chars

  -- insertvalue: %106 = llvm.insertvalue %2, %105[0]
  local v, a, b, idx = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if v then return v, "insertvalue", a:gsub("^%%",""), b:gsub("^%%",""), idx end

  -- extractvalue: %109 = llvm.extractvalue %108[0]
  v, a, idx = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[([%d]+)%]")
  if v then return v, "extractvalue", a:gsub("^%%",""), tonumber(idx) end

  -- getelementptr inbounds: %39 = llvm.getelementptr inbounds %2[%38]
  v, a, idx = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if v then return v, "getelementptr_inbounds", a, idx:gsub("^%%","") end

  -- addressof: %1 = llvm.mlir.addressof @global_smem  (or simplified "addressof")
  v, a = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if v then return v, "addressof", a end

  -- ldmatrix: %146 = nvvm.ldmatrix %145 ...
  v,a = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if v then return v, "ldmatrix", a:gsub("^%%","") end

  -- constants
  v, a = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%((%-?%d+)%s*:")
  if v then return v, "const", tonumber(a) end
  v, a = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%((%-?%d+)%s*%)")
  if v then return v, "const", tonumber(a) end

  -- nvvm.read.ptx.sreg.tid.x
  v = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if v then return v, "tid.x" end

  -- undef
  v = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if v then return v, "undef" end

  -- fallback generic binary op e.g. %x = llvm.add %a, %b
  v, op, a, b = line:match("%%(%w+)%s*=%s*llvm%.?([%w_]+)%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if v and op and a and b then
    a = a:gsub("^%%",""); b = b:gsub("^%%","")
    return v, op, a, b
  end

  -- nothing matched
  return nil
end

-- Build variable map
local function build_vars()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  for _, line in ipairs(lines) do
    local parsed = { parse_line(line) }
    local v = parsed[1]
    local op = parsed[2]
    if op then
      if op == "const" then vars[v] = node("const", nil, nil, parsed[3])
      elseif op == "tid.x" then vars[v] = node("tid.x", nil, nil, "tid.x")
      elseif op == "undef" then vars[v] = node("undef", nil, nil, "undef")
      elseif op == "addressof" then vars[v] = node("addressof", parsed[3], nil, nil)
      elseif op == "getelementptr_inbounds" then vars[v] = node("getelementptr_inbounds", parsed[3], parsed[4], nil)
      elseif op == "ldmatrix" then vars[v] = node("ldmatrix", parsed[3], nil, nil)
      elseif op == "insertvalue" then vars[v] = node("insertvalue", parsed[3], parsed[4], nil, parsed[5])
      elseif op == "extractvalue" then vars[v] = node("extractvalue", parsed[3], parsed[4], nil)
      else vars[v] = node(op, parsed[3], parsed[4], nil) end
    end
  end
  return vars
end

-- Utility to pretty print an expression (concise)
local function expr_to_string(x)
  if type(x) == "table" then
    if x.op == "insertvalue" then
      return string.format("insertvalue(%s, [%s]=%s)", expr_to_string(x.left), tostring(x.extra), expr_to_string(x.right))
    elseif x.op == "getelementptr_inbounds" then
      return string.format("getelementptr_inbounds(%s, %s)", expr_to_string(x.left), tostring(x.right))
    elseif x.op == "addressof" then
      return string.format("addressof(@%s)", tostring(x.left))
    elseif x.op == "ldmatrix" then
      return string.format("ldmatrix(%s)", expr_to_string(x.left))
    elseif x.op == "extractvalue" then
      return string.format("extractvalue(%s[%s])", expr_to_string(x.left), tostring(x.right))
    else
      -- generic op node where left/right may be strings like "%2"
      if x.left and x.right then
        return string.format("%s(%s, %s)", tostring(x.op), expr_to_string(x.left), expr_to_string(x.right))
      elseif x.left then
        return string.format("%s(%s)", tostring(x.op), expr_to_string(x.left))
      else
        return tostring(x.op)
      end
    end
  else
    return tostring(x)
  end
end

-- Simplify a var into a readable expression (returns string or structured table)
local function simplify_var(name, vars, memo)
  memo = memo or {}
  if memo[name] then return memo[name] end

  local nodev = vars[name]
  if not nodev then
    memo[name] = "%" .. tostring(name)
    return memo[name]
  end

  if nodev.op == "const" then memo[name] = tostring(nodev.value); return memo[name] end
  if nodev.op == "tid.x" then memo[name] = "tid.x"; return memo[name] end
  if nodev.op == "undef" then memo[name] = "undef"; return memo[name] end
  if nodev.op == "addressof" then memo[name] = { op = "addressof", left = nodev.left }; return memo[name] end

  if nodev.op == "getelementptr_inbounds" then
    -- left is a var name (base), right is index var or literal
    local base = simplify_var(nodev.left, vars, memo)
    local idx = nodev.right
    memo[name] = { op = "getelementptr_inbounds", left = base, right = idx }
    return memo[name]
  end

  if nodev.op == "ldmatrix" then
    local arg = simplify_var(nodev.left, vars, memo)
    memo[name] = { op = "ldmatrix", left = arg }
    return memo[name]
  end

  if nodev.op == "insertvalue" then
    -- build a small structured object describing insertion chain piece
    local agg = simplify_var(nodev.left, vars, memo)
    local val = simplify_var(nodev.right, vars, memo)
    memo[name] = { op = "insertvalue", left = agg, right = val, extra = nodev.extra }
    return memo[name]
  end

  if nodev.op == "extractvalue" then
    local agg = simplify_var(nodev.left, vars, memo)
    local idx = nodev.right
    -- If aggregate is an insertvalue chain that inserted some element at index idx, try to extract that element
    if type(agg) == "table" and agg.op == "insertvalue" then
      -- aggregate could be nested; try to walk back to find index 0 insertion etc.
      -- for clarity we won't try to implement full algebraic collapse here; return structured extractvalue
      memo[name] = { op = "extractvalue", left = agg, right = idx }
      return memo[name]
    end
    memo[name] = { op = "extractvalue", left = agg, right = idx }
    return memo[name]
  end

  -- generic fallback: keep op and children
  local left_s = nodev.left and simplify_var(nodev.left, vars, memo) or nil
  local right_s = nodev.right and simplify_var(nodev.right, vars, memo) or nil
  memo[name] = node(left_s and (type(left_s)=="string" and left_s or left_s), right_s, nil) -- placeholder
  return memo[name]
end

-- Build a readable dependency tree (indentation text)
local function build_dep_tree(name, vars, memo, seen, indent)
  memo = memo or {}
  seen = seen or {}
  indent = indent or ""
  local lines = {}
  if seen[name] then
    table.insert(lines, indent .. "%" .. name .. " (already shown)")
    return lines
  end
  seen[name] = true

  local n = vars[name]
  if not n then
    table.insert(lines, indent .. "%" .. name .. "  => " .. "%" .. name)
    return lines
  end

  -- Show current node header with simplified expression if possible
  local simplified = simplify_var(name, vars, memo)
  local sstr = expr_to_string(simplified)
  table.insert(lines, indent .. "%" .. name .. "  => " .. sstr)

  -- Then recursively list children with indentation
  if n.op == "getelementptr_inbounds" then
    -- left is base var; right is index
    if n.left then
      local child = n.left
      for _, l in ipairs(build_dep_tree(child, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    end
  elseif n.op == "ldmatrix" then
    if n.left then
      for _, l in ipairs(build_dep_tree(n.left, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    end
  elseif n.op == "extractvalue" or n.op == "insertvalue" then
    if n.left then
      for _, l in ipairs(build_dep_tree(n.left, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    end
    if n.right then
      for _, l in ipairs(build_dep_tree(n.right, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    end
  elseif n.left then
    for _, l in ipairs(build_dep_tree(n.left, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    if n.right then
      for _, l in ipairs(build_dep_tree(n.right, vars, memo, seen, indent .. "  ")) do table.insert(lines, l) end
    end
  end

  return lines
end

-- New: Show dependency tree + simplified formula for var under cursor
function M.show_deps()
  local target = get_var_under_cursor()
  if not target then vim.notify("No %variable under cursor", vim.log.levels.WARN); return end
  local vars = build_vars()
  if not vars[target] then
    vim.notify("Variable %" .. target .. " not found in buffer", vim.log.levels.ERROR)
    return
  end

  local memo = {}
  local resolved = simplify_var(target, vars, memo)
  local final_expr = expr_to_string(resolved)

  local tree_lines = build_dep_tree(target, vars, memo, {}, "")

  local lines = {}
  table.insert(lines, "=== Dependency & Simplified Expression ===")
  table.insert(lines, "")
  table.insert(lines, string.format("Target: %%%s", target))
  table.insert(lines, "")
  table.insert(lines, "Final simplified expression:")
  table.insert(lines, "  " .. final_expr)
  table.insert(lines, "")
  table.insert(lines, "Dependency tree:")
  for _, l in ipairs(tree_lines) do table.insert(lines, "  " .. l) end
  table.insert(lines, "")
  table.insert(lines, "Press q or <Esc> to close")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  local width = math.min(100, vim.o.columns - 8)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  }
  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap=true, silent=true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap=true, silent=true })
end

-- Convenience commands and keybindings
function M.setup()
  vim.api.nvim_create_user_command("LLVMDeps", M.show_deps, {})
  -- keep existing commands if present
  vim.api.nvim_create_user_command("LLVMSimplify", function() vim.notify("Use LLVMDeps for deps view", vim.log.levels.INFO) end, {})
  -- optional keybinding for lvim users
  if pcall(function() return lvim end) then
    lvim.keys.normal_mode["<leader>ld"] = ":LLVMDeps<CR>"
  end
  vim.notify("LLVM Simplifier v2.4 loaded (dependency viewer: :LLVMDeps / <leader>ld)", vim.log.levels.INFO)
end

return M

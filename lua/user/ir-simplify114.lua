
-- LLVM IR Expression Simplifier for LunarVim
-- Version: 5.5 - Enhanced Algebraic Simplification (Identity & Zero Laws)
-- Author: minisparrow (Modified)
-- Date: 2025-11-25

local M = {}

-- Debug flag
M.debug = false

-- Configuration
M.config = {
  use_split_window = true,
  split_position = 'below',
  split_size = 15,
}

local function create_node(op, left, right, value, extra, type_info, aux)
  return { 
    op = op, 
    left = left, 
    right = right, 
    value = value, 
    extra = extra, 
    type_info = type_info,
    aux = aux 
  }
end

-- [FIXED] 精确识别光标下的变量
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 
  
  local current_idx = 1
  while true do
    local s, e, var_name = line:find("%%([%w_%.]+)", current_idx)
    if not s then break end
    if col >= s and col <= e then return var_name end
    current_idx = e + 1
  end
  return nil
end

local function parse_line(line)
  line = line:gsub("^[│├└─ ]+", "")
  
  -- 贪婪匹配类型后缀
  local type_suffix = line:match("^.*:%s*([%w%p%s]+)$")
  if type_suffix then type_suffix = type_suffix:gsub("%s*#.*", "") end

  -- Select
  local var, cond, true_val, false_val = line:match("%%(%w+)%s*=%s*llvm%.select%s+(%%?%w+)%s*,%s*(%%?%w+)%s*,%s*(%%?%w+)")
  if var then return var, "select", cond:gsub("^%%",""), true_val:gsub("^%%",""), false_val:gsub("^%%",""), type_suffix end
  
  -- ICmp
  local var, pred, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.icmp%s+\"([^\"]+)\"%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var then return var, "icmp", arg1:gsub("^%%",""), arg2:gsub("^%%",""), pred, type_suffix end
  
  -- InsertValue
  local var, aggregate, value, indices = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if var then return var, "insertvalue", aggregate:gsub("^%%",""), value:gsub("^%%",""), indices, type_suffix end
  
  -- ExtractValue
  local var, aggregate, indices = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[([^%]]+)%]")
  if var then return var, "extractvalue", aggregate:gsub("^%%",""), indices, nil, type_suffix end
  
  -- GetElementPtr
  local var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then return var, "getelementptr", base, index:gsub("^%%",""), nil, type_suffix end
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then return var, "getelementptr", base, index:gsub("^%%",""), "inbounds", type_suffix end
  
  -- AddressOf
  local var, symbol = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if var then return var, "addressof", symbol, nil, nil, type_suffix end
  
  -- LdMatrix
  local var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if var then return var, "ldmatrix", arg:gsub("^%%",""), nil, nil, type_suffix end
  
  -- InsertElement
  local var, vec, val, idx, idx_type = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[%s*(%%?%w+)%s*:%s*([%w_]+)%s*%]")
  if var then 
      return var, "insertelement", vec:gsub("^%%",""), val:gsub("^%%",""), idx:gsub("^%%",""), type_suffix, idx_type 
  end
  
  -- ExtractElement
  local var, vec, idx, idx_type = line:match("%%(%w+)%s*=%s*llvm%.extractelement%s+(%%?%w+)%s*%[%s*(%%?%w+)%s*:%s*([%w_]+)%s*%]")
  if var then 
      return var, "extractelement", vec:gsub("^%%",""), idx:gsub("^%%",""), nil, type_suffix, idx_type
  end
  
  -- Bitcast
  local var, arg, from_t, to_t = line:match("%%(%w+)%s*=%s*llvm%.bitcast%s+(%%?%w+)%s*:%s*([%w<>%.]+)%s+to%s+([%w<>%.]+)")
  if var then return var, "bitcast", arg:gsub("^%%",""), nil, {from=from_t, to=to_t}, to_t end
  
  -- Binary Ops
  local var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then return var, op, arg1, arg2, nil, type_suffix end
  
  local var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then return var, "or", arg1, arg2, nil, type_suffix end

  -- Constants
  local var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(true%)")
  if var then return var, "const", true, nil, nil, "i1" end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(false%)")
  if var then return var, "const", false, nil, nil, "i1" end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if var then return var, "undef", nil, nil, nil, type_suffix end
  local var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
  if var then return var, "const", arg1, nil, nil, type_suffix end
  local var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d*%.?%d+[eE]?[%-]?%d*)%s*:%s*f")
  if var then return var, "const", arg1, nil, nil, type_suffix end
  local var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if var then return var, "tid.x", nil, nil, nil, "i32" end
  
  return nil
end

local function build_tree()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  for i, line in ipairs(lines) do
    local var, op, arg1, arg2, extra, type_info, aux = parse_line(line)
    if var then
      if op == "const" then 
        local val = arg1
        if val == "true" then val = true elseif val == "false" then val = false else val = tonumber(val) or val end
        vars[var] = create_node("const", nil, nil, val, nil, type_info)
      elseif op == "tid.x" or op == "undef" then vars[var] = create_node(op, nil, nil, op, nil, type_info)
      else
        vars[var] = create_node(op, arg1, arg2, nil, extra, type_info, aux)
      end
    end
  end
  return vars
end

local function lshift(a, b)
    if bit and bit.lshift then return bit.lshift(a, b) end
    return a * (2 ^ b)
end

-- Reconstruct String
local function value_to_string(val, depth)
  depth = depth or 0
  if depth > 10 then return "..." end
  
  if type(val) == "number" or type(val) == "boolean" then return tostring(val) end
  if type(val) == "string" then 
    if val:match("^%d+$") then return "%" .. val end 
    return "%" .. val 
  end
  
  if type(val) ~= "table" then return tostring(val) end
  
  local function fmt(v) return value_to_string(v, depth + 1) end
  local function fmt_type() return val.type_info and (" : " .. val.type_info) or "" end

  local op = val.op
  
  if op == "addressof" then return string.format("llvm.mlir.addressof @%s%s", tostring(val.value), fmt_type())
  
  elseif op == "select" then 
    return string.format("llvm.select %s, %s, %s%s", fmt(val.left), fmt(val.right), fmt(val.extra), fmt_type())
    
  elseif op == "icmp" then 
    return string.format('llvm.icmp "%s" %s, %s%s', tostring(val.extra), fmt(val.left), fmt(val.right), fmt_type())
    
  elseif op == "getelementptr" then 
    local base = type(val.left)=="string" and ("%"..val.left) or fmt(val.left)
    local idx = type(val.right)=="string" and ("%"..val.right) or fmt(val.right)
    return string.format("llvm.getelementptr %s[%s]%s", base, idx, fmt_type())
    
  elseif op == "insertvalue" then
    return string.format("llvm.insertvalue %s, %s[%s]%s", fmt(val.left), fmt(val.right), tostring(val.extra), fmt_type())
    
  elseif op == "extractvalue" then
    return string.format("llvm.extractvalue %s[%s]%s", fmt(val.left), tostring(val.right), fmt_type())
    
  elseif op == "bitcast" then
    local from = (type(val.extra) == "table" and val.extra.from) or "?"
    local to = (type(val.extra) == "table" and val.extra.to) or "?"
    return string.format("llvm.bitcast %s : %s to %s", fmt(val.left), from, to)
  
  elseif op == "ldmatrix" then
    return string.format("nvvm.ldmatrix %s%s", fmt(val.left), fmt_type())

  elseif op == "insertelement" then
     local idx_type = val.aux and (" : " .. val.aux) or ""
     return string.format("llvm.insertelement %s, %s[%s%s]%s", fmt(val.left), fmt(val.right), fmt(val.extra), idx_type, fmt_type())

  elseif op == "extractelement" then
     local idx_type = val.aux and (" : " .. val.aux) or ""
     return string.format("llvm.extractelement %s[%s%s]%s", fmt(val.left), fmt(val.right), idx_type, fmt_type())

  elseif val.left and val.right then
      return string.format("llvm.%s %s, %s%s", op, fmt(val.left), fmt(val.right), fmt_type())
  end
  
  return tostring(val)
end

-- ==========================================================
-- [ENHANCED] Simplify Logic (Algebraic Simplification)
-- ==========================================================
local function simplify(var, vars, memo, depth)
  depth = depth or 0
  if depth > 100 then return "recursion_limit" end
  if memo[var] then return memo[var] end
  local node = vars[var]
  if not node then return var end
  
  if node.op == "const" then memo[var] = node.value; return node.value end
  if node.op == "tid.x" or node.op == "undef" then memo[var] = node.op; return node.op end
  
  local function resolve(operand_var)
      if not operand_var then return nil end
      local res = simplify(operand_var, vars, memo, depth + 1)
      if type(res) == "table" then return operand_var end 
      return res 
  end

  local left = resolve(node.left)
  
  local right
  if node.op == "extractvalue" then
      right = node.right 
  else
      right = resolve(node.right)
  end
  
  -- 1. 常数算术折叠 (两边都是数字)
  if type(left) == "number" and type(right) == "number" then
     if node.op == "add" then memo[var] = left + right; return left + right end
     if node.op == "sub" then memo[var] = left - right; return left - right end
     if node.op == "mul" then memo[var] = left * right; return left * right end
     if node.op == "shl" then memo[var] = lshift(left, right); return memo[var] end
  end
  
  -- 2. 代数恒等式化简 (Identity Simplification)
  -- 规则 A: x op 0 = x
  if right == 0 then
      if node.op == "add" or node.op == "sub" or node.op == "or" or node.op == "xor" or 
         node.op == "shl" or node.op == "lshr" or node.op == "ashr" then
          memo[var] = left
          return left
      end
  end
  
  -- 规则 B: 0 op x = x (交换律)
  if left == 0 then
      if node.op == "add" or node.op == "or" or node.op == "xor" then
          memo[var] = right
          return right
      end
  end

  -- 规则 C: x op 1 = x
  if right == 1 then
      if node.op == "mul" or node.op == "sdiv" or node.op == "udiv" then
          memo[var] = left
          return left
      end
  end

  -- 规则 D: 1 op x = x
  if left == 1 and node.op == "mul" then
      memo[var] = right
      return right
  end
  
  -- 规则 E: 零元素 (Zero Annihilator) -> 0
  if (left == 0 or right == 0) and (node.op == "mul" or node.op == "and") then
      memo[var] = 0
      return 0
  end

  -- 规则 F: 自运算 (Self Operation)
  -- 注意：这里 left 和 right 可能是字符串(变量名)，只要相等即可
  if left == right and left ~= nil then
      if node.op == "and" or node.op == "or" then 
          memo[var] = left; return left  -- x & x = x
      end
      if node.op == "xor" or node.op == "sub" then
          memo[var] = 0; return 0        -- x ^ x = 0
      end
  end

  memo[var] = {
      op = node.op,
      left = left,
      right = right,
      extra = node.extra,
      value = node.value,
      type_info = node.type_info,
      aux = node.aux 
  }
  return memo[var]
end

local function is_simple_node(id, vars)
    local node = vars[id]
    if not node then return false end
    local simple_ops = { ["const"]=true, ["tid.x"]=true, ["undef"]=true, ["addressof"]=true }
    return simple_ops[node.op] or false
end

local function build_dependency_tree(var, vars, memo, visited, indent_prefix, child_prefix, lines, path, label)
    visited = visited or {}
    indent_prefix = indent_prefix or ""
    child_prefix = child_prefix or ""
    lines = lines or {}
    path = path or {}

    local label_suffix = ""
    if label then label_suffix = "  [" .. label .. "]" end

    for _, v in ipairs(path) do
        if v == var then
            table.insert(lines, indent_prefix .. "%" .. var .. " (circular)" .. label_suffix)
            return lines
        end
    end

    local new_path = {}
    for _, v in ipairs(path) do table.insert(new_path, v) end
    table.insert(new_path, var)

    local node = vars[var]
    local result = memo[var] or simplify(var, vars, memo, 0)
    local result_str = value_to_string(result)

    local display_text = string.format("%%%s = %s", var, result_str)

    if visited[var] then
        table.insert(lines, indent_prefix .. display_text .. " (see above)" .. label_suffix)
        return lines
    end

    visited[var] = true
    table.insert(lines, indent_prefix .. display_text .. label_suffix)

    if not node then return lines end

    local children = {}
    local counter = 0
    local function add_child(id, lbl)
        counter = counter + 1
        if id and vars[id] then
            table.insert(children, {id = id, label = lbl, idx = counter})
        end
    end

    if node.op == "select" then
        add_child(node.left, "cond"); add_child(node.right, "true"); add_child(node.extra, "false")
    elseif node.op == "icmp" then
        add_child(node.left, "lhs"); add_child(node.right, "rhs")
    elseif node.op == "insertvalue" then
        add_child(node.left, "agg"); add_child(node.right, "val")
    elseif node.op == "extractvalue" then
        add_child(node.left, "agg")
    elseif node.op == "bitcast" or node.op == "ldmatrix" then
        add_child(node.left, "op")
    elseif node.op == "getelementptr" then
        add_child(node.left, "base"); add_child(node.right, "idx")
    elseif node.op == "insertelement" then
        add_child(node.left, "vec"); add_child(node.right, "val"); add_child(node.extra, "idx")
    elseif node.op == "extractelement" then
        add_child(node.left, "vec"); add_child(node.right, "idx")
    elseif node.left or node.right then
        add_child(node.left, "lhs"); add_child(node.right, "rhs")
    end

    table.sort(children, function(a, b)
        local a_simple = is_simple_node(a.id, vars)
        local b_simple = is_simple_node(b.id, vars)
        if a_simple and not b_simple then return true
        elseif not a_simple and b_simple then return false
        else return a.idx < b.idx end
    end)

    for i, child in ipairs(children) do
        local is_last = (i == #children)
        local branch = is_last and "└─ " or "├─ "
        local next_child_prefix = child_prefix .. (is_last and "   " or "│  ")
        build_dependency_tree(child.id, vars, memo, visited, child_prefix .. branch, next_child_prefix, lines, new_path, child.label)
    end

    return lines
end

function M.show_deps()
  local target_var = get_var_under_cursor()
  if not target_var then vim.notify("No variable under cursor", vim.log.levels.WARN); return end
  
  local vars = build_tree()
  if not vars[target_var] then vim.notify("Variable %"..target_var.." not found", vim.log.levels.ERROR); return end
  
  local memo = {}
  local result = simplify(target_var, vars, memo)
  local result_str = value_to_string(result)
  
  local tree_lines = build_dependency_tree(target_var, vars, memo, {}, "", "", {}, {})
  
  local lines = {
    "╔═══════════════════════════════════════════════════════════╗",
    "║        🔍 LLVM IR Dependency (Hybrid Format)             ║",
    "╚═══════════════════════════════════════════════════════════╝",
    "",
    "  %" .. target_var .. " = " .. result_str,
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 📊 DEPENDENCY TREE                                      │",
    "└─────────────────────────────────────────────────────────┘",
    ""
  }
  for _, line in ipairs(tree_lines) do table.insert(lines, "  " .. line) end
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  local win
  if M.config.use_split_window then
    vim.cmd(M.config.split_position == 'below' and 'botright split' or 'botright vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    if M.config.split_position == 'below' then vim.api.nvim_win_set_height(win, M.config.split_size)
    else vim.api.nvim_win_set_width(win, M.config.split_size) end
  else
    local width, height = math.min(100, vim.o.columns - 4), math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
    win = vim.api.nvim_open_win(buf, true, {relative='editor', width=width, height=height, col=math.floor((vim.o.columns-width)/2), row=math.floor((vim.o.lines-height)/2), style='minimal', border='rounded'})
  end
  
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match LLVMVar /%\w\+/]])
    vim.cmd([[syntax match LLVMString /"[^"]*"/]])
    vim.cmd([[syntax match LLVMOp /llvm\.\w\+\(\.\w\+\)*/]])
    vim.cmd([[syntax match LLVMLabel /\[\w\+\]/]])
    vim.cmd([[highlight link LLVMVar Identifier]])
    vim.cmd([[highlight link LLVMOp Function]])
    vim.cmd([[highlight link LLVMString String]])
    vim.cmd([[highlight link LLVMLabel Type]])
  end)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', {noremap=true, silent=true})
end

function M.setup(user_config)
  if user_config then for k,v in pairs(user_config) do M.config[k] = v end end
  vim.api.nvim_create_user_command('LLVMDeps', M.show_deps, {})
  vim.api.nvim_create_user_command('LLVMDebug', function() M.debug = not M.debug end, {})
  vim.api.nvim_create_user_command('LLVMToggleWindow', function() M.config.use_split_window = not M.config.use_split_window end, {})
end

return M

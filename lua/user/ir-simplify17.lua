
-- LLVM IR Expression Simplifier for LunarVim
-- Version: 4.5 - Improved Dependency Visualization (Inline Labels)
-- Author: minisparrow (Modified)
-- Date: 2025-11-25

local M = {}

-- Debug flag
M.debug = false

-- Configuration
M.config = {
  -- Use split window instead of floating window
  use_split_window = true,
  -- Split window position: 'below' or 'right'
  split_position = 'below',
  -- Split window height (for 'below') or width (for 'right')
  split_size = 15,
}

local function log(msg)
  if M.debug then
    print("[LLVM-Simplifier] " .. msg)
  end
end

-- Expression node structure
local function create_node(op, left, right, value, extra)
  return {
    op = op,
    left = left,
    right = right,
    value = value,
    extra = extra
  }
end

-- Get the variable under cursor (starting with %)
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  
  -- Pattern 1: Extract from current position backwards
  local before = line:sub(1, col)
  local match = before:match(".*%%(%w+)[^%w]*$")
  if match then return match end
  
  -- Pattern 2: Extract from current position forward
  local after = line:sub(col)
  match = after:match("^[^%w]*%%(%w+)")
  if match then return match end
  
  -- Pattern 3: Try to find any %variable in the line
  match = line:match("%%(%w+)")
  if match then return match end
  
  return nil
end

-- Parse a single line to extract variable and expression
local function parse_line(line)
  -- Remove tree characters
  line = line:gsub("^[│├└─ ]+", "")
  
  -- select: %133 = llvm.select %131, %128, %132 : i1, i32
  local var, cond, true_val, false_val = line:match("%%(%w+)%s*=%s*llvm%.select%s+(%%?%w+)%s*,%s*(%%?%w+)%s*,%s*(%%?%w+)")
  if var then
    cond = cond:gsub("^%%","")
    true_val = true_val:gsub("^%%","")
    false_val = false_val:gsub("^%%","")
    return var, "select", cond, true_val, false_val
  end
  
  -- icmp: %131 = llvm.icmp "eq" %130, %128 : i32
  var, pred, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.icmp%s+\"([^\"]+)\"%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var then
    arg1 = arg1:gsub("^%%","")
    arg2 = arg2:gsub("^%%","")
    return var, "icmp", arg1, arg2, pred
  end
  
  -- insertvalue: %106 = llvm.insertvalue %2, %105[0]
  var, aggregate, value, indices = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if var then
    aggregate = aggregate:gsub("^%%","")
    value = value:gsub("^%%","")
    return var, "insertvalue", aggregate, value, indices
  end
  
  -- extractvalue: %109 = llvm.extractvalue %108[0]
  var, aggregate, indices = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[([^%]]+)%]")
  if var then
    aggregate = aggregate:gsub("^%%","")
    return var, "extractvalue", aggregate, indices
  end
  
  -- getelementptr (without inbounds): %2 = llvm.getelementptr %1[%0]
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then
    index = index:gsub("^%%","")
    return var, "getelementptr", base, index
  end
  
  -- getelementptr inbounds: %39 = llvm.getelementptr inbounds %2[%38]
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then
    index = index:gsub("^%%","")
    return var, "getelementptr", base, index
  end
  
  -- addressof: %1 = llvm.mlir.addressof @global_smem
  var, symbol = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if var then
    return var, "addressof", symbol
  end
  
  -- ldmatrix: %146 = nvvm.ldmatrix %145
  var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if var then
    arg = arg:gsub("^%%","")
    return var, "ldmatrix", arg
  end
  
  -- insertelement: %42 = llvm.insertelement %4, %40[%41 : i32]
  var, vec, val, idx = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then
    vec = vec:gsub("^%%","")
    val = val:gsub("^%%","")
    idx = idx:gsub("^%%","")
    return var, "insertelement", vec, val, idx
  end
  
  -- extractelement: %51 = llvm.extractelement %48[%50 : i32]
  var, aggregate, idx = line:match("%%(%w+)%s*=%s*llvm%.extractelement%s+(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then
    aggregate = aggregate:gsub("^%%","")
    idx = idx:gsub("^%%","")
    return var, "extractelement", aggregate, idx
  end
  
  -- bitcast: %58 = llvm.bitcast %51 : f16 to i16
  var, arg, from_type, to_type = line:match("%%(%w+)%s*=%s*llvm%.bitcast%s+(%%?%w+)%s*:%s*([%w<>]+)%s+to%s+([%w<>]+)")
  if var then
    arg = arg:gsub("^%%","")
    return var, "bitcast", arg, nil, {from = from_type, to = to_type}
  end
  
  -- Match patterns like: %43 = llvm.add %29, %0 : i32
  var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then
    return var, op, arg1, arg2
  end
  
  -- Match disjoint or pattern: %24 = llvm.or disjoint %21, %23 : i32
  var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then
    return var, "or", arg1, arg2
  end
  
  -- boolean constant
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(true%)")
  if var then return var, "const", true end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(false%)")
  if var then return var, "const", false end
  
  -- undef
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if var then return var, "undef", nil, nil end
  
  -- constant patterns
  var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
  if var then return var, "const", arg1, nil end
  
  -- float constant
  var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d*%.?%d+[eE]?[%-]?%d*)%s*:%s*f")
  if var then return var, "const", arg1, nil end
  
  -- nvvm.read.ptx.sreg.tid.x
  var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if var then return var, "tid.x", nil, nil end
  
  return nil
end

-- Build expression tree from buffer content
local function build_tree()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  
  for i, line in ipairs(lines) do
    local var, op, arg1, arg2, extra = parse_line(line)
    if var then
      if op == "const" then
        vars[var] = create_node("const", nil, nil, arg1 == "true" and true or (arg1 == "false" and false or (tonumber(arg1) or arg1)))
      elseif op == "tid.x" then
        vars[var] = create_node("tid.x", nil, nil, "tid.x")
      elseif op == "undef" then
        vars[var] = create_node("undef", nil, nil, "undef")
      elseif op == "addressof" then
        vars[var] = create_node("addressof", nil, nil, arg1)
      elseif op == "select" then
        vars[var] = create_node("select", arg1, arg2, nil, extra)
      elseif op == "icmp" then
        vars[var] = create_node("icmp", arg1, arg2, nil, extra)
      elseif op == "getelementptr" then
        vars[var] = create_node("getelementptr", arg1, arg2, nil)
      elseif op == "ldmatrix" then
        vars[var] = create_node("ldmatrix", arg1, nil, nil)
      elseif op == "insertelement" then
        vars[var] = create_node("insertelement", arg1, arg2, nil, extra)
      elseif op == "extractelement" then
        vars[var] = create_node("extractelement", arg1, arg2, nil)
      elseif op == "extractvalue" then
        vars[var] = create_node("extractvalue", arg1, arg2, nil)
      elseif op == "insertvalue" then
        vars[var] = create_node("insertvalue", arg1, arg2, nil, extra)
      elseif op == "bitcast" then
        vars[var] = create_node("bitcast", arg1, nil, nil, extra)
      else
        vars[var] = create_node(op, arg1, arg2, nil)
      end
    end
  end
  return vars
end

-- Safe bit operations
local function bxor(a, b)
  if bit and bit.bxor then return bit.bxor(a, b) end
  local result = 0
  local bit_val = 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then result = result + bit_val end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function bor(a, b)
  if bit and bit.bor then return bit.bor(a, b) end
  local result = 0
  local bit_val = 1
  while a > 0 or b > 0 do
    if (a % 2) == 1 or (b % 2) == 1 then result = result + bit_val end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function band(a, b)
  if bit and bit.band then return bit.band(a, b) end
  local result = 0
  local bit_val = 1
  while a > 0 and b > 0 do
    if (a % 2) == 1 and (b % 2) == 1 then result = result + bit_val end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function lshift(a, b)
  if bit and bit.lshift then return bit.lshift(a, b) end
  return a * (2 ^ b)
end

-- Convert value to string for display, keeping variable references for complex ops
local function value_to_string(val, depth)
  depth = depth or 0
  
  if depth > 10 then return "..." end
  
  if type(val) == "number" then return tostring(val) end
  if type(val) == "boolean" then return tostring(val) end
  if type(val) == "string" then 
    if val:match("^%d+$") then return "%" .. val end
    return val 
  end
  if type(val) ~= "table" then return tostring(val) end
  
  -- Handle special table structures
  if val.op == "addressof" then return string.format("@%s", tostring(val.value))
  elseif val.op == "select" then
    local cond_str = value_to_string(val.left, depth+1)
    local true_str = value_to_string(val.right, depth+1)
    local false_str = value_to_string(val.extra, depth+1)
    return string.format("select(%s ? %s : %s)", cond_str, true_str, false_str)
  elseif val.op == "icmp" then
    local left_str = value_to_string(val.left, depth+1)
    local right_str = value_to_string(val.right, depth+1)
    return string.format("icmp_%s(%s, %s)", tostring(val.extra), left_str, right_str)
  elseif val.op == "getelementptr" then
    local base_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local idx_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    return string.format("getelementptr(%s, %s)", base_str, idx_str)
  elseif val.op == "ldmatrix" then
    local arg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    return string.format("ldmatrix(%s)", arg_str)
  elseif val.op == "extractvalue" then
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    return string.format("extractvalue(%s[%s])", agg_str, tostring(val.right))
  elseif val.op == "insertvalue" then
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local val_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    return string.format("insertvalue(%s, %s[%s])", agg_str, val_str, tostring(val.extra))
  elseif val.op == "bitcast" then
    local arg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local type_info = (type(val.extra) == "table" and val.extra.to) or "?"
    return string.format("bitcast(%s -> %s)", arg_str, type_info)
  elseif val.op == "insertelement" then
    local vec_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local val_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    local idx_str = type(val.extra) == "string" and ("%" .. val.extra) or tostring(val.extra or "?")
    return string.format("insertelement(%s, %s[%s])", vec_str, val_str, idx_str)
  elseif val.op == "extractelement" then
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local idx_str = type(val.right) == "string" and ("%" .. val.right) or tostring(val.right)
    return string.format("extractelement(%s[%s])", agg_str, idx_str)
  end
  
  return tostring(val)
end

-- Simplify expression recursively
local function simplify(var, vars, memo, depth)
  depth = depth or 0
  if depth > 100 then return "recursion_limit" end
  
  if memo[var] then return memo[var] end
  
  local node = vars[var]
  if not node then return var end
  
  -- Handle primitives
  if node.op == "const" then
    memo[var] = node.value
    return node.value
  end
  
  if node.op == "tid.x" or node.op == "undef" then
    memo[var] = node.op
    return node.op
  end
  
  if node.op == "addressof" then
    local result = { op = "addressof", value = node.value }
    memo[var] = result
    return result
  end
  
  -- Handle structural/complex ops
  if node.op == "select" then
    local cond = simplify(node.left, vars, memo, depth + 1)
    local true_val = simplify(node.right, vars, memo, depth + 1)
    local false_val = simplify(node.extra, vars, memo, depth + 1)
    
    if cond == true then memo[var] = true_val; return true_val
    elseif cond == false then memo[var] = false_val; return false_val end
    
    local result = { op = "select", left = cond, right = true_val, extra = false_val }
    memo[var] = result
    return result
  end
  
  if node.op == "icmp" then
    local left = simplify(node.left, vars, memo, depth + 1)
    local right = simplify(node.right, vars, memo, depth + 1)
    local pred = node.extra
    
    if type(left) == "number" and type(right) == "number" then
      if pred == "eq" then memo[var] = (left == right); return left == right
      elseif pred == "ne" then memo[var] = (left ~= right); return left ~= right
      -- Add other predicates as needed
      end
    end
    
    local result = { op = "icmp", left = left, right = right, extra = pred }
    memo[var] = result
    return result
  end
  
  -- Structure ops - preserve refs
  if node.op == "getelementptr" then
    memo[var] = { op = "getelementptr", left = node.left, right = node.right }
    return memo[var]
  end
  
  if node.op == "ldmatrix" then
    memo[var] = { op = "ldmatrix", left = node.left }
    return memo[var]
  end
  
  if node.op == "insertvalue" then
    memo[var] = { op = "insertvalue", left = node.left, right = node.right, extra = node.extra }
    return memo[var]
  end
  
  if node.op == "extractvalue" then
    memo[var] = { op = "extractvalue", left = node.left, right = node.right }
    return memo[var]
  end
  
  if node.op == "bitcast" then
    memo[var] = { op = "bitcast", left = node.left, extra = node.extra }
    return memo[var]
  end
  
  if node.op == "insertelement" then
    memo[var] = { op = "insertelement", left = node.left, right = node.right, extra = node.extra }
    return memo[var]
  end
  
  if node.op == "extractelement" then
    memo[var] = { op = "extractelement", left = node.left, right = node.right }
    return memo[var]
  end
  
  -- Arithmetic ops
  local left = node.left and simplify(node.left, vars, memo, depth + 1) or nil
  local right = node.right and simplify(node.right, vars, memo, depth + 1) or nil
  
  if node.op == "add" then
    if type(left) == "number" and type(right) == "number" then memo[var] = left + right; return left + right
    elseif left == 0 then memo[var] = right; return right
    elseif right == 0 then memo[var] = left; return left
    else memo[var] = string.format("(%s + %s)", value_to_string(left), value_to_string(right)); return memo[var] end
  
  elseif node.op == "mul" then
    if type(left) == "number" and type(right) == "number" then memo[var] = left * right; return left * right
    elseif left == 0 or right == 0 then memo[var] = 0; return 0
    elseif left == 1 then memo[var] = right; return right
    elseif right == 1 then memo[var] = left; return left
    else memo[var] = string.format("(%s * %s)", value_to_string(left), value_to_string(right)); return memo[var] end
    
  elseif node.op == "shl" then
     if type(left) == "number" and type(right) == "number" then memo[var] = lshift(left, right); return left * (2^right)
     else memo[var] = string.format("(%s << %s)", value_to_string(left), value_to_string(right)); return memo[var] end
  end
  
  -- Fallback for other ops (sub, div, logic, etc)
  if right then
    local result = string.format("(%s %s %s)", value_to_string(left), node.op, value_to_string(right))
    memo[var] = result
    return result
  else
    local result = string.format("%s %s", node.op, value_to_string(left))
    memo[var] = result
    return result
  end
end

-- Revised dependency tree builder: puts labels on the same line
local function build_dependency_tree(var, vars, memo, visited, indent_prefix, child_prefix, lines, path, label)
  visited = visited or {}
  indent_prefix = indent_prefix or "" -- Prefix for current line (e.g., "  ├─ ")
  child_prefix = child_prefix or ""   -- Prefix for children (e.g., "  │  ")
  lines = lines or {}
  path = path or {}
  
  -- Check circular ref
  for _, v in ipairs(path) do
    if v == var then
      local txt = "%" .. var .. " (circular)"
      if label then txt = label .. ": " .. txt end
      table.insert(lines, indent_prefix .. txt)
      return lines
    end
  end
  
  local new_path = {}
  for _, v in ipairs(path) do table.insert(new_path, v) end
  table.insert(new_path, var)
  
  local node = vars[var]
  local result = memo[var] or simplify(var, vars, memo, 0)
  local result_str = value_to_string(result)
  
  -- Construct display line
  local display_text = "%" .. var .. " = " .. result_str
  if label then
    display_text = label .. ": " .. display_text
  end
  
  if visited[var] then
    table.insert(lines, indent_prefix .. display_text .. " (see above)")
    return lines
  end
  
  visited[var] = true
  table.insert(lines, indent_prefix .. display_text)
  
  if not node then return lines end
  
  -- Helper to queue children
  local children = {}
  
  -- Collect children based on op type
  if node.op == "select" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="condition"}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="true_val"}) end
    if node.extra and vars[node.extra] then table.insert(children, {id=node.extra, label="false_val"}) end
    
  elseif node.op == "icmp" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="left"}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="right"}) end
    
  elseif node.op == "getelementptr" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="base"}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="index"}) end
    
  elseif node.op == "ldmatrix" or node.op == "bitcast" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="operand"}) end
    
  elseif node.op == "extractvalue" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="aggregate"}) end
    
  elseif node.op == "extractelement" then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="vector"}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="index"}) end
    
  elseif node.op == "insertvalue" or node.op == "insertelement" then
    local target = node.op == "insertelement" and "vector" or "aggregate"
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label=target}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="value"}) end
    if node.extra and vars[node.extra] then table.insert(children, {id=node.extra, label="index"}) end
    
  elseif node.left or node.right then
    if node.left and vars[node.left] then table.insert(children, {id=node.left, label="left"}) end
    if node.right and vars[node.right] then table.insert(children, {id=node.right, label="right"}) end
  end
  
  -- Process children
  for i, child in ipairs(children) do
    local is_last = (i == #children)
    local branch = is_last and "└─ " or "├─ "
    local next_child_prefix = child_prefix .. (is_last and "   " or "│  ")
    
    build_dependency_tree(child.id, vars, memo, visited, child_prefix .. branch, next_child_prefix, lines, new_path, child.label)
  end
  
  return lines
end

-- Show dependency tree view
function M.show_deps()
  local target_var = get_var_under_cursor()
  
  if not target_var then
    vim.notify("No variable found under cursor", vim.log.levels.WARN)
    return
  end
  
  local vars = build_tree()
  if not vars[target_var] then
    vim.notify("Variable %" .. target_var .. " not found in buffer definition.", vim.log.levels.ERROR)
    return
  end
  
  local memo = {}
  local result = simplify(target_var, vars, memo)
  local result_str = value_to_string(result)
  
  -- Build dependency tree (Root call)
  local tree_lines = build_dependency_tree(target_var, vars, memo, {}, "", "", {}, {})
  
  local lines = {
    "╔═══════════════════════════════════════════════════════════╗",
    "║        🔍 LLVM IR Dependency & Simplification            ║",
    "╚═══════════════════════════════════════════════════════════╝",
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 🎯 FINAL SIMPLIFIED RESULT                              │",
    "└─────────────────────────────────────────────────────────┘",
    "",
    string.format("  %%%s = %s", target_var, result_str),
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 📊 DEPENDENCY TREE                                      │",
    "└─────────────────────────────────────────────────────────┘",
    "",
  }
  
  for _, line in ipairs(tree_lines) do
    table.insert(lines, "  " .. line)
  end
  
  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  table.insert(lines, "  Shortcuts: [Q]uit  [Y]ank result  [D]ebug  [W]indow mode")
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Create window
  local win
  if M.config.use_split_window then
    vim.cmd(M.config.split_position == 'below' and 'botright split' or 'botright vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    if M.config.split_position == 'below' then
      vim.api.nvim_win_set_height(win, M.config.split_size)
    else
      vim.api.nvim_win_set_width(win, M.config.split_size)
    end
  else
    local width = math.min(100, vim.o.columns - 4)
    local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
    local opts = {
      relative = 'editor',
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = 'minimal',
      border = 'rounded',
    }
    win = vim.api.nvim_open_win(buf, true, opts)
  end
  
  -- Highlighting
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match LLVMVar /%\w\+/]])
    vim.cmd([[syntax match LLVMOp /[+\-*&|^<>]/]])
    vim.cmd([[syntax match LLVMNumber /\d\+/]])
    vim.cmd([[syntax match LLVMSpecial /tid\.x\|undef\|true\|false/]])
    vim.cmd([[syntax match LLVMHeader /^[╔╗╚╝║─┌┐└┘│━├└]/]])
    vim.cmd([[syntax match LLVMTreeChar /[│├└─]/]])
    -- Match labels like "base:", "index:"
    vim.cmd([[syntax match LLVMLabel /\s\zs\w\+:/]]) 
    
    vim.cmd([[highlight link LLVMVar Identifier]])
    vim.cmd([[highlight link LLVMOp Operator]])
    vim.cmd([[highlight link LLVMNumber Number]])
    vim.cmd([[highlight link LLVMSpecial Special]])
    vim.cmd([[highlight link LLVMHeader Comment]])
    vim.cmd([[highlight link LLVMTreeChar Comment]])
    vim.cmd([[highlight link LLVMLabel Type]])
  end)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Keymaps
  local yank_text = string.format("%%%s = %s", target_var, result_str)
  local keymaps = {
    { 'n', 'q', ':close<CR>' },
    { 'n', '<Esc>', ':close<CR>' },
    { 'n', 'y', string.format(':let @+ = "%s"<CR>:echo "Copied!"<CR>', yank_text:gsub('"', '\\"')) },
    { 'n', 'w', ':LLVMToggleWindow<CR>:close<CR>:LLVMDeps<CR>' },
  }
  
  for _, map in ipairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf, map[1], map[2], map[3], { noremap = true, silent = true })
  end
end

-- Toggle debug mode
function M.toggle_debug()
  M.debug = not M.debug
  print("LLVM Debug: " .. tostring(M.debug))
end

-- Toggle window mode
function M.toggle_window_mode()
  M.config.use_split_window = not M.config.use_split_window
  print("LLVM Window: " .. (M.config.use_split_window and "SPLIT" or "FLOAT"))
end

function M.setup(user_config)
  if user_config then for k,v in pairs(user_config) do M.config[k] = v end end
  
  vim.api.nvim_create_user_command('LLVMDeps', M.show_deps, {})
  vim.api.nvim_create_user_command('LLVMDebug', M.toggle_debug, {})
  vim.api.nvim_create_user_command('LLVMToggleWindow', M.toggle_window_mode, {})
end

return M

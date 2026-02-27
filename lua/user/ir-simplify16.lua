
-- LLVM IR Expression Simplifier for LunarVim
-- Version: 4.4 - Fix extractelement/insertelement index display
-- Author: minisparrow
-- Date: 2025-11-18

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
  
  log("Current line: " .. line)
  log("Cursor column: " .. col)
  
  local var = nil
  
  -- Pattern 1: Extract from current position backwards
  local before = line:sub(1, col)
  local match = before:match(".*%%(%w+)[^%w]*$")
  if match then
    var = match
    log("Found variable (backward search): " .. var)
    return var
  end
  
  -- Pattern 2: Extract from current position forward
  local after = line:sub(col)
  match = after:match("^[^%w]*%%(%w+)")
  if match then
    var = match
    log("Found variable (forward search): " .. var)
    return var
  end
  
  -- Pattern 3: Try to find any %variable in the line
  match = line:match("%%(%w+)")
  if match then
    var = match
    log("Found variable (line search): " .. var)
    return var
  end
  
  log("No variable found")
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
    log(string.format("Parsed select: %%%s = select %%%s ? %%%s : %%%s", var, cond, true_val, false_val))
    return var, "select", cond, true_val, false_val
  end
  
  -- icmp: %131 = llvm.icmp "eq" %130, %128 : i32
  var, pred, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.icmp%s+\"([^\"]+)\"%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var then
    arg1 = arg1:gsub("^%%","")
    arg2 = arg2:gsub("^%%","")
    log(string.format("Parsed icmp: %%%s = icmp %s %%%s, %%%s", var, pred, arg1, arg2))
    return var, "icmp", arg1, arg2, pred
  end
  
  -- insertvalue: %106 = llvm.insertvalue %2, %105[0]
  -- Note: format is insertvalue <aggregate>, <value>[<index>]
  var, aggregate, value, indices = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if var then
    aggregate = aggregate:gsub("^%%","")
    value = value:gsub("^%%","")
    log(string.format("Parsed insertvalue: %%%s = insertvalue %%%s, %%%s[%s]", var, aggregate, value, indices))
    return var, "insertvalue", aggregate, value, indices
  end
  
  -- extractvalue: %109 = llvm.extractvalue %108[0]
  var, aggregate, indices = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[([^%]]+)%]")
  if var then
    aggregate = aggregate:gsub("^%%","")
    log(string.format("Parsed extractvalue: %%%s = extractvalue %%%s[%s]", var, aggregate, indices))
    return var, "extractvalue", aggregate, indices
  end
  
  -- getelementptr (without inbounds): %2 = llvm.getelementptr %1[%0]
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then
    index = index:gsub("^%%","")
    log(string.format("Parsed getelementptr: %%%s = getelementptr %%%s[%%%s]", var, base, index))
    return var, "getelementptr", base, index
  end
  
  -- getelementptr inbounds: %39 = llvm.getelementptr inbounds %2[%38]
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then
    index = index:gsub("^%%","")
    log(string.format("Parsed getelementptr inbounds: %%%s = getelementptr %%%s[%%%s]", var, base, index))
    return var, "getelementptr", base, index
  end
  
  -- addressof: %1 = llvm.mlir.addressof @global_smem
  var, symbol = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if var then
    log(string.format("Parsed addressof: %%%s = addressof @%s", var, symbol))
    return var, "addressof", symbol
  end
  
  -- ldmatrix: %146 = nvvm.ldmatrix %145
  var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if var then
    arg = arg:gsub("^%%","")
    log(string.format("Parsed ldmatrix: %%%s = ldmatrix %%%s", var, arg))
    return var, "ldmatrix", arg
  end
  
  -- insertelement: %42 = llvm.insertelement %4, %40[%41 : i32]
  var, vec, val, idx = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then
    vec = vec:gsub("^%%","")
    val = val:gsub("^%%","")
    idx = idx:gsub("^%%","")
    log(string.format("Parsed insertelement: %%%s = insertelement %%%s, %%%s[%%%s]", var, vec, val, idx))
    return var, "insertelement", vec, val, idx
  end
  
  -- extractelement: %51 = llvm.extractelement %48[%50 : i32]
  var, aggregate, idx = line:match("%%(%w+)%s*=%s*llvm%.extractelement%s+(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then
    aggregate = aggregate:gsub("^%%","")
    idx = idx:gsub("^%%","")
    log(string.format("Parsed extractelement: %%%s = extractelement %%%s[%%%s]", var, aggregate, idx))
    return var, "extractelement", aggregate, idx
  end
  
  -- bitcast: %58 = llvm.bitcast %51 : f16 to i16
  var, arg, from_type, to_type = line:match("%%(%w+)%s*=%s*llvm%.bitcast%s+(%%?%w+)%s*:%s*([%w<>]+)%s+to%s+([%w<>]+)")
  if var then
    arg = arg:gsub("^%%","")
    log(string.format("Parsed bitcast: %%%s = bitcast %%%s : %s to %s", var, arg, from_type, to_type))
    return var, "bitcast", arg, nil, {from = from_type, to = to_type}
  end
  
  -- Match patterns like: %43 = llvm.add %29, %0 : i32
  var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then
    log(string.format("Parsed: %%%s = %s %%%s, %%%s", var, op, arg1, arg2))
    return var, op, arg1, arg2
  end
  
  -- Match disjoint or pattern: %24 = llvm.or disjoint %21, %23 : i32
  var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then
    log(string.format("Parsed: %%%s = or %%%s, %%%s", var, arg1, arg2))
    return var, "or", arg1, arg2
  end
  
  -- boolean constant: %49 = llvm.mlir.constant(true) : i1
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(true%)")
  if var then
    log(string.format("Parsed: %%%s = const true", var))
    return var, "const", true
  end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(false%)")
  if var then
    log(string.format("Parsed: %%%s = const false", var))
    return var, "const", false
  end
  
  -- undef: %50 = llvm.mlir.undef
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if var then
    log(string.format("Parsed: %%%s = undef", var))
    return var, "undef", nil, nil
  end
  
  -- constant patterns: %0 = llvm.mlir.constant(123 : i32) : i32
  var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
  if var then
    log(string.format("Parsed: %%%s = const %s", var, arg1))
    return var, "const", arg1, nil
  end
  
  -- float constant
  var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d*%.?%d+[eE]?[%-]?%d*)%s*:%s*f")
  if var then
    log(string.format("Parsed: %%%s = const %s", var, arg1))
    return var, "const", arg1, nil
  end
  
  -- nvvm.read.ptx.sreg.tid.x
  var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if var then
    log(string.format("Parsed: %%%s = tid.x", var))
    return var, "tid.x", nil, nil
  end
  
  return nil
end

-- Build expression tree from buffer content
local function build_tree()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  local count = 0
  
  log("Building tree from " .. #lines .. " lines")
  
  for i, line in ipairs(lines) do
    local var, op, arg1, arg2, extra = parse_line(line)
    if var then
      count = count + 1
      if op == "const" then
        vars[var] = create_node("const", nil, nil, arg1 == "true" and true or (arg1 == "false" and false or (tonumber(arg1) or arg1)))
      elseif op == "tid.x" then
        vars[var] = create_node("tid.x", nil, nil, "tid.x")
      elseif op == "undef" then
        vars[var] = create_node("undef", nil, nil, "undef")
      elseif op == "addressof" then
        vars[var] = create_node("addressof", nil, nil, arg1)
      elseif op == "select" then
        -- arg1=cond, arg2=true_val, extra=false_val
        vars[var] = create_node("select", arg1, arg2, nil, extra)
      elseif op == "icmp" then
        -- arg1=left, arg2=right, extra=predicate
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
  
  log("Built tree with " .. count .. " variables")
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
    -- If it looks like a variable number, format it with %
    if val:match("^%d+$") then
      return "%" .. val
    end
    return val 
  end
  if type(val) ~= "table" then return tostring(val) end
  
  -- Handle special table structures - KEEP VARIABLE REFERENCES
  if val.op == "addressof" then
    return string.format("@%s", tostring(val.value))
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
    -- Keep both parameters as variable references
    local base_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local idx_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    return string.format("getelementptr(%s, %s)", base_str, idx_str)
  elseif val.op == "ldmatrix" then
    -- Keep parameter as variable reference
    local arg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    return string.format("ldmatrix(%s)", arg_str)
  elseif val.op == "extractvalue" then
    -- Use LLVM IR syntax: extractvalue %aggregate[index]
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    return string.format("extractvalue(%s[%s])", agg_str, tostring(val.right))
  elseif val.op == "insertvalue" then
    -- Use LLVM IR syntax: insertvalue %aggregate, %value[index]
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local val_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    return string.format("insertvalue(%s, %s[%s])", agg_str, val_str, tostring(val.extra))
  elseif val.op == "bitcast" then
    local arg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local type_info = (type(val.extra) == "table" and val.extra.to) or "?"
    return string.format("bitcast(%s -> %s)", arg_str, type_info)
  elseif val.op == "insertelement" then
    -- Use LLVM IR syntax: insertelement %vector, %value[%index]
    local vec_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local val_str = type(val.right) == "string" and ("%" .. val.right) or value_to_string(val.right, depth+1)
    local idx_str = type(val.extra) == "string" and ("%" .. val.extra) or tostring(val.extra or "?")
    return string.format("insertelement(%s, %s[%s])", vec_str, val_str, idx_str)
  elseif val.op == "extractelement" then
    -- Use LLVM IR syntax: extractelement %vector[%index]
    local agg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local idx_str = type(val.right) == "string" and ("%" .. val.right) or tostring(val.right)
    return string.format("extractelement(%s[%s])", agg_str, idx_str)
  end
  
  return tostring(val)
end

-- Simplify expression recursively, keeping variable references for complex ops
local function simplify(var, vars, memo, depth)
  depth = depth or 0
  if depth > 100 then
    log("Recursion limit reached for %" .. var)
    return "recursion_limit"
  end
  
  if memo[var] then return memo[var] end
  
  local node = vars[var]
  if not node then
    log("Variable %" .. var .. " not found in tree")
    return var  -- Return the variable name without %
  end
  
  log("Simplifying %" .. var .. " (op: " .. node.op .. ")")
  
  -- Handle primitives
  if node.op == "const" then
    memo[var] = node.value
    return node.value
  end
  
  if node.op == "tid.x" then
    memo[var] = "tid.x"
    return "tid.x"
  end
  
  if node.op == "undef" then
    memo[var] = "undef"
    return "undef"
  end
  
  if node.op == "addressof" then
    local result = { op = "addressof", value = node.value }
    memo[var] = result
    return result
  end
  
  -- Handle select operation
  if node.op == "select" then
    local cond = simplify(node.left, vars, memo, depth + 1)
    local true_val = simplify(node.right, vars, memo, depth + 1)
    local false_val = simplify(node.extra, vars, memo, depth + 1)
    
    -- If condition is a constant boolean, return the appropriate branch
    if cond == true then
      memo[var] = true_val
      return true_val
    elseif cond == false then
      memo[var] = false_val
      return false_val
    end
    
    local result = { op = "select", left = cond, right = true_val, extra = false_val }
    memo[var] = result
    return result
  end
  
  -- Handle icmp operation
  if node.op == "icmp" then
    local left = simplify(node.left, vars, memo, depth + 1)
    local right = simplify(node.right, vars, memo, depth + 1)
    local pred = node.extra
    
    -- If both operands are constants, evaluate the comparison
    if type(left) == "number" and type(right) == "number" then
      if pred == "eq" then
        memo[var] = (left == right)
        return left == right
      elseif pred == "ne" then
        memo[var] = (left ~= right)
        return left ~= right
      elseif pred == "slt" or pred == "ult" then
        memo[var] = (left < right)
        return left < right
      elseif pred == "sle" or pred == "ule" then
        memo[var] = (left <= right)
        return left <= right
      elseif pred == "sgt" or pred == "ugt" then
        memo[var] = (left > right)
        return left > right
      elseif pred == "sge" or pred == "uge" then
        memo[var] = (left >= right)
        return left >= right
      end
    end
    
    local result = { op = "icmp", left = left, right = right, extra = pred }
    memo[var] = result
    return result
  end
  
  -- Handle structural operations - KEEP VARIABLE REFERENCES
  if node.op == "getelementptr" then
    -- Simplify base but keep as variable reference
    local base = node.left  -- Keep as variable name
    local index = node.right  -- Keep as variable name
    local result = { op = "getelementptr", left = base, right = index }
    memo[var] = result
    return result
  end
  
  if node.op == "ldmatrix" then
    -- Keep the argument as variable reference
    local arg = node.left  -- Keep as variable name
    local result = { op = "ldmatrix", left = arg }
    memo[var] = result
    return result
  end
  
  if node.op == "insertvalue" then
    -- Keep parameters as variable references
    local agg = node.left  -- Keep as variable name
    local val = node.right  -- Keep as variable name
    local result = { op = "insertvalue", left = agg, right = val, extra = node.extra }
    memo[var] = result
    return result
  end
  
  if node.op == "extractvalue" then
    -- Keep aggregate as variable reference
    local agg = node.left  -- Keep as variable name
    local result = { op = "extractvalue", left = agg, right = node.right }
    memo[var] = result
    return result
  end
  
  if node.op == "bitcast" then
    -- Keep argument as variable reference
    local arg = node.left
    local result = { op = "bitcast", left = arg, extra = node.extra }
    memo[var] = result
    return result
  end
  
  if node.op == "insertelement" then
    local vec = node.left  -- Keep as variable name
    local val = node.right  -- Keep as variable name
    local idx = node.extra  -- Keep as variable name (the index)
    local result = { op = "insertelement", left = vec, right = val, extra = idx }
    memo[var] = result
    return result
  end
  
  if node.op == "extractelement" then
    local agg = node.left  -- Keep as variable name
    local idx = node.right  -- Keep as variable name (the index)
    local result = { op = "extractelement", left = agg, right = idx }
    memo[var] = result
    return result
  end
  
  -- Recursively simplify operands for arithmetic ops
  local left = node.left and simplify(node.left, vars, memo, depth + 1) or nil
  local right = node.right and simplify(node.right, vars, memo, depth + 1) or nil
  
  log(string.format("  %%%s: left=%s, right=%s", var, value_to_string(left), value_to_string(right or "nil")))
  
  -- Apply arithmetic operations
  if node.op == "add" then
    if type(left) == "number" and type(right) == "number" then
      memo[var] = left + right
      return left + right
    elseif left == 0 then
      memo[var] = right
      return right
    elseif right == 0 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s + %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "fadd" then
    if type(left) == "number" and type(right) == "number" then
      memo[var] = left + right
      return left + right
    elseif left == 0 or left == 0.0 then
      memo[var] = right
      return right
    elseif right == 0 or right == 0.0 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s +f %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "xor" then
    if type(left) == "number" and type(right) == "number" then
      local result = bxor(left, right)
      memo[var] = result
      return result
    elseif left == 0 then
      memo[var] = right
      return right
    elseif right == 0 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s ^ %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "or" then
    if type(left) == "number" and type(right) == "number" then
      local result = bor(left, right)
      memo[var] = result
      return result
    elseif left == 0 then
      memo[var] = right
      return right
    elseif right == 0 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s | %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "and" then
    if type(left) == "number" and type(right) == "number" then
      local result = band(left, right)
      memo[var] = result
      return result
    elseif left == 0 or right == 0 then
      memo[var] = 0
      return 0
    else
      local result = string.format("(%s & %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "shl" then
    if type(left) == "number" and type(right) == "number" then
      local result = lshift(left, right)
      memo[var] = result
      return result
    elseif right == 0 then
      memo[var] = left
      return left
    elseif left == 0 then
      memo[var] = 0
      return 0
    else
      local result = string.format("(%s << %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "mul" then
    if type(left) == "number" and type(right) == "number" then
      memo[var] = left * right
      return left * right
    elseif left == 0 or right == 0 then
      memo[var] = 0
      return 0
    elseif left == 1 then
      memo[var] = right
      return right
    elseif right == 1 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s * %s)", value_to_string(left), value_to_string(right))
      memo[var] = result
      return result
    end
  end
  
  local result = string.format("unknown_op_%s(%s, %s)", node.op, value_to_string(left), value_to_string(right or ""))
  memo[var] = result
  return result
end

-- Build dependency tree for visualization (improved to avoid false circular refs)
local function build_dependency_tree(var, vars, memo, visited, indent, lines, path)
  visited = visited or {}
  indent = indent or ""
  lines = lines or {}
  path = path or {}
  
  -- Check if we're in a real circular reference (var appears in current path)
  for _, v in ipairs(path) do
    if v == var then
      table.insert(lines, indent .. "%" .. var .. " (circular reference)")
      return lines
    end
  end
  
  -- Mark this var in current path
  local new_path = {}
  for _, v in ipairs(path) do table.insert(new_path, v) end
  table.insert(new_path, var)
  
  local node = vars[var]
  if not node then
    table.insert(lines, indent .. "%" .. var .. " = <not found>")
    return lines
  end
  
  -- Get simplified result
  local result = memo[var] or simplify(var, vars, memo, 0)
  local result_str = value_to_string(result)
  
  -- Add current node
  if visited[var] then
    -- Already shown elsewhere, just reference it
    table.insert(lines, indent .. "%" .. var .. " = " .. result_str .. " (see above)")
    return lines
  end
  
  visited[var] = true
  table.insert(lines, indent .. "%" .. var .. " = " .. result_str)
  
  -- Recursively show dependencies
  local new_indent = indent .. "│ "
  local last_indent = indent .. "  "
  
  if node.op == "select" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "├─ condition:")
      build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
    end
    if node.right and vars[node.right] then
      table.insert(lines, indent .. "├─ true_value:")
      build_dependency_tree(node.right, vars, memo, visited, new_indent, lines, new_path)
    end
    if node.extra and vars[node.extra] then
      table.insert(lines, indent .. "└─ false_value:")
      build_dependency_tree(node.extra, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "icmp" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "├─ left:")
      build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
    end
    if node.right and vars[node.right] then
      table.insert(lines, indent .. "└─ right:")
      build_dependency_tree(node.right, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "getelementptr" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "├─ base:")
      build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
    end
    if node.right and vars[node.right] then
      table.insert(lines, indent .. "└─ index:")
      build_dependency_tree(node.right, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "ldmatrix" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "└─ operand:")
      build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "bitcast" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "└─ operand:")
      build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "extractvalue" then
    if node.left and vars[node.left] then
      table.insert(lines, indent .. "└─ aggregate:")
      build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "extractelement" then
    if node.left and vars[node.left] then
      if node.right and vars[node.right] then
        table.insert(lines, indent .. "├─ vector:")
        build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
      else
        table.insert(lines, indent .. "└─ vector:")
        build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
      end
    end
    if node.right and vars[node.right] then
      table.insert(lines, indent .. "└─ index:")
      build_dependency_tree(node.right, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.op == "insertvalue" or node.op == "insertelement" then
    if node.left and vars[node.left] then
      if node.right and vars[node.right] then
        table.insert(lines, indent .. "├─ aggregate:")
        build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
      else
        table.insert(lines, indent .. "└─ aggregate:")
        build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
      end
    end
    if node.right and vars[node.right] then
      if node.extra and vars[node.extra] then
        table.insert(lines, indent .. "├─ value:")
        build_dependency_tree(node.right, vars, memo, visited, new_indent, lines, new_path)
      else
        table.insert(lines, indent .. "└─ value:")
        build_dependency_tree(node.right, vars, memo, visited, last_indent, lines, new_path)
      end
    end
    if node.extra and vars[node.extra] then
      table.insert(lines, indent .. "└─ index:")
      build_dependency_tree(node.extra, vars, memo, visited, last_indent, lines, new_path)
    end
  elseif node.left or node.right then
    if node.left and vars[node.left] then
      if node.right and vars[node.right] then
        table.insert(lines, indent .. "├─ left:")
        build_dependency_tree(node.left, vars, memo, visited, new_indent, lines, new_path)
      else
        table.insert(lines, indent .. "└─ left:")
        build_dependency_tree(node.left, vars, memo, visited, last_indent, lines, new_path)
      end
    end
    if node.right and vars[node.right] then
      table.insert(lines, indent .. "└─ right:")
      build_dependency_tree(node.right, vars, memo, visited, last_indent, lines, new_path)
    end
  end
  
  return lines
end

-- Show dependency tree view
function M.show_deps()
  log("=== Starting dependency view ===")
  
  local target_var = get_var_under_cursor()
  
  if not target_var then
    vim.notify("No variable (starting with %) found under cursor", vim.log.levels.WARN)
    log("Failed: No variable found")
    return
  end
  
  log("Target variable: %" .. target_var)
  
  local vars = build_tree()
  
  if not vars[target_var] then
    local available = {}
    for k, _ in pairs(vars) do
      table.insert(available, k)
    end
    table.sort(available, function(a,b) 
      local na = tonumber(a)
      local nb = tonumber(b)
      if na and nb then return na < nb end
      return a < b
    end)
    
    local msg = string.format("Variable %%%s not found in buffer.\nAvailable variables: %%%s", 
                              target_var, table.concat(available, ", %"))
    vim.notify(msg, vim.log.levels.ERROR)
    log("Failed: Variable not found. Available: " .. table.concat(available, ", "))
    return
  end
  
  log("Starting simplification and dependency analysis...")
  local memo = {}
  local result = simplify(target_var, vars, memo)
  local result_str = value_to_string(result)
  log("Simplification result: " .. result_str)
  
  -- Build dependency tree
  local tree_lines = build_dependency_tree(target_var, vars, memo, {}, "", {}, {})
  
  -- Build display content
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
  table.insert(lines, "  Shortcuts: [Q]uit  [Y]ank result  [D]ebug  [W]indow mode toggle")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  
  log("Creating window with " .. #lines .. " lines")
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  local win
  
  if M.config.use_split_window then
    -- Create split window below or to the right
    vim.cmd(M.config.split_position == 'below' and 'botright split' or 'botright vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    
    -- Set window size
    if M.config.split_position == 'below' then
      vim.api.nvim_win_set_height(win, M.config.split_size)
    else
      vim.api.nvim_win_set_width(win, M.config.split_size)
    end
  else
    -- Create floating window (original behavior)
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
  
  -- Apply syntax highlighting
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match LLVMVar /%\w\+/]])
    vim.cmd([[syntax match LLVMOp /[+\-*&|^<>]/]])
    vim.cmd([[syntax match LLVMNumber /\d\+/]])
    vim.cmd([[syntax match LLVMSpecial /tid\.x/]])
    vim.cmd([[syntax match LLVMSpecial /undef/]])
    vim.cmd([[syntax match LLVMSpecial /true/]])
    vim.cmd([[syntax match LLVMSpecial /false/]])
    vim.cmd([[syntax match LLVMHeader /^[╔╗╚╝║─┌┐└┘│━├└]/]])
    vim.cmd([[syntax match LLVMKeyword /insertvalue\|extractvalue\|getelementptr\|ldmatrix\|addressof\|select\|icmp/]])
    vim.cmd([[highlight link LLVMVar Identifier]])
    vim.cmd([[highlight link LLVMOp Operator]])
    vim.cmd([[highlight link LLVMNumber Number]])
    vim.cmd([[highlight link LLVMSpecial Special]])
    vim.cmd([[highlight link LLVMHeader Comment]])
    vim.cmd([[highlight link LLVMKeyword Keyword]])
  end)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Store result for yanking
  local yank_text = string.format("%%%s = %s", target_var, result_str)
  
  -- Keybindings
  local keymaps = {
    { 'n', 'q', ':close<CR>', 'Quit' },
    { 'n', 'Q', ':close<CR>', 'Quit' },
    { 'n', '<Esc>', ':close<CR>', 'Quit' },
    { 'n', 'y', string.format(':let @+ = "%s"<CR>:let @" = "%s"<CR>:echo "Result copied!"<CR>', 
      yank_text:gsub('"', '\\"'), yank_text:gsub('"', '\\"')), 'Yank result' },
    { 'n', 'Y', string.format(':let @+ = "%s"<CR>:let @" = "%s"<CR>:echo "Result copied!"<CR>', 
      yank_text:gsub('"', '\\"'), yank_text:gsub('"', '\\"')), 'Yank result' },
    { 'n', 'w', ':LLVMToggleWindow<CR>:close<CR>:LLVMDeps<CR>', 'Toggle window mode' },
    { 'n', 'W', ':LLVMToggleWindow<CR>:close<CR>:LLVMDeps<CR>', 'Toggle window mode' },
  }
  
  for _, keymap in ipairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf, keymap[1], keymap[2], keymap[3], 
      { noremap = true, silent = true })
  end
  
  -- Position cursor at the result line
  vim.api.nvim_win_set_cursor(win, {9, 0})
  
  log("=== Dependency view complete ===")
end

-- Toggle debug mode
function M.toggle_debug()
  M.debug = not M.debug
  vim.notify("LLVM Simplifier debug mode: " .. (M.debug and "ON" or "OFF"), vim.log.levels.INFO)
end

-- Toggle window mode
function M.toggle_window_mode()
  M.config.use_split_window = not M.config.use_split_window
  vim.notify("LLVM Simplifier window mode: " .. (M.config.use_split_window and "SPLIT" or "FLOAT"), vim.log.levels.INFO)
end

-- Setup commands
function M.setup(user_config)
  -- Merge user config with defaults
  if user_config then
    for k, v in pairs(user_config) do
      M.config[k] = v
    end
  end
  
  vim.api.nvim_create_user_command('LLVMDeps', M.show_deps, {})
  vim.api.nvim_create_user_command('LLVMDebug', M.toggle_debug, {})
  vim.api.nvim_create_user_command('LLVMToggleWindow', M.toggle_window_mode, {})
  
  -- Add keybindings
  if pcall(function() return lvim end) then
    lvim.keys.normal_mode["<leader>ld"] = ":LLVMDeps<CR>"
  end
  
  vim.notify("🎯 LLVM Simplifier v4.4 loaded! (by @minisparrow)\n" ..
    "  <leader>ld or :LLVMDeps - Show dependency tree\n" ..
    "  :LLVMDebug - Toggle debug mode\n" ..
    "  :LLVMToggleWindow - Toggle split/float window\n" ..
    "  Fixed: extractelement/insertelement index with % prefix\n" ..
    "  Feature: Split window display (below original code)\n" ..
    "  Inside window: y=copy, q=quit, w=toggle window", 
    vim.log.levels.INFO)
end

return M

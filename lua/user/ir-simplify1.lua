
-- LLVM IR Expression Simplifier for LunarVim
-- Usage: Place cursor on a %variable, then run :LLVMSimplify or press <leader>ls
-- Author: minisparrow
-- Date: 2025-11-11

local M = {}

-- Debug flag
M.debug = false

local function log(msg)
  if M.debug then
    print("[LLVM-Simplifier] " .. msg)
  end
end

-- Expression node structure
local function create_node(op, left, right, value)
  return {
    op = op,
    left = left,
    right = right,
    value = value
  }
end

-- Get the variable under cursor (starting with %)
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1  -- Lua is 1-indexed
  
  log("Current line: " .. line)
  log("Cursor column: " .. col)
  
  -- Try to find % before or at cursor position
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
  
  -- Match patterns like: %43 = llvm.add %29, %0 : i32
  local var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+),%s*%%(%w+)")
  if var then
    log(string.format("Parsed: %%%s = %s %%%s, %%%s", var, op, arg1, arg2))
    return var, op, arg1, arg2
  end
  
  -- Match disjoint or pattern: %24 = llvm.or disjoint %21, %23 : i32
  var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+),%s*%%(%w+)")
  if var then
    log(string.format("Parsed: %%%s = or %%%s, %%%s", var, arg1, arg2))
    return var, "or", arg1, arg2
  end
  
  -- Match constant patterns: %0 = llvm.mlir.constant(123 : i32) : i32
  var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
  if var then
    log(string.format("Parsed: %%%s = const %s", var, arg1))
    return var, "const", arg1, nil
  end
  
  -- Match special patterns like nvvm.read.ptx.sreg.tid.x
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
    local var, op, arg1, arg2 = parse_line(line)
    if var then
      count = count + 1
      if op == "const" then
        vars[var] = create_node("const", nil, nil, tonumber(arg1))
      elseif op == "tid.x" then
        vars[var] = create_node("tid.x", nil, nil, "tid.x")
      else
        vars[var] = create_node(op, arg1, arg2, nil)
      end
    end
  end
  
  log("Built tree with " .. count .. " variables")
  return vars
end

-- Safe bit operations (fallback if bit library not available)
local function bxor(a, b)
  if bit and bit.bxor then
    return bit.bxor(a, b)
  end
  -- Fallback implementation
  local result = 0
  local bit_val = 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then
      result = result + bit_val
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function bor(a, b)
  if bit and bit.bor then
    return bit.bor(a, b)
  end
  local result = 0
  local bit_val = 1
  while a > 0 or b > 0 do
    if (a % 2) == 1 or (b % 2) == 1 then
      result = result + bit_val
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function band(a, b)
  if bit and bit.band then
    return bit.band(a, b)
  end
  local result = 0
  local bit_val = 1
  while a > 0 and b > 0 do
    if (a % 2) == 1 and (b % 2) == 1 then
      result = result + bit_val
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit_val = bit_val * 2
  end
  return result
end

local function lshift(a, b)
  if bit and bit.lshift then
    return bit.lshift(a, b)
  end
  return a * (2 ^ b)
end

-- Simplify expression recursively
local function simplify(var, vars, memo, depth)
  depth = depth or 0
  if depth > 100 then
    log("Recursion limit reached for %" .. var)
    return "recursion_limit"
  end
  
  if memo[var] then
    return memo[var]
  end
  
  local node = vars[var]
  if not node then
    log("Variable %" .. var .. " not found in tree")
    return "%" .. var
  end
  
  log("Simplifying %" .. var .. " (op: " .. node.op .. ")")
  
  if node.op == "const" then
    memo[var] = node.value
    return node.value
  end
  
  if node.op == "tid.x" then
    memo[var] = "tid.x"
    return "tid.x"
  end
  
  -- Recursively simplify operands
  local left = simplify(node.left, vars, memo, depth + 1)
  local right = node.right and simplify(node.right, vars, memo, depth + 1) or nil
  
  log(string.format("  %%%s: left=%s, right=%s", var, tostring(left), tostring(right or "nil")))
  
  -- Apply operations
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
      local result = string.format("(%s + %s)", tostring(left), tostring(right))
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
      local result = string.format("(%s ^ %s)", tostring(left), tostring(right))
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
      local result = string.format("(%s | %s)", tostring(left), tostring(right))
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
      local result = string.format("(%s & %s)", tostring(left), tostring(right))
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
      local result = string.format("(%s << %s)", tostring(left), tostring(right))
      memo[var] = result
      return result
    end
    
  elseif node.op == "sub" then
    if type(left) == "number" and type(right) == "number" then
      memo[var] = left - right
      return left - right
    elseif right == 0 then
      memo[var] = left
      return left
    else
      local result = string.format("(%s - %s)", tostring(left), tostring(right))
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
      local result = string.format("(%s * %s)", tostring(left), tostring(right))
      memo[var] = result
      return result
    end
  end
  
  local result = string.format("unknown_op_%s(%s, %s)", node.op, tostring(left), tostring(right or ""))
  memo[var] = result
  return result
end

-- Collect dependency chain
local function get_dependency_chain(var, vars, chain, visited)
  chain = chain or {}
  visited = visited or {}
  
  if visited[var] then
    return chain
  end
  visited[var] = true
  
  local node = vars[var]
  
  if not node or node.op == "const" or node.op == "tid.x" then
    return chain
  end
  
  if node.left then
    get_dependency_chain(node.left, vars, chain, visited)
  end
  if node.right then
    get_dependency_chain(node.right, vars, chain, visited)
  end
  
  table.insert(chain, var)
  
  return chain
end

-- Main function to simplify the expression under cursor
function M.simplify()
  log("=== Starting simplification ===")
  
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
    table.sort(available)
    
    local msg = string.format("Variable %%%s not found in buffer.\nAvailable variables: %s", 
                              target_var, table.concat(available, ", "))
    vim.notify(msg, vim.log.levels.ERROR)
    log("Failed: Variable not found. Available: " .. table.concat(available, ", "))
    return
  end
  
  log("Starting simplification...")
  local memo = {}
  local result = simplify(target_var, vars, memo)
  log("Simplification result: " .. tostring(result))
  
  -- Get dependency chain
  local chain = get_dependency_chain(target_var, vars)
  table.sort(chain, function(a, b) 
    local num_a = tonumber(a)
    local num_b = tonumber(b)
    if num_a and num_b then
      return num_a < num_b
    end
    return a < b
  end)
  
  log("Dependency chain length: " .. #chain)
  
  -- Build display content - PUT RESULT AT TOP!
  local lines = {
    "╔═══════════════════════════════════════════════════════════╗",
    "║           🎯 LLVM IR Expression Simplifier               ║",
    "╚═══════════════════════════════════════════════════════════╝",
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 🔍 FINAL RESULT                                         │",
    "└─────────────────────────────────────────────────────────┘",
    "",
    string.format("  %%%s = %s", target_var, tostring(result)),
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 📊 Dependency Chain (step by step)                     │",
    "└─────────────────────────────────────────────────────────┘",
    "",
  }
  
  for _, var in ipairs(chain) do
    if memo[var] then
      table.insert(lines, string.format("  %%%s = %s", var, tostring(memo[var])))
    end
  end
  
  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  table.insert(lines, "  Shortcuts: [R]esult  [D]etails  [Q]uit  [Y]ank result")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  
  log("Creating floating window with " .. #lines .. " lines")
  
  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  local width = math.min(80, vim.o.columns - 4)
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
  
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Apply syntax highlighting
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match LLVMVar /%\w\+/]])
    vim.cmd([[syntax match LLVMOp /[+\-*&|^<>]/]])
    vim.cmd([[syntax match LLVMNumber /\d\+/]])
    vim.cmd([[syntax match LLVMSpecial /tid\.x/]])
    vim.cmd([[syntax match LLVMHeader /^[╔╗╚╝║─┌┐└┘│━]/]])
    vim.cmd([[highlight link LLVMVar Identifier]])
    vim.cmd([[highlight link LLVMOp Operator]])
    vim.cmd([[highlight link LLVMNumber Number]])
    vim.cmd([[highlight link LLVMSpecial Special]])
    vim.cmd([[highlight link LLVMHeader Comment]])
  end)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Store result for yanking
  local yank_text = string.format("%%%s = %s", target_var, tostring(result))
  
  -- Enhanced keybindings
  local keymaps = {
    -- Quit shortcuts
    { 'n', 'q', ':close<CR>', 'Quit' },
    { 'n', 'Q', ':close<CR>', 'Quit' },
    { 'n', '<Esc>', ':close<CR>', 'Quit' },
    
    -- Navigation shortcuts
    { 'n', 'r', ':normal! 8G<CR>', 'Jump to Result' },
    { 'n', 'R', ':normal! 8G<CR>', 'Jump to Result' },
    { 'n', 'd', ':normal! 14G<CR>', 'Jump to Details' },
    { 'n', 'D', ':normal! 14G<CR>', 'Jump to Details' },
    { 'n', 'gg', ':normal! 8G<CR>', 'Jump to Result' },
    { 'n', 'G', ':normal! G<CR>', 'Jump to Bottom' },
    
    -- Yank result
    { 'n', 'y', string.format(':let @+ = "%s"<CR>:let @" = "%s"<CR>:echo "Result copied!"<CR>', 
      yank_text:gsub('"', '\\"'), yank_text:gsub('"', '\\"')), 'Yank result' },
    { 'n', 'Y', string.format(':let @+ = "%s"<CR>:let @" = "%s"<CR>:echo "Result copied!"<CR>', 
      yank_text:gsub('"', '\\"'), yank_text:gsub('"', '\\"')), 'Yank result' },
  }
  
  for _, keymap in ipairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf, keymap[1], keymap[2], keymap[3], 
      { noremap = true, silent = true })
  end
  
  -- Position cursor at the result line (line 9)
  vim.api.nvim_win_set_cursor(win, {9, 0})
  
  log("=== Simplification complete ===")
end

-- Quick preview in command line
function M.preview()
  local target_var = get_var_under_cursor()
  
  if not target_var then
    print("No variable found under cursor")
    return
  end
  
  local vars = build_tree()
  if not vars[target_var] then
    print("Variable %" .. target_var .. " not found")
    return
  end
  
  local memo = {}
  local result = simplify(target_var, vars, memo)
  
  print(string.format("%%%s = %s", target_var, tostring(result)))
end

-- Show only the final result in a minimal window
function M.show_result_only()
  local target_var = get_var_under_cursor()
  
  if not target_var then
    vim.notify("No variable found under cursor", vim.log.levels.WARN)
    return
  end
  
  local vars = build_tree()
  if not vars[target_var] then
    vim.notify("Variable %" .. target_var .. " not found", vim.log.levels.ERROR)
    return
  end
  
  local memo = {}
  local result = simplify(target_var, vars, memo)
  
  -- Create a minimal floating window with just the result
  local result_text = string.format("%%%s = %s", target_var, tostring(result))
  
  local lines = {
    "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓",
    "┃  🎯 Simplified Result                                     ┃",
    "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛",
    "",
    "  " .. result_text,
    "",
    "  Press 'q' to close, 'y' to copy, 'd' for details",
  }
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  local width = 60
  local height = #lines
  local opts = {
    relative = 'cursor',
    width = width,
    height = height,
    col = 0,
    row = 1,
    style = 'minimal',
    border = 'rounded',
  }
  
  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Keybindings
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'd', ':close<CR>:LLVMSimplify<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'y', 
    string.format(':let @+ = "%s"<CR>:let @" = "%s"<CR>:echo "Result copied!"<CR>', 
      result_text:gsub('"', '\\"'), result_text:gsub('"', '\\"')), 
    { noremap = true, silent = true })
end

-- Toggle debug mode
function M.toggle_debug()
  M.debug = not M.debug
  vim.notify("LLVM Simplifier debug mode: " .. (M.debug and "ON" or "OFF"), vim.log.levels.INFO)
end

-- Setup command
function M.setup()
  vim.api.nvim_create_user_command('LLVMSimplify', M.simplify, {})
  vim.api.nvim_create_user_command('LLVMPreview', M.preview, {})
  vim.api.nvim_create_user_command('LLVMResult', M.show_result_only, {})
  vim.api.nvim_create_user_command('LLVMDebug', M.toggle_debug, {})
  
  -- Add keybindings
  lvim.keys.normal_mode["<leader>simf"] = ":LLVMSimplify<CR>"     -- Full details
  lvim.keys.normal_mode["<leader>simr"] = ":LLVMResult<CR>"       -- Result only
  lvim.keys.normal_mode["<leader>simp"] = ":LLVMPreview<CR>"      -- Command line preview
  
  vim.notify("🎯 LLVM Simplifier loaded! (by @minisparrow)\n" ..
    "  <leader>simf - Full analysis\n" ..
    "  <leader>simr - Quick result\n" ..
    "  <leader>simp - CLI preview\n" ..
    "  Inside window: r=result, d=details, y=copy, q=quit", 
    vim.log.levels.INFO)
end

return M
--    -- LLVM IR Expression Simplifier for LunarVim
--    -- Usage: Place cursor on a %variable, then run :LLVMSimplify or press <leader>ls
--    -- Debug version with verbose logging
--    
--    local M = {}
--    
--    -- Debug flag
--    M.debug = true
--    
--    local function log(msg)
--      if M.debug then
--        print("[LLVM-Simplifier] " .. msg)
--      end
--    end
--    
--    -- Expression node structure
--    local function create_node(op, left, right, value)
--      return {
--        op = op,
--        left = left,
--        right = right,
--        value = value
--      }
--    end
--    
--    -- Get the variable under cursor (starting with %)
--    local function get_var_under_cursor()
--      local line = vim.api.nvim_get_current_line()
--      local col = vim.api.nvim_win_get_cursor(0)[2] + 1  -- Lua is 1-indexed
--      
--      log("Current line: " .. line)
--      log("Cursor column: " .. col)
--      
--      -- Try to find % before or at cursor position
--      local var = nil
--      
--      -- Pattern 1: Extract from current position backwards
--      local before = line:sub(1, col)
--      local match = before:match(".*%%(%w+)[^%w]*$")
--      if match then
--        var = match
--        log("Found variable (backward search): " .. var)
--        return var
--      end
--      
--      -- Pattern 2: Extract from current position forward
--      local after = line:sub(col)
--      match = after:match("^[^%w]*%%(%w+)")
--      if match then
--        var = match
--        log("Found variable (forward search): " .. var)
--        return var
--      end
--      
--      -- Pattern 3: Try to find any %variable in the line
--      match = line:match("%%(%w+)")
--      if match then
--        var = match
--        log("Found variable (line search): " .. var)
--        return var
--      end
--      
--      log("No variable found")
--      return nil
--    end
--    
--    -- Parse a single line to extract variable and expression
--    local function parse_line(line)
--      -- Remove tree characters
--      line = line:gsub("^[│├└─ ]+", "")
--      
--      -- Match patterns like: %43 = llvm.add %29, %0 : i32
--      local var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+),%s*%%(%w+)")
--      if var then
--        log(string.format("Parsed: %%%s = %s %%%s, %%%s", var, op, arg1, arg2))
--        return var, op, arg1, arg2
--      end
--      
--      -- Match disjoint or pattern: %24 = llvm.or disjoint %21, %23 : i32
--      var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+),%s*%%(%w+)")
--      if var then
--        log(string.format("Parsed: %%%s = or %%%s, %%%s", var, arg1, arg2))
--        return var, "or", arg1, arg2
--      end
--      
--      -- Match constant patterns: %0 = llvm.mlir.constant(123 : i32) : i32
--      var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
--      if var then
--        log(string.format("Parsed: %%%s = const %s", var, arg1))
--        return var, "const", arg1, nil
--      end
--      
--      -- Match special patterns like nvvm.read.ptx.sreg.tid.x
--      var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
--      if var then
--        log(string.format("Parsed: %%%s = tid.x", var))
--        return var, "tid.x", nil, nil
--      end
--      
--      return nil
--    end
--    
--    -- Build expression tree from buffer content
--    local function build_tree()
--      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
--      local vars = {}
--      local count = 0
--      
--      log("Building tree from " .. #lines .. " lines")
--      
--      for i, line in ipairs(lines) do
--        local var, op, arg1, arg2 = parse_line(line)
--        if var then
--          count = count + 1
--          if op == "const" then
--            vars[var] = create_node("const", nil, nil, tonumber(arg1))
--          elseif op == "tid.x" then
--            vars[var] = create_node("tid.x", nil, nil, "tid.x")
--          else
--            vars[var] = create_node(op, arg1, arg2, nil)
--          end
--        end
--      end
--      
--      log("Built tree with " .. count .. " variables")
--      return vars
--    end
--    
--    -- Safe bit operations (fallback if bit library not available)
--    local function bxor(a, b)
--      if bit and bit.bxor then
--        return bit.bxor(a, b)
--      end
--      -- Fallback implementation
--      local result = 0
--      local bit_val = 1
--      while a > 0 or b > 0 do
--        if (a % 2) ~= (b % 2) then
--          result = result + bit_val
--        end
--        a = math.floor(a / 2)
--        b = math.floor(b / 2)
--        bit_val = bit_val * 2
--      end
--      return result
--    end
--    
--    local function bor(a, b)
--      if bit and bit.bor then
--        return bit.bor(a, b)
--      end
--      local result = 0
--      local bit_val = 1
--      while a > 0 or b > 0 do
--        if (a % 2) == 1 or (b % 2) == 1 then
--          result = result + bit_val
--        end
--        a = math.floor(a / 2)
--        b = math.floor(b / 2)
--        bit_val = bit_val * 2
--      end
--      return result
--    end
--    
--    local function band(a, b)
--      if bit and bit.band then
--        return bit.band(a, b)
--      end
--      local result = 0
--      local bit_val = 1
--      while a > 0 and b > 0 do
--        if (a % 2) == 1 and (b % 2) == 1 then
--          result = result + bit_val
--        end
--        a = math.floor(a / 2)
--        b = math.floor(b / 2)
--        bit_val = bit_val * 2
--      end
--      return result
--    end
--    
--    local function lshift(a, b)
--      if bit and bit.lshift then
--        return bit.lshift(a, b)
--      end
--      return a * (2 ^ b)
--    end
--    
--    -- Simplify expression recursively
--    local function simplify(var, vars, memo, depth)
--      depth = depth or 0
--      if depth > 100 then
--        log("Recursion limit reached for %" .. var)
--        return "recursion_limit"
--      end
--      
--      if memo[var] then
--        return memo[var]
--      end
--      
--      local node = vars[var]
--      if not node then
--        log("Variable %" .. var .. " not found in tree")
--        return "%" .. var
--      end
--      
--      log("Simplifying %" .. var .. " (op: " .. node.op .. ")")
--      
--      if node.op == "const" then
--        memo[var] = node.value
--        return node.value
--      end
--      
--      if node.op == "tid.x" then
--        memo[var] = "tid.x"
--        return "tid.x"
--      end
--      
--      -- Recursively simplify operands
--      local left = simplify(node.left, vars, memo, depth + 1)
--      local right = node.right and simplify(node.right, vars, memo, depth + 1) or nil
--      
--      log(string.format("  %%%s: left=%s, right=%s", var, tostring(left), tostring(right or "nil")))
--      
--      -- Apply operations
--      if node.op == "add" then
--        if type(left) == "number" and type(right) == "number" then
--          memo[var] = left + right
--          return left + right
--        elseif left == 0 then
--          memo[var] = right
--          return right
--        elseif right == 0 then
--          memo[var] = left
--          return left
--        else
--          local result = string.format("(%s + %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "xor" then
--        if type(left) == "number" and type(right) == "number" then
--          local result = bxor(left, right)
--          memo[var] = result
--          return result
--        elseif left == 0 then
--          memo[var] = right
--          return right
--        elseif right == 0 then
--          memo[var] = left
--          return left
--        else
--          local result = string.format("(%s ^ %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "or" then
--        if type(left) == "number" and type(right) == "number" then
--          local result = bor(left, right)
--          memo[var] = result
--          return result
--        elseif left == 0 then
--          memo[var] = right
--          return right
--        elseif right == 0 then
--          memo[var] = left
--          return left
--        else
--          local result = string.format("(%s | %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "and" then
--        if type(left) == "number" and type(right) == "number" then
--          local result = band(left, right)
--          memo[var] = result
--          return result
--        elseif left == 0 or right == 0 then
--          memo[var] = 0
--          return 0
--        else
--          local result = string.format("(%s & %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "shl" then
--        if type(left) == "number" and type(right) == "number" then
--          local result = lshift(left, right)
--          memo[var] = result
--          return result
--        elseif right == 0 then
--          memo[var] = left
--          return left
--        elseif left == 0 then
--          memo[var] = 0
--          return 0
--        else
--          local result = string.format("(%s << %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "sub" then
--        if type(left) == "number" and type(right) == "number" then
--          memo[var] = left - right
--          return left - right
--        elseif right == 0 then
--          memo[var] = left
--          return left
--        else
--          local result = string.format("(%s - %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--        
--      elseif node.op == "mul" then
--        if type(left) == "number" and type(right) == "number" then
--          memo[var] = left * right
--          return left * right
--        elseif left == 0 or right == 0 then
--          memo[var] = 0
--          return 0
--        elseif left == 1 then
--          memo[var] = right
--          return right
--        elseif right == 1 then
--          memo[var] = left
--          return left
--        else
--          local result = string.format("(%s * %s)", tostring(left), tostring(right))
--          memo[var] = result
--          return result
--        end
--      end
--      
--      local result = string.format("unknown_op_%s(%s, %s)", node.op, tostring(left), tostring(right or ""))
--      memo[var] = result
--      return result
--    end
--    
--    -- Collect dependency chain
--    local function get_dependency_chain(var, vars, chain, visited)
--      chain = chain or {}
--      visited = visited or {}
--      
--      if visited[var] then
--        return chain
--      end
--      visited[var] = true
--      
--      local node = vars[var]
--      
--      if not node or node.op == "const" or node.op == "tid.x" then
--        return chain
--      end
--      
--      if node.left then
--        get_dependency_chain(node.left, vars, chain, visited)
--      end
--      if node.right then
--        get_dependency_chain(node.right, vars, chain, visited)
--      end
--      
--      table.insert(chain, var)
--      
--      return chain
--    end
--    
--    -- Main function to simplify the expression under cursor
--    function M.simplify()
--      log("=== Starting simplification ===")
--      
--      local target_var = get_var_under_cursor()
--      
--      if not target_var then
--        vim.notify("No variable (starting with %) found under cursor", vim.log.levels.WARN)
--        log("Failed: No variable found")
--        return
--      end
--      
--      log("Target variable: %" .. target_var)
--      
--      local vars = build_tree()
--      
--      if not vars[target_var] then
--        local available = {}
--        for k, _ in pairs(vars) do
--          table.insert(available, k)
--        end
--        table.sort(available)
--        
--        local msg = string.format("Variable %%%s not found in buffer.\nAvailable variables: %s", 
--                                  target_var, table.concat(available, ", "))
--        vim.notify(msg, vim.log.levels.ERROR)
--        log("Failed: Variable not found. Available: " .. table.concat(available, ", "))
--        return
--      end
--      
--      log("Starting simplification...")
--      local memo = {}
--      local result = simplify(target_var, vars, memo)
--      log("Simplification result: " .. tostring(result))
--      
--      -- Get dependency chain
--      local chain = get_dependency_chain(target_var, vars)
--      table.sort(chain, function(a, b) 
--        local num_a = tonumber(a)
--        local num_b = tonumber(b)
--        if num_a and num_b then
--          return num_a < num_b
--        end
--        return a < b
--      end)
--      
--      log("Dependency chain length: " .. #chain)
--      
--      -- Display result in a floating window
--      local lines = {
--        "═══════════════════════════════════════════════════════════",
--        "  LLVM IR Expression Simplifier",
--        "═══════════════════════════════════════════════════════════",
--        "",
--        string.format("Target: %%%s", target_var),
--        "",
--        "Simplified Result:",
--        string.format("  %%%s = %s", target_var, tostring(result)),
--        "",
--        "───────────────────────────────────────────────────────────",
--        "Dependency Chain:",
--        "───────────────────────────────────────────────────────────",
--      }
--      
--      for _, var in ipairs(chain) do
--        if memo[var] then
--          table.insert(lines, string.format("  %%%s = %s", var, tostring(memo[var])))
--        end
--      end
--      
--      table.insert(lines, "")
--      table.insert(lines, "Press 'q' or <Esc> to close")
--      
--      log("Creating floating window with " .. #lines .. " lines")
--      
--      -- Create floating window
--      local buf = vim.api.nvim_create_buf(false, true)
--      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
--      vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
--      vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
--      
--      local width = math.min(80, vim.o.columns - 4)
--      local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
--      local opts = {
--        relative = 'editor',
--        width = width,
--        height = height,
--        col = math.floor((vim.o.columns - width) / 2),
--        row = math.floor((vim.o.lines - height) / 2),
--        style = 'minimal',
--        border = 'rounded',
--      }
--      
--      local win = vim.api.nvim_open_win(buf, true, opts)
--      
--      vim.api.nvim_buf_set_option(buf, 'modifiable', false)
--      
--      -- Keybindings for the floating window
--      vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
--      vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })
--      vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', ':close<CR>', { noremap = true, silent = true })
--      
--      log("=== Simplification complete ===")
--    end
--    
--    -- Quick preview in command line
--    function M.preview()
--      local target_var = get_var_under_cursor()
--      
--      if not target_var then
--        print("No variable found under cursor")
--        return
--      end
--      
--      local vars = build_tree()
--      if not vars[target_var] then
--        print("Variable %" .. target_var .. " not found")
--        return
--      end
--      
--      local memo = {}
--      local result = simplify(target_var, vars, memo)
--      
--      print(string.format("%%%s = %s", target_var, tostring(result)))
--    end
--    
--    -- Toggle debug mode
--    function M.toggle_debug()
--      M.debug = not M.debug
--      vim.notify("LLVM Simplifier debug mode: " .. (M.debug and "ON" or "OFF"), vim.log.levels.INFO)
--    end
--    
--    -- Setup command
--    function M.setup()
--      vim.api.nvim_create_user_command('LLVMSimplify', M.simplify, {})
--      vim.api.nvim_create_user_command('LLVMPreview', M.preview, {})
--      vim.api.nvim_create_user_command('LLVMDebug', M.toggle_debug, {})
--      
--      -- Add keybindings
--      lvim.keys.normal_mode["<leader>ls"] = ":LLVMSimplify<CR>"
--      lvim.keys.normal_mode["<leader>lp"] = ":LLVMPreview<CR>"
--      
--      vim.notify("LLVM Simplifier loaded!\n  <leader>ls - Simplify\n  <leader>lp - Quick preview\n  :LLVMDebug - Toggle debug", vim.log.levels.INFO)
--    end
--    
--    return M

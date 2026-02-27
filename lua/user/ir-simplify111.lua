-- LLVM IR Expression Simplifier for LunarVim
-- Version: 4.7 - Bitcast keeps variable ref + Fix cursor & indices
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

local function log(msg) if M.debug then print("[LLVM] " .. msg) end end

local function create_node(op, left, right, value, extra)
  return { op = op, left = left, right = right, value = value, extra = extra }
end

-- [FIXED] 精确识别光标下的变量
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1 
  
  local current_idx = 1
  while true do
    -- 查找下一个 %var
    local s, e, var_name = line:find("%%([%w_%.]+)", current_idx)
    if not s then break end
    
    -- 判断光标是否在范围内 [s, e]
    if col >= s and col <= e then
      return var_name
    end
    current_idx = e + 1
  end
  return nil
end

local function parse_line(line)
  line = line:gsub("^[│├└─ ]+", "")
  local var, cond, true_val, false_val = line:match("%%(%w+)%s*=%s*llvm%.select%s+(%%?%w+)%s*,%s*(%%?%w+)%s*,%s*(%%?%w+)")
  if var then return var, "select", cond:gsub("^%%",""), true_val:gsub("^%%",""), false_val:gsub("^%%","") end
  
  local var, pred, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.icmp%s+\"([^\"]+)\"%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var then return var, "icmp", arg1:gsub("^%%",""), arg2:gsub("^%%",""), pred end
  
  -- insertvalue
  local var, aggregate, value, indices = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if var then return var, "insertvalue", aggregate:gsub("^%%",""), value:gsub("^%%",""), indices end
  
  -- extractvalue
  local var, aggregate, indices = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[([^%]]+)%]")
  if var then return var, "extractvalue", aggregate:gsub("^%%",""), indices end
  
  -- getelementptr
  local var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then return var, "getelementptr", base, index:gsub("^%%","") end
  var, base, index = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var then return var, "getelementptr", base, index:gsub("^%%","") end
  
  local var, symbol = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if var then return var, "addressof", symbol end
  
  local var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if var then return var, "ldmatrix", arg:gsub("^%%","") end
  
  -- insertelement
  local var, vec, val, idx = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then return var, "insertelement", vec:gsub("^%%",""), val:gsub("^%%",""), idx:gsub("^%%","") end
  
  -- extractelement
  local var, aggregate, idx = line:match("%%(%w+)%s*=%s*llvm%.extractelement%s+(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
  if var then return var, "extractelement", aggregate:gsub("^%%",""), idx:gsub("^%%","") end
  
  -- bitcast
  local var, arg, from_t, to_t = line:match("%%(%w+)%s*=%s*llvm%.bitcast%s+(%%?%w+)%s*:%s*([%w<>]+)%s+to%s+([%w<>]+)")
  if var then return var, "bitcast", arg:gsub("^%%",""), nil, {from=from_t, to=to_t} end
  
  local var, op, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.(%w+)%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then return var, op, arg1, arg2 end
  
  local var, arg1, arg2 = line:match("%%(%w+)%s*=%s*llvm%.or%s+disjoint%s+%%(%w+)%s*,%s*%%(%w+)")
  if var then return var, "or", arg1, arg2 end
  
  local var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(true%)")
  if var then return var, "const", true end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(false%)")
  if var then return var, "const", false end
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if var then return var, "undef", nil, nil end
  local var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d+)%s*:")
  if var then return var, "const", arg1, nil end
  local var, arg1 = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d*%.?%d+[eE]?[%-]?%d*)%s*:%s*f")
  if var then return var, "const", arg1, nil end
  local var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if var then return var, "tid.x", nil, nil end
  
  return nil
end

local function build_tree()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  for i, line in ipairs(lines) do
    local var, op, arg1, arg2, extra = parse_line(line)
    if var then
      if op == "const" then vars[var] = create_node("const", nil, nil, arg1 == "true" and true or (arg1 == "false" and false or (tonumber(arg1) or arg1)))
      elseif op == "tid.x" then vars[var] = create_node("tid.x", nil, nil, "tid.x")
      elseif op == "undef" then vars[var] = create_node("undef", nil, nil, "undef")
      elseif op == "addressof" then vars[var] = create_node("addressof", nil, nil, arg1)
      elseif op == "select" then vars[var] = create_node("select", arg1, arg2, nil, extra)
      elseif op == "icmp" then vars[var] = create_node("icmp", arg1, arg2, nil, extra)
      elseif op == "getelementptr" then vars[var] = create_node("getelementptr", arg1, arg2, nil)
      elseif op == "ldmatrix" then vars[var] = create_node("ldmatrix", arg1, nil, nil)
      elseif op == "insertelement" then vars[var] = create_node("insertelement", arg1, arg2, nil, extra)
      elseif op == "extractelement" then vars[var] = create_node("extractelement", arg1, arg2, nil)
      elseif op == "extractvalue" then vars[var] = create_node("extractvalue", arg1, arg2, nil)
      elseif op == "insertvalue" then vars[var] = create_node("insertvalue", arg1, arg2, nil, extra)
      elseif op == "bitcast" then vars[var] = create_node("bitcast", arg1, nil, nil, extra)
      else vars[var] = create_node(op, arg1, arg2, nil) end
    end
  end
  return vars
end

local function lshift(a, b)
    if bit and bit.lshift then return bit.lshift(a, b) end
    return a * (2 ^ b)
end

local function value_to_string(val, depth)
  depth = depth or 0
  if depth > 10 then return "..." end
  if type(val) == "number" or type(val) == "boolean" then return tostring(val) end
  if type(val) == "string" then 
    if val:match("^%d+$") then return "%" .. val end
    return val 
  end
  if type(val) ~= "table" then return tostring(val) end
  
  if val.op == "addressof" then return string.format("@%s", tostring(val.value))
  elseif val.op == "select" then return string.format("select(%s ? %s : %s)", value_to_string(val.left, depth+1), value_to_string(val.right, depth+1), value_to_string(val.extra, depth+1))
  elseif val.op == "icmp" then return string.format("icmp_%s(%s, %s)", tostring(val.extra), value_to_string(val.left, depth+1), value_to_string(val.right, depth+1))
  elseif val.op == "getelementptr" then 
    local base = type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1)
    local idx = type(val.right)=="string" and ("%"..val.right) or value_to_string(val.right, depth+1)
    return string.format("getelementptr(%s, %s)", base, idx)
  elseif val.op == "ldmatrix" then return string.format("ldmatrix(%s)", type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1))
  elseif val.op == "insertvalue" then
    local agg = type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1)
    local v = type(val.right)=="string" and ("%"..val.right) or value_to_string(val.right, depth+1)
    return string.format("insertvalue(%s, %s[%s])", agg, v, tostring(val.extra))
  elseif val.op == "extractvalue" then
    local agg = type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1)
    return string.format("extractvalue(%s[%s])", agg, tostring(val.right))
  -- [FIX] Bitcast string format with raw variable support
  elseif val.op == "bitcast" then
    local arg_str = type(val.left) == "string" and ("%" .. val.left) or value_to_string(val.left, depth+1)
    local type_info = (type(val.extra) == "table" and val.extra.to) or "?"
    return string.format("bitcast(%s -> %s)", arg_str, type_info)
  elseif val.op == "insertelement" then
    local vec = type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1)
    local v = type(val.right)=="string" and ("%"..val.right) or value_to_string(val.right, depth+1)
    local idx = type(val.extra)=="string" and ("%"..val.extra) or tostring(val.extra)
    return string.format("insertelement(%s, %s[%s])", vec, v, idx)
  elseif val.op == "extractelement" then
    local vec = type(val.left)=="string" and ("%"..val.left) or value_to_string(val.left, depth+1)
    local idx = type(val.right)=="string" and ("%"..val.right) or tostring(val.right)
    return string.format("extractelement(%s[%s])", vec, idx)
  end
  return tostring(val)
end

local function simplify(var, vars, memo, depth)
  depth = depth or 0
  if depth > 100 then return "recursion_limit" end
  if memo[var] then return memo[var] end
  local node = vars[var]
  if not node then return var end
  
  if node.op == "const" then memo[var] = node.value; return node.value end
  if node.op == "tid.x" or node.op == "undef" then memo[var] = node.op; return node.op end
  if node.op == "addressof" then memo[var] = {op="addressof", value=node.value}; return memo[var] end
  
  -- Structural Ops (Preserve References)
  if node.op == "insertvalue" then
      memo[var] = {op="insertvalue", left=node.left, right=node.right, extra=node.extra}
      return memo[var]
  end
  if node.op == "extractvalue" then
      memo[var] = {op="extractvalue", left=node.left, right=node.right}
      return memo[var]
  end
  if node.op == "getelementptr" then
    memo[var] = { op = "getelementptr", left = node.left, right = node.right }
    return memo[var]
  end
  if node.op == "ldmatrix" then
    memo[var] = { op = "ldmatrix", left = node.left }
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
  
  -- [CHANGED] Bitcast now preserves references (no recursive simplify)
  if node.op == "bitcast" then
    memo[var] = { op = "bitcast", left = node.left, extra = node.extra }
    return memo[var]
  end
  
  -- Recursive Arithmetic
  local left = node.left and simplify(node.left, vars, memo, depth + 1) or nil
  local right = node.right and simplify(node.right, vars, memo, depth + 1) or nil
  
  -- Handle simple arithmetic
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
  
  -- Fallback
  if right then memo[var] = string.format("(%s %s %s)", value_to_string(left), node.op, value_to_string(right))
  else memo[var] = string.format("%s %s", node.op, value_to_string(left)) end
  return memo[var]
end

-- ==========================================================
-- [NEW] 辅助函数：判断节点是否为简单常数/原子节点
-- ==========================================================
local function is_simple_node(id, vars)
    local node = vars[id]
    if not node then return false end
    
    -- 定义哪些操作符被视为“简单/常数”节点，应该优先显示
    local simple_ops = {
        ["const"] = true,       -- 常数
        ["tid.x"] = true,       -- 线程ID (视作环境常数)
        ["undef"] = true,       -- 未定义
        ["addressof"] = true,   -- 地址引用 (通常只有一行)
        ["ldmatrix"] = true,    -- 视情况而定，如果它不展开通常很短
    }
    
    return simple_ops[node.op] or false
end

-- ==========================================================
-- [MODIFIED] Build Dependency Tree (常数优先排序 + Suffix Labels)
-- ==========================================================
local function build_dependency_tree(var, vars, memo, visited, indent_prefix, child_prefix, lines, path, label)
    visited = visited or {}
    indent_prefix = indent_prefix or ""
    child_prefix = child_prefix or ""
    lines = lines or {}
    path = path or {}

    local label_suffix = ""
    if label then
        label_suffix = "  [" .. label .. "]"
    end

    -- Check circular ref
    for _, v in ipairs(path) do
        if v == var then
            local txt = "%" .. var .. " (circular)" .. label_suffix
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

    local display_text = "%" .. var .. " = " .. result_str

    if visited[var] then
        table.insert(lines, indent_prefix .. display_text .. " (see above)" .. label_suffix)
        return lines
    end

    visited[var] = true
    table.insert(lines, indent_prefix .. display_text .. label_suffix)

    if not node then return lines end

    -- 1. 收集子节点，同时记录原始顺序 (idx) 以便在同级比较时保持稳定
    local children = {}
    local counter = 0
    local function add_child(id, lbl)
        counter = counter + 1
        if id and vars[id] then
            table.insert(children, {id = id, label = lbl, idx = counter})
        end
    end

    if node.op == "select" then
        add_child(node.left, "condition")
        add_child(node.right, "true_val")
        add_child(node.extra, "false_val")

    elseif node.op == "icmp" then
        add_child(node.left, "left")
        add_child(node.right, "right")

    elseif node.op == "getelementptr" then
        add_child(node.left, "base")
        add_child(node.right, "index")

    elseif node.op == "ldmatrix" then
        add_child(node.left, "operand")

    elseif node.op == "bitcast" then
        add_child(node.left, "operand")

    elseif node.op == "insertvalue" then
        add_child(node.left, "aggregate")
        add_child(node.right, "value")

    elseif node.op == "extractvalue" then
        add_child(node.left, "aggregate")

    elseif node.op == "insertelement" then
        add_child(node.left, "vector")
        add_child(node.right, "value")
        add_child(node.extra, "index")

    elseif node.op == "extractelement" then
        add_child(node.left, "vector")
        add_child(node.right, "index")

    elseif node.left or node.right then
        add_child(node.left, "left")
        add_child(node.right, "right")
    end

    -- 2. [NEW] 排序子节点：简单节点(常数)优先
    table.sort(children, function(a, b)
        local a_simple = is_simple_node(a.id, vars)
        local b_simple = is_simple_node(b.id, vars)

        if a_simple and not b_simple then
            return true -- a 排在前 (因为它简单)
        elseif not a_simple and b_simple then
            return false -- b 排在前
        else
            return a.idx < b.idx -- 如果同类，保持原始 IR 参数顺序
        end
    end)

    -- 3. 递归生成树
    for i, child in ipairs(children) do
        local is_last = (i == #children)
        local branch = is_last and "└─ " or "├─ "
        local next_child_prefix = child_prefix .. (is_last and "   " or "│  ")
        build_dependency_tree(child.id, vars, memo, visited, child_prefix .. branch, next_child_prefix, lines, new_path, child.label)
    end

    return lines
end

-- 显示依赖树的主函数（已修改为可编辑模式）
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
  table.insert(lines, "  [Editable] You can delete lines or add notes with '#'")
  table.insert(lines, "  Shortcuts: [Q]uit  [Y]ank result  [D]ebug  [W]indow mode")
  
  -- 创建 buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- 创建窗口
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
      relative = 'editor', width = width, height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = 'minimal', border = 'rounded',
    }
    win = vim.api.nvim_open_win(buf, true, opts)
  end
  
  -- 设置语法高亮
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match LLVMVar /%\w\+/]])
    vim.cmd([[syntax match LLVMOp /[+\-*&|^<>]/]])
    vim.cmd([[syntax match LLVMNumber /\d\+/]])
    vim.cmd([[syntax match LLVMSpecial /tid\.x\|undef\|true\|false/]])
    vim.cmd([[syntax match LLVMHeader /^[╔╗╚╝║─┌┐└┘│━├└]/]])
    vim.cmd([[syntax match LLVMTreeChar /[│├└─]/]])
    vim.cmd([[syntax match LLVMLabel /\s\zs\w\+:/]]) 
    -- [新增] 支持用户用 # 写注释
    vim.cmd([[syntax match LLVMUserNote /#.*/]])
    
    vim.cmd([[highlight link LLVMVar Identifier]])
    vim.cmd([[highlight link LLVMOp Operator]])
    vim.cmd([[highlight link LLVMNumber Number]])
    vim.cmd([[highlight link LLVMSpecial Special]])
    vim.cmd([[highlight link LLVMHeader Comment]])
    vim.cmd([[highlight link LLVMTreeChar Comment]])
    vim.cmd([[highlight link LLVMLabel Type]])
    vim.cmd([[highlight link LLVMUserNote Todo]]) -- 注释显示为 Todo 颜色（通常高亮明显）
  end)
  
  -- [修改] 允许修改 Buffer
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  -- 保持 buftype=nofile，这样不会提示保存文件，就是一个草稿纸
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- 按键映射
  local yank_text = string.format("%%%s = %s", target_var, result_str)
  local keymaps = {
    { 'n', 'q', ':close<CR>' },
    -- 注意：ESC 在 insert 模式下是退回到 normal 模式，所以在 normal 模式下才映射为关闭
    { 'n', '<Esc>', ':close<CR>' },
    { 'n', 'y', string.format(':let @+ = "%s"<CR>:echo "Copied!"<CR>', yank_text:gsub('"', '\\"')) },
    { 'n', 'w', ':LLVMToggleWindow<CR>:close<CR>:LLVMDeps<CR>' },
  }
  for _, map in ipairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf, map[1], map[2], map[3], { noremap = true, silent = true })
  end
end

function M.toggle_debug() M.debug = not M.debug; print("LLVM Debug: " .. tostring(M.debug)) end
function M.toggle_window_mode() M.config.use_split_window = not M.config.use_split_window; print("LLVM Window: " .. (M.config.use_split_window and "SPLIT" or "FLOAT")) end

function M.setup(user_config)
  if user_config then for k,v in pairs(user_config) do M.config[k] = v end end
  vim.api.nvim_create_user_command('LLVMDeps', M.show_deps, {})
  vim.api.nvim_create_user_command('LLVMDebug', M.toggle_debug, {})
  vim.api.nvim_create_user_command('LLVMToggleWindow', M.toggle_window_mode, {})
end

return M

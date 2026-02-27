
-- LLVM IR Expression Simplifier for LunarVim
-- Version: 4.8 - Suffix Labels + All Previous Fixes
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
local s, e, var_name = line:find("%%([%w_%.]+)", current_idx)
if not s then break end
if col >= s and col <= e then return var_name end
current_idx = e + 1
end
return nil
end

local function parse_line(line)
line = line:gsub("^[│├└─ ]+", "")
local var, cond, true_val, false_val = line:match("%%(%w+)%s*=%sllvm%.select%s+(%%?%w+)%s,%s*(%%?%w+)%s*,%s*(%%?%w+)")
if var then return var, "select", cond:gsub("^%%",""), true_val:gsub("^%%",""), false_val:gsub("^%%","") end

local var, pred, arg1, arg2 = line:match("%%(%w+)%s*=%sllvm%.icmp%s+"([^\"]+)"%s+(%%?%w+)%s,%s*(%%?%w+)")
if var then return var, "icmp", arg1:gsub("^%%",""), arg2:gsub("^%%",""), pred end

-- insertvalue
local var, aggregate, value, indices = line:match("%%(%w+)%s*=%sllvm%.insertvalue%s+(%%?%w+)%s,%s*(%%?%w+)%s*%[([^%]]+)%]")
if var then return var, "insertvalue", aggregate:gsub("^%%",""), value:gsub("^%%",""), indices end

-- extractvalue
local var, aggregate, indices = line:match("%%(%w+)%s*=%sllvm%.extractvalue%s+(%%?%w+)%s%[([^%]]+)%]")
if var then return var, "extractvalue", aggregate:gsub("^%%",""), indices end

-- getelementptr
local var, base, index = line:match("%%(%w+)%s*=%sllvm%.getelementptr%s+%%(%w+)%s%[%s*(%%?%w+)%s*%]")
if var then return var, "getelementptr", base, index:gsub("^%%","") end
var, base, index = line:match("%%(%w+)%s*=%sllvm%.getelementptr%s+inbounds%s+%%(%w+)%s%[%s*(%%?%w+)%s*%]")
if var then return var, "getelementptr", base, index:gsub("^%%","") end

local var, symbol = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
if var then return var, "addressof", symbol end

local var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
if var then return var, "ldmatrix", arg:gsub("^%%","") end

-- insertelement
local var, vec, val, idx = line:match("%%(%w+)%s*=%sllvm%.insertelement%s+(%%?%w+)%s,%s*(%%?%w+)%s*%[%s*(%%?%w+)%s*:")
if var then return var, "insertelement", vec:gsub("^%%",""), val:gsub("^%%",""), idx:gsub("^%%","") end

-- extractelement
local var, aggregate, idx = line:match("%%(%w+)%s*=%sllvm%.extractelement%s+(%%?%w+)%s%[%s*(%%?%w+)%s*:")
if var then return var, "extractelement", aggregate:gsub("^%%",""), idx:gsub("^%%","") end

-- bitcast
local var, arg, from_t, to_t = line:match("%%(%w+)%s*=%sllvm%.bitcast%s+(%%?%w+)%s:%s*([%w<>]+)%s+to%s+([%w<>]+)")
if var then return var, "bitcast", arg:gsub("^%%",""), nil, {from=from_t, to=to_t} end

local var, op, arg1, arg2 = line:match("%%(%w+)%s*=%sllvm%.(%w+)%s+%%(%w+)%s,%s*%%(%w+)")
if var then return var, op, arg1, arg2 end

local var, arg1, arg2 = line:match("%%(%w+)%s*=%sllvm%.or%s+disjoint%s+%%(%w+)%s,%s*%%(%w+)")
if var then return var, "or", arg1, arg2 end

local var = line:match("%%(%w+)%s*=%sllvm%.mlir%.constant%(true%)")
if var then return var, "const", true end
var = line:match("%%(%w+)%s=%sllvm%.mlir%.constant%(false%)")
if var then return var, "const", false end
var = line:match("%%(%w+)%s=%sllvm%.mlir%.undef")
if var then return var, "undef", nil, nil end
local var, arg1 = line:match("%%(%w+)%s=%sllvm%.mlir%.constant%(([%-]?%d+)%s:")
if var then return var, "const", arg1, nil end
local var, arg1 = line:match("%%(%w+)%s*=%sllvm%.mlir%.constant%(([%-]?%d%.?%d+[eE]?[%-]?%d*)%s*:%sf")
if var then return var, "const", arg1, nil end
local var = line:match("%%(%w+)%s=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
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
-- [FIX] Bitcast format
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

-- Structural Ops
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
-- [FIX] Bitcast preserves ref
if node.op == "bitcast" then
memo[var] = { op = "bitcast", left = node.left, extra = node.extra }
return memo[var]
end

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

if right then memo[var] = string.format("(%s %s %s)", value_to_string(left), node.op, value_to_string(right))
else memo[var] = string.format("%s %s", node.op, value_to_string(left)) end
return memo[var]
end

-- ==========================================================
-- [MODIFIED] Build Dependency Tree (Labels as Suffix)
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

local children = {}

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

elseif node.op == "ldmatrix" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="operand"}) end

elseif node.op == "bitcast" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="operand"}) end

-- [FIX] insertvalue/extractvalue logic
elseif node.op == "insertvalue" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="aggregate"}) end
if node.right and vars[node.right] then table.insert(children, {id=node.right, label="value"}) end

elseif node.op == "extractvalue" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="aggregate"}) end

elseif node.op == "insertelement" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="vector"}) end
if node.right and vars[node.right] then table.insert(children, {id=node.right, label="value"}) end
if node.extra and vars[node.extra] then table.insert(children, {id=node.extra, label="index"}) end

elseif node.op == "extractelement" then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="vector"}) end
if node.right and vars[node.right] then table.insert(children, {id=node.right, label="index"}) end

elseif node.left or node.right then
if node.left and vars[node.left] then table.insert(children, {id=node.left, label="left"}) end
if node.right and vars[node.right] then table.insert(children, {id=node.right, label="right"}) end
end

for i, child in ipairs(children) do
local is_last = (i == #children)
local branch = is_last and "└─ " or "├─ "
local next_child_prefix = child_prefix .. (is_last and "   " or "│  ")
build_dependency_tree(child.id, vars, memo, visited, child_prefix .. branch, next_child_prefix, lines, new_path, child.label)
end

return lines
end

-- ==========================================================
-- 显示 UI (Updated Syntax for Suffix Labels)
-- ==========================================================
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
table.insert(lines, "  [Editable] Delete lines (dd) or add notes (#)")
table.insert(lines, "  Shortcuts: [Q]uit  [Y]ank result  [D]ebug  [W]indow mode")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

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

vim.api.nvim_buf_call(buf, function()
vim.cmd([[syntax match LLVMVar /%\w+/]])
vim.cmd([[syntax match LLVMOp /[+-*&|^<>]/]])
vim.cmd([[syntax match LLVMNumber /\d+/]])
vim.cmd([[syntax match LLVMSpecial /tid.x|undef|true|false/]])
vim.cmd([[syntax match LLVMHeader /^[╔╗╚╝║─┌┐└┘│━├└]/]])
vim.cmd([[syntax match LLVMTreeChar /[│├└─]/]])
-- [MODIFIED] Match labels in brackets at end of line, e.g. [base]
vim.cmd([[syntax match LLVMLabel /\[\w\+\]$/]]) 
vim.cmd([[syntax match LLVMUserNote /#.*/]])

vim.cmd([[highlight link LLVMVar Identifier]])
vim.cmd([[highlight link LLVMOp Operator]])
vim.cmd([[highlight link LLVMNumber Number]])
vim.cmd([[highlight link LLVMSpecial Special]])
vim.cmd([[highlight link LLVMHeader Comment]])
vim.cmd([[highlight link LLVMTreeChar Comment]])
vim.cmd([[highlight link LLVMLabel Type]])
vim.cmd([[highlight link LLVMUserNote Todo]])

end)

vim.api.nvim_buf_set_option(buf, 'modifiable', true)
vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

local yank_text = string.format("%%%s = %s", target_var, result_str)
local keymaps = {
{ 'n', 'q', ':close<CR>' },
{ 'n', '<Esc>', ':close<CR>' },
{ 'n', 'y', string.format(':let @+ = "%s"<CR>:echo "Copied!"<CR>', yank_text:gsub('"', '\"')) },
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

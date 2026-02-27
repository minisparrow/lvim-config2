-- LLVM IR Expression Simplifier for LunarVim
-- Enhanced op support: extractelement, extractvalue, insertelement, bitcast, getelementptr(inbounds), store, nvvm.ldmatrix, addressof, llvm.return, llvm.mlir.global external
-- Author: v7(updated)
-- Version: 2.3

local M = {}

-- Debug flag
M.debug = false

local function log(msg)
  if M.debug then
    print("[LLVM-Simplifier] " .. msg)
  end
end

-- Node constructor
local function create_node(op, left, right, value, extra)
  return {
    op = op,
    left = left,
    right = right,
    value = value,
    extra = extra
  }
end

-- Get variable under cursor (starting with %)
local function get_var_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  -- backward
  local before = line:sub(1, col)
  local match = before:match(".*%%(%w+)[^%w]*$")
  if match then return match end
  -- forward
  local after = line:sub(col)
  match = after:match("^[^%w]*%%(%w+)")
  if match then return match end
  match = line:match("%%(%w+)")
  return match
end

-- Parse a single line for many llvm patterns
local function parse_line(line)
  line = line:gsub("^[│├└─ ]+", "")  -- strip tree chars

  -- global external
  local gname = line:match("llvm%.mlir%.global external @([%w_]+)%(")
  if gname then
    return nil, "global_external", gname
  end

  -- addressof: %1 = llvm.mlir.addressof @global_smem : !llvm.ptr<3>
  local var, sym = line:match("%%(%w+)%s*=%s*llvm%.mlir%.addressof%s+@([%w_]+)")
  if var and sym then
    return var, "addressof", sym
  end

  -- getelementptr inbounds: %39 = llvm.getelementptr inbounds %2[%38]
  var, sym, arg = line:match("%%(%w+)%s*=%s*llvm%.getelementptr%s+inbounds%s+%%(%w+)%s*%[%s*(%%?%w+)%s*%]")
  if var and sym and arg then
    -- arg may be a literal or %var, normalize
    arg = arg:gsub("^%%", "")
    return var, "getelementptr_inbounds", sym, arg
  end

  -- store: llvm.store %70, %39 {alignment = 8 : i64} ...
  local src, dst = line:match("llvm%.store%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if src and dst then
    src = src:gsub("^%%", ""); dst = dst:gsub("^%%", "")
    return nil, "store", src, dst
  end

  -- nvvm.ldmatrix: %146 = nvvm.ldmatrix %145 { ... } : (!llvm.ptr<3>) -> !llvm.struct...
  var, arg = line:match("%%(%w+)%s*=%s*nvvm%.ldmatrix%s+(%%?%w+)")
  if var and arg then arg = arg:gsub("^%%","") ; return var, "ldmatrix", arg end

  -- insertelement: %42 = llvm.insertelement %4, %40[%41 : i32]
  var, vec, val, idx = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[%s*(.-)%s*%]")
  if var and vec and val and idx then
    vec = vec:gsub("^%%",""); val = val:gsub("^%%","")
    idx = idx:match("(%d+)") or idx
    return var, "insertelement", vec, val, idx
  end

  -- extractelement: %51 = llvm.extractelement %48[%50 : i32]
  var, agg, idx = line:match("%%(%w+)%s*=%s*llvm%.extractelement%s+(%%?%w+)%s*%[%s*(.-)%s*%]")
  if var and agg and idx then
    agg = agg:gsub("^%%","")
    idx = idx:match("(%d+)") or idx
    return var, "extractelement", agg, idx
  end

  -- extractvalue: %109 = llvm.extractvalue %108[0]
  var, agg, idx = line:match("%%(%w+)%s*=%s*llvm%.extractvalue%s+(%%?%w+)%s*%[%s*(%d+)%s*%]")
  if var and agg and idx then
    agg = agg:gsub("^%%","")
    return var, "extractvalue", agg, idx
  end

  -- insertvalue: %106 = llvm.insertvalue %2, %105[0]
  var, agg, val, indices = line:match("%%(%w+)%s*=%s*llvm%.insertvalue%s+(%%?%w+)%s*,%s*(%%?%w+)%s*%[([^%]]+)%]")
  if var and agg and val and indices then
    agg = agg:gsub("^%%",""); val = val:gsub("^%%","")
    return var, "insertvalue", agg, val, indices
  end

  -- bitcast: %58 = llvm.bitcast %51 : f16 to i16
  var, arg, fromt, tot = line:match("%%(%w+)%s*=%s*llvm%.bitcast%s+(%%?%w+)%s*:%s*([^%s]+)%s*to%s*([^%s]+)")
  if var and arg and fromt and tot then
    arg = arg:gsub("^%%","")
    return var, "bitcast", arg, {from = fromt, to = tot}
  end

  -- icmp/select handled earlier; treat select already supported.

  -- insertelement/simple vector insertion without bracket spacing:
  var, vec, val = line:match("%%(%w+)%s*=%s*llvm%.insertelement%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var and vec and val then
    vec = vec:gsub("^%%",""); val = val:gsub("^%%","")
    return var, "insertelement_simple", vec, val
  end

  -- llvm.mlir.undef
  var = line:match("%%(%w+)%s*=%s*llvm%.mlir%.undef")
  if var then return var, "undef" end

  -- constant (int or index): %0 = llvm.mlir.constant(0 : index) or numeric
  var, num = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%((%-?%d+)%s*:") 
  if var then return var, "const", tonumber(num) end
  var, num = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%((%-?%d+)%s*%)")
  if var then return var, "const", tonumber(num) end
  -- float const
  var, num = line:match("%%(%w+)%s*=%s*llvm%.mlir%.constant%(([%-]?%d*%.%d+)%s*:%s*f[%d]+%s*%)")
  if var then return var, "const", tonumber(num) end

  -- nvvm.read.ptx.sreg.tid.x
  var = line:match("%%(%w+)%s*=%s*nvvm%.read%.ptx%.sreg%.tid%.x")
  if var then return var, "tid.x" end

  -- generic binary ops: %43 = llvm.mlir.something or llvm.add %a, %b
  var, op, a, b = line:match("%%(%w+)%s*=%s*llvm%.?([%w_]+)%s+(%%?%w+)%s*,%s*(%%?%w+)")
  if var and op and a and b then
    a = a:gsub("^%%",""); b = b:gsub("^%%","")
    return var, op, a, b
  end

  -- simple assignment/catchall: %x = something with one arg
  var, op, a = line:match("%%(%w+)%s*=%s*([%w_.]+)%s+(%%?%w+)")
  if var and op and a then
    a = a:gsub("^%%","")
    return var, op, a
  end

  -- llvm.return
  if line:match("llvm%.return") then
    return nil, "return"
  end

  return nil
end

-- Build node map from buffer
local function build_tree()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local vars = {}
  local count = 0
  for _, line in ipairs(lines) do
    local parsed = { parse_line(line) }
    local var = parsed[1]
    local op = parsed[2]
    if op then
      count = count + 1
      if op == "const" then
        vars[var] = create_node("const", nil, nil, parsed[3])
      elseif op == "tid.x" then
        vars[var] = create_node("tid.x", nil, nil, "tid.x")
      elseif op == "undef" then
        vars[var] = create_node("undef", nil, nil, "undef")
      elseif op == "addressof" then
        vars[var] = create_node("addressof", parsed[3], nil, nil)
      elseif op == "getelementptr_inbounds" then
        vars[var] = create_node("getelementptr_inbounds", parsed[3], parsed[4], nil)
      elseif op == "ldmatrix" then
        vars[var] = create_node("ldmatrix", parsed[3], nil, nil)
      elseif op == "insertelement" or op == "insertelement_simple" then
        -- parsed: var, op, vec, val [, idx]
        vars[var] = create_node("insertelement", parsed[3], parsed[4], nil, parsed[5])
      elseif op == "extractelement" then
        vars[var] = create_node("extractelement", parsed[3], parsed[4], nil)
      elseif op == "extractvalue" then
        vars[var] = create_node("extractvalue", parsed[3], parsed[4], nil)
      elseif op == "insertvalue" then
        vars[var] = create_node("insertvalue", parsed[3], parsed[4], nil, parsed[5])
      elseif op == "bitcast" then
        vars[var] = create_node("bitcast", parsed[3], nil, nil, parsed[4])
      elseif op == "store" then
        -- store has no resulting var; create a pseudo node to show relation
        vars["_store_" .. parsed[3] .. "_to_" .. parsed[4]] = create_node("store", parsed[3], parsed[4], nil)
      elseif op == "return" then
        vars["_return_" .. tostring(count)] = create_node("return", nil, nil, nil)
      elseif op == "ldmatrix" then
        vars[var] = create_node("ldmatrix", parsed[3], nil, nil)
      elseif op == "global_external" then
        -- ignore global
      else
        -- generic op: op, left, right
        if var then
          vars[var] = create_node(op, parsed[3], parsed[4], nil)
        end
      end
    end
  end
  log("Parsed " .. tostring(count) .. " op lines")
  return vars
end

-- value to string rendering (handles nodes and primitives)
local function value_to_string(val, depth)
  depth = depth or 0
  if depth > 12 then return "..." end
  if type(val) == "number" or type(val) == "boolean" then return tostring(val) end
  if type(val) == "string" then return val end
  if type(val) == "table" then
    -- node-like tables: {type='insertvalue', aggregate=..., value=..., indices=...} OR node objects created
    if val.type == "insertvalue" then
      local agg = value_to_string(val.aggregate, depth+1)
      local v = value_to_string(val.value, depth+1)
      return string.format("insertvalue{%s, [%s]=%s}", agg, val.indices, v)
    elseif val.op then
      -- pretty print node summary
      local op = val.op
      if op == "insertelement" then
        return string.format("insertelement(%s, [%s]=%s)", value_to_string(val.left, depth+1), tostring(val.extra or "?"), value_to_string(val.right, depth+1))
      elseif op == "extractelement" then
        return string.format("extractelement(%s[%s])", value_to_string(val.left, depth+1), tostring(val.right))
      elseif op == "extractvalue" then
        return string.format("extractvalue(%s[%s])", value_to_string(val.left, depth+1), tostring(val.right))
      elseif op == "bitcast" then
        local totype = (type(val.extra) == "table" and val.extra.to) or tostring(val.extra)
        return string.format("bitcast(%s -> %s)", value_to_string(val.left, depth+1), totype)
      elseif op == "ldmatrix" then
        return string.format("ldmatrix(%s)", value_to_string(val.left, depth+1))
      elseif op == "addressof" then
        return string.format("addressof(%s)", tostring(val.left))
      elseif op == "insertvalue" then
        -- this is our create_node format earlier; fallback
        return string.format("insertvalue(%s,%s[%s])", value_to_string(val.left, depth+1), value_to_string(val.right or "?", depth+1), tostring(val.extra or "?"))
      else
        -- generic
        if val.left and val.right then
          return string.format("%s(%s, %s)", tostring(val.op), value_to_string(val.left, depth+1), value_to_string(val.right, depth+1))
        elseif val.left then
          return string.format("%s(%s)", tostring(val.op), value_to_string(val.left, depth+1))
        else
          return tostring(val.op)
        end
      end
    else
      -- unknown table
      return tostring(val)
    end
  end
  return tostring(val)
end

-- Simplify recursively (fold constants, propagate known simplifications)
local function simplify(varname, vars, memo, depth)
  depth = depth or 0
  if depth > 200 then return "recursion_limit" end
  if memo[varname] then return memo[varname] end

  local node = vars[varname]
  if not node then
    -- variable may be simple local reference like "3" or "tid.x" literal
    if varname == nil then return nil end
    -- If a raw variable string like "50", or "%50" -> return "%50"
    if tostring(varname):match("^%d+$") then
      memo[varname] = tonumber(varname)
      return tonumber(varname)
    end
    memo[varname] = "%" .. tostring(varname)
    return "%" .. tostring(varname)
  end

  -- If node is primitive (const / tid.x / undef)
  if node.op == "const" then memo[varname] = node.value; return node.value end
  if node.op == "tid.x" then memo[varname] = "tid.x"; return "tid.x" end
  if node.op == "undef" then memo[varname] = "undef"; return "undef" end

  -- Handle insertvalue node object already created (when varname is alias to insertvalue structure)
  if node.op == "insertvalue" then
    local agg = simplify(node.left, vars, memo, depth+1)
    local val = simplify(node.right, vars, memo, depth+1)
    local struct = { type = "insertvalue", aggregate = agg, value = val, indices = node.extra }
    memo[varname] = struct
    return struct
  end

  if node.op == "insertelement" then
    local agg = simplify(node.left, vars, memo, depth+1)
    local val = simplify(node.right, vars, memo, depth+1)
    local t = create_node("insertelement", agg, val, nil, node.extra)
    memo[varname] = t
    return t
  end

  if node.op == "extractelement" then
    local agg = simplify(node.left, vars, memo, depth+1)
    local idx = node.right
    local t = create_node("extractelement", agg, idx, nil)
    memo[varname] = t
    return t
  end

  if node.op == "extractvalue" then
    local agg = simplify(node.left, vars, memo, depth+1)
    local idx = node.right
    local t = create_node("extractvalue", agg, idx, nil)
    memo[varname] = t
    return t
  end

  if node.op == "bitcast" then
    local left = simplify(node.left, vars, memo, depth+1)
    local t = create_node("bitcast", left, nil, nil, node.extra)
    memo[varname] = t
    return t
  end

  if node.op == "getelementptr_inbounds" then
    local base = simplify(node.left, vars, memo, depth+1)
    local idx = node.right
    local t = create_node("getelementptr_inbounds", base, idx, nil)
    memo[varname] = t
    return t
  end

  if node.op == "ldmatrix" then
    local arg = simplify(node.left, vars, memo, depth+1)
    local t = create_node("ldmatrix", arg, nil, nil)
    memo[varname] = t
    return t
  end

  -- Generic binary ops and float ops (fadd already handled in prior versions if named 'fadd')
  local left = node.left and simplify(node.left, vars, memo, depth+1) or nil
  local right = node.right and simplify(node.right, vars, memo, depth+1) or nil

  -- integer ops
  if node.op == "add" and type(left) == "number" and type(right) == "number" then
    memo[varname] = left + right; return left + right
  end
  if node.op == "xor" and type(left) == "number" and type(right) == "number" then
    -- bitwise xor fallback
    local function bxor(a,b) local r=0; local bitv=1; while a>0 or b>0 do if (a%2)~=(b%2) then r=r+bitv end; a=math.floor(a/2); b=math.floor(b/2); bitv=bitv*2 end; return r end
    memo[varname] = bxor(left,right); return memo[varname]
  end

  -- Floating ops (common names might be fadd/fsub)
  if node.op == "fadd" or node.op == "addf" or node.op == "addf" then
    if type(left) == "number" and type(right) == "number" then
      memo[varname] = left + right; return memo[varname]
    end
    memo[varname] = string.format("(%s +f %s)", value_to_string(left), value_to_string(right)); return memo[varname]
  end

  -- fallback: return a node object to be pretty-printed later
  local t = create_node(node.op, left, right, nil, node.extra)
  memo[varname] = t
  return t
end

-- Collect dependency chain (in order)
local function get_dependency_chain(target, vars, chain, visited)
  chain = chain or {}
  visited = visited or {}
  if visited[target] then return chain end
  visited[target] = true
  local node = vars[target]
  if not node then return chain end
  if node.left then
    get_dependency_chain(node.left, vars, chain, visited)
  end
  if node.right then
    get_dependency_chain(node.right, vars, chain, visited)
  end
  table.insert(chain, target)
  return chain
end

-- Main simplify entry
function M.simplify()
  local target = get_var_under_cursor()
  if not target then vim.notify("No %var under cursor", vim.log.levels.WARN); return end
  local vars = build_tree()
  if not vars[target] then
    -- if target might be a defined variable that wasn't matched exactly, still try to simplify if present as key
    local available = {}
    for k,_ in pairs(vars) do table.insert(available,k) end
    table.sort(available)
    vim.notify("Variable %" .. target .. " not found. Available: " .. table.concat(available, ", "), vim.log.levels.ERROR)
    return
  end
  local memo = {}
  local result = simplify(target, vars, memo)
  local result_str = value_to_string(result)

  -- build display lines
  local chain = get_dependency_chain(target, vars)
  table.sort(chain, function(a,b) local na= tonumber(a); local nb=tonumber(b); if na and nb then return na<nb end return a<b end)

  local lines = {
    "╔═══════════════════════════════════════════════════════════╗",
    "║           🎯 LLVM IR Expression Simplifier               ║",
    "╚═══════════════════════════════════════════════════════════╝",
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 🔍 FINAL RESULT                                         │",
    "└─────────────────────────────────────────────────────────┘",
    "",
    string.format("  %%%s = %s", target, result_str),
    "",
    "┌─────────────────────────────────────────────────────────┐",
    "│ 📊 Dependency Chain (step by step)                     │",
    "└─────────────────────────────────────────────────────────┘",
    "",
  }

  for _, v in ipairs(chain) do
    if memo[v] then
      table.insert(lines, string.format("  %%%s = %s", v, value_to_string(memo[v])))
    end
  end

  table.insert(lines, "")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  table.insert(lines, "  Shortcuts: [R]esult  [D]etails  [Q]uit  [Y]ank result")
  table.insert(lines, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

  -- floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded'
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap=true, silent=true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap=true, silent=true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'y', string.format(':let @+ = "%s"<CR>:echo "Copied"<CR>', (("%%" .. target .. " = " .. result_str):gsub('"','\\"')) ), { noremap=true, silent=true })

  -- position cursor near result
  vim.api.nvim_win_set_cursor(win, {9, 0})
end

-- minimal preview
function M.preview()
  local target = get_var_under_cursor()
  if not target then print("No %var under cursor"); return end
  local vars = build_tree()
  if not vars[target] then print("Variable %" .. target .. " not found"); return end
  local memo = {}
  local result = simplify(target, vars, memo)
  print(string.format("%%%s = %s", target, value_to_string(result)))
end

function M.setup()
  vim.api.nvim_create_user_command('LLVMSimplify', M.simplify, {})
  vim.api.nvim_create_user_command('LLVMPreview', M.preview, {})
  -- keybindings for lvim (if available)
  if pcall(function() return lvim end) then
    lvim.keys.normal_mode["<leader>lls"] = ":LLVMSimplify<CR>"
    lvim.keys.normal_mode["<leader>llr"] = ":LLVMPreview<CR>"
  end
  vim.notify("LLVM Simplifier v2.3 loaded (extended op support)", vim.log.levels.INFO)
end

return M

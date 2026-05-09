local M = {}

local function insert_sep(result)
  table.insert(result, "")
  table.insert(result, "---")
  table.insert(result, "")
end

local function is_table_line(line)
  return line:match("^%s*|") ~= nil
end

local function is_code_fence(line)
  return line:match("^%s*```") ~= nil
end

local function heading_level(line)
  local hashes = line:match("^(#+)%s")
  return hashes and #hashes or 0
end

local function strip_old_separators(lines)
  local cleaned = {}
  local in_code = false
  local in_frontmatter = false

  -- detect YAML frontmatter
  local fm_end = 0
  if lines[1] and lines[1]:match("^%-%-%-$") then
    for i = 2, #lines do
      if lines[i]:match("^%-%-%-$") then
        fm_end = i
        break
      end
    end
  end

  for i, line in ipairs(lines) do
    if i <= fm_end then
      table.insert(cleaned, line)
    elseif is_code_fence(line) then
      in_code = not in_code
      table.insert(cleaned, line)
    elseif in_code then
      table.insert(cleaned, line)
    elseif is_table_line(line) then
      table.insert(cleaned, line)
    elseif line:match("^%-%-%-$") then
      -- skip old separator
    else
      table.insert(cleaned, line)
    end
  end

  -- collapse consecutive blank lines left behind
  local result = {}
  for _, line in ipairs(cleaned) do
    local prev = result[#result]
    if not (line:match("^%s*$") and prev and prev:match("^%s*$")) then
      table.insert(result, line)
    end
  end
  return result
end

function M.split_slides()
  local buf = vim.api.nvim_get_current_buf()
  local raw_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local lines = strip_old_separators(raw_lines)
  local win_height = vim.api.nvim_win_get_height(0)
  local max_lines = win_height - 2

  -- skip YAML frontmatter
  local start = 1
  if lines[1] and lines[1]:match("^%-%-%-$") then
    for i = 2, #lines do
      if lines[i]:match("^%-%-%-$") then
        start = i + 1
        break
      end
    end
  end

  local result = {}
  for i = 1, start - 1 do
    table.insert(result, lines[i])
  end

  local count = 0
  local i = start
  while i <= #lines do
    local line = lines[i]

    if is_code_fence(line) then
      -- collect entire code block
      local block = { line }
      i = i + 1
      while i <= #lines do
        table.insert(block, lines[i])
        if is_code_fence(lines[i]) then
          break
        end
        i = i + 1
      end
      if count > 0 then
        insert_sep(result)
      end
      for _, l in ipairs(block) do
        table.insert(result, l)
      end
      insert_sep(result)
      count = 0

    elseif is_table_line(line) then
      -- collect entire table
      local block = { line }
      while i + 1 <= #lines and is_table_line(lines[i + 1]) do
        i = i + 1
        table.insert(block, lines[i])
      end
      if count > 0 then
        insert_sep(result)
      end
      for _, l in ipairs(block) do
        table.insert(result, l)
      end
      insert_sep(result)
      count = 0

    elseif line:match("^%s*$") then
      if count >= max_lines then
        table.insert(result, "---")
        table.insert(result, "")
        count = 0
      else
        table.insert(result, line)
        count = count + 1
      end

    elseif heading_level(line) >= 1 then
      local level = heading_level(line)
      if count > 0 then
        insert_sep(result)
      end
      table.insert(result, line)
      if level == 1 then
        insert_sep(result)
        count = 0
      else
        count = 1
      end

    else
      if count >= max_lines then
        insert_sep(result)
        count = 0
      end
      table.insert(result, line)
      count = count + 1
    end

    i = i + 1
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
  vim.notify("Slide separators inserted", vim.log.levels.INFO)
end

return M

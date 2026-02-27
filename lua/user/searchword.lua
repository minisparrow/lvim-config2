local function vimgrep_and_open(keyword)
  local current_position = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_command("vimgrep /" .. keyword .. "/ %")
  vim.api.nvim_command("copen")
  vim.cmd("wincmd p") -- Switch to the previous window
  vim.api.nvim_win_set_cursor(0, current_position)
end

-- 设置一个快捷键，调用上面定义的函数，并传递搜索的关键词
lvim.keys.normal_mode["<leader>swk"] = function()
  local keyword = vim.fn.input("Keyword: ") -- 使用vim.fn.input函数获取用户输入的关键词
  if keyword ~= "" then
    vimgrep_and_open(keyword)
  else
    print("No keyword provided")
  end
end

lvim.keys.normal_mode["<leader>swc"] = function()
  local current_word = vim.fn.expand("<cword>")
  if current_word ~= "" then
    print("Current word: " .. current_word) -- 打印当前光标下的单词
    vimgrep_and_open(current_word)
  else
    print("No word under cursor")
  end
end

-- find_files_with_word_under_cursor
lvim.keys.normal_mode["<leader>swg"] = function()
  local telescope_builtin = require('telescope.builtin')
  -- 获取光标所在的单词并传递给 Telescope
  local word = vim.fn.expand("<cword>")
  telescope_builtin.live_grep({ default_text = word })
end

lvim.keys.normal_mode["<S-s>"] = ":Telescope current_buffer_fuzzy_find<cr>"
lvim.keys.normal_mode["<S-f>"] = ":Telescope find_files<cr>"
lvim.keys.normal_mode["<S-g>"] = ":Telescope live_grep<cr>"

-- Telescope configuration
-- Telescope 搜索预览配置
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ["<C-n>"] = require('telescope.actions').move_selection_next,
        ["<C-p>"] = require('telescope.actions').move_selection_previous,
      },
    },
    layout_strategy = "vertical",
    layout_config = {
      vertical = {
        preview_cutoff = 0,
        mirror = true,              -- 将预览窗口放在底部
        preview_height = 0.4,       -- 设置预览窗口的高度占比
      },
      width = 0.95,                 -- 总宽度占比
      height = 0.8,                 -- 总高度占比
      prompt_position = "top",      -- 提示窗口位置
    },
    sorting_strategy = "ascending", -- 排序方式
  },
  pickers = {
    find_files = {
      layout_strategy = "vertical",
      layout_config = {
        vertical = {
          preview_cutoff = 0,
          mirror = true,        -- 将预览窗口放在底部
          preview_height = 0.8, -- 设置预览窗口的高度占比
        },
      },
    },
    live_grep = {
      layout_strategy = "vertical",
      layout_config = {
        vertical = {
          preview_cutoff = 0,
          mirror = true,        -- 将预览窗口放在底部
          preview_height = 0.4, -- 设置预览窗口的高度占比
        },
      },
    },
  },
}

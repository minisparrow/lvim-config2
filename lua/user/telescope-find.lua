-- Treesitter configuration
require 'nvim-treesitter.configs'.setup {
  highlight = {
    enable = true, -- false will disable the whole extension
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "gnn",
      node_incremental = "grn",
      scope_incremental = "grc",
      node_decremental = "grm",
    },
  },
}

-- Telescope configuration
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
          preview_height = 0.8, -- 设置预览窗口的高度占比
        },
      },
    },
    current_buffer_fuzzy_find = {
      layout_strategy = "vertical",
      layout_config = {
        vertical = {
          preview_cutoff = 0,
          mirror = true,        -- 将预览窗口放在底部
          preview_height = 0.5, -- 设置预览窗口的高度占比
        },
      },
    },
  },
}
lvim.keys.normal_mode["<S-s>"] = ":Telescope current_buffer_fuzzy_find<cr>"
lvim.keys.normal_mode["<S-f>"] = ":Telescope find_files<cr>"
lvim.keys.normal_mode["<S-g>"] = ":Telescope live_grep<cr>"

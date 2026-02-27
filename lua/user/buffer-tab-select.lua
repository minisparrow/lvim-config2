------------------------------------
--tab select
------------------------------------
vim.api.nvim_set_keymap('n', '<leader>1', ':tabnext 1<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>2', ':tabnext 2<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>3', ':tabnext 3<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>4', ':tabnext 4<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>5', ':tabnext 5<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>6', ':tabnext 6<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>7', ':tabnext 7<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>8', ':tabnext 8<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>9', ':tabnext 9<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>0', ':tabnext 0<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>-', ':tabnext -<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>+', ':tabnext +<CR>', { noremap = true, silent = true })
vim.g.airline_extensions_tabline_show_buffers = 1
vim.g.airline_extensions_tabline_buffer_idx_mode = 1
vim.g.airline_extensions_tabline_show_tab_nr = 1 -- 显示tab编号
vim.g.airline_extensions_tabline_enabled = 1
------------------------------------
--buffer select
vim.api.nvim_set_keymap('n', '<leader>sb', ':Buffers<CR>', { noremap = true, silent = true })
------------------------------------

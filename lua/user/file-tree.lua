-- In your plugin list section
local plugins = {
  'kyazdani42/nvim-tree.lua',
}
local keybindings = {
  -- vim.api.nvim_set_keymap('n', '<leader>e', ':NvimTreeToggle<CR>', { noremap = true, silent = true })
}
lvim.keys.normal_mode["<leader>e"] = ":NvimTreeToggle<CR>"

return {
  plugins = plugins,
  keybindings = keybindings,
}

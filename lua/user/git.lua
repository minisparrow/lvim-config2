local plugins = {
  { "tpope/vim-fugitive" },
  { "airblade/vim-gitgutter" },
  { 'rbong/vim-flog' },
}

local keybindings = {
  normal_mode = {
    ["<leader>gb"] = ":Git blame<CR>",
    ["<leader>gs"] = ":Git<CR>",
    ["<leader>gd"] = ":Git diff<CR>",
    ["<leader>gc"] = ":Git commit<CR>",
    ["<leader>gp"] = ":Git push<CR>",
    ["<leader>gt"] = ":Flog <CR>", --看git commit graph
  }
}

return {
  plugins = plugins,
  keybindings = keybindings,
}

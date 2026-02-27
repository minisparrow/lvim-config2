-- Ensure dap and dapui are required properly
local M = {}
local dap = require('dap')

-- Function to add the word under the cursor to the dap watch
function M.add_to_dap_watch()
  local word = vim.fn.expand("<cword>")
  dapui.elements.watches.add(word)
end

-- Function to toggle specific dap-ui element
function M.toggle_element(element)
  -- dapui.close()
  dapui.toggle({ layout = element })
end

lvim.keys.normal_mode["<leader>dwo"] = ":lua require('dapui').toggle()<CR>"
lvim.keys.normal_mode["<leader>dwa"] = ":lua require('user.debug-window').add_to_dap_watch()<CR>"
lvim.keys.normal_mode["<leader>dw1"] = ":lua require('user.debug-window').toggle_element(1)<CR>"
lvim.keys.normal_mode["<leader>dw2"] = ":lua require('user.debug-window').toggle_element(2)<CR>"
lvim.keys.normal_mode["<leader>dw3"] = ":lua require('user.debug-window').toggle_element(3)<CR>"
lvim.keys.normal_mode["<leader>dw4"] = ":lua require('user.debug-window').toggle_element(4)<CR>"
lvim.keys.normal_mode["<leader>dw5"] = ":lua require('user.debug-window').toggle_element(5)<CR>"
lvim.keys.normal_mode["<leader>dw6"] = ":lua require('user.debug-window').toggle_element(6)<CR>"

function open_single_float_element(element)
  -- Close all dap-ui elements
  local dapui = require("dapui")

  -- Open the specific element based on the input
  if element == "watch" then
    local word = vim.fn.expand("<cword>")
    dapui.elements.watches.add(word)
    dapui.float_element("watches", { width = 50, height = 20 })
  elseif element == "breakpoints" then
    dapui.float_element("breakpoints")
  elseif element == "scopes" then
    dapui.float_element("scopes")
  elseif element == "stacks" then
    dapui.float_element("stacks", { width = 50, height = 20 })
  end
end

lvim.keys.normal_mode["<leader>dfw"] = ":lua open_single_float_element('watch')<CR>"
lvim.keys.normal_mode["<leader>dfb"] = ":lua open_single_float_element('breakpoints')<CR>"
lvim.keys.normal_mode["<leader>dfs"] = ":lua open_single_float_element('stacks')<CR>"
lvim.keys.normal_mode["<leader>dfc"] = ":lua open_single_float_element('scopes')<CR>"

return M

vim.opt.clipboard = "unnamedplus"

if vim.env.SSH_CONNECTION then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
else
  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
    vim.g.clipboard = {
      name = "pbcopy",
      copy = { ["+"] = "pbcopy", ["*"] = "pbcopy" },
      paste = { ["+"] = "pbpaste", ["*"] = "pbpaste" },
      cache_enabled = true,
    }
  elseif vim.fn.executable("wl-copy") == 1 then
    vim.g.clipboard = {
      name = "wl-copy",
      copy = { ["+"] = "wl-copy", ["*"] = "wl-copy" },
      paste = { ["+"] = "wl-paste", ["*"] = "wl-paste" },
      cache_enabled = true,
    }
  elseif vim.fn.executable("xclip") == 1 then
    vim.g.clipboard = {
      name = "xclip",
      copy = { ["+"] = "xclip -selection clipboard", ["*"] = "xclip -selection primary" },
      paste = { ["+"] = "xclip -selection clipboard -o", ["*"] = "xclip -selection primary -o" },
      cache_enabled = true,
    }
  end
end

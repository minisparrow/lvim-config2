-- lifunc: formatter
-- clang-format
-- autopep8

vim.g.lvim_format_on_save = true
local null_ls = require("null-ls")
local formatting = null_ls.builtins.formatting

null_ls.setup {
  sources = {
    formatting.clang_format.with({
      extra_args = { "--style=llvm" },
    }),
    formatting.autopep8,
  },
}

vim.cmd [[
augroup FormatAutogroup
  autocmd!
  autocmd BufWritePost *.c,*.cpp,*.h,*.hpp silent! execute '!clang-format -i %'
  autocmd BufWritePost *.py lua vim.lsp.buf.format({ async = true })
augroup END
]]

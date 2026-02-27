-- 添加 clangd LSP 配置
-- 1. cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=1 .. 得到compile_commands.json文件，让vim能找到头文件
-- 2. 或者添加compile_flags.txt文件， 内容是头文件的目录， 如
-- CompileFlags:
--   Add:
--     -Iantlr-generated
--     -Iantlr4-runtime
--     -Iexpression
-- 如此antlr-generated, antlr4-runtime, expression的头文件都可以被vim找到
local lspconfig = require('lspconfig')

lspconfig.clangd.setup {
  cmd = { "clangd" },
  filetypes = { "c", "cpp", "objc", "objcpp" },
  root_dir = lspconfig.util.root_pattern("compile_commands.json", "compile_flags.txt", ".git"),
  on_attach = function(client, bufnr)
    local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
    local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

    buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- 绑定快捷键
    local opts = { noremap = true, silent = true }

    buf_set_keymap('n', 'gd', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
    buf_set_keymap('n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)
    buf_set_keymap('n', 'gi', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    buf_set_keymap('n', '<C-k>', '<Cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
    buf_set_keymap('n', '<space>wa', '<Cmd>lua vim.lsp.buf.add_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<space>wr', '<Cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>', opts)
    buf_set_keymap('n', '<space>wl', '<Cmd>lua vim.lsp.buf.list_workspace_folders()<CR>', opts)
    buf_set_keymap('n', '<space>D', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    buf_set_keymap('n', '<space>rn', '<Cmd>lua vim.lsp.buf.rename()<CR>', opts)
    buf_set_keymap('n', 'gr', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)
    -- buf_set_keymap('n', '<space>e', '<Cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
    buf_set_keymap('n', '[d', '<Cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
    buf_set_keymap('n', ']d', '<Cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
    buf_set_keymap('n', '<space>q', '<Cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
    -- buf_set_keymap('n', '<space>f', '<Cmd>lua vim.lsp.buf.formatting()<CR>', opts)
  end
}

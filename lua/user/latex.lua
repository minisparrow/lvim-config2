-- Default tex file format
vim.g.tex_flavor = 'latex'
-- 配置tex的编译器latexmk和pdf阅读器zathura(也可以替换为其他pdf阅读器,如evince)
-- 需要在本地提前安装好latexmk和zathura
--
--========================================
-- reader option 1: zathura
--========================================
-- -- pdf reader begin
-- -- macos may have issues when inverse search with dbus issue, so macos use skim reader
-- vim.g.vimtex_view_method = 'zathura'
-- -- vim.g.vimtex_view_general_viewer = '/opt/homebrew/bin/zathura'
-- vim.g.vimtex_view_general_options = '--synctex-forward @line:@col @"%pdf" @"%tex" --fork'
-- -- pdf reader end
--========================================

--========================================
-- reader option 2: skim
--========================================
-- pdf reader begin
-- # Choose which program to use to view PDF file
vim.g.vimtex_view_method = 'skim'
-- # Value 1 allows forward search after every successful compilation
vim.g.vimtex_view_skim_sync = 1
-- # Value 1 allows change focus to skim after command `:VimtexView` is given
vim.g.vimtex_view_skim_activate = 1
--========================================
-- -- pdf reader end
--========================================
vim.g.vimtex_log_verbose = 1
vim.g.vimtex_compiler_method = 'latexmk' -- to use latexmk for compiling
-- Setup VimTeX with shell-escape enabled
vim.g.vimtex_compiler_latexmk = {
  build_dir = '',
  callback = 1,
  continuous = 1,
  executable = 'latexmk',
  options = {
    '-pdf',
    '-pdflatex=pdflatex --shell-escape -interaction=nonstopmode -synctex=1',
    '-verbose',
  },
}

-- 反向定位需要用到的命令，每次打开latex文件时，就会自动调用这个命令， 把nvim server写到文件里
vim.cmd([[
function! s:write_server_name() abort
  let nvim_server_file = (has('win32') ? $TEMP : '/tmp') . '/vimtexserver.txt'
  call writefile([v:servername], nvim_server_file)
endfunction

augroup vimtex_common
  autocmd!
  autocmd FileType tex call s:write_server_name()
augroup END
]])

-- utilsnips 设置
vim.g.UltiSnipsExpandTrigger = '<tab>'
vim.g.UltiSnipsJumpForwardTrigger = '<tab>'
vim.g.UltiSnipsJumpBackwardTrigger = '<s-tab>'
vim.g.UltiSnipsSnippetDirectories = { "~/.config/lvim/snippets" }

-- others setting for latex
vim.g.tex_conceal = 'abdmg'
vim.opt.conceallevel = 1
vim.opt.background = 'dark'
-- lvim.colorscheme = "wal"
vim.opt.termguicolors = true
vim.cmd [[highlight Conceal ctermbg=none guibg=none]]
vim.g.vimtex_quickfix_mode = 0


-- inkscape-figures
vim.keymap.set('i', '<C-f>', function()
  local cmd = string.format('silent exec ".!inkscape-figures create \\"%s\\" \\"%s/figures/\\""', vim.fn.getline('.'),
    vim.b.vimtex.root)
  vim.cmd(cmd)
  vim.cmd('write') -- 相当于 `:w`
end, { noremap = true, silent = true })

vim.keymap.set('n', '<C-f>', function()
  local cmd = string.format('silent exec "!inkscape-figures edit \\"%s/figures/\\" > /dev/null 2>&1 &"',
    vim.b.vimtex.root)
  vim.cmd(cmd)
  vim.cmd('redraw!')
end, { noremap = true, silent = true })

-- lvim for python debug
local dap = require('dap')
dap.adapters.python = {
  type = "executable",
  command = 'python3',
  program = "${file}",
  args = { '-m', 'debugpy.adapter' },
}
local get_args = function()
  -- 获取输入命令行参数
  local cmd_args = vim.fn.input('CommandLine Args:')
  local params = {}
  -- 定义分隔符(%s在lua内表示任何空白符号)
  local sep = "%s"
  for param in string.gmatch(cmd_args, "[^%s]+") do
    table.insert(params, param)
  end
  return params
end;

dap.configurations.python = {
  {
    type = 'python',
    request = 'launch',
    name = 'launch file',
    -- 此处指向当前文件
    program = '${file}',
    -- args = get_args,
    pythonpath = function()
      return '/usr/bin/python3'
    end,
  },
}
-- lililili your own builtin
--dap
lvim.builtin.dap.active = true
local mason_path = vim.fn.glob(vim.fn.stdpath "data" .. "/mason/")
pcall(function()
  require("dap-python").setup(mason_path .. "packages/debugpy/venv/bin/python")
  -- require("dap-python").setup("/mnt/t4/triton/.venv3.8/bin/python")
end)

require("neotest").setup({
  adapters = {
    require("neotest-python")({
      dap = {
        justMyCode = false,
        console = "integratedTerminal",
      },
      args = { "--log-level", "DEBUG", "--quiet" },
      runner = "pytest",
    })
  }
})

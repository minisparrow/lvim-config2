-- lifunc: display file path on status line
-- lualine颜色配置
-- 打开 lualine
lvim.builtin.lualine.active = true
lvim.builtin.lualine.sections.lualine_c = {
  {
    'filename',
    path = 1,
    -- color = { fg = '#ff9e64', bg = '#1f2335', gui = 'bold' }
    color = { fg = '#ff9e64', bg = '#1f0000', gui = 'bold' }
  }
}
-- 自定义 lualine 的部分显示
lvim.builtin.lualine.sections.lualine_a = { 'mode' }
lvim.builtin.lualine.sections.lualine_b = { 'branch' }
lvim.builtin.lualine.sections.lualine_x = { 'encoding', 'fileformat', 'filetype' }
lvim.builtin.lualine.sections.lualine_y = { 'progress' }
lvim.builtin.lualine.sections.lualine_z = { 'location' }

-- 自定义 lualine 的颜色设置
lvim.builtin.lualine.options.theme = {
  normal = {
    a = { fg = '#000000', bg = '#FFFFFF' }, -- 模式显示部分
    b = { fg = '#FFFFFF', bg = '#000000' }, -- 版本控制部分
    c = { fg = '#FFFFFF', bg = '#1f2335' }, -- 文件信息部分
  },
  insert = {
    a = { fg = '#000000', bg = '#00FF00' }, -- 模式显示部分
    b = { fg = '#00FF00', bg = '#000000' }, -- 版本控制部分
    c = { fg = '#00FF00', bg = '#1f2335' }, -- 文件信息部分
  },
  visual = {
    a = { fg = '#000000', bg = '#FF0000' }, -- 模式显示部分
    b = { fg = '#FF0000', bg = '#000000' }, -- 版本控制部分
    c = { fg = '#FF0000', bg = '#1f2335' }, -- 文件信息部分
  },
  command = {
    a = { fg = '#000000', bg = '#FFA500' }, -- 模式显示部分
    b = { fg = '#FFA500', bg = '#000000' }, -- 版本控制部分
    c = { fg = '#FFA500', bg = '#1f2335' }, -- 文件信息部分
  },
  inactive = {
    a = { fg = '#FFFFFF', bg = '#1f2335' }, -- 模式显示部分
    b = { fg = '#FFFFFF', bg = '#1f2335' }, -- 版本控制部分
    c = { fg = '#FFFFFF', bg = '#1f2335' }, -- 文件信息部分
  },
}

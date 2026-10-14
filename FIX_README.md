# automatic-verilog 修复版

本 fork 合入 `automatic-verilog-fix` 的修复，保留原项目的 `plugin/`、`docs/`
目录结构，并附上回归测试与验证记录。上游项目为 `HonkW93/automatic-verilog`，
本 fork 为 `MaNan93/automatic-verilog`。

## 修复内容

- 补齐 logic 关键词，修复同一行多个显式端口声明的解析。
- 修复数组维度清理时误删后续端口的问题。
- 支持 typedef struct、包限定类型、嵌套结构体及结构体数组的端口连接。
- 修复 signed 和注释的清理。
- 新连接默认不自动添加位宽范围；更新时保留已有连接表达式和范围。
- 不同目录中的同名文件按完整路径保留，再按 module name 建立模块索引。

结构体功能仅生成模块端口连接，不自动生成结构体变量声明。
多维数组测试验证的是连接结果，现有 IO 数据结构仍未保存完整维度信息。

## 文件位置

```text
automatic-verilog/
├─ plugin/
│  ├─ automatic.vim             # 文件头含本次版本记录
│  └─ automatic/
│     └─ autoinst.vim           # 核心修复
├─ tests/                      # 真实 Vim 测试脚本及说明
├─ tests/VALIDATION.md          # 58 项真实 Vim 验证记录
└─ test-results/               # 本地运行测试后生成，不纳入 Git
```

## Windows GVim 安装

先备份旧插件。在本目录打开 PowerShell，执行：

```powershell
$pluginDir = Join-Path $env:USERPROFILE 'vimfiles\plugin'
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
Copy-Item -Path '.\plugin\*' -Destination $pluginDir -Recurse -Force
```

关闭并重新打开 GVim，然后执行 `:echo exists('*g:AutoInst')`，返回 `1`
表示加载成功。若 GVim 的用户目录与 `%USERPROFILE%` 不同，请以
`:echo expand('~/vimfiles')` 显示的路径为准。

实例化调用保持不变：`:call g:AutoInst(1)`。
参数连接调用：`:call g:AutoPara(1)`。

## 实例连接的位宽行为

新生成的连接默认是 `.data(data)`。已有 `.data(data[31:0])`、
`.data(data[15:8])` 或 `.data(bus_data[31:0])` 时，更新实例会保留原表达式。
新增端口仍使用不带范围的连接。保留更新区域里的已有表达式依赖
`g:atv_autoinst_keep_chg = 1`（默认值）。

如果旧的 `_vimrc`/`.vimrc` 显式开启了位宽，请改为：

```vim
let g:atv_autoinst_incl_width = 0
let g:atv_autoinst_keep_chg = 1
```

如显式设置 `g:atv_autoinst_incl_width = 1`，新连接仍可使用原先自动带范围的行为。

## 同名文件与模块索引

以下两个文件现在都能被读取和实例化，文件名不必等于模块名：

```text
rtl_a/common.sv  -> module alpha
rtl_b/common.sv  -> module beta
```

支持普通目录扫描、递归搜索、显式文件列表、filelist（包括嵌套 filelist）及 tags。
同一完整路径重复出现时只登记一次；一个文件中的多个模块分别登记。
如果不同文件连 module name 也相同，选择按配置/搜索顺序遇到的第一个定义。

`g:AutoVerilog_GetModuleFileDirDic()` 调用和返回的两个字典结构保持不变，
但文件键和模块映射值改用完整路径：

```text
files   = { '/project/rtl_a/common.sv': '/project/rtl_a', ... }
modules = { 'alpha': '/project/rtl_a/common.sv', 'beta': '/project/rtl_b/common.sv', ... }
```

诊断时可使用 `:echo get(modules, 'alpha', '未找到')` 直接查看源文件路径。
更新时请复制完整 `plugin/` 目录的内容，确保 CrossDir、AutoInst、AutoPara、
AutoWire/AutoDef 和 RtlTree 使用一致的索引格式，再重启 Vim/GVim。

## Linux 和换行符

本仓库的代码和文档统一使用 UTF-8 无 BOM、LF 换行符。
`.gitattributes` 和 `.editorconfig` 指定 LF，避免后续 Git 检出或编辑时
转换回 Windows 的 CRLF。二进制图标保持原样。

Linux Vim 手动安装方式（在本目录运行，已有插件时先备份）：

```sh
mkdir -p ~/.vim/plugin
cp -r plugin/. ~/.vim/plugin/
```

重新打开 Vim 后，实例化调用仍是 `:call g:AutoInst(1)`。

## 测试

在本目录运行真实 Vim（替换为自己的 vim.exe 路径）：

```powershell
& '<vim.exe路径>' -Nu NONE -i NONE -n -es -S tests/test_autoinst_logic.vim
& '<vim.exe路径>' -Nu NONE -i NONE -n -es -S tests/test_autoinst_multidim.vim
& '<vim.exe路径>' -Nu NONE -i NONE -n -es -S tests/test_autoinst_struct.vim
& '<vim.exe路径>' -Nu NONE -i NONE -n -es -S tests/test_autoinst_connections.vim
& '<vim.exe路径>' -Nu NONE -i NONE -n -es -S tests/test_crossdir_module_index.vim
```

已通过 logic/参数/CrossDir 17 项、多维数组连接 9 项、结构体连接 13 项，
另有连接保留行为 10 项、同名文件模块索引 9 项，合计 58 项。
各脚本退出码为 0 表示通过。
测试详细说明见 `tests/README.md`。

发布前的验证记录见 `tests/VALIDATION.md`。运行脚本会在 `test-results/`
生成详细结果、实例 RTL 和模块索引；同名文件测试还生成参数、线网与 RtlTree 输出。
该目录及本地导出的补丁不纳入 Git。

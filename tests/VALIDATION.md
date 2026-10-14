# 2026-10-14 验证记录

基线：上游 `HonkW93/automatic-verilog` 的 `master`，提交
`74b753dbdf5cf38222c5fb3e6dccb1a38f310b74`。

环境：真实 Vim 9.1，patches 1-1914，Windows/MSYS 版本。
脚本加载 `plugin/automatic.vim` 并执行插件实际函数，没有模拟正则或替换解析器。

| 测试脚本 | 用例数 | 验证内容 |
| --- | ---: | --- |
| `test_autoinst_logic.vim` | 17 | wire/logic/reg、signed、同行声明、位宽元数据、参数、三种 CrossDir 模式 |
| `test_autoinst_multidim.vim` | 9 | 二维/三维 packed、unpacked、混合数组及同行数组连接 |
| `test_autoinst_struct.vim` | 13 | typedef、包限定类型、嵌套结构体、结构体数组、参数化跨目录模块 |
| `test_autoinst_connections.vim` | 10 | 新连接无范围、已有范围/表达式保留、重复更新及原配置选项 |
| `test_crossdir_module_index.vim` | 9 | 同名文件、路径顺序、递归、filelist/tags、多模块文件及重复模块优先级 |
| `test_autowire_declared.vim` | 24 | 已有 wire/logic/reg、signed、数组、同行/跨行/初始化/注释、局部 typedef/包类型、生成区更新及重复声明修复 |
| 合计 | **82** | **全部通过，六个脚本退出码均为 0** |

同名文件测试还实际调用 AutoPara、AutoParaValue、AutoWire 和 RtlTree，
核对参数值、普通向量声明、源文件路径及树中节点是否已解析。
测试源 RTL 保持不变。所有发布文本核对为 UTF-8 无 BOM、LF 换行。

在仓库根目录运行（回归脚本需要 Vim 8+）：

```sh
vim -Nu NONE -i NONE -n -es -S tests/test_autoinst_logic.vim
vim -Nu NONE -i NONE -n -es -S tests/test_autoinst_multidim.vim
vim -Nu NONE -i NONE -n -es -S tests/test_autoinst_struct.vim
vim -Nu NONE -i NONE -n -es -S tests/test_autoinst_connections.vim
vim -Nu NONE -i NONE -n -es -S tests/test_crossdir_module_index.vim
vim -Nu NONE -i NONE -n -es -S tests/test_autowire_declared.vim
```

Windows 下可将 `vim` 替换为真实 `vim.exe` 的完整路径。
测试输出写入 `test-results/`，该目录由 `.gitignore` 排除；运行后可检查各目录的
`results.txt` 和生成 RTL。这里的结果验证解析和生成行为，未执行 RTL 编译或硬件仿真。

## AutoWire 修复前后

此次 AutoWire 对照基线为 fork 的未修改提交 `5b44ca8`。
复制该提交的 `plugin/` 到本地测试目录，通过 `AUTOWIRE_PLUGIN_ROOT` 加载，
真实 Vim 的同一套 24 项测试仅 **4/24 通过**（退出码 1）。
修复后 **24/24 通过**（退出码 0）。本地对照输出分别在
`test-results/autowire-before/` 和 `test-results/autowire-after/`。

修复前已有声明与生成区中出现重复：

```verilog
logic [7:0] data;
/*autowire*/
    //Start of automatic wire
    //Define assign wires here
    //Define instance wires here
    logic [7:0]                 data                            ;
    wire                        extra                           ;
    //End of automatic wire
```

根因位于 `plugin/automatic/autodef.vim` 的 `s:GetDeclWire()`：只识别 `wire`、
按行且只处理一个 packed 范围；初始化清理从首个等号删到行末，丢失后续声明。
自动区中的 `logic` 也未计入更新列表，第二次执行可能误标 `WIRE_NEW`。
`g:AutoWire()` 的按名称过滤本身已经存在，但拿到的已有声明列表不完整。

修复只调整已有声明的扫描，保留调用接口、IO 推断和生成格式。
测试同时验证未声明信号仍生成、手写声明不变、第二次执行稳定、
失效自动声明删除、已有自动区重复声明清除，以及字符串/初始化表达式和
结构体字段不会被误当成模块信号名。

# AutoInst logic regression

Tested with real Vim 9.1 (patches 1-1914), loading `plugin/automatic.vim`
and calling the public `g:AutoVerilog_GetIO()`, `g:AutoInst()` and
`g:AutoPara()` functions. No parser mocks or Python regex simulation.

Run from the repository root with Vim 8+:

```powershell
& '<path-to-vim.exe>' -Nu NONE -i NONE -n -es -S tests/test_autoinst_logic.vim
$LASTEXITCODE
Get-Content test-results/latest/results.txt
```

Exit code 0 means all assertions passed. The script writes each generated
instance and IO dictionary under `test-results/latest/`. Fixtures use a
temporary directory and do not change the user's RTL. For MSYS Vim, use
MSYS paths (for example `/d/Users/...`) in the optional environment variables
`AUTOINST_REPORT_DIR` and `AUTOINST_PLUGIN_ROOT`. Native Windows Vim accepts
Windows paths. `AUTOINST_PLUGIN_ROOT` selects an unmodified comparison checkout.

## Verified baseline

Upstream HEAD: `74b753dbdf5cf38222c5fb3e6dccb1a38f310b74`.
The exact two-line `input logic` example already works in this revision:

```verilog
.pclk                   (pclk                           ), //input
.presetn                (presetn                        )  //input
```

The unmodified current revision passed 13 of 17 cases. Four failed:

| Case | Actual incorrect port names |
| --- | --- |
| `input logic clk, input logic rst` | `clk`, `inputlogicrst` |
| `input wire clk, output logic [31:0] data, output reg ready` | `clk`, `outputlogicdata`, `outputregready` |
| repeated `input logic signed [15:0]` declarations | `value`, `inputlogicsignedother` |
| signed declaration with `// signed input, logic ignored` | `value`, `logicignored` |

The mixed declaration also assigns the first direction and one type/width to
all ports; the repeated vector declaration loses its widths.

For the historical logic bug, an **unmodified** checkout of
`098e1f58d2b44dc125cdf32ac560826bdc5c9ed6` was tested using
`tests/reproduce_logic.vim`. Its output for the supplied module was:

```verilog
.logicpclk              (logicpclk                      ), //input
.logicpresetn           (logicpresetn                   )  //input
```

The wire variant correctly emitted `pclk` and `presetn`. Neither checked
revision produced the specifically reported `.logic(logic)` spelling.
Commit `863e2144703597ed3d5f4dc5e631ba5d3c016d08` (2022-09-18)
already added logic type detection and stripping to `AutoVerilog_GetIO()`.
An older installed plugin should first be updated to current upstream.

## Cause and patch

`s:VlogTypeData` omits `logic`, but current `AutoVerilog_GetIO()` uses an
explicit type-removal expression that already includes it. Adding only
the vocabulary entry does not fix the current name-extraction failures.

The current parser strips direction/type/width once per source line, splits
on commas, deletes whitespace and extracts `\w\+`. Consequently, the second
explicit declaration becomes a concatenated name. Its `if signed / elseif
comment` cleanup also leaves comments intact whenever signedness occurs.

The production patch changes only `plugin/automatic/autoinst.vim`:

- Include `logic` in the keyword vocabulary.
- Copy the input line list and split comma-separated explicit ANSI declarations
  before passing each through the existing parser. Plain `input logic a, b`
  still stays together and inherits the declaration's metadata.
- Strip trailing comments before declaration splitting and signedness handling.
- Select the final declarator identifier without concatenating its type name,
  supporting typedef structs and package-qualified types.
- Connect named types as whole objects, and remove remaining array ranges
  individually to preserve subsequent port names.

AutoInst invocation, the existing IO tuple and alignment defaults are preserved.
CrossDir's two dictionaries now use full file paths as file identities so that
different directories can contain the same basename without losing modules.

## Result

After the patch: **17/17 PASS**, Vim exit code **0**, `git diff --check` clean.
Coverage includes wire, logic, output vectors, reg, signed logic, inherited and
explicit declarations on one line, mixed directions/widths, keyword-containing
identifiers, `parameter integer`, and CrossDir library/filelist/tags modes.
Assertions check parser names, types/directions/widths where applicable, generated
connections, parameter connections, repeated AutoInst stability, and unchanged RTL.

The subsequent struct extension passes **13/13** cases in
`tests/test_autoinst_struct.vim`: packed/unpacked typedef structs, nested types,
package-qualified types, wire-qualified types, inherited and explicit multiple
ports, struct arrays, comments, and a parameterized module through CrossDir filelist.
The port names and complete-object connections are checked using real Vim;
the extension does not generate struct variable declarations or inspect fields.

`tests/test_autoinst_multidim.vim` now passes **9/9** connection cases, including
the previously failing shared declaration `input logic [7:0] a [0:3], b [0:3]`.
Full multidimensional metadata is still not represented in the existing IO tuple;
these results validate AutoInst connections, not automatic signal declarations.

The connection-update extension passes **10/10** cases in
`tests/test_autoinst_connections.vim`. The default now omits ranges on new
connections while preserving existing full/partial ranges, renamed signals,
concatenations and function expressions. Both comma styles, repeated updates,
and the explicit `incl_width = 1` option are checked. Keep `keep_chg = 1`
(the default) to retain existing connection expressions.

The module-index extension passes **9/9** cases in
`tests/test_crossdir_module_index.vim`: normal/reversed directory order,
recursive search, explicit files, filelist, nested filelist, tags, repeated paths,
and precedence for repeated module names. The same two `common.sv` files are
checked through AutoInst, AutoPara, AutoParaValue, AutoWire and RtlTree.
One file also contains multiple modules. Source RTL remains unchanged.

Combined: **58/58 PASS**. Run the additional suites with the same Vim flags
as the logic suite. Struct output defaults to `test-results/struct/` and the
multidimensional output to `test-results/multidim/`.
Connection-update output defaults to `test-results/connections/`; recorded
before/after results are in `test-results/connections-before/` and
`test-results/connections-after/`.
Module-index output defaults to `test-results/module-index/`; recorded before/after
results are in `test-results/module-index-before/` and `test-results/module-index-after/`.

## Windows GVim update

1. In GVim run `:scriptnames` and find the loaded `automatic/autoinst.vim`.
   `:echo globpath(&runtimepath, 'plugin/automatic/autoinst.vim')` also helps
   identify duplicate installations.
2. Back up the plugin files and copy the contents of this checkout's complete
   `plugin/` directory into the installed plugin directory. CrossDir, AutoInst,
   AutoPara, AutoDef and RtlTree must be updated together. A manual installation places AutoInst at
   `%USERPROFILE%\vimfiles\plugin\automatic\autoinst.vim`; a plugin manager
   uses its own checkout directory. Use the actual loaded location.
3. Restart GVim: the plugin has a loaded guard, so simply sourcing it again
   will not replace the existing definitions.
4. Put `apb_csr #( /*autoinstparam*/ ) u_apb_csr ( /*autoinst*/ );` in the
   parent RTL, then run `:call g:AutoInst(1)` and `:call g:AutoPara(1)`.
   Existing formatting and comment defaults are preserved.

This patch is local. Plugin-manager updates from upstream alone will not install
the new same-line fix until it is present upstream, and may overwrite a local copy.

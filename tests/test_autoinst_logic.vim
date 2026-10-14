" Run with: vim -Nu NONE -n -es -S tests/test_autoinst_logic.vim
set nocompatible
set encoding=utf-8
set nomore
let s:root = empty($AUTOINST_PLUGIN_ROOT)
            \ ? fnamemodify(expand('<sfile>:p'), ':h:h') : $AUTOINST_PLUGIN_ROOT
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:work = tempname()
call mkdir(s:work, 'p')
let s:report = empty($AUTOINST_REPORT_DIR) ? s:root . '/test-results/latest' : $AUTOINST_REPORT_DIR
call mkdir(s:report, 'p')
let s:results = []

function! s:Check(label, declarations, expected, parameterized, crossdir, mode, ...) abort
    let before = len(v:errors)
    let dir = s:work . '/' . a:label
    call mkdir(dir . '/rtl', 'p')
    call mkdir(dir . '/top', 'p')
    let module = a:parameterized ? 'apb_csr' : a:label
    let header = a:parameterized
                \ ? ['module apb_csr #(', '    parameter integer aw = 12', ') (']
                \ : ['module ' . module . ' (']
    let lines = header + a:declarations + [');', '', 'endmodule']
    let source_dir = a:crossdir == '' ? dir . '/top' : dir . '/rtl'
    call writefile(lines, source_dir . '/' . module . '.sv')
    execute 'cd ' . fnameescape(dir . '/top')
    let g:atv_crossdir_mode = a:crossdir == 'filelist' ? 1 : (a:crossdir == 'tags' ? 2 : 0)
    let g:atv_crossdir_flist_browse = 0
    let g:atv_crossdir_tags_browse = 0
    let g:atv_crossdir_flist_file = dir . '/files.f'
    let g:atv_crossdir_tags_file = dir . '/tags'
    call writefile(['./rtl/' . module . '.sv'], g:atv_crossdir_flist_file)
    call writefile([module . "\trtl/" . module . ".sv\t/^module " . module . "/;\"\tm"], g:atv_crossdir_tags_file)
    enew!
    let instance = a:parameterized
                \ ? [module . ' #(', '    /*autoinstparam*/', ') u_' . module . ' (', '    /*autoinst*/);']
                \ : [module . ' u_' . module . ' (', '    /*autoinst*/);']
    if a:crossdir == 'library'
        let instance = ['// verilog-library-directories:("../rtl")'] + instance
    endif
    call setline(1, ['module top;'] + instance + ['endmodule'])
    try
        let seqs = g:AutoVerilog_GetIO(lines, 'seq')
        let ports = filter(values(seqs), 'v:val[0] !=# "keep"')
        call sort(ports, {a, b -> a[1] - b[1]})
        call assert_equal(a:expected, map(copy(ports), 'v:val[5]'), a:label . ' parser names')
        if a:0
            call assert_equal(a:1, map(copy(ports), 'v:val[0:0] + v:val[2:4]'), a:label . ' types, directions and widths')
        endif
        let names = g:AutoVerilog_GetIO(lines, 'name')
        call assert_equal(header + a:declarations + [');', '', 'endmodule'], lines, a:label . ' input lines unchanged')
        for port in ports
            call assert_equal(port, names[port[5]], a:label . ' name/seq modes')
        endfor
        call cursor(1, 1)
        call g:AutoInst(a:mode)
        if a:parameterized
            call cursor(1, 1)
            call g:AutoPara(1)
        endif
        let generated = getline(1, '$')
        call writefile(generated, s:report . '/' . a:label . '.v')
        call writefile([string(seqs)], s:report . '/' . a:label . '.io.txt')
        let connections = []
        for line in generated
            if line =~ '^\s*\.\w\+'
                let name = matchstr(line, '^\s*\.\zs\w\+')
                if name ==# 'aw'
                    call assert_match('\.aw\s*(aw\s*)', line, a:label . ' parameter')
                else
                    call add(connections, name)
                    let port = names[name]
                    call assert_equal(name . port[8], matchstr(line, '(\zs[^)]*\ze)')->trim(), a:label . ' connection ' . name)
                endif
            endif
        endfor
        call assert_equal(a:expected, connections, a:label . ' AutoInst names')
        if a:parameterized
            call assert_match('\.aw\s*(aw\s*)', join(generated, "\n"), a:label . ' AutoPara')
            call assert_false(has_key(names, 'integer'), a:label . ' integer is not a port')
        endif
        " A second invocation must preserve the instance and parameter connections.
        call cursor(1, 1)
        call g:AutoInst(a:mode)
        call assert_equal(generated, getline(1, '$'), a:label . ' repeat AutoInst')
        call assert_equal(lines, readfile(source_dir . '/' . module . '.sv'), a:label . ' RTL unchanged')
    catch
        call add(v:errors, a:label . ': ' . v:exception . ' at ' . v:throwpoint)
    endtry
    call add(s:results, (len(v:errors) == before ? 'PASS ' : 'FAIL ') . a:label)
endfunction

call s:Check('wire', ['    input wire clk'], ['clk'], 0, '', 1, [['wire', 'input', 'c0', 'c0']])
call s:Check('logic', ['    input logic clk'], ['clk'], 0, '', 1, [['logic', 'input', 'c0', 'c0']])
call s:Check('logic_output', ['    output logic [31:0] data'], ['data'], 0, '', 1, [['logic', 'output', '31', '0']])
call s:Check('reg', ['    output reg ready'], ['ready'], 0, '', 0, [['reg', 'output', 'c0', 'c0']])
call s:Check('signed_logic', ['    input logic signed [15:0] value'], ['value'], 0, '', 1, [['logic', 'input', '15', '0']])
call s:Check('multiple_logic', ['    input logic clk, rst, enable'], ['clk', 'rst', 'enable'], 0, '', 1)
call s:Check('multiple_wire', ['    input wire clk, rst, enable'], ['clk', 'rst', 'enable'], 0, '', 1)
call s:Check('repeated_logic', ['    input logic clk, input logic rst'], ['clk', 'rst'], 0, '', 1)
call s:Check('mixed_ports', ['    input wire clk, output logic [31:0] data, output reg ready'], ['clk', 'data', 'ready'], 0, '', 1,
            \ [['wire', 'input', 'c0', 'c0'], ['logic', 'output', '31', '0'], ['reg', 'output', 'c0', 'c0']])
call s:Check('repeated_signed', ['    input logic signed [15:0] value, input logic signed [15:0] other'], ['value', 'other'], 0, '', 1,
            \ [['logic', 'input', '15', '0'], ['logic', 'input', '15', '0']])
call s:Check('signed_comment', ['    input logic signed [15:0] value // signed input, logic ignored'], ['value'], 0, '', 1)
call s:Check('keyword_names', ['    input logic logic_clk,', '    input wire wire_clk,', '    output reg reg_ready'], ['logic_clk', 'wire_clk', 'reg_ready'], 0, '', 1)
call s:Check('parameter_logic', ['    input logic pclk,', '    input logic presetn'], ['pclk', 'presetn'], 1, '', 1)
call s:Check('parameter_wire', ['    input wire pclk,', '    input wire presetn'], ['pclk', 'presetn'], 1, '', 1)
call s:Check('cross_library', ['    input logic pclk,', '    input logic presetn'], ['pclk', 'presetn'], 1, 'library', 0)
call s:Check('cross_filelist', ['    input logic pclk,', '    input logic presetn'], ['pclk', 'presetn'], 1, 'filelist', 1)
call s:Check('cross_tags', ['    input logic pclk,', '    input logic presetn'], ['pclk', 'presetn'], 1, 'tags', 1)

call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

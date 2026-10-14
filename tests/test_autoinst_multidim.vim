" Probe whole-array AutoInst connections with the current plugin.
set nocompatible
set encoding=utf-8
set nomore
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:report = s:root . '/test-results/multidim'
call mkdir(s:report, 'p')
let s:work = tempname()
call mkdir(s:work, 'p')
execute 'cd ' . fnameescape(s:work)
let s:results = []
let s:cases = [
            \ ['packed_2d', 'input logic [1:0][7:0] data', ['data']],
            \ ['packed_3d', 'input logic [1:0][3:0][7:0] data', ['data']],
            \ ['unpacked_2d', 'input logic data [0:1][0:3]', ['data']],
            \ ['unpacked_3d', 'input logic data [0:1][0:3][0:7]', ['data']],
            \ ['mixed_2d', 'input logic [7:0] data [0:3]', ['data']],
            \ ['mixed_3d', 'input logic [7:0] data [0:3][0:1]', ['data']],
            \ ['packed_multiple', 'input logic [1:0][7:0] a, b', ['a', 'b']],
            \ ['mixed_multiple', 'input logic [7:0] a [0:3], b [0:3]', ['a', 'b']],
            \ ['explicit_mixed', 'input logic [7:0] a [0:3], input logic [7:0] b [0:3]', ['a', 'b']]
            \ ]
for s:case in s:cases
    let [s:name, s:declaration, s:expected] = s:case
    let s:before = len(v:errors)
    let s:lines = ['module ' . s:name . ' (', '    ' . s:declaration, ');', 'endmodule']
    call writefile(s:lines, s:name . '.sv')
    enew!
    call setline(1, ['module top;', s:name . ' u_dut (', '    /*autoinst*/);', 'endmodule'])
    let s:io = g:AutoVerilog_GetIO(s:lines, 'name')
    call cursor(1, 1)
    call g:AutoInst(1)
    let s:generated = getline(1, '$')
    call writefile(s:generated, s:report . '/' . s:name . '.v')
    call writefile([string(s:io)], s:report . '/' . s:name . '.io.txt')
    let s:connections = []
    for s:line in s:generated
        if s:line =~ '^\s*\.\w\+'
            let s:port = matchstr(s:line, '^\s*\.\zs\w\+')
            let s:connect = trim(matchstr(s:line, '(\zs[^)]*\ze)'))
            call add(s:connections, s:port)
            call assert_equal(s:port, s:connect, s:name . ' whole-array connection')
        endif
    endfor
    call assert_equal(s:expected, s:connections, s:name . ' names')
    call add(s:results, (len(v:errors) == s:before ? 'PASS ' : 'FAIL ') . s:name . ': ' . s:declaration)
endfor
call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

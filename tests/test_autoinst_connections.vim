" Real Vim regression: omit ranges on new connections, preserve existing expressions.
set nocompatible
set encoding=utf-8
set nomore
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:report = empty($AUTOINST_REPORT_DIR) ? s:root . '/test-results/connections' : $AUTOINST_REPORT_DIR
call mkdir(s:report, 'p')
let s:work = tempname()
call mkdir(s:work, 'p')
let s:results = []
call assert_equal(0, g:atv_autoinst_incl_width, 'default: new connections omit ranges')
call assert_equal(1, g:atv_autoinst_keep_chg, 'default: preserve existing connections')

function! s:Check(label, seed, expected, mode, width, style) abort
    let before = len(v:errors)
    let dir = s:work . '/' . a:label
    call mkdir(dir, 'p')
    execute 'cd ' . fnameescape(dir)
    let child = ['module connection_child (', '    input logic clk,',
                \ '    output logic [31:0] data,', '    output logic [7:0] extra', ');', 'endmodule']
    call writefile(child, 'connection_child.sv')
    let g:atv_autoinst_incl_width = a:width
    let g:atv_autoinst_style = a:style
    enew!
    call setline(1, ['module top;', 'connection_child u_child (', '    /*autoinst*/'] + a:seed + [');', 'endmodule'])
    try
        call cursor(1, 1)
        call g:AutoInst(a:mode)
        let generated = getline(1, '$')
        let connections = {}
        for line in generated
            if line =~ '^\s*,\=\s*\.\w\+'
                let port = matchstr(line, '\.\zs\w\+')
                let expr = trim(matchstr(line, '(\zs.*\ze)'))
                let connections[port] = expr
            endif
        endfor
        call assert_equal(a:expected, connections, a:label . ' connections')
        call cursor(1, 1)
        call g:AutoInst(a:mode)
        " INST_NEW is intentionally removed on the next update; connections stay intact.
        let stable = map(copy(generated), 'substitute(v:val, " //INST_NEW", "", "g")')
        call assert_equal(stable, getline(1, '$'), a:label . ' repeat AutoInst')
        call assert_equal(child, readfile('connection_child.sv'), a:label . ' child RTL unchanged')
        call writefile(generated, s:report . '/' . a:label . '.sv')
    catch
        call add(v:errors, a:label . ': ' . v:exception . ' at ' . v:throwpoint)
    endtry
    call add(s:results, (len(v:errors) == before ? 'PASS ' : 'FAIL ') . a:label)
endfunction

let s:plain = {'clk': 'clk', 'data': 'data', 'extra': 'extra'}
call s:Check('new_without_range', [], s:plain, 1, 0, 0)
call s:Check('preserve_range', ['    .data(data[31:0])'], extend(copy(s:plain), {'data': 'data[31:0]'}), 1, 0, 0)
call s:Check('preserve_partial_range', ['    .data(data[15:8])'], extend(copy(s:plain), {'data': 'data[15:8]'}), 0, 0, 0)
call s:Check('preserve_renamed_range', ['    .data(bus_data[31:0])'], extend(copy(s:plain), {'data': 'bus_data[31:0]'}), 1, 0, 0)
call s:Check('preserve_plain', ['    .data(data)'], s:plain, 1, 0, 0)
call s:Check('preserve_renamed_plain', ['    .data(bus_data)'], extend(copy(s:plain), {'data': 'bus_data'}), 1, 0, 0)
call s:Check('preserve_concat', ["    .data({data[15:0], 16'b0})"], extend(copy(s:plain), {'data': "{data[15:0], 16'b0}"}), 1, 0, 0)
call s:Check('preserve_function', ['    .data(adjust(data[31:0]))'], extend(copy(s:plain), {'data': 'adjust(data[31:0])'}), 1, 0, 0)
call s:Check('preserve_range_style1', ['    .data(data[31:0])'], extend(copy(s:plain), {'data': 'data[31:0]'}), 1, 0, 1)
call s:Check('explicit_width_option', [], {'clk': 'clk', 'data': 'data[31:0]', 'extra': 'extra[7:0]'}, 1, 1, 0)

call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

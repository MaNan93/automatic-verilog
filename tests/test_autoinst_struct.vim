" Real Vim probe for typedef struct ports; expected connections use port names.
set nocompatible
set encoding=utf-8
set nomore
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:report = empty($AUTOINST_REPORT_DIR) ? s:root . '/test-results/struct' : $AUTOINST_REPORT_DIR
call mkdir(s:report, 'p')
let s:work = tempname()
call mkdir(s:work, 'p')
call mkdir(s:work . '/rtl', 'p')
execute 'cd ' . fnameescape(s:work)
let s:results = []
let s:cases = [
            \ ['typedef_input', 'input packet_t req', ['req']],
            \ ['typedef_output', 'output packet_t rsp', ['rsp']],
            \ ['package_type', 'input pkt_pkg::packet_t req', ['req']],
            \ ['wire_type', 'input wire packet_t req', ['req']],
            \ ['typedef_multiple', 'input packet_t req, backup', ['req', 'backup']],
            \ ['explicit_types', 'input packet_t req, output pkt_pkg::packet_t rsp', ['req', 'rsp']],
            \ ['unpacked_struct', 'input record_t req', ['req']],
            \ ['nested_struct', 'input pkt_pkg::nested_t req', ['req']],
            \ ['struct_array', 'input packet_t req [0:3]', ['req']],
            \ ['struct_arrays', 'input packet_t req [0:3], backup [0:3]', ['req', 'backup']],
            \ ['struct_packed_array', 'input packet_t [1:0] req', ['req']],
            \ ['struct_comment', 'input packet_t req /* // request */, backup // backup request', ['req', 'backup']],
            \ ['cross_parameter', 'input pkt_pkg::packet_t req', ['req'], 'filelist']
            \ ]
for s:case in s:cases
    let [s:name, s:declaration, s:expected] = s:case[:2]
    let s:cross = len(s:case) > 3 ? s:case[3] : ''
    let g:atv_crossdir_mode = s:cross == 'filelist' ? 1 : 0
    let g:atv_crossdir_flist_browse = 0
    let s:before = len(v:errors)
    let s:lines = ['package pkt_pkg;', '    typedef struct packed {',
                \ '        logic [7:0] addr;', '        logic valid;',
                \ '    } packet_t;', '    typedef struct {', '        logic [7:0] addr;',
                \ '        logic valid;', '    } record_t;', '    typedef struct packed {',
                \ '        packet_t payload;', '        logic ready;', '    } nested_t;',
                \ 'endpackage', 'import pkt_pkg::*;',
                \ 'module ' . s:name . ' (', '    ' . s:declaration, ');', 'endmodule']
    if s:cross != ''
        let s:header_idx = index(s:lines, 'module ' . s:name . ' (')
        call remove(s:lines, s:header_idx)
        call extend(s:lines, ['module ' . s:name . ' #(', '    parameter integer AW = 8', ') ('], s:header_idx)
    endif
    let s:source = (s:cross == '' ? '' : 'rtl/') . s:name . '.sv'
    call writefile(s:lines, s:source)
    let g:atv_crossdir_flist_file = s:work . '/files.f'
    call writefile(['./' . s:source], g:atv_crossdir_flist_file)
    enew!
    let s:instance = s:cross == '' ? [s:name . ' u_dut (']
                \ : [s:name . ' #(', '    /*autoinstparam*/', ') u_dut (']
    call setline(1, ['module top;'] + s:instance + ['    /*autoinst*/);', 'endmodule'])
    let s:io = g:AutoVerilog_GetIO(s:lines, 'name')
    call assert_equal(sort(copy(s:expected)), sort(keys(s:io)), s:name . ' parser names')
    call cursor(1, 1)
    call g:AutoInst(1)
    if s:cross != ''
        call cursor(1, 1)
        call g:AutoPara(1)
        call assert_match('\.AW\s*(AW\s*)', join(getline(1, '$'), "\n"), s:name . ' parameter')
    endif
    let s:generated = getline(1, '$')
    call writefile(s:generated, s:report . '/' . s:name . '.v')
    call writefile([string(s:io)], s:report . '/' . s:name . '.io.txt')
    let s:connections = []
    for s:line in s:generated
        if s:line =~ '^\s*\.\w\+'
            let s:port = matchstr(s:line, '^\s*\.\zs\w\+')
            if s:port ==# 'AW'
                continue
            endif
            call add(s:connections, s:port)
            call assert_equal(s:port, trim(matchstr(s:line, '(\zs[^)]*\ze)')), s:name . ' connection')
        endif
    endfor
    call assert_equal(s:expected, s:connections, s:name . ' names')
    call cursor(1, 1)
    call g:AutoInst(0)
    call assert_equal(s:generated, getline(1, '$'), s:name . ' repeat AutoInst')
    call assert_equal(s:lines, readfile(s:source), s:name . ' RTL unchanged')
    call add(s:results, (len(v:errors) == s:before ? 'PASS ' : 'FAIL ') . s:name . ': ' . s:declaration)
endfor
call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

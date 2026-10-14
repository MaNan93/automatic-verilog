" Real Vim regression: AutoWire must preserve declarations outside its block.
set nocompatible
set encoding=utf-8
set nomore
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:plugin_root = empty($AUTOWIRE_PLUGIN_ROOT) ? s:root : $AUTOWIRE_PLUGIN_ROOT
let &runtimepath = s:plugin_root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:report = empty($AUTOWIRE_REPORT_DIR) ? s:root . '/test-results/autowire' : $AUTOWIRE_REPORT_DIR
call mkdir(s:report, 'p')
let s:work = tempname()
call mkdir(s:work, 'p')
execute 'cd ' . fnameescape(s:work)
let s:results = []
call writefile(['module child (', '    output logic [7:0] data,', '    output wire extra', ');', 'endmodule'], 'child.sv')

function! s:Check(label, declarations, mode, ...) abort
    let before = len(v:errors)
    let original = ['// verilog-library-directories:(".")',
                \ '// verilog-library-directories-recursive:0', 'module top;',
                \ ] + a:declarations + ['/*autowire*/']
    if a:mode ==# 'after'
        let original = original[0:2] + ['/*autowire*/'] + a:declarations
    elseif a:mode ==# 'stale'
        let original += ['//Start of automatic wire', 'logic [7:0] data;',
                    \ 'wire extra;', 'wire obsolete;', '//End of automatic wire']
        let g:atv_autodef_wire_del = 0
    endif
    if a:mode ==# 'assign'
        let original += ["assign data = 8'h0;", "assign extra = 1'b0;"]
    else
        let original += ['child u_child (.data(data), .extra(extra));']
    endif
    let original += ['endmodule']
    call writefile(original, 'top.sv')
    execute 'edit! ' . fnameescape(s:work . '/top.sv')
    try
        call g:AutoWire()
        let generated = getline(1, '$')
        call writefile(generated, s:report . '/' . a:label . '.sv')
        let block = matchstr(join(generated, "\n"), '//Start of automatic wire\zs\_.\{-}\ze//End of automatic wire')
        if a:0 ? a:1 : !empty(a:declarations)
            call assert_notmatch('\<data\>\s*;', block, a:label . ' declared data must be filtered')
        else
            call assert_match('\<data\>\s*;', block, a:label . ' missing data must be generated')
        endif
        if !empty(a:declarations)
            let offset = a:mode ==# 'after' ? index(generated, a:declarations[0]) : 3
            call assert_equal(a:declarations, generated[offset : offset + len(a:declarations) - 1], a:label . ' manual declarations unchanged')
        endif
        call assert_notmatch('\<obsolete\>\s*;', block, a:label . ' stale generated signal removed')
        call assert_match('\<extra\>\s*;', block, a:label . ' undeclared extra must be generated')
        call g:AutoWire()
        let updated = getline(1, '$')
        let stable = map(copy(generated), 'substitute(v:val, " // WIRE_NEW", "", "g")')
        call assert_equal(stable, updated, a:label . ' second AutoWire preserves declarations')
        " Removing a connection must remove its generated declaration on update.
        if a:mode !=# 'assign'
            call setline(search('child u_child', 'w'), 'child u_child (.data(data));')
            let g:atv_autodef_wire_del = 0
            call g:AutoWire()
            call assert_notmatch('\<extra\>\s*;', join(getline(1, '$'), "\n"), a:label . ' obsolete generated signal removed')
            let g:atv_autodef_wire_del = 1
        endif
    catch
        call add(v:errors, a:label . ': ' . v:exception . ' at ' . v:throwpoint)
    endtry
    call add(s:results, (len(v:errors) == before ? 'PASS ' : 'FAIL ') . a:label)
endfunction

call s:Check('wire', ['wire [7:0] data;'], 'instance')
call s:Check('logic', ['logic [7:0] data;'], 'instance')
call s:Check('reg', ['reg [7:0] data;'], 'instance')
call s:Check('signed_logic', ['logic signed [7:0] data;'], 'instance')
call s:Check('wire_logic', ['wire logic [7:0] data;'], 'instance')
call s:Check('multidim', ['wire [1:0][3:0] data;'], 'instance')
call s:Check('unpacked', ['logic [7:0] data [0:3];'], 'instance')
call s:Check('multiple', ['logic [7:0] first, data;'], 'instance')
call s:Check('initialized_list', ["wire [7:0] first = {4'b0, 4'b0}, data = 0;"], 'instance')
call s:Check('multiline', ['wire [7:0]', '    first,', '    data;'], 'instance')
call s:Check('inline_comments', ['logic /* type */ [7:0] data; // existing'], 'instance')
call s:Check('several_statements', ['wire first; logic [7:0] data;'], 'instance')
call s:Check('package_type', ['pkg::packet_t data;'], 'instance')
call s:Check('typedef_struct', ['typedef struct packed { logic [7:0] payload; } packet_t;', 'packet_t data;'], 'instance')
call s:Check('logic_assign', ['logic [7:0] data;'], 'assign')
call s:Check('reg_assign', ['reg [7:0] data;'], 'assign')
call s:Check('generated_logic', [], 'instance')
call s:Check('generated_wire', [], 'assign')
call s:Check('conditional', ['`ifdef USE_DATA', 'wire [7:0] data;', '`endif'], 'instance')
call s:Check('string_comments', ['string note = "http://host/*path*/"; logic [7:0] data;'], 'instance')
call s:Check('initializer_reference', ["wire [7:0] first = {data, 1'b0};"], 'instance', 0)
call s:Check('struct_field', ['typedef struct packed { logic [7:0] data; } packet_t;'], 'instance', 0)
call s:Check('manual_after_marker', ['logic [7:0] data;'], 'after')
call s:Check('repair_existing_duplicate', ['logic [7:0] data;'], 'stale')

call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

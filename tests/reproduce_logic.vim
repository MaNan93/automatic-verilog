" Reproduce with the selected, unmodified plugin checkout.
set nocompatible
set encoding=utf-8
set nomore
let s:root = empty($AUTOINST_PLUGIN_ROOT)
            \ ? fnamemodify(expand('<sfile>:p'), ':h:h') : $AUTOINST_PLUGIN_ROOT
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:work = tempname()
call mkdir(s:work, 'p')
execute 'cd ' . fnameescape(s:work)
call mkdir($AUTOINST_REPORT_DIR, 'p')
for s:type in ['logic', 'wire']
    call writefile(['module apb_csr #(', '    parameter integer aw = 12', ') (',
                \ '    input ' . s:type . ' pclk,', '    input ' . s:type . ' presetn',
                \ ');', '', 'endmodule'], 'apb_csr.sv')
    enew!
    call setline(1, ['module top;', 'apb_csr #(', '    /*autoinstparam*/',
                \ ') u_apb_csr (', '    /*autoinst*/);', 'endmodule'])
    call cursor(1, 1)
    call g:AutoInst(1)
    call cursor(1, 1)
    call g:AutoPara(1)
    call writefile(getline(1, '$'), $AUTOINST_REPORT_DIR . '/' . s:type . '.v')
    call writefile([string(g:AutoVerilog_GetIO(readfile('apb_csr.sv'), 'name'))],
                \ $AUTOINST_REPORT_DIR . '/' . s:type . '.io.txt')
endfor
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
qa!

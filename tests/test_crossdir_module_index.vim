" Real Vim regression: same filename in different directories, distinct module names.
set nocompatible
set encoding=utf-8
set nomore
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let &runtimepath = s:root . ',' . &runtimepath
runtime plugin/automatic.vim
let s:report = empty($AUTOINST_REPORT_DIR) ? s:root . '/test-results/module-index' : $AUTOINST_REPORT_DIR
call mkdir(s:report, 'p')
let s:work = tempname()
call mkdir(s:work, 'p')
let s:results = []

function! s:Check(label) abort
    let before = len(v:errors)
    let dir = s:work . '/' . a:label
    call mkdir(dir . '/rtl_a', 'p')
    call mkdir(dir . '/rtl_b', 'p')
    call mkdir(dir . '/lists', 'p')
    execute 'cd ' . fnameescape(dir)
    let alpha = ['module alpha #(', '    parameter integer AW = 8', ') (',
                \ '    input wire clk,', '    output wire [7:0] a_data', ');', 'endmodule',
                \ 'module alpha_aux (', '    input wire clk', ');', 'endmodule']
    let beta = ['module beta #(', '    parameter integer BW = 16', ') (',
                \ '    input wire clk,', '    output wire [15:0] b_data', ');', 'endmodule']
    call writefile(alpha, 'rtl_a/common.sv')
    call writefile(beta, 'rtl_b/common.sv')
    let g:atv_crossdir_mode = a:label =~ 'filelist' ? 1 : (a:label ==# 'tags' ? 2 : 0)
    let g:atv_crossdir_flist_browse = 0
    let g:atv_crossdir_tags_browse = 0
    let g:atv_crossdir_flist_file = dir . '/files.f'
    let g:atv_crossdir_tags_file = dir . '/tags'
    call writefile(['../rtl_a/common.sv'], 'lists/a.f')
    call writefile(['../rtl_b/common.sv'], 'lists/b.f')
    call writefile(a:label ==# 'nested_filelist'
                \ ? ['-f ./lists/a.f', '-f ./lists/b.f', './top.sv']
                \ : ['./rtl_a/common.sv', './rtl_b/common.sv', './top.sv'], 'files.f')
    call writefile(["alpha\trtl_a/common.sv\t/^module alpha/;\"\tm",
                \ "alpha_aux\trtl_a/common.sv\t/^module alpha_aux/;\"\tm",
                \ "beta\trtl_b/common.sv\t/^module beta/;\"\tm",
                \ "top\ttop.sv\t/^module top/;\"\tm"], 'tags')
    let config = ['// verilog-library-directories:("./rtl_a")',
                \ '// verilog-library-directories:("./rtl_b")',
                \ '// verilog-library-directories:(".")',
                \ '// verilog-library-directories-recursive:0']
    if a:label ==# 'library_reversed'
        let config[0:1] = reverse(config[0:1])
    elseif a:label ==# 'recursive'
        let config = ['// verilog-library-directories:(".")', '// verilog-library-directories-recursive:1']
    elseif a:label ==# 'explicit_files'
        let config = ['// verilog-library-files:("./rtl_a/common.sv" "./rtl_b/common.sv")',
                    \ '// verilog-library-directories-recursive:0']
    elseif a:label ==# 'repeated_paths'
        call insert(config, '// verilog-library-directories:("./rtl_a")', 2)
    endif
    let top = config + ['module top (', '    input wire clk', ');', '    /*autowire*/',
                \ '    alpha #(', '        /*autoinstparam*/', '    ) u_alpha (', '        /*autoinst*/);',
                \ '    beta #(', '        /*autoinstparam*/', '    ) u_beta (', '        /*autoinst*/);', 'endmodule']
    call writefile(top, 'top.sv')
    execute 'edit! ' . fnameescape(dir . '/top.sv')
    try
        let [files, modules] = g:AutoVerilog_GetModuleFileDirDic()
        call writefile([string(files), string(modules)], s:report . '/' . a:label . '.index.txt')
        let common_files = filter(keys(files), 'fnamemodify(v:val, ":t") ==# "common.sv"')
        call assert_equal(2, len(common_files), a:label . ' both same-name files retained')
        for module in ['alpha', 'alpha_aux', 'beta']
            call assert_true(has_key(modules, module), a:label . ' module ' . module)
        endfor
        if len(common_files) != 2 || !has_key(modules, 'alpha') || !has_key(modules, 'beta')
            throw 'same-name files lost before module indexing'
        endif
        call assert_equal(fnamemodify(dir . '/rtl_a/common.sv', ':p'), modules.alpha, a:label . ' alpha source')
        call assert_equal(fnamemodify(dir . '/rtl_b/common.sv', ':p'), modules.beta, a:label . ' beta source')
        call assert_equal(modules.alpha, modules.alpha_aux, a:label . ' multiple modules per file')
        call cursor(1, 1)
        call g:AutoInst(1)
        call cursor(1, 1)
        call g:AutoPara(1)
        let generated = join(getline(1, '$'), "\n")
        call assert_match('\.a_data\s*(a_data\s*)', generated, a:label . ' alpha AutoInst')
        call assert_match('\.b_data\s*(b_data\s*)', generated, a:label . ' beta AutoInst')
        call assert_match('\.AW\s*(AW\s*)', generated, a:label . ' alpha AutoPara')
        call assert_match('\.BW\s*(BW\s*)', generated, a:label . ' beta AutoPara')
        call g:AutoWire()
        let generated = join(getline(1, '$'), "\n")
        call assert_match('wire\s\+\[7:0\]\s\+a_data\s*;', generated, a:label . ' alpha AutoWire')
        call assert_match('wire\s\+\[15:0\]\s\+b_data\s*;', generated, a:label . ' beta AutoWire')
        for idx in range(1, line('$'))
            call setline(idx, substitute(getline(idx), 'autoinstparam', 'autoinstparam_value', ''))
        endfor
        call cursor(1, 1)
        call g:AutoParaValue(1)
        let generated = join(getline(1, '$'), "\n")
        call assert_match('\.AW\s*(8\s*)', generated, a:label . ' alpha AutoParaValue')
        call assert_match('\.BW\s*(16\s*)', generated, a:label . ' beta AutoParaValue')
        call writefile(getline(1, '$'), 'top.sv')
        call writefile(getline(1, '$'), s:report . '/' . a:label . '.sv')
        RtlTree
        let tree = getline(1, '$')
        call assert_match('u_alpha (alpha)', join(tree, "\n"), a:label . ' alpha RtlTree')
        call assert_match('u_beta (beta)', join(tree, "\n"), a:label . ' beta RtlTree')
        call assert_notmatch('unresolved', join(tree, "\n"), a:label . ' RtlTree paths')
        call writefile(tree, s:report . '/' . a:label . '.tree.txt')
        close
        call assert_equal(alpha, readfile('rtl_a/common.sv'), a:label . ' alpha RTL unchanged')
        call assert_equal(beta, readfile('rtl_b/common.sv'), a:label . ' beta RTL unchanged')
    catch
        call add(v:errors, a:label . ': ' . v:exception . ' at ' . v:throwpoint)
        if &filetype ==# 'rtltree'
            close
        endif
    endtry
    call add(s:results, (len(v:errors) == before ? 'PASS ' : 'FAIL ') . a:label)
endfunction

for s:label in ['library', 'library_reversed', 'recursive', 'explicit_files', 'filelist', 'nested_filelist', 'tags', 'repeated_paths']
    call s:Check(s:label)
endfor

" Same module names remain ambiguous: the first configured directory wins.
let s:before = len(v:errors)
let s:dir = s:work . '/duplicate_module'
call mkdir(s:dir . '/a', 'p')
call mkdir(s:dir . '/b', 'p')
execute 'cd ' . fnameescape(s:dir)
call writefile(['module shared ();', 'endmodule'], 'a/common.sv')
call writefile(['module shared ();', 'endmodule'], 'b/common.sv')
enew!
let g:atv_crossdir_mode = 0
call setline(1, ['// verilog-library-directories:("./b" "./a")', '// verilog-library-directories-recursive:0'])
let [s:files, s:modules] = g:AutoVerilog_GetModuleFileDirDic()
call assert_equal(fnamemodify(s:dir . '/b/common.sv', ':p'), s:modules.shared, 'duplicate module uses first configured file')
call add(s:results, (len(v:errors) == s:before ? 'PASS ' : 'FAIL ') . 'duplicate_module_priority')
call writefile(s:results + v:errors, s:report . '/results.txt')
execute 'cd ' . fnameescape(s:root)
call delete(s:work, 'rf')
if !empty(v:errors)
    cquit
endif
qa!

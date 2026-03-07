" profile slow api calls in vim
" :profile start profile.log
" :profile func *
" :profile file *
" TESTHERE
" :profile pause
" :wq
" from https://www.systutorials.com/profiling-vim-to-find-out-which-plugin-makes-vim-slow/
"

" custom plugin loading

" Function to check for the latest Python version in descending order
function! DetectLatestPython()
  " Define paths in order of preference (newer first)
  let python_paths = ['/d/venvs/316/bin/python3', '/d/venvs/315/bin/python3', '/d/venvs/314/bin/python3', '/d/venvs/313/bin/python3', '/d/venvs/312/bin/python3', '/d/venvs/311/bin/python3', '/d/venv/312/bin/python3', '/d/venv/311/bin/python3', '/d/ssd2/venv/20231016/bin/python3', '/d/venv/310/bin/python']

  " Loop through paths and return the first one that exists
  for path in python_paths
    if executable(path)
      return path
    endif
  endfor

  " Fallback if none found
  return ''
endfunction

" load plugins for files that are not mapped
" to a custom plugin-loading
" function (e.g. bash/shell and rust)
function! LoadCustomPluginsForAnyFileType()

    " Detect and set the latest Python binary path
    " let g:ycm_python_binary_path = '/d/venvs/312/bin/python3'
    let g:ycm_python_binary_path = DetectLatestPython()

    " Optional: Print a message if a path was found
    " if !empty(g:ycm_python_binary_path)
    "     echo "Using Python binary: " . g:ycm_python_binary_path
    " else
    "     echo "ERROR_No suitable Python binary found."
    " endif

    " Plug 'Valloric/YouCompleteMe', { 'do': function('BuildYCM') }
    Plug 'ycm-core/YouCompleteMe', { 'do': function('BuildYCM') }
    Plug 'skywind3000/asyncrun.vim'
    Plug 'neomake/neomake'
    Plug 'flazz/vim-colorschemes'
    Plug 'jistr/vim-nerdtree-tabs'
    Plug 'bcicen/vim-jfmt'
    Plug 'hashivim/vim-terraform'
    Plug 'kkoomen/vim-doge', {'do': { -> doge#install({ 'headless': 1 }) }}
    Plug 'majutsushi/tagbar'
    Plug 'rust-lang/rust.vim'
    Plug 'nvie/vim-flake8'
    Plug 'scrooloose/nerdtree'
    Plug 'timonv/vim-cargo'
    Plug 'tmhedberg/SimpylFold'
    Plug 'tpope/vim-fugitive'
    Plug 'madox2/vim-ai'
    " Plug 'plugin-vim/vim-mm', { 'dir': '/opt/redten/aic/rlhf/plugin-vim/vim-mm' }
    Plug 'vim-scripts/indentpython.vim'
    Plug 'ryanoasis/vim-devicons'
    Plug 'heavenshell/vim-pydocstring', { 'do': 'make install' }
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'

    Plug 'evanleck/vim-svelte'
    Plug 'pangloss/vim-javascript'
    Plug 'HerringtonDarkholme/yats.vim'

    " Use release branch (recommended)
    Plug 'neoclide/coc.nvim', {'branch': 'release'}

    augroup load_us_ycm
        autocmd!
        autocmd InsertEnter * call plug#load('YouCompleteMe') | autocmd! load_us_ycm
    augroup END

endfunction " LoadCustomPluginsForAnyFileType - end

function! AddCorePluginsWithPlug()

    set redrawtime=100000
    set re=0
    filetype plugin indent on
    syntax enable

    call plug#begin('~/.vim/plugged-any')

    call LoadCustomPluginsForAnyFileType()

    call plug#end()

    :call LoadSettingsCommon()
    :call LoadSettingsFZF()
    :call LoadSettingsQuickfixHotKeys()
    :call LoadSettingsRipGrep()

    :call PlugLoadCoc()

    " ctrl + p toggles paste mode on/off
    " set pastetoggle=<F10>
    map <C-p> :call TogglePaste()<cr>

    " set wildcharm=<Tab>
    " vnoremap : :A11
    vnoremap : :Aa
    vnoremap < <gv
    vnoremap > >gv

    " start debug mode with a visual selection
    " command! -range=% A11 <line1>,<line2>
    " command! -range=% As <line1>,<line2>
    command! -range=% Aa <line1>,<line2>

endfunction " AddCorePluginsWithPlug - end

" build youcompleteme
" https://github.com/ycm-core/YouCompleteMe/issues/1751#issuecomment-273380629
function! BuildYCM(info)
    " info is a dictionary with 3 fields
    " - name:   name of the plugin
    " - status: 'installed', 'updated', or 'unchanged'
    " - force:  set on PlugInstall! or PlugUpdate!
    if a:info.status == 'installed' || a:info.force
        !echo "installing YCM - any-filetype-vimrc"
        !./install.py --clang-completer --rust-completer --go-completer
    endif
endfunction

" https://vi.stackexchange.com/questions/10939/how-to-see-if-a-plugin-is-active
function! PlugLoaded(name)
    return (
        \ has_key(g:plugs, a:name) &&
        \ isdirectory(g:plugs[a:name].dir) &&
        \ stridx(&rtp, g:plugs[a:name].dir) >= 0)
endfunction

function! SetupQuickfix()
  " Track whether quickfix is currently open
  let g:coc_qf_open = 0

  function! ToggleCocQuickfix()
    " Get all diagnostics from coc.nvim
    let diags = coc#rpc#request('diagnosticList', [])

    " Build quickfix list manually
    let qfl = []

    for d in diags
      " Determine file path
      let filename = 'unknown'
      if has_key(d, 'location') && has_key(d.location, 'uri')
        let filename = fnamemodify(d.location.uri, ':p')
      elseif has_key(d, 'file')
        let filename = fnamemodify(d.file, ':t')
      else
        let filename = 'not_found'
      endif

      " Determine line and column (1-indexed for quickfix)
      if has_key(d, 'location') && has_key(d.location, 'range')
        let lnum = d.location.range.start.line + 1
        let col  = d.location.range.start.character + 1
      elseif has_key(d, 'lnum') && has_key(d, 'col')
        let lnum = d.lnum
        let col  = d.col
      else
        let lnum = 1
        let col  = 1
      endif

      let inc = 0
      if has_key(d, 'severity')
        let sev = d.severity
        if sev == 'Error'
            let inc = 1
        elseif sev == 'Critical'
            let inc = 1
        endif
      endif

      if inc == 0
          continue
      endif

      " Get message
      let text = get(d, 'message', 'Unknown error')

      " Determine type
      if get(d, 'severity', 1) == 1
        let qtype = 'E'
      else
        let qtype = 'W'
      endif

      " Add to quickfix list
      call add(qfl, {'filename': filename, 'lnum': lnum, 'col': col, 'text': text, 'type': qtype})
    endfor

    " Populate quickfix list and open/close window
    call setqflist(qfl, 'r') " replace quickfix list

    if len(qfl) == 0
        cclose
        lclose
        let g:coc_qf_open = 0
    else
      if g:coc_qf_open == 0
        copen
        let g:coc_qf_open = 1
      endif
    endif
  endfunction

  " Map qq and qw to toggle quickfix manually
  nnoremap qq :CocDiagnostics<CR>
  nnoremap qw :call CloseQuickFix()<CR>

  " Auto-update diagnostics on buffer write
  " autocmd BufWritePost * call ToggleCocQuickfix()
endfunction

function! CloseQuickFix()
  cclose
  lclose
endfunction

function! PlugLoadCoc()
    " let g:coc_user_config = '/d/vim/build/coc-settings.json'
    " autocmd User CocDiagnosticChange call CocActionAsync('diagnosticList') | copen

    " nmap <silent> <C-c> :<C-u>CocDiagnostics<CR>

    " Configure Coc to use quickfix list for diagnostics (alternative approach)
    " This allows traditional quickfix navigation
    " nnoremap <leader>qd :lua vim.diagnostic.setqflist()<CR>

    " highlight CocInlayHint guibg=#cdcdcd guifg=#121212
    highlight CocInlayHint guifg=#808080 guibg=#1e1e1e gui=italic

    " augroup QuickFixAutoClose
    "   autocmd!
    "   autocmd QuickFixCmdPost * if empty(getqflist()) | cclose | endif
    " augroup END

    " https://github.com/neoclide/coc.nvim?tab=readme-ov-file#example-vim-configuration
    " Having longer updatetime (default is 4000 ms = 4s) leads to noticeable
    " delays and poor user experience
    set updatetime=100

    " Always show the signcolumn, otherwise it would shift the text each time
    " diagnostics appear/become resolved
    " set signcolumn=yes
    " set signcolumn=no
    set signcolumn=auto

    " Use tab for trigger completion with characters ahead and navigate
    " NOTE: There's always complete item selected by default, you may want to enable
    " no select by `"suggest.noselect": true` in your configuration file
    " NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
    " other plugin before putting this into your config
    inoremap <silent><expr> <TAB> coc#pum#visible() ? coc#pum#next(1) : CheckBackspace() ? "\<Tab>" : coc#refresh()
    inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

    " Make <CR> to accept selected completion item or notify coc.nvim to format
    " <C-g>u breaks current undo, please make your own choice
    inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm(): "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

    " Use <c-space> to trigger completion
    if has('nvim')
        inoremap <silent><expr> <c-space> coc#refresh()
    else
        inoremap <silent><expr> <c-@> coc#refresh()
    endif

    " Use `[g` and `]g` to navigate diagnostics
    " Use `:CocDiagnostics` to get all diagnostics of current buffer in location list
    nmap <silent><nowait> [g <Plug>(coc-diagnostic-prev)
    nmap <silent><nowait> ]g <Plug>(coc-diagnostic-next)

    " GoTo code navigation
    nmap <silent><nowait> gd <Plug>(coc-definition)
    nmap <silent><nowait> gy <Plug>(coc-type-definition)
    nmap <silent><nowait> gi <Plug>(coc-implementation)
    nmap <silent><nowait> gr <Plug>(coc-references)

    " Use K to show documentation in preview window
    nnoremap <silent> K :call ShowDocumentation()<CR>

    function! ShowDocumentation()
    if CocAction('hasProvider', 'hover')
        call CocActionAsync('doHover')
    else
        call feedkeys('K', 'in')
    endif
    endfunction

    " Highlight the symbol and its references when holding the cursor
    autocmd CursorHold * silent call CocActionAsync('highlight')

    " Symbol renaming
    nmap <leader>rn <Plug>(coc-rename)

    " Formatting selected code
    xmap <leader>f  <Plug>(coc-format-selected)
    nmap <leader>f  <Plug>(coc-format-selected)

    augroup mygroup
    autocmd!
    " Setup formatexpr specified filetype(s)
    autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
    augroup end

    " Applying code actions to the selected code block
    " Example: `<leader>aap` for current paragraph
    xmap <leader>a  <Plug>(coc-codeaction-selected)
    nmap <leader>a  <Plug>(coc-codeaction-selected)

    " Remap keys for applying code actions at the cursor position
    nmap <leader>ac  <Plug>(coc-codeaction-cursor)
    " Remap keys for apply code actions affect whole buffer
    nmap <leader>as  <Plug>(coc-codeaction-source)
    " Apply the most preferred quickfix action to fix diagnostic on the current line
    nmap <leader>qf  <Plug>(coc-fix-current)

    " Remap keys for applying refactor code actions
    nmap <silent> <leader>re <Plug>(coc-codeaction-refactor)
    xmap <silent> <leader>r  <Plug>(coc-codeaction-refactor-selected)
    nmap <silent> <leader>r  <Plug>(coc-codeaction-refactor-selected)

    " Run the Code Lens action on the current line
    nmap <leader>cl  <Plug>(coc-codelens-action)

    " Map function and class text objects
    " NOTE: Requires 'textDocument.documentSymbol' support from the language server
    xmap if <Plug>(coc-funcobj-i)
    omap if <Plug>(coc-funcobj-i)
    xmap af <Plug>(coc-funcobj-a)
    omap af <Plug>(coc-funcobj-a)
    xmap ic <Plug>(coc-classobj-i)
    omap ic <Plug>(coc-classobj-i)
    xmap ac <Plug>(coc-classobj-a)
    omap ac <Plug>(coc-classobj-a)

    " Remap <C-f> and <C-b> to scroll float windows/popups
    if has('nvim-0.4.0') || has('patch-8.2.0750')
    nnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    nnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
    inoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
    inoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
    vnoremap <silent><nowait><expr> <C-f> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
    vnoremap <silent><nowait><expr> <C-b> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
    endif

    " Use CTRL-S for selections ranges
    " Requires 'textDocument/selectionRange' support of language server
    nmap <silent> <C-s> <Plug>(coc-range-select)
    xmap <silent> <C-s> <Plug>(coc-range-select)

    " Add `:Format` command to format current buffer
    command! -nargs=0 Format :call CocActionAsync('format')

    " Add `:Fold` command to fold current buffer
    command! -nargs=? Fold :call     CocAction('fold', <f-args>)

    " Add `:OR` command for organize imports of the current buffer
    command! -nargs=0 OR   :call     CocActionAsync('runCommand', 'editor.action.organizeImport')

    " Add (Neo)Vim's native statusline support
    " NOTE: Please see `:h coc-status` for integrations with external plugins that
    " provide custom statusline: lightline.vim, vim-airline
    " set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}

    " Mappings for CoCList
    " Show all diagnostics
    nnoremap <silent><nowait> <C-a>  :<C-u>CocList diagnostics<cr>
    " Manage extensions
    nnoremap <silent><nowait> <C-,>  :<C-u>CocList extensions<cr>
    " Show commands
    nnoremap <silent><nowait> <C-n>  :<C-u>CocList commands<cr>
    " Find symbol of current document
    nnoremap <silent><nowait> <C-o>  :<C-u>CocList outline<cr>
    " Search workspace symbols
    nnoremap <silent><nowait> <C-s>  :<C-u>CocList -I symbols<cr>
    " Do default action for next item
    " nnoremap <silent><nowait> <C-w>  :<C-u>CocNext<CR>
    " Do default action for previous item
    nnoremap <silent><nowait> <C-u>  :<C-u>CocPrev<CR>
    " Resume latest coc list
    nnoremap <silent><nowait> <C-l>  :<C-u>CocListResume<CR>

    " map gf <C-O><CR>
    nnoremap gz <C-o>
    " autocmd BufWritePost * call SetupQuickfix()
    :call SetupQuickfix()
endfunction

" custom plugin loading - end

" https://vim.fandom.com/wiki/Auto-detect_number_of_cores_for_parallel_build
function! SetMakeToUseALimitedNumberOfCPUs()
    let resource_mode = "light"
    let using_number_of_cpus = 1
    if !empty($HOST_NUMBER_OF_PROCESSORS)
        " this works on Windows and provides a convenient override mechanism otherwise
        let using_number_of_cpus = $HOST_NUMBER_OF_PROCESSORS + 0
    elseif filereadable('/proc/cpuinfo')
        " this works on most Linux systems
        let using_number_of_cpus = system('grep -c ^processor /proc/cpuinfo') - 3
    elseif executable('/usr/sbin/psrinfo')
        " this works on Solaris
        let using_number_of_cpus = system('/usr/sbin/psrinfo -p')
    else
        " default to single process if we can't figure it out automatically
        let using_number_of_cpus = 1
    endif
    let &makeprg = 'make' . (using_number_of_cpus > 1 ? (' -j'.(using_number_of_cpus + 0)) : '')
    " load plugins based off the number of cpu
    if using_number_of_cpus < 6
        let resource_mode = "light"
    else
        let resource_mode = "heavy"
    endif
endfunction " SetMakeToUseALimitedNumberOfCPUs - end

function! StartPerformanceBenchmarkTest() abort
    " if you need to profile startup times run vim with these args:
    " vim --startuptime profile.log SOME_FILE
    :profile start profile.log
    :profile func *
    :profile file *
endfunction

function! StopPerformanceBenchmarkTest() abort
    :profile pause
endfunction

function! EnableColorTesting() abort
    " added 2021-11-02 for color testing
    "
    " Change the color scheme from a list of color scheme names.
    " Version 2010-09-12 from http://vim.wikia.com/wiki/VimTip341
    " Press key:
    "   F8                next scheme
    "   Shift-F8          previous scheme
    "   Alt-F8            random scheme
    " Set the list of color schemes used by the above (default is 'all'):
    "   :SetColors all              (all $VIMRUNTIME/colors/*.vim)
    "   :SetColors my               (names built into script)
    "   :SetColors blue slate ron   (these schemes)
    "   :SetColors                  (display current scheme names)
    " Set the current color scheme based on time of day:
    "   :SetColors now
    if v:version < 700 || exists('loaded_setcolors') || &cp
        finish
    endif

    let loaded_setcolors = 1
    let s:mycolors = ['slate', 'torte', 'darkblue', 'delek', 'murphy', 'elflord', 'pablo', 'koehler']  " colorscheme names that we use to set color
    let s:mycolors = []  " browse all schemes

    " Set list of color scheme names that we will use, except
    " argument 'now' actually changes the current color scheme.
    function! s:SetColors(args) abort
        if len(a:args) == 0
            echo 'Current color scheme names:'
            let i = 0
            while i < len(s:mycolors)
            echo '  '.join(map(s:mycolors[i : i+4], 'printf("%-14s", v:val)'))
            let i += 5
            endwhile
        elseif a:args == 'all'
            let paths = split(globpath(&runtimepath, 'colors/*.vim'), "\n")
            let s:mycolors = uniq(sort(map(paths, 'fnamemodify(v:val, ":t:r")')))
            echo 'List of colors set from all installed color schemes'
        elseif a:args == 'my'
            let c1 = 'default elflord peachpuff desert256 breeze morning'
            let c2 = 'darkblue gothic aqua earth black_angus relaxedgreen'
            let c3 = 'darkblack freya motus impact less chocolateliquor'
            let s:mycolors = split(c1.' '.c2.' '.c3)
            echo 'List of colors set from built-in names'
        elseif a:args == 'now'
            call s:HourColor()
        else
            let s:mycolors = split(a:args)
            echo 'List of colors set from argument (space-separated names)'
        endif
    endfunction " s:SetColors - end

    command! -nargs=* SetColors call s:SetColors('<args>')

    " Set next/previous/random (how = 1/-1/0) color from our list of colors.
    " The 'random' index is actually set from the current time in seconds.
    " Global (no 's:') so can easily call from command line.
    function! NextColor(how) abort
        call s:NextColor(a:how, 1)
    endfunction " NextColor - end

    " Helper function for NextColor(), allows echoing of the color name to be
    " disabled.
    function! s:NextColor(how, echo_color) abort
        if len(s:mycolors) == 0
            call s:SetColors('all')
        endif
        if exists('g:colors_name')
            let current = index(s:mycolors, g:colors_name)
        else
            let current = -1
        endif
        let missing = []
        let how = a:how
        for i in range(len(s:mycolors))
            if how == 0
            let current = localtime() % len(s:mycolors)
            let how = 1  " in case random color does not exist
            else
            let current += how
            if !(0 <= current && current < len(s:mycolors))
                let current = (how>0 ? 0 : len(s:mycolors)-1)
            endif
            endif
            try
            execute 'colorscheme '.s:mycolors[current]
            break
            catch /E185:/
            call add(missing, s:mycolors[current])
            endtry
        endfor
        redraw
        if len(missing) > 0
            echo 'Error: colorscheme not found:' join(missing)
        endif
        if (a:echo_color)
            echo g:colors_name
        endif
        call LoadSettingsMenuColors()
    endfunction " s:NextColor - end

    " Set color scheme according to current time of day.
    function! s:HourColor() abort
        let hr = str2nr(strftime('%H'))
        if hr <= 3
            let i = 0
        elseif hr <= 7
            let i = 1
        elseif hr <= 14
            let i = 2
        elseif hr <= 18
            let i = 3
        else
            let i = 4
        endif
        let nowcolors = 'elflord morning desert evening pablo'
        execute 'colorscheme '.split(nowcolors)[i]
        redraw
        echo g:colors_name
    endfunction " s:HourColor - end
endfunction " EnableColorTesting  - end

" end color testing

function! ToggleSyntastic() abort
    for i in range(1, winnr('$'))
        let bnum = winbufnr(i)
        if getbufvar(bnum, '&buftype') == 'quickfix'
            lclose
            return
        endif
    endfor
endfunction " ToggleSyntastic - end

" custom start up functions per file type

function! LoadSettingsMenuColors() abort
    hi Search cterm=NONE ctermfg=black ctermbg=Yellow
    hi Pmenu ctermfg=2 ctermbg=0 guifg=#00ff91 guibg=#00ff91
    hi PmenuSel ctermfg=0 ctermbg=2 guifg=#00ff91 guibg=#00ff91
    au QuickFixCmdPre * hi Search ctermbg=Yellow
endfunction " LoadSettingsMenuColors - end

function! LoadSettingsTagbar() abort
    let g:tagbar_case_insensitive = 1
    let g:tagbar_show_data_type = 1
    let g:tagbar_show_visibility = 1
    let g:tagbar_wrap = 1
    let g:tagbar_width = max([25, winwidth(0) / 3])
    let g:tagbar_silent = 1
    let g:tagbar_autoshowtag = 0
    let g:tagbar_show_balloon = 1
    let g:tagbar_autofocus = 1
    let g:no_status_line = 1
    function! TagbarClose() abort
        call tagbar#ToggleWindow()
        let g:tagbar_autofocus = 0
    endfunction " TagbarClose - end
    function! TagbarRefresh() abort
        call tagbar#ToggleWindow()
    endfunction " TagbarRefresh - end
    " tagbar hot keys
    map ff :call TagbarRefresh()<CR>
endfunction " LoadSettingsTagbar - end

function! TogglePaste()
    if(&paste == 0)
        set paste
        echo "Paste Mode Enabled"
    else
        set nopaste
        echo "Paste Mode Disabled"
    endif
endfunction

function! LoadSettingsCommon() abort

    " https://github.com/junegunn/fzf.vim/issues/969#issuecomment-611611154
    " set termguicolors

    " list bat colorschemes:
    " bat --list-themes

    " leave quickfix window on close
    " https://stackoverflow.com/questions/7476126/how-to-automatically-close-the-quick-fix-window-when-leaving-a-file
    aug QFClose
        au!
        au WinEnter * if winnr('$') == 1 && &buftype == "quickfix"|q|endif
    aug END

    " https://github.com/skywind3000/asyncrun.vim/wiki/Quickfix-Best-Practice
    " automate opening quickfix window when AsyncRun starts (won't be triggered by other quickfix commands)
    augroup vimrc
        autocmd User AsyncRunStart call asyncrun#quickfix_toggle(8, 1)
    augroup END

    set autoindent " always set autoindenting on"
    set smartindent " use smart indent if there is no indent file"
    set tabstop=4 " <tab> inserts 4 spaces"
    set softtabstop=4 " <BS> over an autoindent deletes 4 spaces."
    set smarttab " Handle tabs more intelligently"
    set expandtab " Use spaces, not tabs, for autoindent/tab key."
    set shiftwidth=4 " an indent level is 4 spaces wide."
    set shiftround " rounds indent to a multiple of shiftwidth"
    set showmode
    set hlsearch
    set autowrite
    set backspace=indent,eol,start
    set clipboard=unnamedplus

    " https://superuser.com/questions/1108120/how-to-disable-bash-on-windows-notification-sound-effect
    set visualbell
    set t_vb=

    " Copy paste with ctr+c, ctr+v, etc
    " :behave mswin

    augroup auto_comment
        au!
        au FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o
    augroup END

    set encoding=utf-8
    set fileencoding=utf-8
    set nocompatible

    " Enable folding
    set foldmethod=indent
    set foldlevel=99

    " https://github.com/bcicen/vim-jfmt
    let g:jfmt_autofmt  = 1

    " slow completion
    " https://github.com/davidhalter/jedi-vim#the-completion-is-too-slow
    let g:jedi#completions_enabled = 0
    " no types in deoplete
    let g:deoplete#sources#jedi#enable_typeinfo = 0
    let g:deoplete#sources#jedi#show_docstring = 1
    let g:SimpylFold_docstring_preview=1

    " neomake linting
    " automatically close the quickfix window if there are no errors, warnings or issues
    let g:neomake_open_list = 2

    :call LoadSettingsMenuColors()
    :call LoadSettingsCommonHotKeys()
    :call LoadSettingsYCM()

    " open the tagbar if the file type is supported
    if filereadable($HOME."/.vim/plugged-any/tagbar/plugin/tagbar.vim")
        call LoadSettingsTagbar()
    endif
endfunction " LoadSettingsCommon - end

function! LoadSettingsCPP()
    autocmd FileType cpp setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
    au BufNewFile,BufRead *.cpp set tabstop=4 set softtabstop=4 set shiftwidth=4 set textwidth=79 set expandtab set autoindent set fileformat=unix
    au BufRead,BufNewFile *.cpp,*.h match BadWhitespace /\s\+$/
    nnoremap ga :DogeGenerate()<CR>
    " newer vim releases need this file to load c/c++ files and the vim author is
    " very opinionated about how to set this up... i dont understand this approach
    " at all but what do i know
    if filereadable($HOME.'/.vim/plugged-any/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py')
        let g:ycm_global_ycm_extra_conf = $HOME.'/.vim/plugged-any/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py'
    endif
endfunction " LoadSettingsCPP - end

function! LoadSettingsC()
    autocmd FileType c setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
    au BufNewFile,BufRead *.c set tabstop=4 set softtabstop=4 set shiftwidth=4 set textwidth=79 set expandtab set autoindent set fileformat=unix
    au BufRead,BufNewFile *.c,*.cxx,*.h match BadWhitespace /\s\+$/
    nnoremap ga :DogeGenerate()<CR>
    " newer vim releases need this file to load c/c++ files and the vim author is
    " very opinionated about how to set this up... i dont understand this approach
    " at all but what do i know
    if filereadable($HOME.'/.vim/plugged-any/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py')
        let g:ycm_global_ycm_extra_conf = $HOME.'/.vim/plugged-any/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py'
    endif
endfunction " LoadSettingsC - end

function! LoadSettingsShell()
    nnoremap ga :DogeGenerate()<CR>
endfunction " LoadSettingsShell - end

function! LoadSettingYaml()
    autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
    autocmd FileType yaml setl indentkeys-=<:>
endfunction

function! LoadSettingsNode() abort
    au BufNewFile,BufRead *.js,*.html,*.css set tabstop=2 set softtabstop=2 set shiftwidth=2
    nnoremap ga :DogeGenerate()<CR>
endfunction " LoadSettingsNode - end

function! LoadSettingsGo() abort
    autocmd BufNewFile,BufRead *.go setlocal noexpandtab tabstop=4 shiftwidth=4 
    " Go vimrc
    " echo "downloading go version: ${go_version}"
    " curl -O https://storage.googleapis.com/golang/go${go_version}.linux-amd64.tar.gz --output /tmp/golang.tgz
    " tar xvf /tmp/golang.tgz
    " echo "adding vim plugins"
    " curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    " https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    " git clone https://github.com/fatih/vim-go.git ~/.vim/plugged-any/vim-go
    "
    " run :GoBuild or :GoTestCompile based on the go file

    " call plug#begin()
    " Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries' }
    " call plug#end()

    "Make sure to run at least once in a vim session:"
    " :GoInstallBinaries
    " :PluginInstall
    " go hot keys
    map gb :GoBuild<CR>
    " map gv :GoCoverage<CR>
    map gt :GoTest<CR>
    map gr :GoRun<CR>
    map gc :GoTestCompile<CR>
    map gf :GoTestFunc<CR>
    map cn :cnext<CR>
    map cm :cprevious<CR>
    nnoremap <leader>a :cclose<CR>
    nnoremap ga :DogeGenerate()<CR>

endfunction " LoadSettingsGo - end

function! LoadSettingsRust()
    " rust hot keys
    map BB :Cargo build<CR>
    map TT :Cargo test<CR>
    nnoremap ga :DogeGenerate()<CR>
    " if your host is fast enough you can leave this enabled to check on save
    let g:rustfmt_autosave = 1
    let g:rustfmt_autosave = 0

    let g:asyncrun_open = 10
    let resource_mode = "light"

    let using_number_of_cpus = 1
    if !empty($HOST_NUMBER_OF_PROCESSORS)
        " this works on Windows and provides a convenient override mechanism otherwise
        let using_number_of_cpus = $HOST_NUMBER_OF_PROCESSORS + 0
    elseif filereadable('/proc/cpuinfo')
        " this works on most Linux systems
        let using_number_of_cpus = system('grep -c ^processor /proc/cpuinfo') - 3
    elseif executable('/usr/sbin/psrinfo')
        " this works on Solaris
        let using_number_of_cpus = system('/usr/sbin/psrinfo -p')
    else
        " default to single process if we can't figure it out automatically
        let using_number_of_cpus = 1
    endif
    let &makeprg = 'make' . (using_number_of_cpus > 1 ? (' -j'.(using_number_of_cpus + 0)) : '')
    " load plugins based off the number of cpu
    if using_number_of_cpus < 6
        if !empty($USE_VIM_HEAVY_RESOURCES)
            let resource_mode = "light"
        else
            let resource_mode = "light"
        endif
    else
        let resource_mode = "heavy"
        " requires an ssd + 8 cpu + 8 gb ram
    endif

    " :call LoadSettingsCargoCheckMustRunVimFromDirWithCargoToml()
endfunction " LoadSettingsRust - end

function! LoadSettingsCargoCheckMustRunVimFromDirWithCargoToml()
    " add this to your ~/.bashrc to use this approach
    "
    " function vim() {
    "     rust_find_cargo_toml_manifest_path
    "     /usr/bin/env vim "$@"
    "     clear
    " } # vim - end
    "
    " function rust_find_cargo_toml_manifest_path() {
    "    var_cur_dir=$(pwd)
    "    var_dirs_to_check_in_order=". .. ../.. ../../.. ../../.."
    "    export INCLUDE_CARGO_MANIFEST_PATH_ARG_FROM_BASH_VIM_FUNCTION=""
    "    for var_check_dir in ${var_dirs_to_check_in_order}; do
    "        var_is_cargo_toml_here="${var_check_dir}/Cargo.toml"
    "        if [[ -e "${var_is_cargo_toml_here}" ]]; then
    "            export INCLUDE_CARGO_MANIFEST_PATH_ARG_FROM_BASH_VIM_FUNCTION="${var_is_cargo_toml_here}"
    "            return
    "            break
    "        fi
    "    done
    " } # rust_find_cargo_toml_manifest_path - end
    "
    function! RunQuickFixCommandForCargoCheck()
        " https://doc.rust-lang.org/cargo/commands/cargo-check.html
        " https://github.com/skywind3000/asyncrun.vim/wiki/Quickfix-Best-Practice
        if filereadable("/usr/bin/run-custom-rust-linter.sh")
            :call asyncrun#run("", "", "/usr/bin/run-custom-rust-linter.sh")
        else
            :call asyncrun#run("", "", "cargo check $INCLUDE_CARGO_MANIFEST_PATH_ARG_FROM_BASH_VIM_FUNCTION -j 2 -q --workspace --message-format=json-diagnostic-short --all-targets --offline | jq -r '. | select(.message != null) | .message.rendered' | grep -Ei 'error|critical|warn|fail'")
        endif
    endfunction

    " map qq :call RunQuickFixCommandForCargoCheck()<CR>
    " autocmd BufWritePost *.rs call RunQuickFixCommandForCargoCheck()
endfunction " LoadSettingsCargoCheckMustRunVimFromDirWithCargoToml - end

function! LoadSettingsQuickfixHotKeys()
    " if you're using quickfix, you can close it with this hotkey: qq
    " map qq :ccl<CR>
    map af :lnext<CR>
    map fa :lprevious<CR>
endfunction " LoadSettingsQuickfixHotKeys - end

function! LoadSettingsPython()
    autocmd FileType python setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
    au BufNewFile,BufRead *.py set tabstop=4 set softtabstop=4 set shiftwidth=4 set textwidth=79 set expandtab set autoindent set fileformat=unix
    au BufRead,BufNewFile *.py,*.pyw,*.c,*.h match BadWhitespace /\s\+$/
    let python_highlight_all = 1
    " let g:pydocstring_doq_path = '/opt/venv/bin/doq'
    let g:pydocstring_formatter = 'sphinx'
    let g:pymode_rope = 0
    let NERDTreeIgnore = ['\.pyc$', '\~$'] "ignore files in NERDTree
    " python hot keys
    " auto-insert pydoc strings for python code
    map ga :call pydocstring#insert()<CR>
    " https://github.com/kkoomen/vim-doge
    let g:doge_doc_standard_python = 'numpy'
endfunction " LoadSettingsPython - end

function! LoadSettingsCommonHotKeys() abort
    " exit insert mode with jj
    inoremap jj <ESC>

    " colorscheme hot keys
    nnoremap <F6> :call EnableColorTesting()<CR>
    nnoremap <F7> :call NextColor(1)<CR>
    nnoremap <S-F7> :call NextColor(-1)<CR>
    nnoremap <A-F7> :call NextColor(0)<CR>

    " enable folding with the spacebar
    nnoremap <space> za

    " navigation hot keys
    nnoremap <C-J> <C-W><C-J>
    nnoremap <C-K> <C-W><C-K>
    nnoremap <C-L> <C-W><C-L>
    nnoremap <C-H> <C-W><C-H>

    " map commands with hot keys
    :smap <Del> <C-g>"_d
    :smap <C-c> <C-g>y
    :smap <C-x> <C-g>x
    :imap <C-v> <Esc>pi
    :smap <C-v> <C-g>p
    :smap <Tab> <C-g>1>
    :smap <S-Tab> <C-g>1<

    " after write-quiting the file you can view the local profile.log output with:
    " cat ./profile.log
    map QQ :call StartPerformanceBenchmarkTest()<CR>
    map QW :call StopPerformanceBenchmarkTest()<CR>
endfunction " LoadSettingsCommonHotKeys - end

function! LoadSettingsYCM() abort
    " let g:ycm_rust_src_path = $HOME.'/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/library'
    let g:ycm_confirm_extra_conf = 0
    let g:ycm_autoclose_preview_window_after_completion = 1
    " youcompleteme hot keys
    " https://github.com/ycm-core/YouCompleteMe/issues/1918#issuecomment-439672628
    " On a method/class/function if you use:
    " g + g    it will go-to that code... super helpful navigate
    map gg :YcmCompleter GoToDefinitionElseDeclaration<CR>
    map gl :YcmCompleter GoToDeclaration<CR>
    map gF :YcmCompleter GoToDefinition<CR>
    " and go back with 'CTRL + O' or 'gG'
    map gf <C-O><CR>
endfunction " LoadSettingsYCM - end

function! LoadSettingsRipGrep()
    " https://dev.to/hayden/optimizing-your-workflow-with-fzf-ripgrep-2eai
    set grepformat=%f:%l:%c:%m,%f:%l:%m
    set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --follow
    let g:rg_derive_root='true'
    " remap the search to the faster ripgrep

    " Ripgrep advanced
    " function! RipgrepFzf(query, fullscreen)
    "     " let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case %s || true'
    "     let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case %s || true'
    "     let initial_command = printf(command_fmt, shellescape(a:query))
    "     let reload_command = printf(command_fmt, '{q}')
    "     let spec = {
    "         'options': [
    "             '--ansi',
    "             '--disabled',
    "             '--query', a:query,
    "             '--bind', 'change:reload:sleep 0.1; '.reload_command.' || true',
    "             '--delimiter', ':',
    "             '--preview', 'BAT_THEME=TwoDark bat --color=always {} --highlight-line {}'
    "             '--preview-window', 'up,60%,border-bottom,+{2}+3/3,~3'
    "         ]
    "     }
    "     " let spec = {
    "     "     'options': [
    "     "         '--phony',
    "     "         '--query', a:query,
    "     "         '--bind', 'change:reload:'.reload_command
    "     "     ]
    "     " }
    "     call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
    " endfunction

    " command! -nargs=* -bang RG call RipgrepFzf(<q-args>, <bang>0)
    " command! -nargs=* RG call RipgrepFzf(<q-args>, <bang>0)

    nnoremap \ :Rg<CR>
    " type aa to open up the search menu
    nnoremap aa :Rg<CR>
    map aA :Files<cr>
    map QZ :Buffers<cr>
    map QX :BLines<cr>

    let customColorTan = '#FFD168'
    let customColorGrayDark = '#282828'
    let customColorBlack = '#000000'
    let customColorRed = '#E01B24'
    let customColorCyan = '#4DEFFF'
    let customColorBlue = '#6DD1F0'
    let customColorGreen = '#00FF0E'
    let customColorMint = '#38FFA8'
    let customColorPurple = '#DC8ADD'
    let customColorYellow = '#F2FF00'
    let customColorWhite = '#FFFFFF'

    " let $FZF_DEFAULT_OPTS = '--color=bg+:'.customColorBlack.',bg:'.customColorBlack.',border:'.customColorWhite.',spinner:'.customColorMint.',hl:'.customColorMint.',fg:'.customColorBlue.',header:'.customColorYellow.',info:'.customColorGreen.',pointer:'.customColorRed.',marker:#F92672,fg+:#F8F8F2,prompt:#F92672,hl+:'.customColorMint
    " let FZF_DEFAULT_OPTS = '--color=bg+:'.customColorBlack.',bg:'.customColorBlack.',border:'.customColorWhite.',spinner:'.customColorMint.',hl:'.customColorMint.',fg:'.customColorBlue.',header:'.customColorYellow.',info:'.customColorGreen.',pointer:'.customColorRed.',marker:#F92672,fg+:#F8F8F2,prompt:#F92672,hl+:'.customColorMint

endfunction

function! LoadSettingsFZF() abort
    " function! s:build_quickfix_list(lines)
    "     call setqflist(map(copy(a:lines), '{ "filename": v:val }'))
    "     copen
    "     cc
    " endfunction

    " let g:fzf_action = {
    "     \ 'ctrl-y': function('s:build_quickfix_list'),
    "     \ 'ctrl-x': 'split',
    "     \ 'ctrl-v': 'vsplit' }

    " This is the default option:
    "   - Preview window on the right with 50% width
    "   - CTRL-/ will toggle preview window.
    " - Note that this array is passed as arguments to fzf#vim#with_preview function.
    " - To learn more about preview window options, see `--preview-window` section of `man fzf`.
    " let g:fzf_preview_window = ['right:50%', 'ctrl-/']

    " Preview window on the upper side of the window with 40% height,
    " hidden by default, ctrl-/ to toggle
    " let g:fzf_preview_window = ['up:40%:hidden', 'ctrl-y']
    let g:fzf_preview_window = ['up:40%', 'ctrl-t']

    " Empty value to disable preview window altogether
    " let g:fzf_preview_window = []

    " [Buffers] Jump to the existing window if possible
    let g:fzf_buffers_jump = 1

    " [[B]Commits] Customize the options used by 'git log':
    let g:fzf_commits_log_options = '--graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr"'

    " [Tags] Command to generate tags file
    let g:fzf_tags_command = 'ctags -R'

    " [Commands] --expect expression for directly executing the command
    let g:fzf_commands_expect = 'alt-enter,ctrl-x'

    function! s:fzf_statusline()
        " Override statusline as you like
        highlight fzf1 ctermfg=161 ctermbg=251
        highlight fzf2 ctermfg=23 ctermbg=251
        highlight fzf3 ctermfg=237 ctermbg=251
        setlocal statusline=%#fzf1#\ >\ %#fzf2#fz%#fzf3#f
    endfunction

    autocmd! User FzfStatusLine call <SID>fzf_statusline()

    let g:fzf_layout = { 'window': { 'width': 0.8, 'height': 0.8, 'xoffset': 0.8, 'yoffset': 0.2 } }
    " let $FZF_DEFAULT_OPTS = '--bind ctrl-a:select-all'
    " let $FZF_DEFAULT_COMMAND = 'rg --column --line-number --no-heading --color=always --smart-case $(printf %q "${*:-}")'
    " command! -bang -nargs=* Rg call fzf#vim#grep("rg --column --line-number --no-heading --color=always --smart-case ".shellescape(<q-args>), 1, {'options': '--delimiter : --nth 4..'}, <bang>0)

endfunction " LoadSettingsFZF - end

:call AddCorePluginsWithPlug()

" handle loading based off the file type
:call LoadSettingYaml()
" :call LoadSettingsNode()
:call LoadSettingsShell()
" :call LoadSettingsC()
" :call LoadSettingsCPP()
" :call LoadSettingsGo()
" :call LoadSettingsPython()
:call LoadSettingsRust()

" show the status line
set laststatus=2

" custom start up actions - end

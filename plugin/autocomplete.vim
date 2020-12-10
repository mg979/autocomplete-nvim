" Last Change: 2020 avr 01

if exists('g:loaded_autocomplete') | finish | endif
let g:loaded_autocomplete = 1

let s:save_cpo = &cpo
set cpo&vim

let g:autocomplete = get(g:, 'autocomplete', {})

let s:autocomplete = {
      \ 'snippets':               get(g:autocomplete, 'snippets', ""),
      \ 'confirm_key':            get(g:autocomplete, 'confirm_key', ""),
      \ 'auto_popup':             get(g:autocomplete, 'auto_popup', 1),
      \ 'auto_signature':         get(g:autocomplete, 'auto_signature', 1),
      \ 'auto_paren':             get(g:autocomplete, 'auto_paren', 0),
      \ 'auto_hover':             get(g:autocomplete, 'auto_hover', 0),
      \ 'docked_hover':           get(g:autocomplete, 'docked_hover', 0),
      \ 'minimum_size':           get(g:autocomplete, 'minimum_size', 5),
      \ 'maximum_size':           get(g:autocomplete, 'maximum_size', 20),
      \ 'prefix_length':          get(g:autocomplete, 'prefix_length', 2),
      \ 'timer_cycle':            get(g:autocomplete, 'timer_cycle', 80),
      \ 'sorting':                get(g:autocomplete, 'sorting', 'alphabet'),
      \ 'fuzzy_match':            get(g:autocomplete, 'fuzzy_match', 0),
      \ 'ignore_case':            get(g:autocomplete, 'ignore_case', 0),
      \ 'matching':               get(g:autocomplete, 'matching', ['exact']),
      \ 'items_priority':         get(g:autocomplete, 'items_priority', {}),
      \}

call extend(g:autocomplete, s:autocomplete, 'keep')

let g:autocomplete.chains = get(g:autocomplete, 'chains', {
      \   'default': {
      \      'comment': [ 'keyn', 'file' ],
      \      'default': [ ['snippet', 'lsp'], 'keyn', 'file' ]
      \}})

let g:autocomplete.sources = get(g:autocomplete, 'sources', {})

command! -bar -bang CompletionToggle  call autocomplete#toggle(<bang>0)
command! -bar CompletionTriggers lua print(vim.inspect(require'autocomplete.sources'.lspTriggerCharacters()))
command! -bar CompletionChain lua print(vim.inspect(require'autocomplete.manager'.chains[vim.fn.bufnr()]))
command! -bar CompletionUpdateChain lua require'autocomplete.chains'.updateChain()

inoremap <silent> <Plug>(TabComplete) <C-r>=autocomplete#tab(1)<CR>
inoremap <silent> <Plug>(TabCompletePrev) <C-r>=autocomplete#tab(0)<CR>
inoremap <silent> <Plug>(ForceComplete) <C-r>=luaeval("require'autocomplete'.manualCompletion()")<CR>
inoremap <silent> <Plug>(NextSource) <C-r>=autocomplete#changeSource('next')<CR>
inoremap <silent> <Plug>(PrevSource) <C-r>=autocomplete#changeSource('prev')<CR>
inoremap <expr><silent> <Plug>(ConfirmCompletion) autocomplete#confirm()
inoremap <silent> <Plug>(InsCompletion) <C-r>=g:autocomplete_inscompletion<CR>
inoremap <silent> <Plug>(ShowHover) <C-r>=luaeval("require'autocomplete'.showHover()")<CR>

fun! autocomplete#confirm() abort
  let key = get(g:autocomplete, 'confirm_key', '')
  if pumvisible() && complete_info()["selected"] != -1
    lua require'autocomplete'.confirmCompletion()
    return "\<C-Y>"
  elseif pumvisible() && key == "\<C-Y>"
    return "\<C-G>\<C-G>"
  elseif pumvisible()
    return "\<C-G>\<C-G>" . key
  else
    return key
  endif
endfun

fun! autocomplete#toggle(all) abort
  if a:all
    lua require'autocomplete'.toggleCompletion(1)
  else
    lua require'autocomplete'.toggleCompletion(0)
  endif
endfun

fun! autocomplete#attach() abort
  if exists('b:completion_auto_popup') | return | endif
  autocmd InsertEnter   <buffer> lua require'autocomplete'.on_InsertEnter()
  autocmd InsertLeave   <buffer> lua require'autocomplete'.on_InsertLeave()
  autocmd InsertCharPre <buffer> lua require'autocomplete'.on_InsertCharPre()
  autocmd CompleteDone  <buffer> lua require'autocomplete'.on_CompleteDone()
  autocmd BufEnter      <buffer> lua require'autocomplete'.on_BufEnter()
  let b:completion_auto_popup = get(g:autocomplete, 'auto_popup', v:true)
  let b:completion_triggers = get(b:, 'completion_triggers', {})
  if get(g:autocomplete, 'confirm_key', '') != ''
    exe 'imap' g:autocomplete.confirm_key '<Plug>(ConfirmCompletion)'
  endif
endfun

fun! autocomplete#nextSource() abort
  return "\<C-g>\<C-g>" . luaeval("require'autocomplete.completion'.nextSource(true)")
endfun

fun! autocomplete#changeSource(dir) abort
  lua require'autocomplete.manager'.forceCompletion = true
  let ret = complete_info().selected >= 0 ? "\<C-e>" : ''
  return ret . "\<C-r>=luaeval(\"require'autocomplete.completion'.".a:dir."Source()\")\<CR>"
endfun

fun! autocomplete#tab(next) abort
  return pumvisible() ? a:next ? "\<C-N>" : "\<C-P>" : luaeval("require'autocomplete'.manualCompletion()")
endfun

" overwrite vsnip_integ autocmd since we handle it on ourself in confirmCompletion
autocmd InsertEnter * ++once
      \ if exists('#vsnip_integ') |
      \   autocmd! vsnip_integ |
      \   augroup! vsnip_integ |
      \ end

let &cpo = s:save_cpo
unlet s:save_cpo

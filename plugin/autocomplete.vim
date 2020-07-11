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
      \ 'auto_hover':             get(g:autocomplete, 'auto_hover', 1),
      \ 'docked_hover':           get(g:autocomplete, 'docked_hover', 0),
      \ 'minimum_size':           get(g:autocomplete, 'minimum_size', 5),
      \ 'maximum_size':           get(g:autocomplete, 'maximum_size', 20),
      \ 'trigger_length':         get(g:autocomplete, 'trigger_length', 2),
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

command! -nargs=0 -bar CompletionToggle  lua require'autocomplete'.toggleCompletion()
command! -bar LspTriggerCharacters   lua print(vim.inspect(require'autocomplete.sources'.lspTriggerCharacters()))

inoremap <silent> <Plug>(TabComplete) <C-r>=autocomplete#tab()<CR>
inoremap <silent> <Plug>(Autocomplete) <C-r>=luaeval("require'autocomplete'.manualCompletion()")<CR>
inoremap <silent> <Plug>(NextSource) <C-r>=autocomplete#changeSource('next')<CR>
inoremap <silent> <Plug>(PrevSource) <C-r>=autocomplete#changeSource('prev')<CR>
inoremap <silent> <Plug>(ConfirmCompletion) <C-r>=autocomplete#confirm()<CR>
inoremap <silent> <Plug>(InsCompletion) <C-r>=g:autocomplete_inscompletion<CR>
inoremap <silent> <Plug>(ShowHover) <C-r>=luaeval("require'autocomplete'.showHover()")<CR>

fun! autocomplete#confirm() abort
  if pumvisible() && complete_info()["selected"] >= 0
    lua require'autocomplete'.confirmCompletion()
    return "\<C-Y>"
  else
    return "\<C-G>\<C-G>" . get(g:autocomplete, 'confirm_key', '')
  endif
endfun

fun! autocomplete#attach() abort
  if exists('b:completion_auto_popup') | return | endif
  autocmd InsertEnter   <buffer> lua require'autocomplete'.on_InsertEnter()
  autocmd InsertLeave   <buffer> lua require'autocomplete'.on_InsertLeave()
  autocmd InsertCharPre <buffer> lua require'autocomplete'.on_InsertCharPre()
  autocmd CompleteDone  <buffer> lua require'autocomplete'.on_CompleteDone()
  autocmd BufEnter      <buffer> lua require'autocomplete'.on_BufEnter()
  let b:completion_auto_popup = get(g:autocomplete, 'auto_popup', 1)
  let b:completion_triggers = get(b:, 'completion_triggers', {})
  if get(g:autocomplete, 'confirm_key', '') != ''
    exe 'imap' g:autocomplete.confirm_key '<Plug>(ConfirmCompletion)'
  endif
endfun

fun! autocomplete#nextSource() abort
  lua require'autocomplete.completion'.nextSource()
  return ''
endfun

fun! autocomplete#changeSource(dir) abort
  lua require'autocomplete.manager'.forceCompletion = true
  let ret = complete_info().selected >= 0 ? "\<C-e>" : ''
  return ret . "\<C-r>=luaeval(\"require'autocomplete.completion'.".a:dir."Source()\")\<CR>"
endfun

fun! autocomplete#tab() abort
  return pumvisible() ? "\<C-N>" : luaeval("require'autocomplete'.manualCompletion()")
endfun

let &cpo = s:save_cpo
unlet s:save_cpo

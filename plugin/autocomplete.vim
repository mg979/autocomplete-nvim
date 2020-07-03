" Last Change: 2020 avr 01

if exists('g:loaded_autocomplete') | finish | endif
let g:loaded_autocomplete = 1

let s:save_cpo = &cpo
set cpo&vim

" default minimum number of characters before cursor for automatic completion
let s:trigger_lengths = {'lsp': 2, 'snippet': 1, 'path': 1, 'default': 2}

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
      \ 'trigger_length':         get(g:autocomplete, 'trigger_length', s:trigger_lengths),
      \ 'timer_cycle':            get(g:autocomplete, 'timer_cycle', 80),
      \ 'sorting':                get(g:autocomplete, 'sorting', 'alphabet'),
      \ 'fuzzy_match':            get(g:autocomplete, 'fuzzy_match', 0),
      \ 'ignore_case':            get(g:autocomplete, 'ignore_case', 0),
      \ 'matching':               get(g:autocomplete, 'matching', ['exact']),
      \ 'items_priority':         get(g:autocomplete, 'items_priority', {}),
      \}

call extend(g:autocomplete, s:autocomplete, 'keep')

let g:autocomplete.chains = get(g:autocomplete, 'chains', {
      \   'default': [
      \       ['snippet', 'lsp'], 'keyn', 'file', 'c-n'
      \   ]
      \})

      " \       ['snippet', 'lsp'], 'path', 'keyn', 'omni'
command! -nargs=0 -bar CompletionToggle  lua require'autocomplete'.toggleCompletion()

inoremap <silent> <Plug>(Autocomplete) <C-r>=luaeval("require'autocomplete'.manualCompletion()")<CR>
inoremap <silent> <Plug>(NextSource) <cmd>lua require'autocomplete.completion'.nextSource()<CR>
inoremap <silent> <Plug>(PrevSource) <cmd>lua require'autocomplete.completion'.prevSource()<CR>
inoremap <silent> <Plug>(ConfirmCompletion) <C-r>=autocomplete#confirm()<CR>
inoremap <silent> <Plug>(InsCompletion) <C-r>=g:autocomplete_inscompletion<CR>

fun! autocomplete#confirm() abort
  if pumvisible() && complete_info()["selected"] >= 0
    lua require'autocomplete'.confirmCompletion()
    return "\<C-Y>"
  else
    return "\<C-G>\<C-G>" . get(g:autocomplete, 'confirm_key', '')
  endif
endfun

fun! autocomplete#attach() abort
  augroup CompletionCommand
    autocmd!
    autocmd InsertEnter   <buffer> lua require'autocomplete'.on_InsertEnter()
    autocmd InsertLeave   <buffer> lua require'autocomplete'.on_InsertLeave()
    autocmd InsertCharPre <buffer> lua require'autocomplete'.on_InsertCharPre()
    autocmd CompleteDone  <buffer> lua require'autocomplete'.confirmCompletion()
  augroup end
  let b:completion_auto_popup = get(g:autocomplete, 'auto_popup', 1)
  if get(g:autocomplete, 'confirm_key', '') != ''
    exe 'imap' g:autocomplete.confirm_key '<Plug>(ConfirmCompletion)'
  endif
endfun

fun! autocomplete#nextSource() abort
  lua require'autocomplete.completion'.nextSource()
  return ''
endfun

let &cpo = s:save_cpo
unlet s:save_cpo
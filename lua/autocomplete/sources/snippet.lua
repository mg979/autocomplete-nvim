local vim = vim
local api = vim.api
local match = require'autocomplete.matching'
local M = {}

local snippetsFunc

local function getUltisnipItems(prefix)
  if vim.fn.exists("*UltiSnips#SnippetsInCurrentScope") == 0 then return {} end
  local snippetsList = api.nvim_call_function('UltiSnips#SnippetsInCurrentScope', {})
  local sources = {}
  if vim.tbl_isempty(snippetsList) then
    return {}
  end
  local priority = vim.g.autocomplete.items_priority['UltiSnips'] or 1
  -- fix lua parsing issue
  snippetsList[true] = nil
  for key, val in pairs(snippetsList) do
    local item = {}
    item.word = key
    item.kind = ' ↷  ' .. string.sub(val, 1, 50)
    item.priority = priority
    local user_data = {hover = val}
    item.user_data = user_data
    item.user_data.snippet = 'UltiSnips'
    match.matching(sources, prefix, item)
  end
  return sources
end

local function getNeosnippetItems(prefix)
  if vim.fn.exists("*neosnippet#helpers#get_completion_snippets") == 0 then return {} end
  local snippetsList = api.nvim_call_function('neosnippet#helpers#get_completion_snippets', {})
  local sources = {}
  if vim.tbl_isempty(snippetsList) == 0 then
    return {}
  end
  local priority = vim.g.autocomplete.items_priority['Neosnippet'] or 1
  -- fix lua parsing issue
  snippetsList[true] = nil
  for key, val in pairs(snippetsList) do
    local user_data = {hover = val.description}
    local item = {}
    item.word = key
    item.kind = ' ↷  ' .. string.sub(val, 1, 50)
    item.priority = priority
    item.user_data = user_data
    item.user_data.snippet = 'Neosnippet'
    match.matching(sources, prefix, item)
  end
  return sources
end

local function getVsnipItems(prefix)
  if vim.fn.exists('g:loaded_vsnip') == 0 then return {} end
  local snippetsList = api.nvim_call_function('vsnip#source#find', {api.nvim_get_current_buf()})
  local sources = {}
  if vim.tbl_isempty(snippetsList) == 0 then
    return {}
  end
  local priority = vim.g.autocomplete.items_priority['vim-vsnip'] or 1
  for _, source in pairs(snippetsList) do
    for _, snippet in pairs(source) do
      for _, word in pairs(snippet.prefix) do
        local user_data = {hover = snippet.description}
        local item = {}
        item.word = word
        item.kind = ' ↷  ' .. string.sub(snippet.description, 1, 50)
        item.menu = ''
        item.priority = priority
        item.user_data = user_data
        item.user_data.snippet = 'vim-vsnip'
        match.matching(sources, prefix, item)
      end
    end
  end
  return sources
end

-- if g:autocomplete.snippets is set to some value, it will be used,
-- otherwise it will be autodetected
local function provider()
  local plugin = ''
  if vim.g.autocomplete.snippets ~= '' then
    plugin = vim.g.autocomplete.snippets
  elseif vim.fn.exists("*UltiSnips#SnippetsInCurrentScope") ~= 0 then
    plugin = 'UltiSnips'
  elseif vim.fn.exists("*neosnippet#helpers#get_completion_snippets") ~= 0 then
    plugin = 'Neosnippet'
  elseif vim.fn.exists('g:loaded_vsnip') ~= 0 then
    plugin = 'vim-vsnip'
  end

  if     string.lower(plugin) == 'ultisnips'  then return getUltisnipItems
  elseif string.lower(plugin) == 'neosnippet' then return getNeosnippetItems
  elseif string.lower(plugin) == 'vim-vsnip'  then return getVsnipItems
  else return function() return {} end
  end
end

function M.getSnippets(prefix)
  snippetsFunc = snippetsFunc or provider()
  return snippetsFunc(prefix)
end

return M

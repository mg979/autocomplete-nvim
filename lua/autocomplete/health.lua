local vim = vim
local api = vim.api
local chains = require'autocomplete.chains'
local util = require'autocomplete.util'

local health_start = vim.fn["health#report_start"]
local health_ok = vim.fn['health#report_ok']
local health_info = vim.fn['health#report_info']
local health_error = vim.fn['health#report_error']

local M = {}

local function validateChain(chain, ft, scope)
  local Ft, Hl, error = false
  for _,item in ipairs(chain) do
    if not chains.validateChainItem(item) then
      Ft = ft and (', in filetype "' .. ft .. '"') or ''
      Hl = scope and (', for scope "' .. scope  .. '"') or ''
      health_error(vim.inspect(item) .. " is not a valid completion source" .. Ft .. Hl)
      error = true
    end
  end
  return not error
end

local function checkCompletionSource()
  local error = false

  -- vim.g.autocomplete.chains is a simple list
  if util.is_list(vim.g.autocomplete.chains) then
    return validateChain(vim.g.autocomplete.chains)
  end

  -- vim.g.autocomplete.chains has filetypes
  for filetype, ft_chain in pairs(vim.g.autocomplete.chains) do
    if util.is_list(ft_chain) then
      if not validateChain(ft_chain, filetype) then error = true end
    else
      -- vim.g.autocomplete.chains has filetypes and scopes
      for scope, sc_chain in pairs(ft_chain) do
        if not validateChain(sc_chain, filetype, scope) then error = true end
      end
    end
  end
  return not error
end

local function checkSnippetSource()
  local plugin
  if vim.g.autocomplete.snippets ~= '' then
    plugin = vim.g.autocomplete.snippets
  elseif vim.fn.exists("*UltiSnips#SnippetsInCurrentScope") ~= 0 then
    plugin = 'UltiSnips'
  elseif vim.fn.exists("*neosnippet#helpers#get_completion_snippets") ~= 0 then
    plugin = 'Neosnippet'
  elseif vim.fn.exists('g:loaded_vsnip') ~= 0 then
    plugin = 'vim-vsnip'
  end

  if plugin == 'UltiSnips' then
    if string.match(api.nvim_get_option("rtp"), ".*ultisnips.*") then
      health_ok("You are using UltiSnips as your snippet source.")
    else
      health_error("UltiSnips is not available! Check if you installed Ultisnips correctly.")
    end
  elseif plugin == 'Neosnippet' then
    if string.match(api.nvim_get_option("rtp"), ".*neosnippet.vim.*") == 1 then
      health_ok("You are using Neosnippet as your snippet source.")
    else
      health_error("Neosnippet is not available! Check if you installed Neosnippet correctly.")
    end
  elseif plugin == 'vim-vsnip' then
    if string.match(api.nvim_get_option("rtp"), ".*vsnip.*") then
      health_ok("You are using vim-vsnip as your snippet source.")
    else
      health_error("vim-vsnip is not available! Check if you installed vim-vsnip correctly.")
    end
  else
    health_info("You haven't setup any snippet source. UltiSnips, Neosnippet, vim-vsnip are supported.")
  end
end

function M.checkHealth()
  health_start("general")
  if vim.tbl_filter == nil then
    health_error("vim.tbl_filter is not found!", {'consider recompile neovim from the latest master branch'})
  else
    health_ok("neovim version is supported")
  end
  health_start("completion source")
  if checkCompletionSource() then health_ok("all completion source are valid") end
  health_start("snippet source")
  checkSnippetSource()
end

return M

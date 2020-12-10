local vim = vim
local api = vim.api
local sources = require 'autocomplete.sources'
local completion = require 'autocomplete.completion'
local hover = require'autocomplete.hover'
local Var = require 'autocomplete.manager'

local M = {}



------------------------------------------------------------------------
--                            autocommands                            --
------------------------------------------------------------------------

function M.on_InsertCharPre()
  Var.forceCompletion = false
  Var.insertChar = true
  Var.textHover = true
  Var.selected = -1
  -- inserting a character and no popup? then reset chain
  if vim.fn.pumvisible() == 0 then
    Var.chainIndex = 1
  end
  -- restore 'noselect' in 'completeopt'
  if Var.noSelect then
    Var.noSelect = false
    vim.api.nvim_command('set completeopt+=noselect')
  end
end

function M.on_InsertLeave()
  Var.insertLeave = true
  completion.popup.auto.stop()
  completion.asynch.stop()
end

function M.on_InsertEnter()
  -- setup variables
  completion.init()
  -- start timer for auto popup
  if not vim.g.autocomplete.auto_popup_disabled and
      vim.b.completion_auto_popup then
    completion.popup.auto.start()
  end
end

-- handle completion confirmation and dismiss hover popup
function M.on_CompleteDone()
  if Var.confirmedCompletion then
    Var.confirmedCompletion = false
    M.hasConfirmedCompletion()
  end
  if hover.winnr ~= nil and api.nvim_win_is_valid(hover.winnr) then
    api.nvim_win_close(hover.winnr, true)
  end
end

-- reset several cached settings
function M.on_BufEnter()
  Var.chains[vim.fn.bufnr()] = nil
  -- these LSP triggers were automatically stored, clear them
  if vim.b.lsp_triggers then
    vim.api.nvim_command('unlet b:lsp_triggers')
  end
end



------------------------------------------------------------------------
--                          external commands                         --
------------------------------------------------------------------------

function M.manualCompletion()
  completion.popup.manual()
  return ''
end

function M.showHover()
  if not hover.winnr then hover.autoOpenHoverInPopup() end
  return ''
end

-- provide api for custom sources
function M.addSource(key, value)
  if sources.registered[key] then
    return
  end
  sources.registered[key] = value
end

function M.toggleCompletion(disable_all)
  if disable_all == 1 then
    local v = vim.g.autocomplete
    v.auto_popup_disabled = not v.auto_popup_disabled
    vim.g.autocomplete = v
    local s = v.auto_popup_disabled and 'disabled' or 'enabled'
    print('[autocomplete] auto popup ' .. s .. ' for all buffers')
  elseif vim.b.completion_auto_popup == nil then
    M.initialize()
  else
    vim.b.completion_auto_popup = not vim.b.completion_auto_popup
    local s = vim.b.completion_auto_popup and 'enabled' or 'disabled'
    print('[autocomplete] auto popup ' .. s .. ' for current buffer')
  end
end

function M.initialize(opt)
  vim.fn['autocomplete#attach']()
  if opt == nil then return end
  local sorter = opt.sorter
  local matcher = opt.matcher
  if sorter ~= nil then
    vim.validate{sorter={sorter, 'string'}}
    vim.b.completion_sorting = sorter
  end
  if matcher ~= nil then
    vim.validate{matcher={matcher, 'table'}}
    vim.b.completion_matching = matcher
  end
end



------------------------------------------------------------------------
--                      post-completion edits                         --
------------------------------------------------------------------------

-- apply additionalTextEdits in LSP specs
local function applyAddtionalTextEdits(completed_item)
  local item = completed_item.user_data.lsp.completion_item
  -- vim-vsnip have better additional text edits...
  if vim.fn.exists('g:loaded_vsnip_integ') == 1 then
    vim.fn['vsnip_integ#do_complete_done']({
      completed_item = completed_item,
      completion_item = item,
      apply_additional_text_edits = true
    })
  else
    if item.additionalTextEdits then
      local lnum = vim.fn.getcurpos()[2]
      local edits = vim.tbl_filter(
        function(x) return x.range.start.line ~= (lnum - 1) end,
        item.additionalTextEdits
      )
      vim.lsp.util.apply_text_edits(edits, vim.fn.bufnr())
    end
  end
end

local function AddParens(completed_item)
  if completed_item.kind == nil then return end
  if  string.match(completed_item.kind, '.*Function.*') ~= nil or
      string.match(completed_item.kind, '.*Method.*') then
    api.nvim_input("()<left>")
  end
end

-- This function is triggered by manual confirmation, in the case that
-- a mapping for it has been set.
function M.confirmCompletion()
  Var.confirmedCompletion = true
end

function M.hasConfirmedCompletion()
  local completed_item = vim.v.completed_item
  if completed_item.user_data.lsp ~= nil then
    applyAddtionalTextEdits(completed_item)
  end
  if vim.g.autocomplete.auto_paren == 1 then
    AddParens(completed_item)
  end
  if completed_item.user_data.snippet == 'UltiSnips' then
    vim.fn['UltiSnips#ExpandSnippet']()
  elseif completed_item.user_data.snippet == 'Neosnippet' then
    api.nvim_input("<c-r>".."=neosnippet#expand('"..completed_item.word.."')".."<CR>")
  elseif completed_item.user_data.snippet == 'vim-vsnip' then
    vim.fn['vsnip#expand']()
  end
end

return M


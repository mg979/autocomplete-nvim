local vim = vim
local api = vim.api
local sources = require 'autocomplete.sources'
local completion = require 'autocomplete.completion'
local hover = require'autocomplete.hover'
local Var = require 'autocomplete.manager'

local M = {}
local G = vim.g.autocomplete



------------------------------------------------------------------------
--                            autocommands                            --
------------------------------------------------------------------------

function M.on_InsertCharPre()
  Var.insertChar = true
  Var.textHover = true
  Var.selected = -1
  if vim.fn.pumvisible() == 0 then
    Var.chainIndex = 1
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
  if vim.b.completion_auto_popup == 1 then completion.popup.auto.start() end
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



------------------------------------------------------------------------
--                          external commands                         --
------------------------------------------------------------------------

function M.manualCompletion()
  Var.forceCompletion = true
  completion.popup.manual()
end

-- provide api for custom sources
function M.addSource(key, value)
  if sources.builtin[key] or sources.ctrlx[key] then
    return
  end
  sources.builtin[key] = value
end

function M.toggleCompletion()
  if vim.b.completion_auto_popup == nil then
    M.initialize()
  elseif vim.b.completion_auto_popup == 0 then
    vim.b.completion_auto_popup = 1
  else
    vim.b.completion_auto_popup = 0
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
--                         confirm completion                         --
------------------------------------------------------------------------

-- post-completion edits handled by lsp client or vim-vsnip
-- @param completed_item the item that has just been selected/completed
local function PostCompletionEdits(completed_item)
  local item = completed_item.user_data.lsp.completion_item
  local lnum = api.nvim_win_get_cursor(0)[0]
  local bufnr = api.nvim_get_current_buf()
  if item.additionalTextEdits then
    local edits = vim.tbl_filter(
    function(x) return x.range.start.line ~= (lnum - 1) end,
    item.additionalTextEdits
    )
    vim.lsp.util.apply_text_edits(edits, bufnr)
  end
  if vim.fn.exists('g:loaded_vsnip_integ') == 1 then
    api.nvim_call_function('vsnip_integ#on_complete_done_for_lsp',
    { { completed_item = completed_item, completion_item = item } })
  end
end

local function AddParens(completed_item)
  if completed_item.kind == nil then return end
  if string.match(completed_item.kind, '.*Function.*') ~= nil
    or string.match(completed_item.kind, '.*Method.*') then
    api.nvim_input("()<left>")
  end
end

-- This function is triggered by manual confirmation, in the case that
-- a mapping for it has been set.
function M.confirmCompletion()
  Var.confirmedCompletion = true
end

function M.hasConfirmedCompletion()
  local completed_item = api.nvim_get_vvar('completed_item')
  if completed_item.user_data.lsp ~= nil then
    PostCompletionEdits(completed_item)
  end
  if G.auto_paren == 1 then
    AddParens(completed_item)
  end
  if completed_item.kind == 'UltiSnips' then
    api.nvim_call_function('UltiSnips#ExpandSnippet', {})
  elseif completed_item.kind == 'Neosnippet' then
    api.nvim_input("<c-r>".."=neosnippet#expand('"..completed_item.word.."')".."<CR>")
  elseif completed_item.kind == 'vim-vsnip' then
    api.nvim_call_function('vsnip#expand', {})
  end
end

return M


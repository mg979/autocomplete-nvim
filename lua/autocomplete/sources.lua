local vim = vim
local util = require 'autocomplete.util'
local lsp = require 'autocomplete.sources.lsp'
local snippet = require 'autocomplete.sources.snippet'
local path = require 'autocomplete.sources.path'
local Var = require 'autocomplete.manager'

local M = {}
local is_keyword = '\\<\\k\\+'
local is_slash = vim.fn.has('win32') == 1 and {'\\'} or {'/'}


----------------------------------------------------------------------------------------
--|                               tables                                              -|
--|                                                                                   -|
--| Possible properties for sources are:                                              -|
--|                                                                                   -|
--| generateItems: function to generate a list of completion items                    -|
--| callback:      becomes true when item generation has been completed               -|
--| items:         function to collect the completion items once generated            -|
--| asynch:        boolean that flags asynch sources                                  -|
--| triggerLength: minimum length of the word before completion can trigger           -|
--| triggers:      [func->] list of chars that can trigger the completion             -|
--| regexes:       [func->] list of regexes that can trigger the completion           -|
----------------------------------------------------------------------------------------

M.builtin = {
  ['lsp'] = {
    generateItems = lsp.triggerFunction,
    callback = lsp.getCallback,
    items = lsp.getLspCompletions,
    asynch = true,
    triggers = function() return vim.b.completion_triggers.lsp or vim.b.lsp_triggers end,
    triggerLength = vim.g.autocomplete.trigger_length,
  },
  ['snippet'] = {
    items = snippet.getSnippets,
    triggerLength = 1,
  },
  ['path'] = {
    generateItems = path.triggerFunction,
    callback = path.getCallback,
    items = path.getPaths,
    asynch = true,
    triggerLength = vim.g.autocomplete.trigger_length,
    triggers = is_slash,
    regexes = {'\\f\\+'},
  },
}

M.ctrlx = {
  ['line'] = "<c-x><c-l>",
  ['cmd'] = "<c-x><c-v>",
  ['defs'] = "<c-x><c-d>",
  ['dict'] = "<c-x><c-k>",
  ['file'] = "<c-x><c-f>",
  ['incl'] = "<c-x><c-i>",
  ['keyn'] = "<c-x><c-n>",
  ['keyp'] = "<c-x><c-p>",
  ['omni'] = "<c-x><c-o>",
  ['spel'] = "<c-x>s",
  ['tags'] = "<c-x><c-]>",
  ['thes'] = "<c-x><c-t>",
  ['user'] = "<c-x><c-u>",
  ['c-p'] = "<c-g><c-g><c-p>",
  ['c-n'] = "<c-g><c-g><c-n>",
}

function M.lspTriggerCharacters()
  for _, client in pairs(vim.lsp.buf_get_clients()) do
    if client.server_capabilities.completionProvider ~= nil then
      return client.server_capabilities.completionProvider.triggerCharacters
    end
  end
  return nil
end

function M.getCurrent()
  return Var.activeChain[Var.chainIndex]
end


------------------------------------------------------------------------
-- source triggers                                                    --
------------------------------------------------------------------------

-- return a list of triggers for the requested completion method
function M.getTriggers(source)
  local triggers = {}
  for _, m in ipairs(source.methods) do
    -- for ins-completion methods, trigger is regex-based
    -- we just make exceptions for file/omni/tags completion
    if M.ctrlx[m] then
      return m == 'file' and is_slash or
             m == 'omni' and {'.'} or
             m == 'tags' and {'.'} or {}
    end
    -- source.triggers can be either a function or a list
    local trg = M.builtin[m].triggers or {}
    if type(trg) == 'function' then trg = trg() or {} end
    for _,val in ipairs(trg) do
      table.insert(triggers, val)
    end
  end
  -- also add buffer-local extra triggers if they have been defined
  local buflocal = vim.b.autocomplete_extra_triggers
  if buflocal then
    if util.is_list(buflocal) then
      for _,val in ipairs(buflocal) do table.insert(triggers, val) end
    else
      for k,v in pairs(buflocal) do
        if k == 'default' then
          for _,val in ipairs(v) do table.insert(triggers, val) end
        else
          for kb,mb in pairs(buflocal) do
            if M.ctrlx[kb] or M.builtin[kb] then
              for _,val in ipairs(mb) do table.insert(triggers, val) end
            end
          end
        end
      end
    end
  end
  return triggers
end

function M.getRegexes(source)
  local regexes = {}
  for _, m in ipairs(source.methods) do
    -- method.regexes can be either boolean, a function or a list
    if M.ctrlx[m] then return {is_keyword} end
    local rxs = M.builtin[m].regexes or {}
    if type(rxs) == 'function' then rxs = rxs() or {} end
    for _,val in ipairs(rxs) do
      table.insert(regexes, val)
    end
  end
  return regexes
end

return M

local vim = vim
local lsp = require 'autocomplete.sources.lsp'
local snippet = require 'autocomplete.sources.snippet'
local path = require 'autocomplete.sources.path'
local util = require 'autocomplete.util'
local Var = require 'autocomplete.manager'

local M = {}
local is_keyword = '\\<\\k\\+'
local is_path = vim.fn.has('win32') == 1 and '\\\\\\?f*$' or '/\\?\\f*$'


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
    pattern = is_path,
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
  -- return buffer-local triggers if they have been defined
  local buftriggers = vim.b.completion_triggers
  if buftriggers then
    for _, method in ipairs(source.methods) do
      if buftriggers[method] then
        table.insert(triggers, unpack(buftriggers[method]))
      end
    end
    if next(triggers) then return triggers end
  end
  for _, m in ipairs(source.methods) do
    -- for ins-completion methods, trigger is regex-based
    -- we just make exceptions for omni/tags completion
    if M.ctrlx[m] then
      return m == 'omni' and {'.'} or
             m == 'tags' and {'.'} or {}
    end
    -- source.triggers can be either a function or a list
    local trg = M.builtin[m].triggers or {}
    if type(trg) == 'function' then trg = trg() or {} end
    for _,val in ipairs(trg) do
      table.insert(triggers, val)
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

-- A source can define its own pattern to match the currently typed word.
-- While most sources will look for keyword characters, some may want to look
-- for special characters as well. If the source doesn't specify a pattern, the
-- default '\\k*$' will be used, and this function will return nil.
--
-- Example: paths will look for slashes and all legal filename characters
--
function M.getPatternForPartialWord(method)
  if util.is_list(method) then
    return nil
  elseif M.ctrlx[method] then
    return method == 'file' and is_path or nil
  else
    return M.builtin[method].pattern
  end
end

return M

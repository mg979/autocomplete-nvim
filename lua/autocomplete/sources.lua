local vim = vim
local lsp = require 'autocomplete.sources.lsp'
local snippet = require 'autocomplete.sources.snippet'
local path = require 'autocomplete.sources.path'
local util = require 'autocomplete.util'
local Var = require 'autocomplete.manager'

local M = {}
local is_path = '\\f*$'


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
--| regex:         bool or regex pattern that can trigger the completion              -|
----------------------------------------------------------------------------------------

M.registered = {
  ['lsp'] = {
    generateItems = lsp.triggerFunction,
    callback = lsp.getCallback,
    items = lsp.getLspCompletions,
    asynch = true,
    triggers = function() return vim.b.completion_triggers.lsp or vim.b.lsp_triggers end,
  },
  ['snippet'] = {
    items = snippet.getSnippets,
    triggerLength = 1,
    -- accept any punctuation or alphanumeric character, except opening brackets
    pattern = '\\%([[:punct:][:alnum:]]\\&[^([{]\\)*$'
  },
  ['path'] = {
    generateItems = path.triggerFunction,
    callback = path.getCallback,
    items = path.getPaths,
    asynch = true,
    pattern = is_path,
  },
}

local ctrlx = {
  ['line'] = "<c-x><c-l>",
  ['cmd']  = "<c-x><c-v>",
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

for k,v in pairs(ctrlx) do
  M.registered[k] = {
    feedKeys        = true,
    keys            = v,
    asynch          = false,
    pattern         = k == 'file' and is_path or nil,
    allowBackspace  = (k == 'file' or k == 'line') and true or nil
  }
end

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
function M.getTriggers(src)
  local triggers = {}
  -- return buffer-local triggers if they have been defined
  local buftriggers = vim.b.completion_triggers
  if buftriggers then
    for _, method in ipairs(src.methods) do
      if buftriggers[method] then
        table.insert(triggers, unpack(buftriggers[method]))
      end
    end
    if next(triggers) then return triggers end
  end
  for _, m in ipairs(src.methods) do
    -- for ins-completion methods, trigger is regex-based
    -- we just make exceptions for omni/tags completion
    if src.feedKeys then
      return m == 'omni' and {'.'} or
             m == 'tags' and {'.'} or {}
    end
    -- src.triggers can be either a function or a list
    local trg = M.registered[m].triggers or {}
    if type(trg) == 'function' then trg = trg() or {} end
    for _,val in ipairs(trg) do
      table.insert(triggers, val)
    end
  end
  return triggers
end

-- Sources can define a regex pattern that must match in the line. If no pattern
-- is defined (as it usually happens) then we assume completion can be tried.
-- If it is defined as 'false', this check always fails: then the source needs
-- a valid trigger for completion to be attempted.
--
function M.checkRegex(src, line_to_cursor)
  for _, m in ipairs(src.methods) do
    -- ins-completion methods are always ok
    if src.feedKeys then return true end
    -- if method.regex is absent, we assume it can match
    if M.registered[m].regex == nil or M.registered[m].regex == true then return true
    elseif M.registered[m].regex == false then return false end
    if vim.fn.match(line_to_cursor, M.registered[m].regex .. '$') >= 0 then return true end
  end
  return false
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
    for _,v in ipairs(method) do
      if M.registered[v].pattern then
        return M.registered[v].pattern
      end
    end
    return Var.default_pattern
  else
    return M.registered[method].pattern or Var.default_pattern
  end
end

return M

local util = require 'autocomplete.util'
local sources = require 'autocomplete.sources'
local Var = require 'autocomplete.manager'
local M = {}

-- Chains are obtained from the current value of g:autocomplete.chains, or
-- from b:autocomplete_chain if it exists. A chain is a list of completion
-- methods, expressed either as:
--
--    string          (a single method)
--    list of strings (methods to be merged in a single popup)
--
-- Chains must be fetched from the global/buffer variable, then each member
-- must be validated. Once done, each member must be converted to a table:
--
-- {
--   methods:         a list of methods (can be a single method in a list)
--   asynch:          boolean
--   insCompletion:   boolean
--   triggerLength:   the minimum trigger length for the methods
--
-- [optional]
--   pattern:         if not nil, it's the pattern to be used for the prefix
--   notIfPumvisible: stop evaluating completions if popup is already visible
-- }



------------------------------------------------------------------------
--                           local defaults                           --
------------------------------------------------------------------------

-- trigger length to be used for method if it doesn't define it in its table
local defaultTriggerLength = vim.g.autocomplete.trigger_length

-- default chain to be used if no valid chain can be fetched from definitions
local defaultScopedChain = {
    comment = { 'file', 'keyn' },
    default = { {'snippet', 'lsp'}, 'file', 'keyn' }
  }


------------------------------------------------------------------------
--                     default chain verification                     --
------------------------------------------------------------------------

-- default chain to be used if no valid chain can be fetched from definitions
local function getDefaultChain()
  return M.defaultChain or {
        comment = { 'file', 'keyn' },
        default = { {'snippet', 'lsp'}, 'file', 'keyn' }
      }
end

local function verifyDefaultChain()
  if M.defaultChain then
    return
  elseif not vim.g.autocomplete.chains.default then
    M.defaultChain = defaultScopedChain
  else
    M.defaultChain = M.toScoped(vim.g.autocomplete.chains.default, 1)
  end
end

------------------------------------------------------------------------
--                  local functions to parse chains                   --
------------------------------------------------------------------------

local function getScopedChain(ft_chain)
  -- a generic, non-scoped chain
  if #ft_chain > 0 then return ft_chain end

  local atPoint = util.syntaxAtCursor():lower()
  -- check if the filetype chain has a match for the current scope
  for syntax, chain in pairs(ft_chain) do
    if syntax ~= 'default' and string.match(atPoint, '.*' .. syntax:lower() .. '.*') then
      return chain
    end
  end
  -- default chain for unmatched syntaxes exists
  if ft_chain.default then return ft_chain.default end

  -- nothing matches, process the default chain
  return getScopedChain(getDefaultChain())
end

-- get a chain that the result of a merge of the user-defined chain, and the
-- default chain, converting the user chain to a scoped chain if necessary
function M.toScoped(chain, is_default)
  local scoped = {}
  if util.is_list(chain) then
    -- if user-defined chain is not scoped, turn it into one
    for k,v in pairs(is_default and defaultScopedChain or getDefaultChain()) do
      scoped[k] = { unpack(v) }
    end
    -- overwrite default scope with the chain provided by the user
    scoped.default = { unpack(chain) }
  else
    -- extend the default scoped chain with the user-defined one
    for k,v in pairs(is_default and defaultScopedChain or getDefaultChain()) do
      scoped[k] = { unpack(v) }
    end
    for k,v in pairs(chain) do
      scoped[k] = { unpack(v) }
    end
  end
  return scoped
end

local function getGlobalChain(filetype)
  local chains = vim.g.autocomplete.chains
  if util.is_list(chains) then
    return M.toScoped(chains)
  elseif chains[filetype] then
    return M.toScoped(chains[filetype])
  elseif chains.default then
    return M.toScoped(chains.default, true)
  else
    return getDefaultChain()
  end
end


------------------------------------------------------------------------
--                          chain validation                          --
------------------------------------------------------------------------

-- add missing members in valid sources
local function fixItem(item)
  -- make sure the method has a defined triggerLength
  if not sources.registered[item].triggerLength then
    sources.registered[item].triggerLength = defaultTriggerLength
  end
end

-- check that all elements are valid sources
function M.validateChainItem(item)
  if util.is_list(item) then
    -- if the item is a list, elements cannot be ins-completion sources
    for _, v in ipairs(item) do
      if sources.registered[v].insCompletion then return nil
      else fixItem(v) end
    end
  elseif not sources.registered[item] then
    return nil
  else
    fixItem(item)
  end
  return item
end



------------------------------------------------------------------------
--                          chain conversion                          --
------------------------------------------------------------------------

-- extend sources with custom options
local function extendItem(item)
  local method = item.methods[1]
  if vim.g.autocomplete.sources[method] then
    for k,v in pairs(vim.g.autocomplete.sources[method]) do
      item[k] = v
    end
  end
  return item
end

-- each validated element must be converted to a table
-- this process takes place once when the buffer-local chain is assigned
local function convertChain(chain)
  local validated = {}
  for _, m in ipairs(chain) do
    if M.validateChainItem(m) then
      -- turn each chain member into a table
      local item = {}
      if util.is_list(m) then
        local tl
        item.methods = m
        item.asynch = false
        for _, v in ipairs(m) do
          -- item.asynch will be true if any of the methods is asynch
          if sources.registered[v].asynch then
            item.asynch = true
          end
          -- item.triggerLength will be the highest of the methods triggerLength's
          if not tl or sources.registered[v].triggerLength < tl then
            tl = sources.registered[v].triggerLength
          end
        end
        item.triggerLength = tl
      else
        item.asynch = sources.registered[m].asynch
        item.methods = {m}
        item.triggerLength = sources.registered[m].triggerLength or defaultTriggerLength
        item.insCompletion = sources.registered[m].insCompletion
      end
      item.pattern = sources.getPatternForPartialWord(m)
      table.insert(validated, extendItem(item))
    end
  end
  return validated
end


------------------------------------------------------------------------
--                        main module function                        --
------------------------------------------------------------------------

local function bufferChain(filetype)
  -- return previously generated chain
  local bufnr = vim.fn.bufnr()
  if Var.chains[bufnr] then return Var.chains[bufnr] end

  -- verify default chain first
  verifyDefaultChain()

  -- chain could be local to buffer
  local chain = vim.b.autocomplete_chain and
                M.toScoped(vim.b.autocomplete_chain) or getGlobalChain(filetype)

  local validated = {}
  for scope, scopedChain in pairs(chain) do
    validated[scope] = convertChain(scopedChain)
  end
  -- store chain in buffer variable
  Var.chains[bufnr] = validated
  if vim.g.autocomplete.debug then print(vim.inspect(validated)) end
  return validated
end

function M.getChain()
  return getScopedChain(bufferChain(vim.bo.filetype))
end


return M

local util = require 'autocomplete.util'
local sources = require 'autocomplete.sources'
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
--   methods:       a list of methods (can be a single method in a list)
--   asynch:        boolean
--   triggerLength: the minimum trigger length for the methods
-- }



------------------------------------------------------------------------
--                           local defaults                           --
------------------------------------------------------------------------

-- trigger length to be used for method if it doesn't define it in its table
local defaultTriggerLength = vim.g.autocomplete.trigger_length.default or 2

-- regex triggers to be used for method if it doesn't define any in its table
local defaultRegexes = {'\\<\\k\\+'}

-- default chain to be used if no valid chain can be fetched from definitions
local defaultScopedChain = {
    comment = { 'path', 'keyn' },
    default = { {'snippet', 'lsp'}, 'path', 'keyn' }
  }


------------------------------------------------------------------------
--                  local functions to parse chains                   --
------------------------------------------------------------------------

local function getScopedChain(ft_chain)
  -- a generic chain, not filetype-specific
  if util.is_list(ft_chain) then return ft_chain end

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
  return getScopedChain(vim.g.autocomplete.default_chain or defaultScopedChain)
end

local function getGlobalChain(filetype)
  local chains = vim.g.autocomplete.chains
  if util.is_list(chains) then
    return chains
  elseif chains[filetype] then
    return chains[filetype]
  elseif chains.default then
    return chains.default
  else
    return vim.g.autocomplete.default_chain or defaultScopedChain
  end
end


------------------------------------------------------------------------
--                          chain validation                          --
------------------------------------------------------------------------

local function fixItem(item)
  -- fix mandatory missing members in valid sources
  if sources.builtin[item] then
    -- an item must have some way of being triggered
    if not sources.builtin[item].triggers and
      not sources.builtin[item].regexes then
      sources.builtin[item].regexes = defaultRegexes
    end
    -- make sure the method has a defined triggerLength
    if not sources.builtin[item].triggerLength then
      sources.builtin[item].triggerLength = defaultTriggerLength
    end
  end
end

-- check that all elements are valid sources
function M.validateChainItem(item)
  if util.is_list(item) then
    -- if the item is a list, its elements must be built-in sources
    for _, v in ipairs(item) do
      if not sources.builtin[v] then return nil
      else fixItem(v) end
    end
  elseif not sources.builtin[item] and
         not sources.ctrlx[item] then
    return nil
  else
    fixItem(item)
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
      if sources.ctrlx[m] then
        item.asynch = false
        item.methods = {m}
        item.triggerLength = defaultTriggerLength
      else
        if util.is_list(m) then
          local tl
          item.methods = m
          item.asynch = false
          for _, v in ipairs(m) do
            -- item.asynch will be true if any of the methods is asynch
            if sources.builtin[v].asynch then
              item.asynch = true
            end
            -- item.triggerLength will be the highest of the methods triggerLength's
            if not tl or sources.builtin[v].triggerLength < tl then
              tl = sources.builtin[v].triggerLength
            end
          end
          item.triggerLength = tl
        else
          item.asynch = sources.builtin[m].asynch or false
          item.methods = {m}
          item.triggerLength = sources.builtin[m].triggerLength or defaultTriggerLength
        end
      end
      table.insert(validated, item)
    end
  end
  return validated
end


------------------------------------------------------------------------
--                        main module function                        --
------------------------------------------------------------------------

local function bufferChain(filetype)
  -- return previously generated chain
  if vim.b._autocomplete_chain then return vim.b._autocomplete_chain end
  -- chain could be local to buffer
  local chain = vim.b.autocomplete_chain or getGlobalChain(filetype)

  local validated = {}
  if util.is_list(chain) then
    validated = convertChain(chain)
  else
    for scope, scopedChain in pairs(chain) do
      validated[scope] = convertChain(scopedChain)
    end
  end
  -- store chain in buffer variable
  util.setBufVar('_autocomplete_chain', validated)
  return validated
end

function M.getChain()
  return getScopedChain(bufferChain(vim.bo.filetype))
end


return M

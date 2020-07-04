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
--                  local functions to parse chains                   --
------------------------------------------------------------------------

local function getScopedChain(ft_chain)
  local atPoint = util.syntaxAtCursor():lower()
  -- check if the filetype chain has a match for the current scope
  for syntax, chain in pairs(ft_chain) do
    if string.match(atPoint, '.*' .. syntax:lower() .. '.*') then
      return chain
    end
  end
  -- by default, in comments only complete paths and words from this buffer
  if string.match(atPoint, '.*comment.*') then
    return { 'path', 'keyn' }
  else
    -- return the default chain
    return vim.g.autocomplete.default_chain or { { 'snippet', 'lsp' }, 'path', 'keyn', 'c-n' }
  end
end

local function getInnerChain(chains)
  return util.is_list(chains) and chains or getScopedChain(chains)
end

local function getGlobalChain(filetype)
  local chains = vim.g.autocomplete.chains
  if util.is_list(chains) then
    return chains
  elseif chains[filetype] then
    return getInnerChain(chains[filetype])
  elseif chains.default then
    return getInnerChain(chains.default)
  else
    return getScopedChain({})
  end
end


------------------------------------------------------------------------
--                          chain validation                          --
------------------------------------------------------------------------

-- check that all elements are valid sources
function M.validateChainItem(item)
  if util.is_list(item) then
    -- if the item is a list, its elements must be built-in sources
    for _, v in ipairs(item) do
      if not sources.builtin[v] then return nil end
    end
  elseif not sources.builtin[item] and
         not sources.ctrlx[item] then
    return nil
  end
  return item
end


------------------------------------------------------------------------
--                        main module function                        --
------------------------------------------------------------------------

function M.getChain(filetype)
  -- return previously generated chain
  if vim.b._autocomplete_chain then return vim.b._autocomplete_chain end
  -- chain could be local to buffer
  local chain, ft_chain = vim.b.autocomplete_chain
  if ft_chain ~= nil then
    -- if it is, it could be a simple list, or a table with scopes
    chain = util.is_list(ft_chain) and ft_chain or getScopedChain(ft_chain)
  else
    -- if it's not, use the global chains definitions
    chain = getGlobalChain(filetype)
  end

  -- trigger length to be used for method if it doesn't define it in its table
  local defaultTriggerLength = vim.g.autocomplete.trigger_length.default or 2

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
          local tl = 0
          item.methods = m
          item.asynch = false
          for _, v in ipairs(m) do
            -- item.asynch will be true if any of the methods is asynch
            if sources.builtin[v].asynch then
              item.asynch = true
            end
            -- item.triggerLength will be the highest of the methods triggerLength's
            if sources.builtin[v].triggerLength > tl then
              tl = sources.builtin[v].triggerLength
            end
          end
          item.triggerLength = tl
        else
          item.asynch = m.asynch
          item.methods = {m}
          item.triggerLength = sources.builtin[m].triggerLength or defaultTriggerLength
        end
      end
      table.insert(validated, item)
    end
  end
  -- store chain in buffer variable
  util.setBufVar('_autocomplete_chain', validated)
  return validated
end


return M

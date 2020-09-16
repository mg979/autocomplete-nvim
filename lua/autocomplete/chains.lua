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
--   feedKeys:        boolean (the source uses feedkeys for the popup)
--   prefixLen:       the minimum prefix length for the methods
--
-- [optional]
--   pattern:         if not nil, it's the pattern to be used for the prefix
--   allowBackspace:  leave popup alone also when backspacing
-- }



------------------------------------------------------------------------
--                           local defaults                           --
------------------------------------------------------------------------

-- default chain to be used if no valid chain can be fetched from definitions
local defaultScopedChain = {
  comment = { 'keyn' },
  default = { {'snippet', 'lsp'}, 'keyn', 'file' }
}


------------------------------------------------------------------------
--                     default chain verification                     --
------------------------------------------------------------------------

-- default chain to be used if no valid chain can be fetched from definitions
local function getDefaultChain()
  return M.defaultChain or {
    comment = { 'keyn' },
    default = { {'snippet', 'lsp'}, 'keyn', 'file' }
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

-- check that all elements are valid sources
function M.validateChainItem(item)
  if util.is_list(item) then
    -- if the item is a list, elements cannot be ins-completion sources
    for _, v in ipairs(item) do
      if sources.registered[v].feedKeys then return nil end
    end
  elseif not sources.registered[item] then
    return nil
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

-- turn a chain member into a table
local function convertItem(m)
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
      if sources.registered[v].allowBackspace then
        item.allowBackspace = true
      end
      -- item.prefixLen will be the highest of the methods prefixLen's
      local mtl = sources.registered[v].prefixLen or
                  vim.g.autocomplete.prefix_length
      if not tl or mtl < tl then tl = mtl end
    end
    item.prefixLen = tl
  else
    item.asynch = sources.registered[m].asynch
    item.methods = {m}
    item.prefixLen = sources.registered[m].prefixLen or
                     vim.g.autocomplete.prefix_length
    item.feedKeys = sources.registered[m].feedKeys
    item.allowBackspace = sources.registered[m].allowBackspace
  end
  item.pattern = sources.getPatternForPartialWord(m)
  return extendItem(item)
end

-- each validated element must be converted to a table
-- this process takes place once when the buffer-local chain is assigned
local function convertChain(chain)
  local validated = {}
  for _, m in ipairs(chain) do
    if M.validateChainItem(m) then
      table.insert(validated, convertItem(m))
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

function M.updateChain()
  Var.chains[vim.fn.bufnr()] = nil
  Var.activeChain = M.getChain()
end


return M

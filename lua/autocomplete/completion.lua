local vim = vim
local Var = require 'autocomplete.manager'
local util = require 'autocomplete.util'
local sources = require 'autocomplete.sources'
local chains = require 'autocomplete.chains'
local hover = require'autocomplete.hover'
local signature = require'autocomplete.signature_help'

local completion = { popup = { auto = {} }, asynch = {} }
local popup = completion.popup
local asynch = completion.asynch
local pumvisible = function() return vim.fn.pumvisible() == 1 end


------------------------------------------------------------------------
--                     initialize/retry completion                    --
------------------------------------------------------------------------

-- init completion source and variables
function completion.init()
  Var.init()
  -- LSP triggers shouldn't change once loaded, am I wrong?
  if not vim.b.completion_triggers.lsp and
     vim.lsp.buf_get_clients() ~= nil and
     vim.b.lsp_triggers == nil then
    util.setBufVar('lsp_triggers', sources.lspTriggerCharacters())
  end
end

-- current completion must be re-evaluated
function completion.retry()
  Var.changedTick = 0
  Var.insertChar = true
  asynch.stop()
  popup.dismiss()
  completion.try()
end

function completion.reset()
  Var.changedTick = 0
  Var.chainIndex = 1
  asynch.stop()
  popup.dismiss()
end



------------------------------------------------------------------------
--                            local helpers                           --
------------------------------------------------------------------------

-- check if hover popup should open
local function openHover()
  if vim.g.autocomplete.auto_hover == 1 then
    hover.autoOpenHoverInPopup()
  end
end

-- check if signature popup should open
local function checkSignature(line_to_cursor)
  if vim.g.autocomplete.auto_signature == 1 then
    signature.autoOpenSignatureHelp(line_to_cursor)
  end
end

-- verify that there were changes to buffer
local function changedTick()
  local tick = vim.api.nvim_buf_get_changedtick(0)
  if tick == Var.changedTick then return false end
  Var.changedTick = tick
  return true
end

-- run the functions that will fetch the completion items for custom methods
local function getCompletionItems(items_array, prefix)
  local src = {}
  for _,func in ipairs(items_array) do
    local res = func(prefix, util.fuzzy_score)
    if res then vim.list_extend(src, func(prefix, util.fuzzy_score)) end
  end
  return src
end

-- return true when all callbacks in array are true
local function checkCallback(callback_array)
  for _,val in ipairs(callback_array) do
    if not val or type(val) == 'function' and not val() then
      return false
    end
  end
  return true
end

------------------------------------------------------------------------
-- getPositionalParams returns 3 values:
--
-- line_to_cursor:  the string with the part of the line up to the cursor
-- from_column:     the column at which the current prefix starts
-- prefix:          the part of the word for which we could find a completion
------------------------------------------------------------------------
local function getPositionalParams()
  local line           = vim.api.nvim_get_current_line()
  local pos            = vim.api.nvim_win_get_cursor(0)
  local line_to_cursor = line:sub(1, pos[2])
  local from_column    = vim.fn.match(line_to_cursor, '\\k*$')
  local prefix         = line_to_cursor:sub(from_column+1)
  return line_to_cursor, from_column, prefix
end

------------------------------------------------------------------------
-- getArrays returns 2 values:
--
-- callback_array:  callbacks become true when completion items have been generated
-- items_array:     array of generateItems functions for each completion source
------------------------------------------------------------------------
local function getArrays(methods, prefix, from_column)
  local callback_array = {}
  local items_array = {}
  for _, s in ipairs(methods) do
    local src = sources.builtin[s]
    -- we include the source in the popup only if we typed enough characters
    -- if #prefix == 0, it means a non-keyword char has triggered the completion
    -- (example: '.' for member completion), in this case we include it anyway
    if Var.forceCompletion or #prefix == 0 or src.triggerLength <= #prefix then
      table.insert(callback_array, src.callback or true)
      -- a bit messy: we can have only src.items or we can have both
      -- src.generateItems and src.items (both must be functions)
      if src.generateItems then src.generateItems(prefix, from_column) end
      if src.items then table.insert(items_array, src.items) end
    end
  end
  return items_array, callback_array
end



------------------------------------------------------------------------
--                           popup controls                           --
------------------------------------------------------------------------

-- feed the key sequence that resets completion
function popup.dismiss()
  if pumvisible() then
    vim.fn.complete(vim.api.nvim_win_get_cursor(0)[2], {})
  end
end


-- Manually triggered completion
function popup.manual()
  Var.forceCompletion = true
  if pumvisible() or not Var.canTryCompletion then
    return completion.retry() -- manual completion will be retriggered
  end
  -- set these variables to pass the tests in completion.try()
  Var.changedTick = 0
  Var.insertChar = true
  completion.try()
end


-- stop timer for auto popup if still ongoing
function popup.auto.stop()
  if popup.timer and not popup.timer:is_closing() then
    popup.timer:stop()
    popup.timer:close()
  end
end


-- stop autopopup timer and start a new one
function popup.auto.restart()
  popup.auto.stop()
  popup.auto.start()
end


function popup.auto.start()
  popup.timer = vim.loop.new_timer()
  popup.timer:start(100, vim.g.autocomplete.timer_cycle, vim.schedule_wrap(function()
    if not util.isInsertMode() then return popup.auto.stop() end
    completion.try()
  end))
end



------------------------------------------------------------------------
--                 verify prerequisites for completion                --
------------------------------------------------------------------------

-- Test if completion can be triggered, if this will result in a completion
-- popup will obviously depend on whether there are candidates for the prefix.
-- Here we'll consider (in order):
--
-- canTryCompletion:  flag for asynch completion in progress, nothing can be
--                    done while this is false
-- changedTick:       differently from insertChar, this is tested early, there
--                    are other conditions that can change the tick, other than
--                    insertChar
-- check source:      check there is a valid chain/source
-- check hover:       hover should appear for TextChangedP, but not after insertChar
-- check insertChar:  stop if no character is inserted
-- check signature:   differently from hover, signature needs an inserted character
-- check triggers:    these are characters of any type that alone are enough to
--                    warrant a completion attempt, they are source-specific
-- prefix length:     auto popup should be only triggered after a certain number
--                    of characters has been entered
-- forceCompletion:   by manual completion or manual source change, it bypasses
--                    prefix lenght check
-- check regex:       also source-specific, for sources without triggers
--
-- If no completion can/should be tried for the current source, try the next
-- one, unless already at the last chain.
------------------------------------------------------------------------
function completion.try()
  -- asynch completion timer in progress
  if not Var.canTryCompletion then return end

  -- do nothing if no changes to buffer
  if not changedTick() then return end

  -- verify that there's some source
  Var.activeChain = chains.getChain()
  local src = sources.getCurrent()
  if not src then return end

  openHover() -- open hover popup if appropriate

  -- stop if no new character has been inserted, or reset the flag
  if not Var.insertChar then return else Var.insertChar = false end

  local line_to_cursor, from_column, prefix = getPositionalParams()

  checkSignature(line_to_cursor) -- open signature popup if appropriate

  -- check the triggers now, because also non-keyword characters could be valid
  -- triggers, but prefix only matches keyword characters
  local can_trigger = util.checkTriggers(line_to_cursor, sources.getTriggers(src))

  -- don't proceed when backspacing in insert mode, or when typing a new word
  local word_too_short = not Var.forceCompletion and
                         not can_trigger and
                         #prefix < src.triggerLength

  if word_too_short then return completion.reset() end

  local can_try = Var.forceCompletion or
                  can_trigger or
                  util.checkRegexes(line_to_cursor, sources.getRegexes(src))

  -- print(vim.inspect(src.methods), prefix, can_trigger, can_try) -- DEBUG

  if can_try then
    completion.perform(src, prefix, from_column)
  -- not because a method can't be tried we're blocking the whole chain...
  -- but if it's the last chain this could lead to an endless loop
  elseif Var.chainIndex ~= #Var.activeChain then
    completion.nextSource()
  end
end


-- run the appropriate completion method
function completion.perform(src, prefix, from_column)
  if sources.ctrlx[src.methods[1]] then -- it's and ins-completion source
    completion.ctrlx(src.methods[1])
  elseif src.asynch then
    asynch.completion(src.methods, prefix, from_column)
  else
    completion.blocking(src.methods, prefix, from_column)
  end
end



------------------------------------------------------------------------
--                        blocking completions                        --
------------------------------------------------------------------------

local insplug = vim.api.nvim_replace_termcodes("<Plug>(InsCompletion)", true, false, true)

-- this handles stock vim ins-completion methods
function completion.ctrlx(mode)
  -- if popup is visible we don't have to mess with vim completion
  if pumvisible() then return end
  -- calling a completion method when the option is not set would cause an error
  if mode == "omni" and vim.bo.omnifunc == "" then return end
  if mode == "user" and vim.bo.completefunc == "" then return end
  if mode == "spel" and not vim.wo.spell then return end
  -- if the keys won't be followed by a popup, we'll change source
  local keys = sources.ctrlx[mode]
  keys = keys .. "<c-r>=pumvisible()?'':autocomplete#nextSource()<cr>"
  -- see https://github.com/neovim/neovim/issues/12297
  keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
  -- this variable holds the keys that will be inserted by <Plug>(InsCompletion)
  vim.g.autocomplete_inscompletion = keys
  vim.api.nvim_feedkeys(insplug, 'm', true)
end

-- custom non-asynch completions
function completion.blocking(methods, prefix, from_column)
  local items_array = getArrays(methods, prefix, from_column)
  if not next(items_array) then return completion.nextSource() end
  local items = getCompletionItems(items_array, prefix)
  if vim.g.autocomplete.sorting ~= "none" then
    util.sort_completion_items(items)
  end
  if #items ~= 0 then
    vim.fn.complete(from_column+1, items)
  else
    completion.nextSource()
  end
end


------------------------------------------------------------------------
--                          asynch completion                         --
------------------------------------------------------------------------

function asynch.completion(methods, prefix, from_column)
  -- we inform that there's a completion attempt running
  Var.canTryCompletion = false
  local items_array, callback_array = getArrays(methods, prefix, from_column)
  if not next(items_array) then return completion.nextSource() end

  asynch.timer = vim.loop.new_timer()
  asynch.timer:start(20, 50, vim.schedule_wrap(function()
    if not util.isInsertMode() then return asynch.stop()
    elseif asynch.timer:is_closing() then return
      -- a character has been inserted, or insert mode has been left
    elseif Var.insertChar or Var.insertLeave then asynch.stop()
      -- only perform complete when callback_array are all true
    elseif checkCallback(callback_array) == true then
      asynch.stop()
      local items = getCompletionItems(items_array, prefix)
      if vim.g.autocomplete.sorting ~= "none" then
        util.sort_completion_items(items)
      end
      if #items ~= 0 then
        vim.fn.complete(from_column+1, items)
      else
        completion.nextSource()
      end
    end
  end))
end


-- stop current asynch completion timer
function asynch.stop()
  if asynch.timer and not asynch.timer:is_closing() then
    asynch.timer:stop()
    asynch.timer:close()
  end
  Var.canTryCompletion = true
end



------------------------------------------------------------------------
--                           chain controls                           --
------------------------------------------------------------------------

-- <c-g><c-g> sequence is used to dismiss popup and reset completion method
local cgcg = vim.api.nvim_replace_termcodes("<c-g><c-g>", true, false, true)

local function stopChanging()
  -- manual completion flag must be reset if no completions are found
  if pumvisible() or Var.forceCompletion then
    Var.forceCompletion = false
    completion.retry() -- bring back last possible completion
  else
    vim.api.nvim_feedkeys(cgcg, 'n', true) -- reset vim completion mode
  end
end

function completion.nextSource()
  if Var.chainIndex ~= #Var.activeChain then
    Var.chainIndex = Var.chainIndex + 1
    completion.retry()
  else
    Var.chainIndex = 1
    stopChanging()
  end
  return ''
end

function completion.prevSource()
  if Var.chainIndex ~= 1 then
    Var.chainIndex = Var.chainIndex - 1
    completion.retry()
  else
    Var.chainIndex = #Var.activeChain
    stopChanging()
  end
  return ''
end


return completion

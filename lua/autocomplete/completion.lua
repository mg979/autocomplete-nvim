local vim = vim
local Var = require 'autocomplete.manager'
local util = require 'autocomplete.util'
local sources = require 'autocomplete.sources'
local hover = require'autocomplete.hover'
local signature = require'autocomplete.signature_help'

local completion = { popup = { auto = {} }, asynch = {} }
local popup = completion.popup
local asynch = completion.asynch
local pumvisible = function() return vim.fn.pumvisible() == 1 end

-- <c-g><c-g> sequence is used to dismiss popup and reset completion method
local cgcg = vim.api.nvim_replace_termcodes("<c-g><c-g>", true, false, true)
local insc = vim.api.nvim_replace_termcodes("<Plug>(InsCompletion)", true, false, true)



------------------------------------------------------------------------
--                     initialize/reset completion                    --
------------------------------------------------------------------------

-- init completion source and variables
function completion.init()
  Var.init()
  -- LSP triggers shouldn't change once loaded, am I wrong?
  if vim.lsp.buf_get_clients() ~= nil and vim.b.lsp_triggers == nil then
    util.setBufVar('lsp_triggers', sources.lspTriggerCharacters())
  end
end

-- current completion must be re-evaluated
function completion.retry()
  Var.changedTick = 0
  Var.insertChar = true
  -- Var.oldPrefixLen = 0
  asynch.stop()
  popup.dismiss()
  completion.try()
end



------------------------------------------------------------------------
--                           popup controls                           --
------------------------------------------------------------------------

------------------------------------------------------------------------
-- getPositionalParams returns 3 values:

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


-- feed the key sequence that resets completion
function popup.dismiss()
  if pumvisible() then
    vim.fn.complete(vim.api.nvim_win_get_cursor(0)[2], {})
    -- vim.api.nvim_feedkeys(cgcg, 'n', true)
  end
end


-- Manually triggered completion
function popup.manual()
  Var.forceCompletion = true
  if pumvisible() or not Var.canTryCompletion then
    return completion.retry() -- manual completion will be retriggered
  end
  -- set this variables to pass the tests in completion.try()
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
    completion.try()
  end))
end


------------------------------------------------------------------------
--                 verify prerequisites for completion                --
------------------------------------------------------------------------

-- check if hover or signature popup should open
local function checkHover()
  if vim.g.autocomplete.auto_hover == 1 then
    hover.autoOpenHoverInPopup()
  end
  if vim.g.autocomplete.auto_signature == 1 then
    signature.autoOpenSignatureHelp()
  end
end

-- verify that there were changes to buffer
local function changedTick()
  local tick = vim.api.nvim_buf_get_changedtick(0)
  if tick == Var.changedTick then return false end
  Var.changedTick = tick
  return true
end

-- test if completion can be triggered, if this will result in a completion
-- popup will obviously depend on whether there are candidates for the prefix
function completion.try()
  -- do nothing if no changes to buffer
  if not changedTick() then return end

  -- asynch completion timer in progress
  if not Var.canTryCompletion then return end

  -- verify that there's some source
  local src = sources.getCurrent()
  if not src then return end

  -- change source if no item is available from previous attempt
  if Var.changeSource then
    Var.changeSource = false
    return completion.nextSource()
  end

  checkHover() -- open hover and signature popup if appropriate

  local line_to_cursor, from_column, prefix = getPositionalParams()

  -- don't proceed when backspacing in insert mode, or when typing a new word
  local word_too_short = not Var.forceCompletion and #prefix < src.triggerLength
  Var.oldPrefixLen = #prefix

  if word_too_short then return popup.dismiss() end

  -- stop if no new character has been inserted
  if not Var.insertChar then return end
  -- can reset the flag now
  Var.insertChar = false

  local can_try = Var.forceCompletion or
                  util.checkTriggers(line_to_cursor, sources.getTriggers(src)) or
                  util.checkRegexes(line_to_cursor, sources.getRegexes(src))

  if can_try then
    -- print(vim.inspect(src.methods), prefix, from_column)
    completion.perform(src, prefix, from_column)
  end
end

------------------------------------------------------------------------
--                         perform completion                         --
------------------------------------------------------------------------

local function getCompletionItems(items_array, prefix)
  local src = {}
  for _,func in ipairs(items_array) do
    vim.list_extend(src, func(prefix, util.fuzzy_score))
  end
  return src
end

-- this handles stock vim ins-completion methods
local function insCompletion(mode)
  -- if popup is visible we don't have to mess with vim completion
  if pumvisible() then return end
  local keys = sources.ctrlx[mode]
  -- calling a completion method when the option is not set would cause an error
  if keys == "<c-x><c-o>" and vim.bo.omnifunc == "" then return end
  if keys == "<c-x><c-u>" and vim.bo.completefunc == "" then return end
  if keys == "<c-x>s" and not vim.wo.spell then return end
  -- if the keys won't be followed by a popup, we'll change source
  keys = keys .. "<c-r>=pumvisible()?'':autocomplete#nextSource()<cr>"
  -- see https://github.com/neovim/neovim/issues/12297
  keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
  -- this variable holds the keys that will be inserted in 'silent' mode by the
  -- <Plug>(InsCompletion) defined in plugin/autocomplete.vim
  vim.g.autocomplete_inscompletion = keys
  vim.api.nvim_feedkeys(insc, 'm', true)
end

local function blockingCompletion(methods, prefix, from_column)
  local items_array = {}
  for _, m in ipairs(methods) do
    local source = sources.builtin[m]
    if source.generateItems then source.generateItems(prefix, from_column) end
    if source.items then table.insert(items_array, source.items) end
  end
  local items = getCompletionItems(items_array, prefix)
  if vim.g.autocomplete.sorting ~= "none" then
    util.sort_completion_items(items)
  end
  if #items ~= 0 then
    vim.fn.complete(from_column+1, items)
  else
    Var.changeSource = true
  end
end

function completion.perform(src, prefix, from_column)
  if sources.ctrlx[src.methods[1]] then -- it's and ins-completion source
    insCompletion(src.methods[1])
  elseif src.asynch then
    asynch.completion(src.methods, prefix, from_column)
  else
    blockingCompletion(src.methods, prefix, from_column)
  end
end


------------------------------------------------------------------------
--                          asynch completion                         --
------------------------------------------------------------------------

-- stop current asynch completion timer
function asynch.stop()
  if asynch.timer and not asynch.timer:is_closing() then
    asynch.timer:stop()
    asynch.timer:close()
  end
  Var.canTryCompletion = true
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

function asynch.completion(methods, prefix, from_column)
  -- we inform that there's a completion attempt running
  Var.canTryCompletion = false
  -- callback_array: if asynch, callback for method will be initially false, it
  -- will become true when completion items have been generated
  local callback_array = {}
  -- items_array: array of generateItems functions for each completion source
  local items_array = {}
  for _, s in ipairs(methods) do
    local src = sources.builtin[s]
    -- treat as blocking by default
    table.insert(callback_array, src.callback or true)
    -- a bit messy: we can have only src.items or we can have both
    -- src.generateItems and src.items (both must be functions)
    if src.generateItems then src.generateItems(prefix, from_column) end
    if src.items then table.insert(items_array, src.items) end
  end

  asynch.timer = vim.loop.new_timer()
  asynch.timer:start(20, 50, vim.schedule_wrap(function()
    if asynch.timer:is_closing() then return
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
        Var.changedTick = 0 -- to bypass completion.try() check
        Var.changeSource = true
      end
    end
  end))
end

------------------------------------------------------------------------
--                           chain controls                           --
------------------------------------------------------------------------

local function stopChanging()
  -- manual completion flag must be reset if no completions are found
  Var.forceCompletion = false
  if pumvisible() then
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

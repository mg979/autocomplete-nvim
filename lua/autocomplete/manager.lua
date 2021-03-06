local manager = {}

------------------------------------------------------------------------
--                    plugin variables and states                     --
------------------------------------------------------------------------
-- Global variables table, accessed in scripts as Var.variable_name

manager = {
  canTryCompletion = true,     -- becomes false if a completion is already being tried
  insertChar = false,          -- flag for InsertCharPre event, turn off imediately when performing completion
  insertLeave = false,         -- flag for InsertLeave, prevent every completion if true
  textHover = false,           -- handle auto hover
  selected = -1,               -- handle selected items in v:complete-items for auto hover
  changedTick = 0,             -- handle changeTick
  confirmedCompletion = false, -- flag for manual confirmation of completion
  forceCompletion = false,     -- flag for forced manual completion/source change
  chains = {},                 -- here we store validated chains for each buffer
  activeChain = nil,           -- currently used completion chain
  chainIndex = 1,              -- current index in loaded chain
  noSelect = false,            -- if 'noselect' in 'completeopt' must be restored
  default_pattern = '\\k*$',   -- default pattern for prefix matching
}

function manager.init()
  -- this is run on InsertEnter
  manager.activeChain         = nil
  manager.insertLeave         = false
  manager.canTryCompletion    = true
  manager.insertChar          = false
  manager.textHover           = false
  manager.selected            = -1
  manager.confirmedCompletion = false
  manager.forceCompletion     = false
  manager.chainIndex          = 1
end

function manager.debugActiveChain()
  print('activeChain = ' .. vim.inspect(manager.activeChain))
end

function manager.debug()
  print(
  'canTryCompletion = '    .. vim.inspect(manager.canTryCompletion)    .. '\n' ..
  'insertChar = '          .. vim.inspect(manager.insertChar)          .. '\n' ..
  'insertLeave = '         .. vim.inspect(manager.insertLeave)         .. '\n' ..
  'textHover = '           .. vim.inspect(manager.textHover)           .. '\n' ..
  'selected = '            .. vim.inspect(manager.selected)            .. '\n' ..
  'changedTick = '         .. vim.inspect(manager.changedTick)         .. '\n' ..
  'confirmedCompletion = ' .. vim.inspect(manager.confirmedCompletion) .. '\n' ..
  'forceCompletion = '     .. vim.inspect(manager.forceCompletion)     .. '\n' ..
  'chainIndex = '          .. vim.inspect(manager.chainIndex)
  )
end

return manager

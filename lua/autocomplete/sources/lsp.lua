local vim = vim
local protocol = require 'vim.lsp.protocol'
local match = require 'autocomplete.matching'
local M = {}

M.callback = false

function M.getLspCompletions()
  return M.items
end

local function get_completion_word(item)
  if item.textEdit ~= nil and item.textEdit ~= vim.NIL
    and item.textEdit.newText ~= nil and (item.insertTextFormat ~= 2 or vim.fn.exists('g:loaded_vsnip_integ')) then
    return item.textEdit.newText
  elseif item.insertText ~= nil and item.insertText ~= vim.NIL then
    return item.insertText
  end
  return item.label
end

local function text_document_completion_list_to_complete_items(result, prefix)
  local items = vim.lsp.util.extract_completion_items(result)
  if vim.tbl_isempty(items) then
    return {}
  end

  local customize_label = {}
  -- items = remove_unmatch_completion_items(items, prefix)
  -- sort_completion_items(items)

  local matches = {}

  for _, completion_item in ipairs(items) do
    local item = {}
    if vim.fn.exists('g:loaded_vsnip_integ') == 1 or
      protocol.CompletionItemKind[completion_item.kind] ~= 'Snippet' then
      local info = ' '
      local documentation = completion_item.documentation
      if documentation then
        if type(documentation) == 'string' and documentation ~= '' then
          info = documentation
        elseif type(documentation) == 'table' and type(documentation.value) == 'string' then
          info = documentation.value
        -- else
          -- TODO(ashkan) Validation handling here?
        end
      end
      item.info = info

      item.word = get_completion_word(completion_item)
      item.user_data = {
        lsp = {
          completion_item = completion_item
        }
      }
      local kind = protocol.CompletionItemKind[completion_item.kind]
      item.kind = customize_label[kind] or kind
      item.abbr = completion_item.label
      item.priority = vim.g.autocomplete.items_priority[item.kind]
      item.menu = completion_item.detail or ''

      match.matching(matches, prefix, item)
    end
  end

  return matches
end

function M.getCallback()
  return M.callback
end

function M.triggerFunction(prefix)
  local params = vim.lsp.util.make_position_params()
  M.callback = false
  M.items = {}
  if #vim.lsp.buf_get_clients() == 0 then
    M.callback = true
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.lsp.buf_request(bufnr, 'textDocument/completion', params, function(err, _, result)
    if err or not result then
      M.callback = true
      return
    end
    local matches = text_document_completion_list_to_complete_items(result, prefix)
    M.items = matches
    M.callback = true
  end)
end

return M

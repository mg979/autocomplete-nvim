local vim = vim
local util = require'autocomplete.util'
local M = {}

local function fuzzy_match(prefix, word)
  local score = util.fuzzy_score(prefix, word)
  return score < 1, score
end

local function substring_match(prefix, word)
  return string.find(word, prefix)
end

local function exact_match(prefix, word)
  return vim.startswith(word, prefix)
end

local function adjusted_case(prefix, word)
  if vim.g.autocomplete.ignore_case then
    prefix = string.lower(prefix)
    word = string.lower(word)
  end
  return prefix, word
end

local matching_strategy = {
  fuzzy = fuzzy_match,
  substring = substring_match,
  exact = exact_match
}

function M.matching (sources, prefix, item)
  local matcher_list = vim.b.completion_matching or vim.g.autocomplete.matching
  local matching_priority = 2
  prefix, item.word = adjusted_case(prefix, item.word)
  for _, method in ipairs(matcher_list) do
    local is_match, score = matching_strategy[method](prefix, item.word)
    if is_match then
      item.score = score
      item.priority = (item.priority or 0) + 10 * matching_priority
      util.addCompletionItems(sources, item)
      break
    end
    matching_priority = matching_priority - 1
  end
end

return M

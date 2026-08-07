-- trigger_help.lang — locale-aware language selection (bilingual docs)

local M = {}

-- Locale: zh* -> Chinese (same rule as wokamark help: LC_ALL > LC_MESSAGES > LANG)
function M.is_zh()
  local lang = (vim.env.LC_ALL or vim.env.LC_MESSAGES or vim.env.LANG or ''):lower()
  return lang:match('^zh') ~= nil
end

-- Pick the language-appropriate value: { en = ..., zh = ... } tables are
-- selected by locale; plain values (string / list / function) pass through.
function M.pick_lang(v)
  if type(v) ~= 'table' then return v end
  local zh = M.is_zh()
  if zh and v.zh ~= nil then return v.zh end
  if not zh and v.en ~= nil then return v.en end
  return v.en or v.zh -- fallback to whichever language exists
end

return M

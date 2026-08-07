-- trigger_help.source — document sources: registered docs, user content md,
-- built-in help tags, plus name resolution and selector items.
-- Depends on trigger_help.lang (locale) and trigger_help.config (content).

local lang = require('trigger_help.lang')
local config = require('trigger_help.config')

local M = {}

local registered = {}  -- id -> doc spec (register_doc); same id overwrites
local help_cache = nil -- lazy help-tag scan cache; nil until first use
local warned = {}      -- md paths already WARNed (once per path)

-- Load an md file: `#`/`##` heading lines get Title highlight (extmark
-- rows are returned in `titles` for panel.render), lines starting with
-- `-` are indented 2 spaces, everything else as-is.
-- Missing file -> WARN once per path (warned), returns nil.
function M.load_md(path)
  local full = vim.fn.expand(path)
  if vim.fn.filereadable(full) ~= 1 then
    if not warned[full] then
      warned[full] = true
      vim.notify('[trigger-help] md file not found: ' .. full, vim.log.levels.WARN)
    end
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, full)
  if not ok or type(lines) ~= 'table' then return nil end
  local out, titles = {}, {}
  for i, line in ipairs(lines) do
    if line:match('^#+') then
      out[i] = line
      titles[#titles + 1] = i - 1
    elseif line:match('^%-') then
      out[i] = line:gsub('^%-%s?', '  ')
    else
      out[i] = line
    end
  end
  return out, nil, titles
end

-- ── register_doc API ────────────────────────────────────────────────
-- Other plugins register docs with trigger-help, e.g. wokamark's
-- command cheatsheet. Content source is the first non-nil of
-- text > file > fn. Same id re-registered = overwrite (one entry).
-- Registered docs show in the picker as `[id] name` and resolve via
-- :TriggerHelp <name> (name, or id when the name contains spaces).
-- Does not depend on setup(); may be called before it.
function M.register_doc(spec)
  if type(spec) ~= 'table' then
    vim.notify('[trigger-help] register_doc: expected a table', vim.log.levels.WARN)
    return M
  end
  if type(spec.id) ~= 'string' or spec.id == '' then
    vim.notify('[trigger-help] register_doc: id (string) required', vim.log.levels.WARN)
    return M
  end
  if type(spec.name) ~= 'string' and (type(spec.name) ~= 'table' or (spec.name.en == nil and spec.name.zh == nil)) then
    vim.notify('[trigger-help] register_doc: name required for id "' .. spec.id .. '"', vim.log.levels.WARN)
    return M
  end
  local kind, value
  if spec.text ~= nil then
    if type(spec.text) ~= 'table' then
      vim.notify('[trigger-help] register_doc: text must be a list of lines for id "' .. spec.id .. '"', vim.log.levels.WARN)
      return M
    end
    kind, value = 'text', spec.text
  elseif spec.file ~= nil then
    if type(spec.file) ~= 'string' then
      vim.notify('[trigger-help] register_doc: file must be a path string for id "' .. spec.id .. '"', vim.log.levels.WARN)
      return M
    end
    kind, value = 'file', spec.file
  elseif spec.fn ~= nil then
    if type(spec.fn) ~= 'function' then
      vim.notify('[trigger-help] register_doc: fn must be a function for id "' .. spec.id .. '"', vim.log.levels.WARN)
      return M
    end
    kind, value = 'fn', spec.fn
  else
    vim.notify('[trigger-help] register_doc: no content (text/file/fn) for id "' .. spec.id .. '"', vim.log.levels.WARN)
    return M
  end
  registered[spec.id] = { id = spec.id, name = spec.name, kind = kind, value = value }
  return M
end

function M.get_registered(id)
  return registered[id]
end

-- Resolve a registered doc to panel lines (+ft, +titles for md files).
-- Values may be { en = ..., zh = ... } — pick by locale first.
function M.doc_lines(doc)
  local value = lang.pick_lang(doc.value)
  local name = lang.pick_lang(doc.name)
  if doc.kind == 'text' then
    if type(value) ~= 'table' then
      vim.notify('[trigger-help] register_doc text must be a table for "' .. name .. '"', vim.log.levels.WARN)
      return nil
    end
    return value
  elseif doc.kind == 'file' then
    return M.load_md(value) -- missing file already WARNs once per path
  else -- 'fn'
    local ok, lines = pcall(value)
    if not ok or type(lines) ~= 'table' then
      vim.notify('[trigger-help] register_doc fn failed for "' .. name .. '"', vim.log.levels.WARN)
      return nil
    end
    return lines
  end
end

-- ── help tag scan (lazy, cached) ────────────────────────────────────
-- Note: getcompletion('', 'help') only returns the help-related subset
-- (empty-pattern quirk in Vim), so iterate prefixes (a-z/A-Z, digits,
-- leading punctuation) to cover all tags. Uppercase A-Z prefixes are
-- required: real tags include E128, VimL function tags, etc., and
-- getcompletion prefix-matches case-sensitively.
function M.help_tags()
  if help_cache == nil then
    local seen, out = {}, {}
    local prefixes = { '0','1','2','3','4','5','6','7','8','9',
      'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z',
      'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
      "'", '-', ':', '[', ']', '!', '@', '#', '*', '_', '<', '>', '~' }
    for _, p in ipairs(prefixes) do
      local ok, tags = pcall(vim.fn.getcompletion, p, 'help')
      if ok and type(tags) == 'table' then
        for _, t in ipairs(tags) do
          if not seen[t] then
            seen[t] = true
            out[#out + 1] = t
          end
        end
      end
    end
    help_cache = out
  end
  return help_cache
end

-- ── name resolution ─────────────────────────────────────────────────
-- content key > registered doc name (or id) > md filename > help tag.
function M.resolve(name)
  if name == nil or name == '' then return nil end
  if config.cfg.content[name] ~= nil then
    return { kind = 'md', path = config.cfg.content[name], name = name }
  end
  -- registered docs: match displayed name (locale-picked), then id
  -- (id lets :TriggerHelp wokamark open a doc whose display name has
  -- spaces, e.g. 'wokamark 使用')
  for _, doc in pairs(registered) do
    if lang.pick_lang(doc.name) == name or doc.id == name then
      return { kind = 'doc', id = doc.id, name = lang.pick_lang(doc.name) }
    end
  end
  for key, path in pairs(config.cfg.content) do
    local base = vim.fn.fnamemodify(vim.fn.expand(path), ':t:r')
    if base == name then return { kind = 'md', path = path, name = key } end
  end
  -- help tag: exact query bypasses the 300-per-prefix cache cap, so
  -- :TriggerHelp E900 works even though E900 is not in the picker list
  local exact = vim.fn.getcompletion(name, 'help')
  if #exact > 0 and vim.tbl_contains(exact, name) then
    return { kind = 'help', tag = name }
  end
  return nil
end

-- ── selector items ──────────────────────────────────────────────────
-- User content docs ([md] <name>) + registered docs ([id] <name>) +
-- built-in help tags ([help] <tag>). Exposed for tests; also used by the
-- picker.
function M.picker_items()
  local items = {}
  for name, path in pairs(config.cfg.content) do
    items[#items + 1] = {
      kind = 'md',
      name = name,
      path = path,
      text = '[md] ' .. name,
    }
  end
  for _, doc in pairs(registered) do
    local shown = lang.pick_lang(doc.name)
    items[#items + 1] = {
      kind = 'doc',
      id = doc.id,
      name = shown,
      text = '[' .. doc.id .. '] ' .. shown,
    }
  end
  for _, tag in ipairs(M.help_tags()) do
    items[#items + 1] = { kind = 'help', tag = tag, text = '[help] ' .. tag }
  end
  table.sort(items, function(a, b) return a.text < b.text end)
  return items
end

return M

-- lua/trigger_help/init.lua — trigger-help.nvim
-- Command-triggered help panel.
--   :TriggerHelp            toggle: close the open panel, or open the
--                           snacks picker to browse docs
--   :TriggerHelp <name>     open that doc directly (skip the picker)
-- Name resolution (in order): content key > md filename > help tag.
-- Content comes from markdown files or built-in :h tags; the plugin
-- ships no content of its own.

local M = {}

local defaults = {
  content = {},        -- name -> md file path (string)
  height = 40,         -- panel height, percent of window height
  position = 'bottom', -- 'bottom' | 'top'
}

local cfg = {}
local state = { win = nil, buf = nil, warned = {} }
local help_cache = nil -- lazy help-tag scan cache; nil until first use

local ns = vim.api.nvim_create_namespace('trigger_help')

-- Close the panel and delete its buffer (W2: no accumulation).
-- Idempotent: no window -> no-op.
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_is_loaded(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

-- Load an md file: `#`/`##` heading lines get Title highlight,
-- lines starting with `-` are indented 2 spaces, everything else as-is.
-- Missing file -> WARN once per path (state.warned), returns nil.
local function load_md(path)
  local full = vim.fn.expand(path)
  if vim.fn.filereadable(full) ~= 1 then
    if not state.warned[full] then
      state.warned[full] = true
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

-- Load a built-in help tag: silent :help <tag>, read the section around
-- the tag line, close the help window, return lines + 'help' filetype.
-- W1: only windows this call opened (set difference) are closed; a reused
-- user help window is left untouched. W2: opened windows' buffers deleted.
local function load_help(tag)
  local prev_win = vim.api.nvim_get_current_win()
  local before = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do before[w] = true end
  pcall(vim.cmd, 'silent! help ' .. vim.fn.fnameescape(tag))
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local new_wins = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if not before[w] then new_wins[#new_wins + 1] = w end
  end
  if vim.bo[buf].filetype ~= 'help' then
    -- tag not found: nothing was opened
    for _, w in ipairs(new_wins) do pcall(vim.api.nvim_win_close, w, true) end
    pcall(vim.api.nvim_set_current_win, prev_win)
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out = {}
  -- Tag line + following body, up to the next section header.
  for i = cursor[1], #all do
    local line = all[i]
    if i > cursor[1] and line ~= '' and not line:match('^[\t ]') and not line:match('^=+$') then
      break
    end
    out[#out + 1] = line
    if #out >= 120 then break end -- defensive cap
  end
  -- Close only windows this call opened, and delete their buffers (W2);
  -- a reused user help window/buffer is left untouched (W1).
  for _, w in ipairs(new_wins) do
    local wb = vim.api.nvim_win_get_buf(w)
    pcall(vim.api.nvim_win_close, w, true)
    if vim.api.nvim_buf_is_valid(wb) and vim.api.nvim_buf_is_loaded(wb) then
      pcall(vim.api.nvim_buf_delete, wb, { force = true })
    end
  end
  pcall(vim.api.nvim_set_current_win, prev_win)
  return out, 'help'
end

-- Lazy scan of built-in help tags; cached for the session (module var,
-- scanned at most once). Note: getcompletion('', 'help') only returns the
-- help-related subset (empty-pattern quirk in Vim), so iterate prefixes
-- (a-z, digits, leading punctuation) to cover all tags.
local function help_tags()
  if help_cache == nil then
    local seen, out = {}, {}
    local prefixes = { '0','1','2','3','4','5','6','7','8','9',
      'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z',
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

-- Resolve a name to a doc entry: content key > md filename > help tag.
-- Returns { kind = 'md', path = ..., name = ... } or
--         { kind = 'help', tag = ... } or nil.
local function resolve(name)
  if name == nil or name == '' then return nil end
  if cfg.content[name] ~= nil then
    return { kind = 'md', path = cfg.content[name], name = name }
  end
  for key, path in pairs(cfg.content) do
    local base = vim.fn.fnamemodify(vim.fn.expand(path), ':t:r')
    if base == name then return { kind = 'md', path = path, name = key } end
  end
  for _, tag in ipairs(help_tags()) do
    if tag == name then return { kind = 'help', tag = tag } end
  end
  return nil
end

-- Render lines into the bottom/top split panel (not focused). Regular
-- window -> mouse wheel / scrolling work natively. `q` closes the panel.
local function render(lines, ft, titles)
  M.close()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if ft then vim.bo[buf].filetype = ft end
  for _, ln in ipairs(titles or {}) do
    vim.api.nvim_buf_set_extmark(buf, ns, ln, 0, {
      hl_group = 'Title',
      end_col = #lines[ln + 1],
    })
  end
  vim.bo[buf].modifiable = false
  -- buffer-level q: close window + delete buffer (W2)
  vim.keymap.set('n', 'q', function()
    M.close()
  end, { buffer = buf, silent = true, nowait = true })
  state.buf = buf
  local height = math.max(3, math.floor(vim.o.lines * cfg.height / 100))
  state.win = vim.api.nvim_open_win(buf, false, {
    split = cfg.position == 'top' and 'above' or 'below',
    height = height,
  })
end

-- Open the panel for a resolved doc entry.
local function open(entry)
  if entry.kind == 'md' then
    local lines, ft, titles = load_md(entry.path)
    if not lines then return end
    render(lines, ft, titles)
  else
    local lines, ft = load_help(entry.tag)
    if not lines then
      vim.notify('[trigger-help] help tag not found: ' .. entry.tag, vim.log.levels.WARN)
      return
    end
    render(lines, ft)
  end
end

-- Selector items: user content docs ([md] <name>) + built-in help tags
-- ([help] <tag>). Exposed for tests; also used by the picker.
function M.picker_items()
  local items = {}
  for name, path in pairs(cfg.content) do
    items[#items + 1] = {
      kind = 'md',
      name = name,
      path = path,
      text = '[md] ' .. name,
    }
  end
  for _, tag in ipairs(help_tags()) do
    items[#items + 1] = { kind = 'help', tag = tag, text = '[help] ' .. tag }
  end
  table.sort(items, function(a, b) return a.text < b.text end)
  return items
end

-- Open the snacks picker over the doc list.
local function open_picker()
  -- snacks.picker 内部引用全局 Snacks；先 require('snacks') 建立它，
  -- 避免依赖用户环境的加载顺序（workmark 能跑是因为 snacks 已被其他插件加载）。
  local ok_snacks = pcall(require, 'snacks')
  if not ok_snacks then
    vim.notify('[trigger-help] snacks.nvim required for picker', vim.log.levels.WARN)
    return
  end
  local ok, snacks = pcall(require, 'snacks.picker')
  if not ok then
    vim.notify('[trigger-help] snacks.nvim required for picker', vim.log.levels.WARN)
    return
  end
  local items = M.picker_items()
  snacks.pick({
    title = 'Trigger help',
    items = items,
    format = function(item)
      local hl = item.kind == 'md' and 'Special' or 'Comment'
      return { { item.text, hl } }
    end,
    preview = function(ctx)
      local item = ctx.item
      if item.kind == 'md' then
        ctx.preview:set_title(item.name)
        ctx.preview:set_lines(load_md(item.path) or { '(file not found)' })
      else
        ctx.preview:set_title('help: ' .. item.tag)
        ctx.preview:set_lines({ 'Built-in help tag: ' .. item.tag, '', 'Press <CR> to open.' })
      end
      return true
    end,
    confirm = function(picker, item)
      picker:close()
      open(item)
    end,
  })
end

-- :TriggerHelp [name]
--   no args: panel open -> close (toggle); else open the picker.
--   name:    resolve (content key > md filename > help tag) and open.
local function trigger_help(name)
  if name == nil or name == '' then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      M.close()
      return
    end
    open_picker()
    return
  end
  local entry = resolve(name)
  if entry == nil then
    vim.notify('[trigger-help] no doc named "' .. name .. '"', vim.log.levels.WARN)
    return
  end
  open(entry)
end

function M.setup(opts)
  -- Idempotency guard: a second setup (double source of the config file,
  -- repeated require) must not register the user command again.
  if vim.g.trigger_help_loaded then return M end
  cfg = vim.tbl_extend('keep', opts or {}, defaults)
  vim.g.trigger_help_loaded = true
  vim.api.nvim_create_user_command('TriggerHelp', function(args)
    trigger_help(args.fargs[1])
  end, { nargs = '?', desc = 'Toggle trigger-help panel, or open the picker' })
  return M
end

return M

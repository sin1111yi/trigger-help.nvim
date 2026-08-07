-- lua/trigger_help/init.lua — trigger-help.nvim
-- Event-triggered help floating window.
-- Content comes from markdown files or built-in :h tags; trigger/close
-- events and window style are fully configurable.
-- Empty content table = zero behavior (no autocmds registered).

local M = {}

local defaults = {
  content = {},      -- key -> md file path (string) or { help = '<tag>' }
  trigger = 'CmdlineEnter', -- string or { event = ..., pattern = ... }
  close = 'CmdlineLeave',   -- string or array of events
  match = nil,       -- function() -> content key; nil/'' = no display
  width = 25,        -- side panel width, percent of window columns
  side = 'right',    -- 'left' | 'right'
}

local cfg = {}
local state = { win = nil, buf = nil, warned = {} }

local ns = vim.api.nvim_create_namespace('trigger_help')

-- Close the side panel and delete its buffer (W2: no accumulation).
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

local function normalize_trigger(t)
  if type(t) == 'string' then return { event = t } end
  if type(t) == 'table' then return t end
  return { event = defaults.trigger }
end

local function normalize_close(c)
  if type(c) == 'string' then return { c } end
  if type(c) == 'table' then return c end
  return {}
end

local function has_cmdline_trigger(ev)
  if type(ev) == 'string' then
    return ev:find('CmdlineEnter', 1, true) ~= nil
  end
  if type(ev) == 'table' then
    for _, e in ipairs(ev) do
      if tostring(e):find('CmdlineEnter', 1, true) then return true end
    end
  end
  return false
end

-- Load an md file: `#`/`##` heading lines get Title highlight,
-- lines starting with `-` are indented 2 spaces, everything else as-is.
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
-- the tag line, close the help window, render into the float with
-- filetype='help' for syntax highlighting.
local function load_help(tag)
  local prev_win = vim.api.nvim_get_current_win()
  -- :help reuses an existing help window instead of opening a new one, so
  -- "current window changed" is NOT proof we opened a window. Record the
  -- window set before; only windows in the set difference are plugin-owned.
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

local function load_content(entry)
  if type(entry) == 'string' then return load_md(entry) end
  if type(entry) == 'table' and type(entry.help) == 'string' then
    return load_help(entry.help)
  end
  return nil
end

local function render(lines, ft, titles)
  M.close()
  local width = math.max(10, math.floor(vim.o.columns * cfg.width / 100))
  local buf = vim.api.nvim_create_buf(false, true)
  -- interaction hint on top: while in cmdline, mouse belongs to the cmdline;
  -- <C-c> leaves it, then the panel scrolls/clicks like a normal window
  local hint = '  [<C-c> 退出命令模式后可滚动/点击]'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { hint })
  vim.api.nvim_buf_set_lines(buf, 1, -1, false, lines)
  if ft then vim.bo[buf].filetype = ft end
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { hl_group = 'Comment', end_col = #hint })
  for _, ln in ipairs(titles or {}) do
    vim.api.nvim_buf_set_extmark(buf, ns, ln + 1, 0, {
      hl_group = 'Title',
      end_col = #lines[ln + 1],
    })
  end
  vim.bo[buf].modifiable = false
  state.buf = buf -- W2: track the scratch buffer so M.close can delete it
  -- Side panel: vertical split on the configured side, not focused.
  -- It is a regular window, so mouse-wheel scrolling works natively
  -- once the user leaves the cmdline with <C-c>.
  state.win = vim.api.nvim_open_win(buf, false, {
    split = cfg.side == 'left' and 'left' or 'right',
    width = width,
  })
end

-- Trigger callback: match() -> content key -> load -> float.
function M.show(args)
  local key = cfg.match and cfg.match(args)
  if key == nil or key == '' then return end
  M._show_key(key)
end

-- Show the panel for a specific content key (used by the per-key autocmds).
function M._show_key(key)
  local entry = cfg.content[key]
  if entry == nil then return end -- key not in content: silent
  local lines, ft, titles = load_content(entry)
  if not lines then return end
  render(lines, ft, titles)
end

function M.setup(opts)
  -- Idempotency guard: a second setup (double source of the config file,
  -- repeated require) must not register autocmds again.
  if vim.g.trigger_help_loaded then return M end
  cfg = vim.tbl_extend('keep', opts or {}, defaults)
  if next(cfg.content) == nil then return M end -- zero behavior

  local trigger = normalize_trigger(cfg.trigger)
  local close_events = normalize_close(cfg.close)

  vim.g.trigger_help_loaded = true
  local group = vim.api.nvim_create_augroup('TriggerHelp', { clear = true })
  -- One autocmd per content key: CmdlineEnter's pattern IS the cmdline char
  -- (vim doc), so pattern = key matches exactly ('/' '?' ':') — far more
  -- reliable than getcmdtype()/v:event.cmdtype at callback time.
  -- Non-cmdline triggers (e.g. BufEnter) still need `match` to pick a key.
  for key in pairs(cfg.content) do
    vim.api.nvim_create_autocmd(trigger.event, {
      group = group,
      pattern = vim.pesc(key),
      callback = function(args)
        if cfg.match and cfg.match(args) ~= key then return end
        M._show_key(key)
      end,
    })
  end
  if #close_events > 0 then
    vim.api.nvim_create_autocmd(close_events, {
      group = group,
      callback = function(args)
        -- <C-c> aborting the cmdline also fires CmdlineLeave; keep the panel
        -- open so the user can scroll/click it. Only close on a real command
        -- execution (Enter) or any other close event.
        if args.event == 'CmdlineLeave' and vim.v.event and vim.v.event.abort == 1 then
          return
        end
        M.close()
      end,
    })
  end
  return M
end

return M

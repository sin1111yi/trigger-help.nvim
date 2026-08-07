-- trigger_help.panel — the help panel: window/buffer lifecycle, rendering,
-- md/help loading glue. Depends on trigger_help.source (doc sources) and
-- trigger_help.config (height/position).

local source = require('trigger_help.source')
local config = require('trigger_help.config')

local M = {}

local state = { win = nil, buf = nil }
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

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- Render lines into the bottom/top split panel, taking focus. Regular
-- window -> mouse wheel / scrolling work natively. Closing is standard
-- buffer behaviour (:q, <C-w>c, or re-running :TriggerHelp).
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
  -- No custom q/Esc bindings: the panel behaves like any normal buffer
  -- (:q, <C-w>c, or re-running :TriggerHelp closes it). This keeps q
  -- free for its ordinary meaning and matches the rest of the UI.
  vim.bo[buf].bufhidden = 'wipe' -- closing the window (e.g. :q) wipes the
  -- scratch buffer so it cannot accumulate across a session (W2)
  state.buf = buf
  local height = math.max(3, math.floor(vim.o.lines * config.cfg.height / 100))
  state.win = vim.api.nvim_open_win(buf, true, {
    split = config.cfg.position == 'top' and 'above' or 'below',
    height = height,
  })
end

-- Open the panel for a resolved doc entry.
function M.open(entry)
  if entry.kind == 'md' then
    local lines, ft, titles = source.load_md(entry.path)
    if not lines then return end
    render(lines, ft, titles)
  elseif entry.kind == 'doc' then
    local doc = source.get_registered(entry.id)
    if not doc then return end
    local lines, ft, titles = source.doc_lines(doc)
    if not lines then return end
    render(lines, ft, titles)
  else
    local lines, ft = M.load_help(entry.tag)
    if not lines then
      vim.notify('[trigger-help] help tag not found: ' .. entry.tag, vim.log.levels.WARN)
      return
    end
    render(lines, ft)
  end
end

-- Load a built-in help tag: silent :help <tag>, read the section around
-- the tag line, close the help window, return lines + 'help' filetype.
-- W1: only windows this call opened (set difference) are closed; a reused
-- user help window is left untouched. W2: opened windows' buffers deleted.
function M.load_help(tag)
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
    if i > cursor[1] and line ~= '' and not line:match('^[\\t ]') and not line:match('^=+$') then
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

return M

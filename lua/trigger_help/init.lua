-- lua/trigger_help/init.lua — trigger-help.nvim entry point
-- Command-triggered help panel.
--   :TriggerHelp            toggle: close the open panel, or open the
--                           snacks picker to browse docs
--   :TriggerHelp <name>     open that doc directly (skip the picker)
-- Name resolution (in order): content key > registered doc name > md
-- filename > help tag. Content comes from markdown files, built-in :h
-- tags, or docs registered via register_doc() (other plugins); the
-- plugin ships no content of its own.
--
-- Modules: config (defaults), lang (locale), source (doc sources +
-- resolution + selector items), panel (window/buffer lifecycle + render),
-- picker (snacks selector). This file only wires setup + the command.

local config = require('trigger_help.config')
local source = require('trigger_help.source')
local panel = require('trigger_help.panel')
local picker = require('trigger_help.picker')

local M = {}

-- :TriggerHelp [name]
--   no args: panel open -> close (toggle); else open the picker.
--   name:    resolve (content key > md filename > help tag) and open.
local function trigger_help(name)
  if name == nil or name == '' then
    if panel.is_open() then
      panel.close()
      return
    end
    picker.open()
    return
  end
  local entry = source.resolve(name)
  if entry == nil then
    vim.notify('[trigger-help] no doc named "' .. name .. '"', vim.log.levels.WARN)
    return
  end
  panel.open(entry)
end

function M.setup(opts)
  -- Idempotency guard: a second setup (double source of the config file,
  -- repeated require) must not register the user command again.
  if vim.g.trigger_help_loaded then return M end
  config.cfg = vim.tbl_extend('keep', opts or {}, config.defaults)
  vim.g.trigger_help_loaded = true
  vim.api.nvim_create_user_command('TriggerHelp', function(args)
    trigger_help(args.fargs[1])
  end, { nargs = '?', desc = 'Toggle trigger-help panel, or open the picker' })
  return M
end

-- Public API (used by tests and other plugins):
M.close = panel.close
M.register_doc = source.register_doc
M.picker_items = source.picker_items

return M

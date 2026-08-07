-- trigger_help.picker — the snacks selector over all doc sources.
-- Depends on trigger_help.source (items/doc_lines) and trigger_help.panel.

local source = require('trigger_help.source')
local panel = require('trigger_help.panel')

local M = {}

-- Open the snacks picker over the doc list.
function M.open()
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
  local items = source.picker_items()
  snacks.pick({
    title = 'Trigger help',
    items = items,
    format = function(item)
      local hl = item.kind == 'help' and 'Comment' or 'Special'
      return { { item.text, hl } }
    end,
    preview = function(ctx)
      local item = ctx.item
      if item.kind == 'md' then
        ctx.preview:set_title(item.name)
        ctx.preview:set_lines(source.load_md(item.path) or { '(file not found)' })
      elseif item.kind == 'doc' then
        local doc = source.get_registered(item.id)
        local lines = doc and source.doc_lines(doc) or nil
        ctx.preview:set_title(item.name)
        ctx.preview:set_lines(lines or { '(no content)' })
      else
        ctx.preview:set_title('help: ' .. item.tag)
        ctx.preview:set_lines({ 'Built-in help tag: ' .. item.tag, '', 'Press <CR> to open.' })
      end
      return true
    end,
    confirm = function(picker, item)
      picker:close()
      panel.open(item)
    end,
  })
end

return M

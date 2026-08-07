-- trigger_help.config — configuration (defaults + merged runtime cfg)
-- Other modules read config.cfg (set by init.setup).

local M = {}

M.defaults = {
  content = {},        -- name -> md file path (string)
  height = 40,         -- panel height, percent of window height
  position = 'bottom', -- 'bottom' | 'top'
}

-- merged at setup(); read-only afterwards
M.cfg = {}

return M

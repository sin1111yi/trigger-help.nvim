# trigger-help.nvim

事件触发帮助浮动窗口：按下 `/`、`?`、`:` 等按键（或任意可配置事件）时，在屏幕右上角弹出对应帮助内容。内容来自 **markdown 文件**或 **内置 `:h` 文档**，插件本身不内置任何内容。

零依赖、单文件（`lua/trigger_help/init.lua`）、`setup()` 全参数可配。

## 安装

放到 `pack/*/opt/trigger-help.nvim/`（独立本地插件，不受 vim.pack 管理），然后在配置中 `packadd` 并调用 setup：

```lua
vim.cmd('packadd trigger-help.nvim')
require('trigger_help').setup({
  content = {
    ['/'] = '~/.config/nvim/docs/trigger-help.nvim/search.md', -- md 文件路径
    ['?'] = { help = 'search' },                 -- 内置 :h 文档形态
    [':'] = '~/.config/nvim/docs/trigger-help.nvim/cmd.md',
  },
  trigger = 'CmdlineEnter',     -- string 或 { event = 'BufEnter', pattern = '*.lua' }
  close = 'CmdlineLeave',       -- string 或 array（多个关闭事件）
  -- match = function() return vim.fn.getcmdtype() end,  -- 返回 content 键；nil/'' 不显示
  width = 25,                   -- 侧边面板宽度（窗口列数的百分比）
  side = 'right',               -- 'left' | 'right'
})
```

## 配置项

| 项 | 默认 | 说明 |
|----|------|------|
| `content` | `{}` | 内容表：键 → md 文件路径（string）或 `{ help = '<tag>' }`。空表 = 零行为（不注册任何 autocmd） |
| `trigger` | `'CmdlineEnter'` | 触发事件。string，或 `{ event = ..., pattern = ... }`（如 `{ event = 'BufEnter', pattern = '*.lua' }`） |
| `close` | `'CmdlineLeave'` | 关闭事件。string 或数组（任一事件触发即幂等关闭） |
| `match` | 见下 | 触发后调用，返回 content 键；返回 `nil`/`''` 不显示。默认：trigger 含 `CmdlineEnter` 时自动用 `v:event.cmdtype`（回退 `vim.fn.getcmdtype()`），其他事件无默认（不显示） |
| `width` | `25` | 侧边面板宽度，窗口列数的百分比 |
| `side` | `'right'` | 侧边方向：`'left'` 或 `'right'` |

## 行为

- **侧边面板**：内容渲染到右侧（或 `side='left'`）垂直分屏 buffer，宽度 25%（可配）。不抢占焦点；是普通窗口，鼠标滚轮可直接滚动。
- **md 渲染极简**：行首 `#`/`##` 整行用 `Title` 高亮；行首 `-` 替换为 2 空格缩进；其余原样（不解析行内 md）。
- **`:h` 形态**：静默执行 `:help <tag>` → 读取该 tag 所在小节内容 → 关闭 help 窗口 → 渲染到侧边面板（保留 `filetype='help'` 获得内置高亮）。
- md 文件缺失 → `vim.notify` WARN **一次**（每个路径每会话一次），不显示不崩溃。
- `match()` 返回的键不在 `content` 中 → 静默不显示。
- 同一时刻只保留一个浮动窗口（新内容覆盖旧的）；关闭幂等（重复触发关闭事件不报错）。
- `setup()` 幂等：重复调用不重复注册 autocmd（`vim.g.trigger_help_loaded` 守卫，与 workmark.nvim 同模式）。

## 示例：BufEnter 触发（进入 lua 文件显示）

```lua
require('trigger_help').setup({
  content = { [':'] = '~/.config/nvim/keyhelp/lua-notes.md' },
  trigger = { event = 'BufEnter', pattern = '*.lua' },
  close = { 'BufLeave', 'FocusLost' },
  match = function() return ':' end,
  pos = 'bottom-right',
})
```

## md 内容示例

```markdown
# 搜索帮助
- /foo        向后搜索 foo
- n / N       下一个 / 上一个

## 模式
- /^foo       行首匹配
```

渲染后：标题行高亮，`-` 行缩进 2 空格，其余原样。

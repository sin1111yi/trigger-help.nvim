# trigger-help.nvim

命令触发的帮助面板：`:TriggerHelp` 打开 snacks picker 浏览文档（用户 md 文件 + 其他插件注册的文档 + 内置 `:h` tag），或 `:TriggerHelp <名称>` 直接打开。面板为底部（或顶部）横向分屏，高度 40%（可配），不抢焦点。内容来自 markdown 文件、内置 `:h` 文档或 `register_doc()` 注册的文档，插件不内置任何内容。

零依赖（picker 需要 snacks.nvim）、单文件（`lua/trigger_help/init.lua`）、`setup()` 全参数可配。

## 安装

源码仓库在 `~/projects/trigger-help.nvim`（git），通过 vim.pack 本地路径安装（`plugins.lua` 里 `$NVIM_LOCAL_PLUGINS .. '/trigger-help.nvim'`，`vim.pack.update()` 克隆到 `pack/core/opt/`）。然后在配置中 `packadd` 并调用 setup：

```lua
vim.cmd('packadd trigger-help.nvim')
require('trigger_help').setup({
  content = {
    search  = '~/.config/nvim/docs/trigger-help.nvim/search.md',
    reverse = '~/.config/nvim/docs/trigger-help.nvim/reverse.md',
    cmd     = '~/.config/nvim/docs/trigger-help.nvim/cmd.md',
  },
  height = 40,        -- 面板高度（窗口高度百分比）
  position = 'bottom', -- 'bottom' | 'top'
})
```

## 命令

| 命令 | 行为 |
|------|------|
| `:TriggerHelp` | 面板已开 → 关闭（toggle）；未开 → 打开 snacks picker 选择文档 |
| `:TriggerHelp <名称>` | 直接打开指定文档（跳过 selector） |

名称解析顺序：**content 键 → 注册文档 name（含 id 别名）→ md 文件名 → help tag**；都不中 → `vim.notify` WARN 提示，不崩溃。

## 配置项

| 项 | 默认 | 说明 |
|----|------|------|
| `content` | `{}` | 文档表：**键 = 文档名**（selector 显示名）→ md 文件路径（string） |
| `height` | `40` | 面板高度，窗口高度的百分比 |
| `position` | `'bottom'` | 面板位置：`'bottom'` 或 `'top'` |

## register_doc API

其他插件可向 trigger-help 注册文档（如 wokamark 注册命令速查）。不依赖 `setup()`，可在其之前调用：

```lua
local th = require('trigger_help')
th.register_doc({
  id = 'wokamark',          -- 来源标识（selector 前缀 [wokamark]）
  name = 'wokamark 使用',    -- 文档名（selector 显示 + :TriggerHelp <name> 直开）
  text = { '...', '...' },  -- 内容：文本行数组
  -- file = '/path/doc.md',  -- 内容：md 文件（三选一，text > file > fn）
  -- fn = function() return { '...' } end,  -- 内容：动态函数
})
```

- 同 id 重复注册 = 覆盖（不重复条目）。
- 注册文档进入 selector（`[id] <name>` 前缀）与名称解析（`:TriggerHelp <name>` 直开；name 含空格时 id 也可直开）。

## 行为

- **selector**：`snacks.pick` 列出三类条目——用户 content 文档（`[md] <name>` 前缀）、注册文档（`[id] <name>` 前缀）与内置 help tag（`[help] <tag>` 前缀，`getcompletion` 前缀遍历懒扫描，会话内只扫一次、内存缓存）。选中 → 面板打开对应文档。
- **面板**：底部（或 `position='top'` 顶部）横向分屏普通 buffer，高度 = 窗口高度 × `height%`。打开即聚焦（光标落入面板便于滚动）；普通窗口，鼠标滚轮/滚动天然支持。无自定义 `q`/`Esc` 绑定——`:q`、`<C-w>c` 或再次 `:TriggerHelp` 均可关闭，关闭即删除自建 buffer（`bufhidden='wipe'`）。
- **md 渲染极简**：行首 `#`/`##` 整行用 `Title` 高亮；行首 `-` 替换为 2 空格缩进；其余原样（不解析行内 md）。
- **`:h` 形态**：静默执行 `:help <tag>`（pcall）→ 读取该 tag 所在小节内容 → 渲染到面板（保留 `filetype='help'` 获得内置高亮）→ 只关闭**本调用新增**的 help 窗口（复用用户已有 help 窗口时不动它），并删除新增窗口的 buffer。
- md 文件缺失 → `vim.notify` WARN **一次**（每个路径每会话一次），不显示不崩溃。
- 同一时刻只保留一个面板（新内容覆盖旧的）；关闭幂等。
- `setup()` 幂等：`vim.g.trigger_help_loaded` 守卫，重复调用不重复注册命令（opt 插件双 source 场景）。
- **不内置 keymap**：用户自行绑定，如 `<leader>xh` → `:TriggerHelp<CR>`。

## md 内容示例

```markdown
# 搜索帮助
- /foo        向后搜索 foo
- n / N       下一个 / 上一个

## 模式
- /^foo       行首匹配
```

渲染后：标题行高亮，`-` 行缩进 2 空格，其余原样。

# trigger-help.nvim

Command-triggered help panel: `:TriggerHelp` opens a snacks picker over
browsable documents (user md files + docs registered by other plugins +
built-in `:h` tags), or `:TriggerHelp <name>` opens one directly. The panel
is a horizontal split (bottom or top), height 40% (configurable), and does
not steal focus. Content comes from markdown files, built-in `:h` docs, or
`register_doc()` registrations — the plugin ships no content of its own.

Zero dependencies at runtime (picker needs snacks.nvim), small module count
(`lua/trigger_help/`), fully configurable `setup()`.

---

## Installation

### lazy.nvim (recommended)

```lua
-- plugin spec
{
  'sin1111yi/trigger-help.nvim',
  lazy = false, -- eager: :TriggerHelp should be available immediately
  config = function()
    require('trigger_help').setup({
      content = {
        search  = '~/.config/nvim/docs/trigger-help.nvim/search.md',
        reverse = '~/.config/nvim/docs/trigger-help.nvim/reverse.md',
        cmd     = '~/.config/nvim/docs/trigger-help.nvim/cmd.md',
      },
      height = 40,        -- panel height (% of window height)
      position = 'bottom', -- 'bottom' | 'top'
    })
  end,
}
```

Then `:Lazy sync` inside Neovim.

#### Dev mode (local source)

```lua
require('lazy').setup({
  dev = {
    path = '~/Development',
    patterns = { 'github.com/sin1111yi/' },
    fallback = true,
  },
  -- ...
})
```

When `~/Development/trigger-help.nvim` exists it is used; other machines
without it fall back to the GitHub install.

### vim.pack (legacy)

```lua
local local_plugins = vim.env.NVIM_LOCAL_PLUGINS or vim.fn.expand('~/projects')
vim.pack.add({ local_plugins .. '/trigger-help.nvim' })
-- nvim --headless -c 'lua vim.pack.update()' -c 'qa!'
vim.cmd('packadd trigger-help.nvim')
require('trigger_help').setup({ ... })
```

---

## Commands

| Command | Behavior |
|---------|----------|
| `:TriggerHelp` | Panel open → close (toggle); closed → open the picker |
| `:TriggerHelp <name>` | Open the named document directly (skips selector) |

Name resolution order: **content key → registered doc name (id alias) →
md filename → help tag**; none match → `vim.notify` WARN, no crash.

---

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `content` | `{}` | Docs table: **key = doc name** (shown in selector) → md path |
| `height` | `40` | Panel height, percentage of window height |
| `position` | `'bottom'` | Panel position: `'bottom'` or `'top'` |

---

## register_doc API

Other plugins can register docs (e.g. wokamark registers its command
cheatsheet). Does not depend on `setup()`, can be called before it:

```lua
local th = require('trigger_help')
th.register_doc({
  id = 'wokamark',          -- source id (selector prefix [wokamark])
  name = 'wokamark 使用',    -- doc name (selector display + :TriggerHelp <name>)
  text = { '...', '...' },  -- content: text lines
  -- file = '/path/doc.md', -- content: md file (one of text/file/fn)
  -- fn = function() return { '...' } end, -- content: dynamic function
})
```

- Re-registering the same id overwrites (no duplicate entries).
- Registered docs appear in the selector (`[id] <name>` prefix) and in name
  resolution (`:TriggerHelp <name>`; when name has spaces, the id works too).

---

## Behavior

- **Selector**: `snacks.pick` lists three kinds — user content docs
  (`[md] <name>` prefix), registered docs (`[id] <name>` prefix), built-in
  help tags (`[help] <tag>` prefix; prefix-traversal lazy scan via
  `getcompletion`, scanned once per session, memory-cached). Selecting opens
  the panel with that document.
- **Panel**: bottom (or top) horizontal split, normal buffer, height =
  window height × `height%`. Opens focused (cursor inside for scrolling);
  normal window — mouse wheel / scrolling work naturally. No custom
  `q`/`Esc` bindings — `:q`, `<C-w>c`, or `:TriggerHelp` again all close;
  closing wipes the self-created buffer (`bufhidden='wipe'`).
- **md rendering minimal**: leading `#`/`##` lines get `Title` highlight;
  leading `-` becomes 2-space indent; everything else passes through
  (no inline md parsing).
- **`:h` form**: silently `:help <tag>` (pcall) → read the tag's section →
  render into the panel (keeps `filetype='help'` for built-in highlighting)
  → close only the help windows **this call created** (reused existing help
  windows are left alone) and delete their buffers.
- Missing md file → `vim.notify` WARN **once** (per path per session), no
  display, no crash.
- Only one panel at a time (new content replaces the old); close is
  idempotent.
- `setup()` idempotent: `vim.g.trigger_help_loaded` guard, repeated calls do
  not re-register commands (opt-plugin double-source scenario).
- **No built-in keymap**: bind your own, e.g. `<leader>xh` → `:TriggerHelp<CR>`.

---

## Module layout

```
lua/trigger_help/
  init.lua     entry: setup, :TriggerHelp, API
  config.lua   options
  lang.lua     locale (LC_ALL > LC_MESSAGES > LANG), bilingual picks
  source.lua   registration + content + help-tag scan + name resolution
  panel.lua    panel window / rendering
  picker.lua   snacks picker integration
```

---

## md content example

```markdown
# Search help
- /foo        search forward for foo
- n / N       next / previous

## Modes
- /^foo       anchor at line start
```

Rendered: title lines highlighted, `-` lines indented 2 spaces, rest as-is.

---

## License

MIT

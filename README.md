# claude-write

A Neovim plugin that uses Claude's API directly for intelligent code editing and analysis with git-style diff interface.

## Features

- **Reader Mode** (`<leader>cr`): Load current buffer into persistent memory
- **Copy Check** (`<leader>cc`): Check current line for grammar/spelling/clarity
- **Line Edit** (`<leader>cl`): Edit current line with interactive diff view
- **Git Browse** (`<leader>cg`): Browse and load files from git repositories
- **Clear Memory** (`<leader>cR`): Clear all stored context

## Installation

### Manual Installation

1. Copy the `claude-write` folder to your Neovim config:
   ```bash
   cp -r claude-write ~/.config/nvim/pack/plugins/start/
   ```

### Using Lazy.nvim

```lua
{
  dir = "/home/servus/Programs/claude-editor/claude-write",
  config = function()
    require("claude-write").setup({
      -- Optional: customize settings
      keymaps = {
        reader = "<leader>cr",
        copy_check = "<leader>cc",
        line_edit = "<leader>cl",
        git_browse = "<leader>cg",
        clear_memory = "<leader>cR",
      },
    })
  end,
}
```

### Using Packer

```lua
use {
  "/home/servus/Programs/claude-editor/claude-write",
  config = function()
    require("claude-write").setup()
  end,
}
```

## Requirements

- Neovim >= 0.8.0
- [Claude Code CLI](https://github.com/anthropics/claude-code) installed and authenticated (credentials at `~/.claude/.credentials.json`)
- `curl` command available
- Git (for repository cloning)

## Configuration

```lua
require("claude-write").setup({
  -- Cache directory (default: vim cache dir)
  cache_dir = vim.fn.stdpath("cache") .. "/claude-write",

  -- Keybindings
  keymaps = {
    reader = "<leader>cr",
    copy_check = "<leader>cc",
    line_edit = "<leader>cl",
    git_browse = "<leader>cg",
    clear_memory = "<leader>cR",
  },

  -- UI settings
  ui = {
    border = "rounded",  -- "none", "single", "double", "rounded"
    width = 0.8,
    height = 0.8,
  },

  -- Claude session settings
  session = {
    timeout = 300000,  -- 5 minutes
    max_retries = 3,
  },
})
```

## Usage

### Reader Mode

Load the current buffer into Claude's persistent memory:

```
<leader>cr
```

or

```
:ClaudeReader
```

### Copy Check

Check the current line for issues:

```
<leader>cc
```

or

```
:ClaudeCopyCheck
```

### Line Edit with Diff View

Edit the current line with an interactive git-style diff view:

```
<leader>cl
```

or

```
:ClaudeLineEdit
```

**How it works:**
1. Place cursor on the line you want to edit
2. Press `<leader>cl` to trigger analysis
3. A diff window opens on the right showing:
   - `- original line` (in red)
   - `+ suggested line` (in green)
4. In the diff window:
   - `dd` on the `-` line: **Accept** the change (keep the `+` line)
   - `dd` on the `+` line: **Reject** the change (keep the original)
   - `a`: Accept all changes
   - `r`: Reject all changes
   - `q`: Close diff window

**Example:**
```diff
# Word choice improvement recommended

@@ Line 42 @@
- This function should be ran every time
+ This function should be run every time
```

Delete the `-` line to accept Claude's suggestion, or delete the `+` line to keep your original.

### Git Repository Browser

1. Press `<leader>cg` or run `:ClaudeGitBrowse`
2. Enter a git URL (or press 's' to edit)
3. Press 's' to sync/clone the repository
4. Navigate files with j/k
5. Press 'i' to include/exclude files
6. Press Enter to save selection to memory

Keybindings in Git Browser:
- `e` - Edit git URL
- `s` - Sync repository (clone or pull)
- `i` - Include/exclude file (toggle checkbox)
- `Enter` - Save selection to memory
- `q` - Quit browser

### Clear Memory

Clear all stored context:

```
<leader>cR
```

or

```
:ClaudeClearMemory
```

## Architecture

The plugin uses OAuth credentials from `~/.claude/.credentials.json` to make direct API calls to Claude's API. This allows for:

- Direct authentication without CLI overhead
- Automatic token refresh when expired
- Streaming responses for real-time feedback
- Interactive diff-based editing workflow
- Maintaining persistent context across operations

## Memory System

Context is stored in `~/.cache/nvim/claude-write/memory.json` and includes:

- Loaded file contents
- Selected files from git repositories
- Custom context items
- Timestamps for all entries

## License

MIT

## Contributing

Issues and pull requests welcome!

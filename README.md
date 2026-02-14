# claude-write

A Neovim plugin that integrates Claude Code CLI for intelligent code editing and analysis.

## Features

- **Reader Mode** (`<leader>cr`): Load current buffer into persistent memory
- **Copy Check** (`<leader>cc`): Check current line for grammar/spelling/clarity
- **Line Edit** (`<leader>cl`): Edit and improve last 10 lines
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
- [Claude Code CLI](https://github.com/anthropics/claude-code) installed and configured
- Git (for repository cloning)

## Configuration

```lua
require("claude-write").setup({
  -- Claude CLI command (default: "claude")
  claude_cmd = "claude",

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

### Line Edit

Edit the last 10 lines:

```
<leader>cl
```

or

```
:ClaudeLineEdit
```

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

The plugin calls `claude -p` commands in ephemeral terminal sessions and parses the stdout. This allows for:

- Orchestrating multiple Claude sessions
- Using Claude's Task tool for sub-agent delegation
- Maintaining persistent context across operations
- Pipeline-based workflows (15-20+ concurrent operations)

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

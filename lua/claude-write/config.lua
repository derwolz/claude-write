-- Configuration for claude-write
local M = {}

M.defaults = {
  -- Directory for cloned repos and cache
  cache_dir = vim.fn.stdpath("cache") .. "/claude-write",

  -- Memory file for persistent context
  memory_file = vim.fn.stdpath("cache") .. "/claude-write/memory.json",

  -- Default git branch to checkout
  default_branch = "main",

  -- Keybindings
  keymaps = {
    reader = "<leader>cr",        -- Load into memory
    copy_check = "<leader>cc",    -- Copy-edit current line (grammar/spelling diff)
    line_edit = "<leader>cl",     -- Edit current line with diff view
    reader_check = "<leader>cs",  -- Reader reaction to current line/selection
    git_browse = "<leader>cg",    -- Browse git repo
    clear_memory = "<leader>cR",  -- Clear memory (capital R)
  },

  -- UI settings
  ui = {
    border = "rounded",
    width = 0.8,  -- 80% of screen width
    height = 0.8, -- 80% of screen height
  },

  -- Claude session settings
  session = {
    timeout = 300000, -- 5 minutes in milliseconds
    max_retries = 3,
  },
}

-- Initialize options with defaults
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Ensure cache directory exists
  vim.fn.mkdir(M.options.cache_dir, "p")

  return M.options
end

return M

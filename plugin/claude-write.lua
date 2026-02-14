-- Plugin entry point for claude-write
if vim.g.loaded_claude_write then
  return
end
vim.g.loaded_claude_write = true

-- Auto-setup with defaults if not already configured
vim.defer_fn(function()
  if not vim.g.claude_write_configured then
    require("claude-write").setup()
  end
end, 0)

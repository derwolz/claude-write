-- Memory management for persistent context
local M = {}
local config = require("claude-write.config")

-- Memory structure
M.memory = {
  files = {},      -- Loaded files
  git_repos = {},  -- Cloned git repos
  context = {},    -- Custom context items
  timestamp = nil,
}

-- Load memory from disk
function M.load()
  local file = io.open(config.options.memory_file, "r")
  if not file then
    return M.memory
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if ok and data then
    M.memory = data
  end

  return M.memory
end

-- Save memory to disk
function M.save()
  M.memory.timestamp = os.time()

  local content = vim.json.encode(M.memory)
  local file = io.open(config.options.memory_file, "w")
  if not file then
    vim.notify("Failed to save memory", vim.log.levels.ERROR)
    return false
  end

  file:write(content)
  file:close()

  return true
end

-- Add file to memory
function M.add_file(filepath, content)
  M.memory.files[filepath] = {
    content = content,
    timestamp = os.time(),
  }
  M.save()
end

-- Add git repo to memory
function M.add_repo(repo_url, local_path, selected_files)
  M.memory.git_repos[repo_url] = {
    local_path = local_path,
    selected_files = selected_files,
    timestamp = os.time(),
  }
  M.save()
end

-- Add custom context
function M.add_context(key, value)
  M.memory.context[key] = value
  M.save()
end

-- Clear all memory
function M.clear()
  M.memory = {
    files = {},
    git_repos = {},
    context = {},
    timestamp = os.time(),
  }
  M.save()
  vim.notify("Memory cleared", vim.log.levels.INFO)
end

-- Get formatted context for Claude
function M.get_context_string()
  local parts = {}

  -- Add files
  if next(M.memory.files) then
    table.insert(parts, "=== Loaded Files ===")
    for filepath, data in pairs(M.memory.files) do
      table.insert(parts, string.format("File: %s", filepath))
      table.insert(parts, data.content)
      table.insert(parts, "")
    end
  end

  -- Add git repos
  if next(M.memory.git_repos) then
    table.insert(parts, "=== Git Repositories ===")
    for repo_url, data in pairs(M.memory.git_repos) do
      table.insert(parts, string.format("Repo: %s", repo_url))
      table.insert(parts, string.format("Files: %s", table.concat(data.selected_files, ", ")))
      table.insert(parts, "")
    end
  end

  -- Add custom context
  if next(M.memory.context) then
    table.insert(parts, "=== Context ===")
    for key, value in pairs(M.memory.context) do
      table.insert(parts, string.format("%s: %s", key, value))
    end
  end

  return table.concat(parts, "\n")
end

-- Initialize
M.load()

return M

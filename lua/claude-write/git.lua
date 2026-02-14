-- Git operations module
local M = {}
local config = require("claude-write.config")

-- Parse git URL to get repo name
function M.parse_git_url(url)
  -- Handle both HTTPS and SSH URLs
  local patterns = {
    "https?://[^/]+/(.+/.+)%.git",
    "https?://[^/]+/(.+/.+)",
    "git@[^:]+:(.+/.+)%.git",
    "git@[^:]+:(.+/.+)",
  }

  for _, pattern in ipairs(patterns) do
    local match = url:match(pattern)
    if match then
      return match:gsub("/", "-")
    end
  end

  return nil
end

-- Clone or update a git repository
function M.sync_repo(repo_url, callback)
  local repo_name = M.parse_git_url(repo_url)
  if not repo_name then
    if callback then
      callback(nil, "Invalid git URL")
    end
    return
  end

  local repo_path = config.options.cache_dir .. "/repos/" .. repo_name

  -- Check if repo already exists
  local exists = vim.fn.isdirectory(repo_path) == 1

  local cmd
  if exists then
    -- Pull latest changes
    cmd = string.format("cd '%s' && git pull", repo_path)
  else
    -- Clone repo
    vim.fn.mkdir(config.options.cache_dir .. "/repos", "p")
    cmd = string.format("git clone '%s' '%s'", repo_url, repo_path)
  end

  vim.fn.jobstart(cmd, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        if callback then
          callback(repo_path, nil)
        end
      else
        if callback then
          callback(nil, "Git operation failed")
        end
      end
    end,
  })
end

-- List all files in a repository
function M.list_files(repo_path, callback)
  local cmd = string.format(
    "cd '%s' && git ls-files",
    repo_path
  )

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        local files = {}
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(files, line)
          end
        end
        if callback then
          callback(files, nil)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 and callback then
        callback(nil, "Failed to list files")
      end
    end,
  })
end

-- Read file content from repo
function M.read_file(repo_path, filepath)
  local full_path = repo_path .. "/" .. filepath
  local file = io.open(full_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  return content
end

return M

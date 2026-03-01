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
  local memory_file = config.options.memory_file or config.defaults.memory_file
  if not memory_file then
    return M.memory
  end

  local file = io.open(memory_file, "r")
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
  local memory_file = config.options.memory_file or config.defaults.memory_file
  if not memory_file then
    vim.notify("Memory file path not configured", vim.log.levels.ERROR)
    return false
  end

  M.memory.timestamp = os.time()

  local content = vim.json.encode(M.memory)
  local file = io.open(memory_file, "w")
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

-- Detect chapter number from a file: check first line for "chapter XX", then filename for numbers
-- Also detects "prologue" (chapter 0) and "epilogue" (returns -1 as sentinel)
local function detect_chapter_info(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t"):lower()

  -- Check for prologue/epilogue in filename
  if filename:match("prologue") then
    return 0, "prologue"
  end
  if filename:match("epilogue") then
    return -1, "epilogue"
  end

  local f = io.open(filepath, "r")
  if not f then return nil, nil end

  local first_line = f:read("*l") or ""
  f:close()

  local first_lower = first_line:lower()

  -- Check first line for prologue/epilogue
  if first_lower:match("^prologue") then
    return 0, "prologue"
  end
  if first_lower:match("^epilogue") then
    return -1, "epilogue"
  end

  -- Check first line for "chapter XX"
  local num = first_lower:match("^chapter%s+(%d+)")
  if num then return tonumber(num), "chapter" end

  -- Fall back to numbers in filename
  num = filename:match("(%d+)")
  if num then return tonumber(num), "chapter" end

  return nil, nil
end

-- Load chapter summaries from chapter_dir up to chapter N, replacing all memory
-- Prologue (chapter 0) is always included if present.
-- Epilogue is only included if up_to_chapter is nil (load all).
function M.load_chapters(up_to_chapter)
  local chapter_dir = config.options.chapter_dir
  if not chapter_dir then
    return nil, "No chapter_dir configured. Use :ClaudeWriteConfig to set it."
  end

  chapter_dir = vim.fn.expand(chapter_dir)
  if vim.fn.isdirectory(chapter_dir) == 0 then
    return nil, "Chapter directory does not exist: " .. chapter_dir
  end

  local files = vim.fn.glob(chapter_dir .. "/*", false, true)
  local chapters = {}    -- num -> { filepath, content }
  local has_epilogue = false
  local epilogue_data = nil

  for _, filepath in ipairs(files) do
    if vim.fn.filereadable(filepath) == 1 then
      local chapter_num, kind = detect_chapter_info(filepath)
      if chapter_num then
        local f = io.open(filepath, "r")
        if f then
          local content = f:read("*a")
          f:close()

          if kind == "epilogue" then
            has_epilogue = true
            epilogue_data = { filepath = filepath, content = content }
          elseif chapter_num <= up_to_chapter then
            chapters[chapter_num] = {
              filepath = filepath,
              content = content,
            }
          end
        end
      end
    end
  end

  if not next(chapters) and not has_epilogue then
    return nil, "No chapter files found in " .. chapter_dir
  end

  -- Clear memory and replace with chapters
  M.memory = {
    files = {},
    git_repos = {},
    context = {},
    timestamp = os.time(),
  }

  local loaded = {}

  -- Load prologue first if present (chapter 0)
  if chapters[0] then
    M.memory.files["prologue"] = {
      content = chapters[0].content,
      timestamp = os.time(),
    }
    table.insert(loaded, "prologue")
  end

  -- Load chapters in order
  for num = 1, up_to_chapter do
    if chapters[num] then
      local key = string.format("chapter_%02d", num)
      M.memory.files[key] = {
        content = chapters[num].content,
        timestamp = os.time(),
      }
      table.insert(loaded, num)
    end
  end

  M.save()
  return loaded, nil
end

-- Get just the context notes (compact, no file blobs) for reader mode
function M.get_reader_context()
  if not next(M.memory.context) then
    return ""
  end
  local parts = {}
  for key, value in pairs(M.memory.context) do
    table.insert(parts, key .. ": " .. value)
  end
  return table.concat(parts, "\n")
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

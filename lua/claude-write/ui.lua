-- UI module for popups and interactive elements
local M = {}
local config = require("claude-write.config")
local git = require("claude-write.git")
local memory = require("claude-write.memory")

-- Create a centered floating window
function M.create_float(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * config.options.ui.width)
  local height = opts.height or math.floor(vim.o.lines * config.options.ui.height)

  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = config.options.ui.border,
  })

  return buf, win
end

-- Git repository browser
function M.show_git_browser(initial_url)
  local buf, win = M.create_float()

  -- State
  local state = {
    url = initial_url or "",
    repo_path = nil,
    files = {},
    selected = {},
    cursor = 1,
  }

  -- Render function
  local function render()
    local lines = {}
    table.insert(lines, "=== Claude Write - Git Repository Browser ===")
    table.insert(lines, "")
    table.insert(lines, "Git URL: " .. state.url)
    table.insert(lines, "Press 'e' to edit URL, 's' to sync, 'q' to quit")
    table.insert(lines, "Press 'i' to include/exclude file, 'Enter' to save selection")
    table.insert(lines, "")

    if state.repo_path then
      table.insert(lines, "Repository: " .. state.repo_path)
      table.insert(lines, "")
      table.insert(lines, "Files:")

      for idx, file in ipairs(state.files) do
        local checkbox = state.selected[file] and "[x]" or "[ ]"
        local line = string.format("%s %s", checkbox, file)
        table.insert(lines, line)
      end
    else
      table.insert(lines, "Press 's' to sync repository")
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end

  -- Edit URL
  local function edit_url()
    vim.ui.input({ prompt = "Git URL: ", default = state.url }, function(input)
      if input then
        state.url = input
        state.repo_path = nil
        state.files = {}
        state.selected = {}
        render()
      end
    end)
  end

  -- Sync repository
  local function sync_repo()
    vim.notify("Syncing repository...", vim.log.levels.INFO)

    git.sync_repo(state.url, function(repo_path, err)
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      state.repo_path = repo_path

      git.list_files(repo_path, function(files, list_err)
        if list_err then
          vim.notify("Error: " .. list_err, vim.log.levels.ERROR)
          return
        end

        state.files = files
        vim.notify("Repository synced successfully", vim.log.levels.INFO)
        render()
      end)
    end)
  end

  -- Toggle file selection
  local function toggle_file()
    local line_num = vim.api.nvim_win_get_cursor(win)[1]
    local file_idx = line_num - 8  -- Offset for header lines

    if file_idx > 0 and file_idx <= #state.files then
      local file = state.files[file_idx]
      state.selected[file] = not state.selected[file]
      render()
      vim.api.nvim_win_set_cursor(win, { line_num, 0 })
    end
  end

  -- Save selection to memory
  local function save_selection()
    local selected_files = {}
    for file, is_selected in pairs(state.selected) do
      if is_selected then
        table.insert(selected_files, file)
      end
    end

    if #selected_files == 0 then
      vim.notify("No files selected", vim.log.levels.WARN)
      return
    end

    -- Add to memory
    memory.add_repo(state.url, state.repo_path, selected_files)

    -- Read and store file contents
    for _, file in ipairs(selected_files) do
      local content = git.read_file(state.repo_path, file)
      if content then
        memory.add_file(file, content)
      end
    end

    vim.notify(string.format("Added %d files to memory", #selected_files), vim.log.levels.INFO)
    vim.api.nvim_win_close(win, true)
  end

  -- Keymaps
  local opts_local = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "e", edit_url, opts_local)
  vim.keymap.set("n", "s", sync_repo, opts_local)
  vim.keymap.set("n", "i", toggle_file, opts_local)
  vim.keymap.set("n", "<CR>", save_selection, opts_local)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, opts_local)

  -- Initial render
  render()
end

-- Show result in a popup
function M.show_result(title, content)
  local buf, win = M.create_float({ height = 15 })

  local lines = {}
  table.insert(lines, "=== " .. title .. " ===")
  table.insert(lines, "")

  -- Split content into lines
  for line in content:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { noremap = true, silent = true, buffer = buf })
end


return M

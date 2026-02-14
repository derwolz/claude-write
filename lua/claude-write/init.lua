-- Main module for claude-write
local M = {}

local config = require("claude-write.config")
local claude = require("claude-write.claude")
local memory = require("claude-write.memory")
local ui = require("claude-write.ui")
local diff_ui = require("claude-write.diff_ui")

-- Setup function
function M.setup(opts)
  config.setup(opts)

  -- Create user commands
  vim.api.nvim_create_user_command("ClaudeReader", M.reader, {})
  vim.api.nvim_create_user_command("ClaudeCopyCheck", M.copy_check, {})
  vim.api.nvim_create_user_command("ClaudeLineEdit", M.line_edit, { range = true })
  vim.api.nvim_create_user_command("ClaudeGitBrowse", M.git_browse, {})
  vim.api.nvim_create_user_command("ClaudeClearMemory", M.clear_memory, {})

  -- Set up keymaps if enabled
  if config.options.keymaps then
    if config.options.keymaps.reader then
      vim.keymap.set("n", config.options.keymaps.reader, M.reader, {
        noremap = true,
        silent = true,
        desc = "Claude: Load current buffer into memory"
      })
    end

    if config.options.keymaps.copy_check then
      vim.keymap.set("n", config.options.keymaps.copy_check, M.copy_check, {
        noremap = true,
        silent = true,
        desc = "Claude: Check current line for issues"
      })
    end

    if config.options.keymaps.line_edit then
      -- Normal mode: edit current line
      vim.keymap.set("n", config.options.keymaps.line_edit, M.line_edit, {
        noremap = true,
        silent = true,
        desc = "Claude: Edit current line with diff view"
      })
      -- Visual mode: edit selected lines
      vim.keymap.set("v", config.options.keymaps.line_edit, function()
        M.line_edit_visual()
      end, {
        noremap = true,
        silent = true,
        desc = "Claude: Edit selected lines with diff view"
      })
    end

    if config.options.keymaps.git_browse then
      vim.keymap.set("n", config.options.keymaps.git_browse, M.git_browse, {
        noremap = true,
        silent = true,
        desc = "Claude: Browse and clone git repository"
      })
    end

    if config.options.keymaps.clear_memory then
      vim.keymap.set("n", config.options.keymaps.clear_memory, M.clear_memory, {
        noremap = true,
        silent = true,
        desc = "Claude: Clear all memory"
      })
    end
  end
end

-- Load current buffer into memory
function M.reader()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if filepath == "" then
    vim.notify("No file associated with this buffer", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  memory.add_file(filepath, content)
  vim.notify("Added to memory: " .. vim.fn.fnamemodify(filepath, ":t"), vim.log.levels.INFO)
end

-- Check current line for issues
function M.copy_check()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line_content = vim.api.nvim_get_current_line()

  if line_content == "" then
    vim.notify("Current line is empty", vim.log.levels.WARN)
    return
  end

  vim.notify("Starting line check...", vim.log.levels.INFO)
  local loading_buf, loading_win = ui.show_loading("Checking line...")

  claude.check_line(line_content, function(result, err)
    -- Safely close the loading window
    pcall(function()
      if vim.api.nvim_win_is_valid(loading_win) then
        vim.api.nvim_win_close(loading_win, true)
      end
    end)

    if err then
      vim.notify("Claude Error: " .. err, vim.log.levels.ERROR)
      local log_file = vim.fn.stdpath("cache") .. "/claude-write-debug.log"
      vim.notify("Check log file: " .. log_file, vim.log.levels.INFO)
      return
    end

    if not result or result == "" then
      vim.notify("No result received from Claude", vim.log.levels.WARN)
      return
    end

    ui.show_result("Line Check - Line " .. line_num, result)
  end)
end

-- Edit current line with diff view
function M.line_edit()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]

  vim.notify("Analyzing line " .. line_nr .. "...", vim.log.levels.INFO)
  local loading_buf, loading_win = ui.show_loading("Claude is analyzing...")

  claude.edit_current_line(bufnr, line_nr, function(result, err)
    -- Safely close the loading window
    pcall(function()
      if vim.api.nvim_win_is_valid(loading_win) then
        vim.api.nvim_win_close(loading_win, true)
      end
    end)

    if err then
      vim.notify("Claude Error: " .. err, vim.log.levels.ERROR)
      local log_file = vim.fn.stdpath("cache") .. "/claude-write-debug.log"
      vim.notify("Check log file: " .. log_file, vim.log.levels.INFO)
      return
    end

    if not result or result == "" then
      vim.notify("No result received from Claude", vim.log.levels.WARN)
      return
    end

    -- Parse the JSON response
    local edit_data, parse_err = diff_ui.parse_edit_response(result)
    if parse_err then
      vim.notify("Failed to parse response: " .. parse_err, vim.log.levels.ERROR)
      -- Show raw response for debugging
      ui.show_result("Raw Response (Debug)", result)
      return
    end

    -- Display the diff
    diff_ui.display_diff(bufnr, edit_data)
  end)
end

-- Edit multiple selected lines with diff view
function M.line_edit_visual()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get visual selection range
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Exit visual mode
  vim.cmd("normal! \\<Esc>")

  local line_count = end_line - start_line + 1
  vim.notify(string.format("Analyzing %d lines (%d-%d)...", line_count, start_line, end_line), vim.log.levels.INFO)
  local loading_buf, loading_win = ui.show_loading("Claude is analyzing " .. line_count .. " lines...")

  claude.edit_multiple_lines(bufnr, start_line, end_line, function(result, err)
    -- Safely close the loading window
    pcall(function()
      if vim.api.nvim_win_is_valid(loading_win) then
        vim.api.nvim_win_close(loading_win, true)
      end
    end)

    if err then
      vim.notify("Claude Error: " .. err, vim.log.levels.ERROR)
      local log_file = vim.fn.stdpath("cache") .. "/claude-write-debug.log"
      vim.notify("Check log file: " .. log_file, vim.log.levels.INFO)
      return
    end

    if not result or result == "" then
      vim.notify("No result received from Claude", vim.log.levels.WARN)
      return
    end

    -- Parse the JSON response
    local edit_data, parse_err = diff_ui.parse_edit_response(result)
    if parse_err then
      vim.notify("Failed to parse response: " .. parse_err, vim.log.levels.ERROR)
      -- Show raw response for debugging
      ui.show_result("Raw Response (Debug)", result)
      return
    end

    -- Display the diff
    diff_ui.display_diff(bufnr, edit_data)
  end)
end

-- Browse git repository
function M.git_browse()
  vim.ui.input({ prompt = "Git URL (or leave empty to edit): " }, function(input)
    ui.show_git_browser(input or "")
  end)
end

-- Clear memory
function M.clear_memory()
  vim.ui.input({ prompt = "Clear all memory? (y/n): " }, function(input)
    if input and input:lower() == "y" then
      memory.clear()
    end
  end)
end

return M

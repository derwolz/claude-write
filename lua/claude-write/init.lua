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
  vim.api.nvim_create_user_command("ClaudeReaderCheck", M.reader_check, {})
  vim.api.nvim_create_user_command("ClaudeGitBrowse", M.git_browse, {})
  vim.api.nvim_create_user_command("ClaudeClearMemory", M.clear_memory, {})
  vim.api.nvim_create_user_command("ClaudeWriteChapter", function(cmd_opts)
    M.load_chapter(cmd_opts.args)
  end, { nargs = 1 })
  vim.api.nvim_create_user_command("ClaudeWriteConfig", M.write_config, {})

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
      vim.keymap.set("v", config.options.keymaps.line_edit, ":<C-u>lua require('claude-write').line_edit_visual()<CR>", {
        noremap = true,
        silent = true,
        desc = "Claude: Edit selected lines with diff view"
      })
    end

    if config.options.keymaps.reader_check then
      vim.keymap.set("n", config.options.keymaps.reader_check, M.reader_check, {
        noremap = true,
        silent = true,
        desc = "Claude: Reader reaction to current line"
      })
      vim.keymap.set("v", config.options.keymaps.reader_check, ":<C-u>lua require('claude-write').reader_check_visual()<CR>", {
        noremap = true,
        silent = true,
        desc = "Claude: Reader reaction to selected lines"
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

    if config.options.keymaps.load_chapter then
      vim.keymap.set("n", config.options.keymaps.load_chapter, function()
        vim.ui.input({ prompt = "Load chapters up to: " }, function(input)
          if input then M.load_chapter(input) end
        end)
      end, {
        noremap = true,
        silent = true,
        desc = "Claude: Load chapters up to N"
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

-- Copy-edit current line: grammar and spelling only, with diff view
function M.copy_check()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line_content = vim.api.nvim_get_current_line()

  if line_content == "" then
    vim.notify("Current line is empty", vim.log.levels.WARN)
    return
  end

  vim.notify("Copy-editing line " .. line_nr .. "...", vim.log.levels.INFO)

  claude.copy_edit_line(bufnr, line_nr, function(result, err)

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

    local edit_data, parse_err = diff_ui.parse_edit_response(result)
    if parse_err then
      vim.notify("Failed to parse response: " .. parse_err, vim.log.levels.ERROR)
      ui.show_result("Raw Response (Debug)", result)
      return
    end

    diff_ui.display_diff(bufnr, edit_data)
  end)
end

-- Edit current line with diff view
function M.line_edit()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]

  vim.notify("Analyzing line " .. line_nr .. "...", vim.log.levels.INFO)

  claude.edit_current_line(bufnr, line_nr, function(result, err)

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

  claude.edit_multiple_lines(bufnr, start_line, end_line, function(result, err)

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

-- Parse reader JSON response (shared by both reader functions)
local function parse_reader_response(raw)
  local json_str = raw:match("```json\n(.-)```") or raw:match("```\n(.-)```") or raw
  local ok, data = pcall(vim.json.decode, json_str)
  if not ok or not data or not data.response then
    return nil, "Failed to parse reader response"
  end
  return data, nil
end

-- Reader reaction to current line
function M.reader_check()
  local source_win = vim.api.nvim_get_current_win()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local line_content = vim.api.nvim_get_current_line()

  if line_content == "" then
    vim.notify("Current line is empty", vim.log.levels.WARN)
    return
  end

  vim.notify("Getting reader reaction...", vim.log.levels.INFO)

  local context_string = memory.get_reader_context()

  claude.reader_react(line_content, context_string, function(result, err)

    if err then
      vim.notify("Claude Error: " .. err, vim.log.levels.ERROR)
      return
    end

    if not result or result == "" then
      vim.notify("No result received from Claude", vim.log.levels.WARN)
      return
    end

    local data, parse_err = parse_reader_response(result)
    if parse_err then
      vim.notify(parse_err, vim.log.levels.ERROR)
      return
    end

    if data.memory and #data.memory > 0 then
      for _, item in ipairs(data.memory) do
        if item.key and item.value then
          memory.add_context(item.key, item.value)
        end
      end
    end

    diff_ui.display_reader(source_win, "Reader — Line " .. line_nr, data.response)
  end)
end

-- Reader reaction to visual selection
function M.reader_check_visual()
  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  vim.cmd("normal! \\<Esc>")

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    vim.notify("No lines selected", vim.log.levels.WARN)
    return
  end

  local text = table.concat(lines, "\n")
  local line_count = end_line - start_line + 1

  vim.notify(string.format("Getting reader reaction for %d lines...", line_count), vim.log.levels.INFO)

  local context_string = memory.get_reader_context()

  claude.reader_react(text, context_string, function(result, err)

    if err then
      vim.notify("Claude Error: " .. err, vim.log.levels.ERROR)
      return
    end

    if not result or result == "" then
      vim.notify("No result received from Claude", vim.log.levels.WARN)
      return
    end

    local data, parse_err = parse_reader_response(result)
    if parse_err then
      vim.notify(parse_err, vim.log.levels.ERROR)
      return
    end

    if data.memory and #data.memory > 0 then
      for _, item in ipairs(data.memory) do
        if item.key and item.value then
          memory.add_context(item.key, item.value)
        end
      end
    end

    local title = string.format("Reader — Lines %d-%d", start_line, end_line)
    diff_ui.display_reader(source_win, title, data.response)
  end)
end

-- Load chapters up to N into memory
function M.load_chapter(input)
  local chapter_num = tonumber(input)
  if not chapter_num then
    vim.notify("Invalid chapter number: " .. tostring(input), vim.log.levels.ERROR)
    return
  end

  local loaded, err = memory.load_chapters(chapter_num)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  -- Format loaded list for display
  local parts = {}
  for _, v in ipairs(loaded) do
    if type(v) == "string" then
      table.insert(parts, v)
    else
      table.insert(parts, tostring(v))
    end
  end
  vim.notify("Loaded chapters: " .. table.concat(parts, ", "), vim.log.levels.INFO)
end

-- Configure claude-write settings interactively
function M.write_config()
  vim.ui.input({
    prompt = "Chapter summaries folder: ",
    default = config.options.chapter_dir or "",
    completion = "dir",
  }, function(input)
    if input and input ~= "" then
      config.options.chapter_dir = input
      vim.notify("Chapter directory set to: " .. input, vim.log.levels.INFO)
    end
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

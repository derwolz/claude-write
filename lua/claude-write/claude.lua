-- Claude interaction module using claude CLI pipe mode
local M = {}
local config = require("claude-write.config")

-- Debug logging
local function debug_log(msg)
  local log_file = vim.fn.stdpath("cache") .. "/claude-write-debug.log"
  local f = io.open(log_file, "a")
  if f then
    f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
    f:close()
  end
end

-- Call claude CLI via pipe: echo content | claude -p "prompt"
-- The prompt argument is the instruction/system prompt.
-- The stdin_content is piped in as user input.
-- Response comes back as raw text on stdout.
local function call_claude_cli(stdin_content, prompt, callback)
  debug_log("Calling claude CLI with prompt length: " .. #prompt)

  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart({ "claude", "-p", prompt }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      debug_log("claude CLI exited with code: " .. exit_code)

      if exit_code ~= 0 then
        local error_msg = #stderr_data > 0
          and table.concat(stderr_data, "\n")
          or "claude CLI failed with code " .. exit_code
        callback(nil, error_msg)
        return
      end

      local response = table.concat(stdout_data, "\n")
      debug_log("claude CLI response received, length: " .. #response)

      if response == "" then
        callback(nil, "Empty response from claude CLI")
        return
      end

      callback(response, nil)
    end,
  })

  if job_id <= 0 then
    callback(nil, "Failed to start claude CLI (is 'claude' in PATH?)")
    return
  end

  -- Pipe stdin content and close stdin
  vim.fn.chansend(job_id, stdin_content)
  vim.fn.chanclose(job_id, "stdin")

  debug_log("claude CLI job started with ID: " .. tostring(job_id))
end

-- Execute prompt asynchronously with callback
function M.execute_async(prompt, callback, opts)
  opts = opts or {}
  call_claude_cli("", prompt, callback)
end

-- Get system prompts from config (allows user customization)
local function get_prompt(name)
  return config.options.prompts[name]
end

-- Edit current line with line editor mode
function M.edit_current_line(bufnr, line_nr, callback)
  -- Get the current line (line_nr is 1-indexed from Neovim)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)
  if #lines == 0 then
    callback(nil, "No line at position " .. line_nr)
    return
  end

  local line_content = lines[1]
  local zero_indexed_line = line_nr - 1

  local user_input = string.format("[Line %d] %s", zero_indexed_line, line_content)
  local prompt = get_prompt("line_editor") .. "\n\nNow review this line:"

  call_claude_cli(user_input, prompt, callback)
end

-- Edit multiple lines with line editor mode
function M.edit_multiple_lines(bufnr, start_line, end_line, callback)
  -- Get the lines (line numbers are 1-indexed from Neovim)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    callback(nil, "No lines in range " .. start_line .. "-" .. end_line)
    return
  end

  -- Build prompt with all lines
  local line_prompts = {}
  for i, line_content in ipairs(lines) do
    local zero_indexed_line = start_line - 1 + (i - 1)
    table.insert(line_prompts, string.format("[Line %d] %s", zero_indexed_line, line_content))
  end

  local user_input = table.concat(line_prompts, "\n")
  local prompt = get_prompt("line_editor") .. "\n\nNow review these lines:"

  call_claude_cli(user_input, prompt, callback)
end

-- Copy edit current line (grammar and spelling only) with diff view
function M.copy_edit_line(bufnr, line_nr, callback)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)
  if #lines == 0 then
    callback(nil, "No line at position " .. line_nr)
    return
  end

  local line_content = lines[1]
  local zero_indexed_line = line_nr - 1

  local user_input = string.format("[Line %d] %s", zero_indexed_line, line_content)
  local prompt = get_prompt("copy_editor") .. "\n\nNow copy-edit this line:"

  call_claude_cli(user_input, prompt, callback)
end

-- Check current line for grammar/spelling
function M.check_line(line_content, callback)
  local prompt = "Check this line for grammar, spelling, and clarity issues. Provide brief feedback:"
  call_claude_cli(line_content, prompt, callback)
end

-- Get a reader's reaction to a passage, with existing context
function M.reader_react(text, context_string, callback)
  local context_part = ""
  if context_string and context_string ~= "" then
    context_part = "\n\nExisting reader notes:\n" .. context_string .. "\n"
  end

  local prompt = get_prompt("reader") .. context_part .. "\n\nPassage:"

  call_claude_cli(text, prompt, callback)
end

-- Edit last N lines
function M.edit_lines(lines, callback)
  local content = table.concat(lines, "\n")
  local prompt = "Review and improve these lines. Provide the edited version:"
  call_claude_cli(content, prompt, callback)
end

-- Create a persistent session for complex tasks
function M.create_session(context, callback)
  local prompt = "You are helping with code editing. Reply 'ready' when you've loaded this context."
  call_claude_cli(vim.json.encode(context), prompt, callback)
end

return M

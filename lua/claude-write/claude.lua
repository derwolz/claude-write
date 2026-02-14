-- Claude CLI interaction module
local M = {}
local config = require("claude-write.config")

-- Execute claude command and parse JSON output
function M.execute(prompt, opts)
  opts = opts or {}
  local timeout = opts.timeout or config.options.session.timeout

  -- Build command
  local cmd = string.format(
    "%s -p '%s' 2>&1",
    config.options.claude_cmd,
    prompt:gsub("'", "'\\''")  -- Escape single quotes
  )

  -- Execute command
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute claude command"
  end

  local output = handle:read("*a")
  local success, exit_type, code = handle:close()

  if not success then
    return nil, "Claude command failed: " .. (output or "unknown error")
  end

  return output, nil
end

-- Execute claude command asynchronously with callback
function M.execute_async(prompt, callback, opts)
  opts = opts or {}

  vim.fn.jobstart(
    string.format("%s -p '%s'", config.options.claude_cmd, prompt:gsub("'", "'\\'''")),
    {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if data then
          local output = table.concat(data, "\n")
          if callback then
            callback(output, nil)
          end
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 then
          local error = table.concat(data, "\n")
          if callback then
            callback(nil, error)
          end
        end
      end,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 and callback then
          callback(nil, "Claude command exited with code " .. exit_code)
        end
      end,
    }
  )
end

-- Check current line for grammar/spelling
function M.check_line(line_content, callback)
  local prompt = string.format(
    "Check this line for grammar, spelling, and clarity issues. Provide brief feedback:\n\n%s",
    line_content
  )

  M.execute_async(prompt, callback)
end

-- Edit last N lines
function M.edit_lines(lines, callback)
  local content = table.concat(lines, "\n")
  local prompt = string.format(
    "Review and improve these lines. Provide the edited version:\n\n%s",
    content
  )

  M.execute_async(prompt, callback)
end

-- Create a persistent session for complex tasks
function M.create_session(context, callback)
  local prompt = string.format(
    "You are helping with code editing. Context:\n%s\n\nReply 'ready' when you've loaded this context.",
    vim.json.encode(context)
  )

  M.execute_async(prompt, callback)
end

return M

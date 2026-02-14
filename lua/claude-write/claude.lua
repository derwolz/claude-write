-- Claude CLI interaction module
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

  local stdout_data = {}
  local stderr_data = {}

  local cmd = string.format("%s -p '%s'", config.options.claude_cmd, prompt:gsub("'", "'\\'''"))
  debug_log("Starting command: " .. cmd)

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      debug_log("stdout received: " .. vim.inspect(data))
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      debug_log("stderr received: " .. vim.inspect(data))
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      debug_log("Command exited with code: " .. exit_code)
      debug_log("stdout_data: " .. vim.inspect(stdout_data))
      debug_log("stderr_data: " .. vim.inspect(stderr_data))

      if not callback then
        debug_log("ERROR: No callback provided!")
        return
      end

      if exit_code ~= 0 then
        local error_msg = #stderr_data > 0
          and table.concat(stderr_data, "\n")
          or ("Claude command exited with code " .. exit_code)
        debug_log("Calling callback with error: " .. error_msg)
        callback(nil, error_msg)
      else
        local output = table.concat(stdout_data, "\n")
        debug_log("Calling callback with output length: " .. #output)
        callback(output, nil)
      end
    end,
  })

  debug_log("Job started with ID: " .. tostring(job_id))
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

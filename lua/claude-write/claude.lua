-- Claude API interaction module using credentials hijacking
local M = {}
local config = require("claude-write.config")

-- Paths
local CREDENTIALS_PATH = vim.fn.expand("~/.claude/.credentials.json")
local CONFIG_PATH = vim.fn.expand("~/.claude.json")
local API_URL = "https://api.anthropic.com/v1/messages"
local REFRESH_URL = "https://api.anthropic.com/v1/oauth/token"

-- Cached credentials
local cached_credentials = nil
local cached_access_token = nil
local cached_refresh_token = nil
local cached_expires_at = nil

-- Debug logging
local function debug_log(msg)
  local log_file = vim.fn.stdpath("cache") .. "/claude-write-debug.log"
  local f = io.open(log_file, "a")
  if f then
    f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
    f:close()
  end
end

-- Load credentials from ~/.claude/.credentials.json
local function load_credentials()
  debug_log("Loading credentials from " .. CREDENTIALS_PATH)

  local file = io.open(CREDENTIALS_PATH, "r")
  if not file then
    return nil, "Claude Code credentials not found at " .. CREDENTIALS_PATH
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to parse credentials file: " .. tostring(data)
  end

  local oauth_data = data.claudeAiOauth
  if not oauth_data then
    return nil, "No claudeAiOauth data found in credentials"
  end

  cached_credentials = data
  cached_access_token = oauth_data.accessToken
  cached_refresh_token = oauth_data.refreshToken
  cached_expires_at = oauth_data.expiresAt

  if not cached_access_token or not cached_refresh_token or not cached_expires_at then
    return nil, "Incomplete OAuth credentials"
  end

  debug_log("Credentials loaded successfully")
  return true
end

-- Check if token is expired
local function is_token_expired()
  if not cached_expires_at then
    return true
  end

  local current_time = os.time()
  local buffer_seconds = 300 -- 5 minutes
  return current_time >= (cached_expires_at - buffer_seconds)
end

-- Refresh access token
local function refresh_access_token()
  debug_log("Refreshing access token...")

  if not cached_refresh_token then
    return nil, "No refresh token available"
  end

  local json_data = vim.json.encode({
    grant_type = "refresh_token",
    refresh_token = cached_refresh_token
  })

  local curl_cmd = string.format(
    "curl -s -X POST '%s' -H 'Content-Type: application/json' -d '%s'",
    REFRESH_URL,
    json_data:gsub("'", "'\\''")
  )

  local handle = io.popen(curl_cmd)
  if not handle then
    return nil, "Failed to execute curl command"
  end

  local response = handle:read("*a")
  handle:close()

  local ok, data = pcall(vim.json.decode, response)
  if not ok then
    return nil, "Failed to parse refresh response: " .. tostring(data)
  end

  if not data.access_token or not data.expires_in then
    return nil, "Invalid refresh response: " .. vim.inspect(data)
  end

  -- Update cached tokens
  cached_access_token = data.access_token
  cached_expires_at = os.time() + data.expires_in

  -- Update credentials file
  if cached_credentials and cached_credentials.claudeAiOauth then
    cached_credentials.claudeAiOauth.accessToken = cached_access_token
    cached_credentials.claudeAiOauth.expiresAt = cached_expires_at

    local file = io.open(CREDENTIALS_PATH, "w")
    if file then
      file:write(vim.json.encode(cached_credentials))
      file:close()
      debug_log("Updated credentials file")
    else
      debug_log("Warning: Failed to update credentials file")
    end
  end

  debug_log("Access token refreshed successfully")
  return true
end

-- Get valid access token
local function get_access_token()
  if not cached_credentials then
    local ok, err = load_credentials()
    if not ok then
      return nil, err
    end
  end

  if is_token_expired() then
    local ok, err = refresh_access_token()
    if not ok then
      return nil, err
    end
  end

  return cached_access_token
end

-- Make API call to Claude
local function call_claude_api(messages, callback)
  local access_token, err = get_access_token()
  if not access_token then
    callback(nil, err)
    return
  end

  local request_body = vim.json.encode({
    model = "claude-sonnet-4-5-20250929",
    max_tokens = 4096,
    messages = messages
  })

  debug_log("Making API call to Claude...")

  local curl_cmd = string.format(
    "curl -s -X POST '%s' -H 'Authorization: Bearer %s' -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' -H 'anthropic-beta: oauth-2025-04-20' -d '%s'",
    API_URL,
    access_token,
    request_body:gsub("'", "'\\''")
  )

  -- Run curl asynchronously
  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart(curl_cmd, {
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
      debug_log("API call exited with code: " .. exit_code)

      if exit_code ~= 0 then
        local error_msg = #stderr_data > 0
          and table.concat(stderr_data, "\n")
          or "API call failed with code " .. exit_code
        callback(nil, error_msg)
        return
      end

      local response = table.concat(stdout_data, "\n")
      debug_log("API response received, length: " .. #response)

      local ok, data = pcall(vim.json.decode, response)
      if not ok then
        callback(nil, "Failed to parse API response: " .. tostring(data))
        return
      end

      if data.error then
        callback(nil, "API error: " .. vim.inspect(data.error))
        return
      end

      -- Extract text from response
      if data.content and #data.content > 0 then
        local text = data.content[1].text
        callback(text, nil)
      else
        callback(nil, "No content in API response")
      end
    end,
  })

  debug_log("API job started with ID: " .. tostring(job_id))
end

-- Execute prompt asynchronously with callback
function M.execute_async(prompt, callback, opts)
  opts = opts or {}

  local messages = {
    {
      role = "user",
      content = prompt
    }
  }

  call_claude_api(messages, callback)
end

-- Line editor system prompt
local LINE_EDITOR_PROMPT = [[You are a line editor reviewing a document for stylistic improvements.

Your role:
- Review the current line for word choice, sentence length, flow, and redundancy
- Provide ONE concrete suggestion per line, or respond with no changes if the line is excellent
- Focus on clarity, conciseness, and impact
- Suggest alternatives that maintain the author's voice
- Be specific and actionable

The context will be provided with line numbers in the format: [Line N] text
The line number N is the actual 0-indexed line number in the document.

You MUST respond with valid JSON in the following format:
{
  "explanation": "Brief explanation of your reasoning (1-2 sentences)",
  "edit": [
    {"line": N, "text": "suggested replacement text"}
  ]
}

IMPORTANT: Use the EXACT line number from the [Line N] prefix in your JSON response.
- If suggesting a change: Include the line number (from [Line N]) and new text in the "edit" array
- If the line is good as-is: Return an empty "edit" array: []
- The "line" field MUST match the line number from the [Line N] prefix
- The "explanation" should always be present, even if the edit array is empty

Always respond with ONLY the JSON object, no additional text.]]

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

  -- Build the prompt with system prompt and user message
  local user_prompt = string.format("[Line %d] %s", zero_indexed_line, line_content)

  -- Create messages with system prompt
  local messages = {
    {
      role = "user",
      content = LINE_EDITOR_PROMPT .. "\n\nNow review this line:\n" .. user_prompt
    }
  }

  call_claude_api(messages, callback)
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

  local user_prompt = table.concat(line_prompts, "\n")

  -- Create messages with system prompt
  local messages = {
    {
      role = "user",
      content = LINE_EDITOR_PROMPT .. "\n\nNow review these lines:\n" .. user_prompt
    }
  }

  call_claude_api(messages, callback)
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

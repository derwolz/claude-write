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

  local user_input = string.format("[Line %d] %s", zero_indexed_line, line_content)
  local prompt = LINE_EDITOR_PROMPT .. "\n\nNow review this line:"

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
  local prompt = LINE_EDITOR_PROMPT .. "\n\nNow review these lines:"

  call_claude_cli(user_input, prompt, callback)
end

-- Copy editor system prompt: grammar and spelling only
local COPY_EDITOR_PROMPT = [[You are a copy editor reviewing a document for grammar and spelling errors ONLY.

Your role:
- Fix grammar errors (subject-verb agreement, tense, pronoun agreement, punctuation, etc.)
- Fix spelling mistakes
- Do NOT suggest stylistic rewrites, word choice changes, or restructuring for clarity
- You MAY include a brief note (2-3 sentences MAX) in the explanation if a sentence is stylistically awkward, but do NOT change it in the edit
- Preserve the author's voice and style completely

The context will be provided with line numbers in the format: [Line N] text
The line number N is the actual 0-indexed line number in the document.

You MUST respond with valid JSON in the following format:
{
  "explanation": "Brief note on what was corrected. If awkward but grammatically correct, note it here in 2-3 sentences max.",
  "edit": [
    {"line": N, "text": "corrected text with only grammar/spelling fixes applied"}
  ]
}

IMPORTANT: Use the EXACT line number from the [Line N] prefix in your JSON response.
- If there are grammar/spelling errors: Include the corrected text in the "edit" array
- If the line is grammatically correct and spelled correctly: Return an empty "edit" array: []
- Do NOT change anything that is not a grammar or spelling error
- The "explanation" should always be present, even if the edit array is empty

Always respond with ONLY the JSON object, no additional text.]]

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
  local prompt = COPY_EDITOR_PROMPT .. "\n\nNow copy-edit this line:"

  call_claude_cli(user_input, prompt, callback)
end

-- Check current line for grammar/spelling
function M.check_line(line_content, callback)
  local prompt = "Check this line for grammar, spelling, and clarity issues. Provide brief feedback:"
  call_claude_cli(line_content, prompt, callback)
end

-- Reader reaction system prompt
local READER_PROMPT = [[You are a first-time reader encountering this passage cold. React honestly as a reader.

Focus on: immediate impressions, what you understood or felt, anything that confused or pulled you in.
Keep it compact: 2-4 sentences total. Do not give writing advice.

If this passage reveals something memorable about a character, raises a strong question, or creates a notable effect worth tracking, include a brief memory note. Keep memory values under 20 words.

Respond with valid JSON only:
{
  "response": "your 2-4 sentence reader reaction",
  "memory": [{"key": "compact_key", "value": "compact note under 20 words"}]
}

The memory array may be empty [] if nothing warrants saving.
Always respond with ONLY the JSON object, no additional text.]]

-- Get a reader's reaction to a passage, with existing context
function M.reader_react(text, context_string, callback)
  local context_part = ""
  if context_string and context_string ~= "" then
    context_part = "\n\nExisting reader notes:\n" .. context_string .. "\n"
  end

  local prompt = READER_PROMPT .. context_part .. "\n\nPassage:"

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

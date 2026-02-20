-- Diff UI for displaying git-style line edits
local M = {}

-- Store current diff state
M.diff_bufnr = nil
M.diff_winnr = nil
M.current_edits = {}
M.source_bufnr = nil

-- Store reader window state
M.reader_bufnr = nil
M.reader_winnr = nil

-- Close the reader window
function M.close_reader_window()
  if M.reader_winnr and vim.api.nvim_win_is_valid(M.reader_winnr) then
    vim.api.nvim_win_close(M.reader_winnr, true)
  end
  M.reader_winnr = nil
end

-- Show reader response in a right-side window, return focus to source_win
function M.display_reader(source_win, title, response_text)
  -- Close diff window if open
  if M.diff_winnr and vim.api.nvim_win_is_valid(M.diff_winnr) then
    vim.api.nvim_win_close(M.diff_winnr, true)
    M.diff_winnr = nil
    M.current_edits = {}
  end

  -- Reuse or create reader window
  if not M.reader_winnr or not vim.api.nvim_win_is_valid(M.reader_winnr) then
    -- Focus source window before splitting so split appears on the right of it
    if source_win and vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    end
    vim.cmd("rightbelow vsplit")
    M.reader_winnr = vim.api.nvim_get_current_win()
  else
    vim.api.nvim_set_current_win(M.reader_winnr)
  end

  if not M.reader_bufnr or not vim.api.nvim_buf_is_valid(M.reader_bufnr) then
    M.reader_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M.reader_bufnr, "Claude Reader")
  end

  vim.api.nvim_win_set_buf(M.reader_winnr, M.reader_bufnr)
  vim.api.nvim_buf_set_option(M.reader_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.reader_bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(M.reader_bufnr, "swapfile", false)
  vim.api.nvim_win_set_option(M.reader_winnr, "number", false)
  vim.api.nvim_win_set_option(M.reader_winnr, "relativenumber", false)
  vim.api.nvim_win_set_option(M.reader_winnr, "wrap", true)
  vim.api.nvim_win_set_option(M.reader_winnr, "linebreak", true)

  -- Build content
  local lines = { "# " .. title, "" }
  for line in response_text:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_option(M.reader_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.reader_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.reader_bufnr, "modifiable", false)

  -- Syntax: just highlight the header
  vim.api.nvim_buf_call(M.reader_bufnr, function()
    vim.cmd("syntax clear")
    vim.cmd("syntax match ClaudeReaderHeader '^#.*'")
    vim.cmd("highlight ClaudeReaderHeader ctermfg=cyan guifg=#56b6c2")
  end)

  -- q to close
  vim.keymap.set("n", "q", function()
    M.close_reader_window()
  end, { noremap = true, silent = true, buffer = M.reader_bufnr })

  -- Return focus to source window
  if source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end
end

-- Create or show the diff window on the right side
function M.show_diff_window()
  -- Close reader window if open
  if M.reader_winnr and vim.api.nvim_win_is_valid(M.reader_winnr) then
    vim.api.nvim_win_close(M.reader_winnr, true)
    M.reader_winnr = nil
  end

  -- If diff window already exists and is valid, just focus it
  if M.diff_winnr and vim.api.nvim_win_is_valid(M.diff_winnr) then
    vim.api.nvim_set_current_win(M.diff_winnr)
    return
  end

  -- Create a vertical split on the right
  vim.cmd("rightbelow vsplit")
  M.diff_winnr = vim.api.nvim_get_current_win()

  -- Create or reuse buffer
  if not M.diff_bufnr or not vim.api.nvim_buf_is_valid(M.diff_bufnr) then
    M.diff_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M.diff_bufnr, "Claude Diff")
  end

  vim.api.nvim_win_set_buf(M.diff_winnr, M.diff_bufnr)

  -- Set buffer options
  vim.api.nvim_buf_set_option(M.diff_bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.diff_bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(M.diff_bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(M.diff_bufnr, "filetype", "claudediff")
  vim.api.nvim_buf_set_option(M.diff_bufnr, "modifiable", true)

  -- Set window options
  vim.api.nvim_win_set_option(M.diff_winnr, "number", false)
  vim.api.nvim_win_set_option(M.diff_winnr, "relativenumber", false)
  vim.api.nvim_win_set_option(M.diff_winnr, "wrap", true)
  vim.api.nvim_win_set_option(M.diff_winnr, "linebreak", true)

  -- Set up keybindings for accepting/rejecting changes
  M.setup_diff_keybindings()
end

-- Setup keybindings in the diff buffer
function M.setup_diff_keybindings()
  local opts = { noremap = true, silent = true, buffer = M.diff_bufnr }

  -- Only override specific keys, let everything else work normally

  -- A to Accept current change (apply the + line)
  vim.keymap.set("n", "A", function()
    M.accept_current_change()
  end, opts)

  -- C to Cancel/reject current change (keep original)
  vim.keymap.set("n", "C", function()
    M.reject_current_change()
  end, opts)

  -- dd to delete current line (accept the other)
  vim.keymap.set("n", "dd", function()
    M.delete_line_and_apply()
  end, opts)

  -- q to close diff window
  vim.keymap.set("n", "q", function()
    M.close_diff_window()
  end, opts)
end

-- Close the diff window
function M.close_diff_window()
  if M.diff_winnr and vim.api.nvim_win_is_valid(M.diff_winnr) then
    vim.api.nvim_win_close(M.diff_winnr, true)
  end
  M.diff_winnr = nil
  M.current_edits = {}
end

-- Parse JSON response from Claude
function M.parse_edit_response(response)
  -- Try to extract JSON from markdown code blocks
  local json_str = response:match("```json\n(.-)```") or response:match("```\n(.-)```") or response

  local ok, data = pcall(vim.json.decode, json_str)
  if not ok then
    return nil, "Failed to parse JSON response: " .. tostring(data)
  end

  if not data.explanation then
    return nil, "Missing 'explanation' field in response"
  end

  if not data.edit then
    return nil, "Missing 'edit' field in response"
  end

  return data, nil
end

-- Display diff for line edits
function M.display_diff(source_bufnr, edit_data)
  M.source_bufnr = source_bufnr
  M.current_edits = edit_data.edit

  -- Show the diff window
  M.show_diff_window()

  -- Build diff content
  local lines = {}
  table.insert(lines, "# " .. edit_data.explanation)
  table.insert(lines, "")

  if #M.current_edits == 0 then
    -- Don't open a diff window just to say nothing changed
    vim.notify(edit_data.explanation, vim.log.levels.INFO)
    M.close_diff_window()
    return
  else
    for _, edit in ipairs(M.current_edits) do
      -- Get original line from source buffer (edit.line is 0-indexed)
      local line_nr = edit.line + 1  -- Convert to 1-indexed for Neovim
      local original_lines = vim.api.nvim_buf_get_lines(source_bufnr, edit.line, line_nr, false)
      local original_text = original_lines[1] or ""

      -- Add line number header
      table.insert(lines, string.format("@@ Line %d @@", line_nr))

      -- Add diff lines with metadata
      table.insert(lines, "- " .. original_text)
      table.insert(lines, "+ " .. edit.text)
      table.insert(lines, "")
    end
  end

  -- Set content in diff buffer
  vim.api.nvim_buf_set_option(M.diff_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.diff_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.diff_bufnr, "modifiable", true)  -- Keep modifiable for deleting

  -- Apply syntax highlighting
  M.apply_diff_syntax()
end

-- Apply syntax highlighting to diff buffer
function M.apply_diff_syntax()
  if not M.diff_bufnr or not vim.api.nvim_buf_is_valid(M.diff_bufnr) then
    return
  end

  vim.api.nvim_buf_call(M.diff_bufnr, function()
    -- Clear any existing syntax
    vim.cmd("syntax clear")

    -- Define syntax matches
    vim.cmd("syntax match ClaudeDiffComment '^#.*'")
    vim.cmd("syntax match ClaudeDiffLocation '^@@.*@@'")
    vim.cmd("syntax match ClaudeDiffRemove '^-.*'")
    vim.cmd("syntax match ClaudeDiffAdd '^+.*'")

    -- Define highlights
    vim.cmd("highlight ClaudeDiffComment ctermfg=cyan guifg=#56b6c2")
    vim.cmd("highlight ClaudeDiffLocation ctermfg=yellow guifg=#e5c07b")
    vim.cmd("highlight ClaudeDiffRemove ctermfg=red guifg=#e06c75")
    vim.cmd("highlight ClaudeDiffAdd ctermfg=green guifg=#98c379")
  end)
end

-- Find the edit and line number for current cursor position
local function find_current_edit()
  if not M.diff_winnr or not vim.api.nvim_win_is_valid(M.diff_winnr) then
    return nil, nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(M.diff_winnr)
  local line_nr = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(M.diff_bufnr, 0, -1, false)

  -- Find which edit this belongs to by scanning backwards for @@ header
  local target_line_nr = nil
  for i = line_nr, 1, -1 do
    local line = lines[i]
    local match = line:match("^@@ Line (%d+) @@")
    if match then
      target_line_nr = tonumber(match)
      break
    end
  end

  if not target_line_nr then
    return nil, nil, nil
  end

  -- Find the edit for this line
  for idx, edit in ipairs(M.current_edits) do
    if edit.line + 1 == target_line_nr then
      return idx, edit, target_line_nr
    end
  end

  return nil, nil, target_line_nr
end

-- Accept current change (apply the + line)
function M.accept_current_change()
  local edit_idx, edit, target_line_nr = find_current_edit()

  if not edit_idx then
    vim.notify("No edit found at cursor position", vim.log.levels.WARN)
    return
  end

  -- Get the current + line text (in case it was edited)
  local cursor = vim.api.nvim_win_get_cursor(M.diff_winnr)
  local line_nr = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(M.diff_bufnr, 0, -1, false)

  -- Find the + line for this edit
  local plus_line_text = nil
  for i = line_nr, math.min(line_nr + 5, #lines) do
    if lines[i]:match("^%+") then
      plus_line_text = lines[i]:sub(3)  -- Remove "+ " prefix
      break
    end
  end
  for i = line_nr, math.max(line_nr - 5, 1), -1 do
    if lines[i]:match("^%+") then
      plus_line_text = lines[i]:sub(3)  -- Remove "+ " prefix
      break
    end
  end

  if not plus_line_text then
    vim.notify("Could not find + line", vim.log.levels.ERROR)
    return
  end

  -- Apply the change
  vim.api.nvim_buf_set_lines(M.source_bufnr, edit.line, edit.line + 1, false, { plus_line_text })
  vim.notify("Applied change to line " .. target_line_nr, vim.log.levels.INFO)

  -- Remove this edit and close if done
  table.remove(M.current_edits, edit_idx)
  if #M.current_edits == 0 then
    M.close_diff_window()
  else
    -- Refresh the display
    M.refresh_display()
  end
end

-- Reject current change (keep original)
function M.reject_current_change()
  local edit_idx, edit, target_line_nr = find_current_edit()

  if not edit_idx then
    vim.notify("No edit found at cursor position", vim.log.levels.WARN)
    return
  end

  vim.notify("Kept original line " .. target_line_nr, vim.log.levels.INFO)

  -- Remove this edit and close if done
  table.remove(M.current_edits, edit_idx)
  if #M.current_edits == 0 then
    M.close_diff_window()
  else
    -- Refresh the display
    M.refresh_display()
  end
end

-- Edit the suggestion (make + line editable)
function M.edit_suggestion()
  if not M.diff_winnr or not vim.api.nvim_win_is_valid(M.diff_winnr) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(M.diff_winnr)
  local line_nr = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(M.diff_bufnr, 0, -1, false)
  local current_line = lines[line_nr]

  -- Find the + line
  local plus_line_nr = nil
  if current_line:match("^%+") then
    plus_line_nr = line_nr
  else
    -- Search nearby for + line
    for i = line_nr, math.min(line_nr + 5, #lines) do
      if lines[i]:match("^%+") then
        plus_line_nr = i
        break
      end
    end
    if not plus_line_nr then
      for i = line_nr, math.max(line_nr - 5, 1), -1 do
        if lines[i]:match("^%+") then
          plus_line_nr = i
          break
        end
      end
    end
  end

  if not plus_line_nr then
    vim.notify("No + line found. Position cursor on or near the suggestion.", vim.log.levels.WARN)
    return
  end

  -- Move cursor to the + line and enter insert mode
  vim.api.nvim_win_set_cursor(M.diff_winnr, { plus_line_nr, 2 })  -- Position after "+ "
  vim.cmd("startinsert")
  vim.notify("Edit the suggestion, then press 'A' to accept", vim.log.levels.INFO)
end

-- Refresh the display after removing an edit
function M.refresh_display()
  if not M.source_bufnr or not M.diff_bufnr then
    return
  end

  -- Rebuild the display with remaining edits
  local lines = {}
  table.insert(lines, "# Review remaining changes")
  table.insert(lines, "")

  for _, edit in ipairs(M.current_edits) do
    local line_nr = edit.line + 1
    local original_lines = vim.api.nvim_buf_get_lines(M.source_bufnr, edit.line, line_nr, false)
    local original_text = original_lines[1] or ""

    table.insert(lines, string.format("@@ Line %d @@", line_nr))
    table.insert(lines, "- " .. original_text)
    table.insert(lines, "+ " .. edit.text)
    table.insert(lines, "")
  end

  vim.api.nvim_buf_set_lines(M.diff_bufnr, 0, -1, false, lines)
  M.apply_diff_syntax()
end

-- Delete current line and apply the change
function M.delete_line_and_apply()
  local cursor = vim.api.nvim_win_get_cursor(M.diff_winnr)
  local line_nr = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(M.diff_bufnr, 0, -1, false)
  local current_line = lines[line_nr]

  -- Check if it's a diff line
  if not current_line:match("^[-+]") then
    vim.notify("Not on a diff line", vim.log.levels.WARN)
    return
  end

  -- Find the corresponding edit
  local is_remove = current_line:match("^-")
  local is_add = current_line:match("^%+")

  -- Find which edit this belongs to by scanning backwards for @@ header
  local edit_idx = nil
  local target_line_nr = nil
  for i = line_nr, 1, -1 do
    local line = lines[i]
    local match = line:match("^@@ Line (%d+) @@")
    if match then
      target_line_nr = tonumber(match)
      break
    end
  end

  if not target_line_nr then
    vim.notify("Could not find line number for this diff", vim.log.levels.ERROR)
    return
  end

  -- Find the edit for this line
  for idx, edit in ipairs(M.current_edits) do
    if edit.line + 1 == target_line_nr then
      edit_idx = idx
      break
    end
  end

  if not edit_idx then
    vim.notify("Could not find edit for line " .. target_line_nr, vim.log.levels.ERROR)
    return
  end

  local edit = M.current_edits[edit_idx]

  -- Apply the change based on which line was deleted
  if is_remove then
    -- User deleted the "-" line, so accept the "+" change
    vim.api.nvim_buf_set_lines(M.source_bufnr, edit.line, edit.line + 1, false, { edit.text })
    vim.notify("Applied change to line " .. target_line_nr, vim.log.levels.INFO)
  elseif is_add then
    -- User deleted the "+" line, so keep the original (do nothing)
    vim.notify("Kept original line " .. target_line_nr, vim.log.levels.INFO)
  end

  -- Remove this edit from display
  table.remove(M.current_edits, edit_idx)

  -- Remove the diff section from display (header + both lines + empty line)
  for i = line_nr + 2, line_nr, -1 do
    if i <= #lines then
      table.remove(lines, i)
    end
  end
  -- Remove the header line
  for i = line_nr - 1, 1, -1 do
    if lines[i]:match("^@@") then
      table.remove(lines, i)
      break
    end
  end

  -- Update display
  vim.api.nvim_buf_set_lines(M.diff_bufnr, 0, -1, false, lines)

  -- Close window if no more edits
  if #M.current_edits == 0 then
    vim.notify("All changes processed!", vim.log.levels.INFO)
    M.close_diff_window()
  end
end

-- Accept all changes (apply all edits)
function M.accept_all_changes()
  for _, edit in ipairs(M.current_edits) do
    vim.api.nvim_buf_set_lines(M.source_bufnr, edit.line, edit.line + 1, false, { edit.text })
  end
  vim.notify("Applied all changes", vim.log.levels.INFO)
  M.close_diff_window()
end

-- Reject all changes (keep original)
function M.reject_all_changes()
  vim.notify("Rejected all changes", vim.log.levels.INFO)
  M.close_diff_window()
end

return M

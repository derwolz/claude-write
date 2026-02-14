-- Diff UI for displaying git-style line edits
local M = {}

-- Store current diff state
M.diff_bufnr = nil
M.diff_winnr = nil
M.current_edits = {}
M.source_bufnr = nil

-- Create or show the diff window on the right side
function M.show_diff_window()
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
  vim.api.nvim_win_set_option(M.diff_winnr, "wrap", false)

  -- Set up keybindings for accepting/rejecting changes
  M.setup_diff_keybindings()
end

-- Setup keybindings in the diff buffer
function M.setup_diff_keybindings()
  local opts = { noremap = true, silent = true, buffer = M.diff_bufnr }

  -- dd to delete current line (accept the other)
  vim.keymap.set("n", "dd", function()
    M.delete_line_and_apply()
  end, opts)

  -- q to close diff window
  vim.keymap.set("n", "q", function()
    M.close_diff_window()
  end, opts)

  -- a to accept all changes
  vim.keymap.set("n", "a", function()
    M.accept_all_changes()
  end, opts)

  -- r to reject all changes
  vim.keymap.set("n", "r", function()
    M.reject_all_changes()
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
    table.insert(lines, "No changes suggested - line is good as-is!")
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

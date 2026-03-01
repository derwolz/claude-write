-- Configuration for claude-write
local M = {}

M.defaults = {
  -- Directory for cloned repos and cache
  cache_dir = vim.fn.stdpath("cache") .. "/claude-write",

  -- Memory file for persistent context
  memory_file = vim.fn.stdpath("cache") .. "/claude-write/memory.json",

  -- Chapter summaries folder
  chapter_dir = nil,

  -- Default git branch to checkout
  default_branch = "main",

  -- Keybindings
  keymaps = {
    reader = "<leader>cr",        -- Load into memory
    copy_check = "<leader>cc",    -- Copy-edit current line (grammar/spelling diff)
    line_edit = "<leader>cl",     -- Edit current line with diff view
    reader_check = "<leader>cs",  -- Reader reaction to current line/selection
    git_browse = "<leader>cg",    -- Browse git repo
    clear_memory = "<leader>cR",  -- Clear memory (capital R)
    load_chapter = "<leader>cC",  -- Load chapters up to N
    write_config = "<leader>cG",  -- Configure chapter directory
  },

  -- UI settings
  ui = {
    border = "rounded",
    width = 0.8,  -- 80% of screen width
    height = 0.8, -- 80% of screen height
  },

  -- Claude session settings
  session = {
    timeout = 300000, -- 5 minutes in milliseconds
    max_retries = 3,
  },

  -- System prompts (override to customize behavior)
  prompts = {
    line_editor = [[You are a line editor reviewing a document for stylistic improvements.

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

Always respond with ONLY the JSON object, no additional text.]],

    copy_editor = [[You are a copy editor reviewing a document for grammar and spelling errors ONLY.

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

Always respond with ONLY the JSON object, no additional text.]],

    reader = [[You are a first-time reader encountering this passage cold. React honestly as a reader.

Focus on: immediate impressions, what you understood or felt, anything that confused or pulled you in.
Keep it compact: 2-4 sentences total. Do not give writing advice.

If this passage reveals something memorable about a character, raises a strong question, or creates a notable effect worth tracking, include a brief memory note. Keep memory values under 20 words.

Respond with valid JSON only:
{
  "response": "your 2-4 sentence reader reaction",
  "memory": [{"key": "compact_key", "value": "compact note under 20 words"}]
}

The memory array may be empty [] if nothing warrants saving.
Always respond with ONLY the JSON object, no additional text.]],
  },
}

-- Initialize options with defaults
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Ensure cache directory exists
  vim.fn.mkdir(M.options.cache_dir, "p")

  return M.options
end

return M

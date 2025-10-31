# Claude Code Hook Interface Specification

This document defines the standard interface that all hook scripts in this repository must follow.

## Usage Modes

Scripts support two modes:

1. **Hook mode** - Receives JSON via STDIN from Claude Code
2. **Direct invocation** - Receives file paths as command-line arguments (for testing)

## Input Format

### Hook Mode (STDIN)

When called as a Claude Code hook, scripts receive JSON on STDIN with the following structure:

```json
{
  "inputs": {
    "file_path": "path/to/file.rb"
  },
  "response": {
    "filePath": "path/to/file.rb"
  }
}
```

Scripts should extract the file path from either `inputs.file_path` or `response.filePath`.

### Direct Invocation

```bash
script_name [-v|--verbose] [file1 file2 ...]
```

## Exit Codes

Scripts must follow this exit code convention:

- **Exit 0** - Success
  - stdout shown to user in transcript mode (Ctrl-O)
  - Use for: clean code or auto-corrected issues

- **Exit 2** - Blocking error
  - stderr fed back to Claude immediately for automatic processing
  - Use for: issues requiring manual fixes

- **Other exit codes** - Non-blocking error
  - stderr shown to user only, execution continues
  - Use for: configuration issues, missing dependencies

## Output Format

All scripts follow a consistent 4-tier output pattern:

```
tool: N/A          # No files provided (gray)
tool: ✓            # Clean code (green)
[output]           # Auto-corrections made (green ✓)
tool: ✓
[output]           # Manual fixes needed (red ✗, exit 2)
tool: ✗
```

## File Filtering

Scripts should:
- Check file extensions via regex in hook mode
- Only process files relevant to their tool (e.g., `.rb` for RuboCop, `.css/.scss` for Stylelint)
- Output `tool: N/A` for irrelevant files

## Reference Implementation

See `scripts/PostToolUse/rubocop_changed_files` for a complete reference implementation.

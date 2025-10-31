# Claude Code Hook Scripts

Linter hook scripts for Claude Code that provide consistent output and
automatic fixing and provide the LLM with non-blocking feedback.

## Scripts

All PostToolUse hook scripts are in the `scripts/PostToolUse/` directory:

- **rubocop_changed_files** - RuboCop with auto-correction
- **haml_check_changed_files** - HAML syntax validation
- **eslint_changed_files** - ESLint with auto-fix
- **prettier_changed_files** - Prettier formatting
- **stylelint_changed_files** - Stylelint with auto-fix

## Using

To use in your project, add the following to your Claude Code configuration:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/PostToolUse/rubocop_changed_files"
          },
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/PostToolUse/typescript_check_changed_files"
          }
        ]
      }
    ]
  }
}
```

This should go in `./claude/settings.local.json`.

Note: you'll have to restart claude code for changes to take effect. Typically I `/exit` and then restart with `claude -c` and state that I restarted.


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

See `docs/output_examples.md` for detailed examples.

## Usage

Scripts are called by Claude Code with explicit file arguments:

```bash
# Called by Claude Code
./scripts/PostToolUse/rubocop_changed_files app/models/user.rb app/services/processor.rb

# Verbose mode
./scripts/PostToolUse/rubocop_changed_files --verbose app/models/user.rb
```

**Note:** These scripts do NOT auto-detect files via git. Claude Code passes files explicitly as arguments.

## Testing

All scripts have comprehensive test coverage using bats-core.

```bash
cd tests
./run-tests
```

See `tests/README.md` for full testing documentation.

## Debugging

Debug helper scripts are in the `scripts/debug/` directory:

- `log_hook_params` - Logs all parameters passed to hooks
- `log_tool_name` - Logs tool name for debugging

## Claude Code Hook System

### Hook Interface

All scripts conform to the Claude Code hook interface specification.

**See [docs/hook_interface.md](docs/hook_interface.md) for complete details on:**
- Input formats (JSON STDIN and command-line args)
- Exit code behavior
- Output format conventions
- File filtering

### Hook Locations

When setting up hooks, you have three options:

1. **Project settings (local)** - Saved in `.claude/settings.local.json` (gitignored)
2. **Project settings** - Checked in at `.claude/settings.json` (shared with team)
3. **User settings** - Saved in `~/.claude/settings.json` (global to your machine)

## Design Philosophy

These scripts are designed for **Claude Code hooks**, not git hooks:
- Claude Code passes files explicitly as arguments
- No git auto-detection
- Consistent output format across all linters
- Auto-fix when possible, clear errors when not

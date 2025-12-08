# Claude Code Hook Scripts

Linter hook scripts for Claude Code that provide consistent output and
automatic fixing and provide the LLM with non-blocking feedback.

## Design principles

I had the following design principles:

 - Comply with the Claude Code hook interface specification
 - Make it modular: easily add and configure linters for different projects
 - Provide minimal output to save tokens
 - Auto-fix issues when possible, and provide that output to the LLM to reduce future churn
 - Output errors when not auto-correctable, so that the LLM can fix
 - Use plain `bash` for maximum compatibility and minimal setup
   - Tested with [`bats-core`](https://github.com/bats-core/bats-core)

## Scripts

### PostToolUse

All PostToolUse hook scripts are in the `scripts/PostToolUse/` directory:

- **rubocop_changed_files** - RuboCop with auto-correction
- **haml_check_changed_files** - HAML syntax validation
- **eslint_changed_files** - ESLint with auto-fix
- **prettier_changed_files** - Prettier formatting
- **stylelint_changed_files** - Stylelint with auto-fix

### SessionStart

SessionStart hook scripts are in the `scripts/SessionStart/` directory:

- **nvm_setup** - Load nvm and set Node version from `.nvmrc`

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

This should go in `./claude/settings.local.json` (see below for possible hook locations).

### SessionStart Hooks

SessionStart hooks run once when Claude Code starts a session. They're useful for setting up the environment:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/SessionStart/nvm_setup"
          }
        ]
      }
    ]
  }
}
```

#### Persisting Environment Variables

SessionStart hooks have special support for persisting environment variables via `CLAUDE_ENV_FILE`. Any variables written to this file are automatically sourced in all subsequent bash commands during the session.

This is essential for tools like nvm that modify the environment—without persistence, PostToolUse hooks (like eslint) would use the system Node version instead of the project's `.nvmrc` version.

Example from `nvm_setup`:

```bash
# Persist key environment variables to CLAUDE_ENV_FILE
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export PATH=\"$PATH\"" >> "$CLAUDE_ENV_FILE"
  echo "export NVM_DIR=\"$NVM_DIR\"" >> "$CLAUDE_ENV_FILE"
fi
```

See [Claude Code hooks documentation](https://code.claude.com/docs/en/hooks#persisting-environment-variables) for more details.

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

Typically, local project settings are best for hook scripts, as they can vary per project and most likely won't be shared.

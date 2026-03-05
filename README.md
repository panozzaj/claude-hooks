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

### PreToolUse

PreToolUse hook scripts run before tool execution. Located in `scripts/PreToolUse/`:

- **jj_snapshot** - Snapshots jj working copy before Bash/Edit/Write operations for recovery

### PostToolUse

All PostToolUse hook scripts are in the `scripts/PostToolUse/` directory:

- **cargo_clippy_changed_files** - Cargo clippy with auto-fix
- **cargo_fmt_changed_files** - Cargo fmt formatting
- **css_class_check_changed_files** - CSS class validation for HAML/ERB templates
- **eslint_changed_files** - ESLint with auto-fix
- **gofmt_changed_files** - Go formatting
- **haml_check_changed_files** - HAML syntax validation
- **mypy_check_changed_files** - mypy type checking for Python
- **prettier_changed_files** - Prettier formatting
- **rubocop_changed_files** - RuboCop with auto-correction
- **ruff_check_changed_files** - Ruff linting with auto-fix for Python
- **ruff_format_changed_files** - Ruff formatting for Python
- **shellcheck_changed_files** - ShellCheck for shell scripts
- **stylelint_changed_files** - Stylelint with auto-fix
- **typescript_check_changed_files** - TypeScript type checking

### Stop

> [!WARNING]
> Stop hooks are still being refined. Expect rough edges — prompts, classification accuracy, and edge case handling are actively being improved.

Stop hook scripts fire after Claude finishes responding. They can block Claude from stopping and force it to keep working. Located in `scripts/Stop/`:

- **stop_diy_check** - Detects when Claude tells the user to do something the agent could do itself (run commands, restart servers, etc.) and blocks, asking Claude to do it instead
- **stop_auto_commit** - Detects uncommitted git changes that look ready to commit and blocks, asking Claude to review and commit them
- **stop_missing_tests** - Detects when source files are changed without any test files being modified and blocks, asking Claude to add tests. No LLM needed - pure git diff analysis.
- **stop_stale_build** - Checks if build artifacts are stale (source files newer than artifact mtime) and blocks, asking Claude to rebuild. Takes artifact path(s) as command-line arguments. No LLM needed - pure timestamp comparison.

`stop_diy_check` and `stop_auto_commit` use a local LLM (via `llm` CLI backed by ollama) for classification and degrade gracefully if the LLM is unavailable. `stop_stale_build` uses only `find -newer` and has no dependencies beyond `jq`.

### Shared Helpers

- **scripts/common/llm_classify** - Wraps the `llm` CLI for fast YES/NO classification. Uses `gemma3:4b` by default (overridable via `LLM_CLASSIFY_MODEL` env var). Passes `--no-log` and `-o temperature 0` for deterministic output with a 30-second timeout. Requires `llm` CLI (`pip install llm`) and an ollama model (`ollama pull gemma3:4b`).
- **scripts/common/cooldown** - Per-session cooldown to prevent Stop hooks from blocking repeatedly. Default 5-minute cooldown, configurable via `STOP_HOOK_COOLDOWN` env var.
- **scripts/common/say_with_project** - Uses macOS `say` to announce a message with the project name appended (e.g., "check my-project").

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

### PreToolUse Hooks

PreToolUse hooks run before tool execution. They're useful for capturing state before potentially destructive operations:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/PreToolUse/jj_snapshot"
          }
        ]
      }
    ]
  }
}
```

The `jj_snapshot` hook triggers a jj snapshot before file changes, allowing recovery via `jj evolog` if something goes wrong. It exits silently if jj isn't installed or the directory isn't a jj repo. See [Making snapshots automatic](https://www.panozzaj.com/blog/2025/11/22/avoid-losing-work-with-jujutsu-jj-for-ai-coding-agents/#making-snapshots-automatic) for background on this approach.

### Stop Hooks

Stop hooks fire after Claude finishes responding. They can block Claude from stopping by outputting `{"decision": "block", "reason": "..."}`. They receive JSON on stdin with `stop_hook_active` (must check to avoid infinite loops), `transcript_path`, `cwd`, and other fields.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/Stop/stop_diy_check"
          },
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/Stop/stop_auto_commit"
          },
          {
            "type": "command",
            "command": "/path/to/claude-hooks/scripts/Stop/stop_stale_build dist/bundle.js tmp/pids/server.pid"
          }
        ]
      }
    ]
  }
}
```

**Prerequisites:** `stop_diy_check` and `stop_auto_commit` require `jq`, the `llm` CLI tool, and an ollama model (default: `gemma3:4b`). `stop_stale_build` requires only `jq`. Install with:

```bash
brew install jq
pip install llm          # for stop_diy_check, stop_auto_commit
ollama pull gemma3:4b    # for stop_diy_check, stop_auto_commit
```

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

Note: you'll have to restart Claude Code for changes to take effect. You can use a [reload command](https://panozzaj.com/blog/2026/02/07/building-a-reload-command-for-claude-code/) to restart without losing session context.

## Optional daemon tools

Some hooks automatically use daemon/server versions of linters when available, falling back to cold invocations if not installed. These eliminate startup overhead and make hooks significantly faster:

| Hook     | Daemon tool                                        | Install                            | Speedup        |
| -------- | -------------------------------------------------- | ---------------------------------- | -------------- |
| rubocop  | `rubocop --server` (built-in)                      | Already included in RuboCop 1.31+  | ~1.0s → ~0.2s  |
| eslint   | [eslint_d](https://github.com/mantoni/eslint_d.js) | `npm install -g eslint_d`          | ~0.7s → ~0.06s |
| prettier | [prettierd](https://github.com/fsouza/prettierd)   | `npm install -g @fsouza/prettierd` | ~0.3s → ~0.04s |

Each can be disabled per-project by touching a file in `./tmp/` (e.g. `./tmp/no-eslint-d`, `./tmp/no-prettierd`) or via environment variables (`NO_RUBOCOP_SERVER`, `NO_ESLINT_D`, `NO_PRETTIERD`).

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
- `log_lifecycle_event` - Logs lifecycle events (hook name, tool, agent type) to file and stdout
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

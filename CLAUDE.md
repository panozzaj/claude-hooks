# Instructions for Claude

See README.md for full documentation on the hook scripts, usage, and Claude Code hook system.

## Design Principles

### Informative Feedback to LLM

When auto-fixes are applied, scripts should provide detailed feedback about what was changed so the LLM can learn from corrections.

**Gold standard: RuboCop**
- Shows specific errors with line numbers
- Indicates which offenses were `[Corrected]`
- Automatically fixes what it can
- Shows errors for unfixable issues

All scripts should strive to:
1. Show what was wrong (specific errors/warnings with line numbers)
2. Indicate what was auto-fixed
3. Report unfixable issues with clear error messages
4. Provide enough context for the LLM to learn from the corrections

## Directory Structure

This is a local development repository. Hook scripts are in the `scripts/` directory.

```
claude-hooks/                           # This repository (local dev)
├── README.md                           # Main documentation
├── CLAUDE.md                           # This file - instructions for Claude
├── docs/                               # Documentation
│   ├── hook_interface.md               # Hook interface specification
│   └── output_examples.md              # Visual output examples
├── scripts/                            # Hook scripts
│   ├── PreToolUse/                     # PreToolUse hook scripts
│   │   └── jj_snapshot                # Snapshot jj working copy before changes
│   ├── PostToolUse/                    # PostToolUse hook scripts
│   │   ├── cargo_clippy_changed_files
│   │   ├── cargo_fmt_changed_files
│   │   ├── eslint_changed_files
│   │   ├── gofmt_changed_files
│   │   ├── haml_check_changed_files
│   │   ├── mypy_check_changed_files
│   │   ├── prettier_changed_files
│   │   ├── rubocop_changed_files
│   │   ├── ruff_check_changed_files
│   │   ├── ruff_format_changed_files
│   │   ├── shellcheck_changed_files
│   │   ├── stylelint_changed_files
│   │   └── typescript_check_changed_files
│   ├── Stop/                           # Stop hook scripts
│   │   ├── stop_auto_commit           # Blocks when git has uncommitted changes
│   │   ├── stop_diy_check             # Blocks when Claude tells user to DIY
│   │   ├── stop_missing_tests         # Blocks when source changed without tests
│   │   └── stop_stale_build           # Blocks when build artifacts are stale
│   ├── common/                         # Shared helpers
│   │   ├── cooldown                   # Per-session cooldown to prevent repeat blocks
│   │   ├── jj_snapshot                # jj snapshot helper
│   │   ├── llm_classify               # YES/NO classification via local LLM
│   │   └── say_with_project           # macOS say with project name
│   ├── SessionStart/                   # SessionStart hook scripts
│   │   └── nvm_setup                  # Load nvm and set Node version
│   └── debug/                          # Debug utilities
│       ├── log_hook_params
│       ├── log_lifecycle_event
│       └── log_tool_name
└── tests/                              # Test suite
    ├── run-tests                       # Unit test runner (fast, mocked)
    ├── run-evals                       # Eval runner (slow, real LLM)
    ├── README.md                       # Testing docs
    ├── test_helper.bash                # Test utilities
    ├── *.bats                          # Unit test files
    ├── evals/                          # LLM eval tests
    │   └── stop_diy_check_eval.bats   # Prompt quality evals
    └── fixtures/                       # Test data
```

Users reference these scripts with absolute paths in their Claude Code settings (e.g., `.claude/settings.local.json`).

## Testing

Unit tests (fast, mocked LLM):

```bash
./tests/run-tests 2>&1 | tee ./tmp/test-output.txt
```

Eval tests (slow, requires ollama with gemma3:4b):

```bash
./tests/run-evals 2>&1 | tee ./tmp/eval-output.txt
```

Evals test LLM prompt quality against real examples. Run evals after changing any LLM system prompt.

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
│   ├── PostToolUse/                    # PostToolUse hook scripts
│   │   ├── rubocop_changed_files
│   │   ├── haml_check_changed_files
│   │   ├── eslint_changed_files
│   │   ├── prettier_changed_files
│   │   ├── stylelint_changed_files
│   │   └── typescript_check_changed_files
│   └── debug/                          # Debug utilities
│       ├── log_hook_params
│       └── log_tool_name
└── tests/                              # Test suite
    ├── run-tests                       # Test runner
    ├── README.md                       # Testing docs
    ├── test_helper.bash                # Test utilities
    ├── *.bats                          # Test files
    └── fixtures/                       # Test data
```

Users reference these scripts with absolute paths in their Claude Code settings (e.g., `.claude/settings.local.json`).

## Testing

To run tests, use the script and `tee` to avoid hanging:

```bash
./tests/run-tests 2>&1 | tee ./tmp/test-output.txt
```

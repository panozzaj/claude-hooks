# Testing for Claude Code Hook Scripts

This directory contains automated tests for the Claude Code hook scripts using [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Test Coverage

All linter hook scripts are fully tested. Each script is tested for:

- **N/A Output** - Shows `tool: N/A` when called with no file arguments
- **Clean Code** - Shows `tool: ✓` when code is compliant
- **Auto-Corrections** - Shows output + `tool: ✓` when issues auto-fixed
- **Manual Fixes** - Shows output + `tool: ✗` (exit 2) when manual fixes needed
- **Verbose Mode** - Shows file info with `--verbose` flag
- **Multiple Files** - Handles multiple files passed as arguments
- **Tool Flags** - Passes correct flags to underlying tools
- **Special Cases** - Tool-specific behaviors (multi-type files, exclusions, file filtering)

### Test Quality

- **Fast:** Runs in seconds
- **Reliable:** No flaky tests, deterministic results
- **No git dependencies:** Tests work without git setup
- **Readable:** Clear test names and inline documentation
- **Maintainable:** Shared fixtures and helper functions
- **Comprehensive:** All code paths and edge cases covered

## Prerequisites

Install bats-core via Homebrew:

```bash
brew install bats-core
```

## Running Tests

### Run all tests:

```bash
# Using the test runner script
cd ~/.claude/scripts/tests
./run-tests

# Or using bats directly
cd ~/.claude/scripts/tests
bats *.bats
```

### Run tests for a specific script:

```bash
cd ~/.claude/scripts/tests
bats rubocop_changed_files.bats
bats haml_check_changed_files.bats
bats eslint_changed_files.bats
bats prettier_changed_files.bats
bats stylelint_changed_files.bats
```

### Run with verbose output:

```bash
cd ~/.claude/scripts/tests
bats --verbose-run rubocop_changed_files.bats
```

### Run a specific test:

```bash
cd ~/.claude/scripts/tests
bats --filter "shows only green check" rubocop_changed_files.bats
```

## Test Structure

### Test Fixtures

`tests/fixtures/` contains sample output from linters:

**RuboCop:**
- `rubocop_success_no_offenses.txt` - Clean RuboCop run
- `rubocop_success_with_corrections.txt` - Auto-corrected issues
- `rubocop_failure_uncorrectable.txt` - Manual fixes needed

**HAML:**
- `haml_success.txt` - Valid HAML
- `haml_failure.txt` - HAML syntax errors

**ESLint:**
- `eslint_success_no_warnings.txt` - Clean ESLint run
- `eslint_success_with_fixes.txt` - Auto-fixed issues
- `eslint_failure_unfixable.txt` - Manual fixes needed

**Prettier:**
- `prettier_success_no_changes.txt` - No formatting needed
- `prettier_success_with_formatting.txt` - Files formatted
- `prettier_failure.txt` - Syntax errors

**Stylelint:**
- `stylelint_success_no_warnings.txt` - Clean Stylelint run
- `stylelint_success_with_fixes.txt` - Auto-fixed issues
- `stylelint_failure_unfixable.txt` - Manual fixes needed

### Test Helpers

`tests/test_helper.bash` provides utilities:
- `setup_test_repo()` - Creates isolated git repository
- `teardown_test_repo()` - Cleans up after tests
- `create_changed_file()` - Creates git-tracked modified files
- `strip_colors()` - Removes ANSI color codes for assertions

### Mocking Strategy

Tests use PATH manipulation to inject mock commands:
1. Create temporary directory for each test
2. Add executable mock scripts
3. Prepend mock directory to PATH
4. Mock commands return fixtures and exit codes

**Important:** Tests do NOT use git. Claude Code passes files explicitly as arguments, so tests create files directly without git commits.

This approach:
- ✓ No filesystem side effects outside temp dirs
- ✓ No dependency on real linters
- ✓ No dependency on git
- ✓ Fully isolated test environment
- ✓ Fast execution

## What's Being Tested

Each script is tested for:

1. **No arguments** - Shows `tool: N/A` when called with no file arguments
2. **Success (no changes)** - Shows only green check when files are compliant
3. **Success (with corrections)** - Shows output + green check when auto-fixed
4. **Failure (uncorrectable)** - Exits 2 with errors shown to LLM
5. **Verbose mode** - Shows detailed file info
6. **Multiple files** - Handles multiple files passed as arguments
7. **Tool flags** - Passes correct flags to underlying linters
8. **Special cases** - Tool-specific behaviors (multi-type files, exclusions, etc.)

### Special Test Cases by Script

**RuboCop:**
- ✓ Passes `--force-exclusion` flag (respects `.rubocop.yml` exclusions)
- ✓ Detects auto-corrections via "corrected" keyword in output

**HAML:**
- ✓ Skips non-existent files with warning (verbose mode)
- ✓ Finds `check_haml_syntax` in multiple locations
- ✓ Filters files to ensure they exist before checking

**ESLint:**
- ✓ Works with both `./bin/eslint` and `yarn eslint`
- ✓ Detects errors/warnings via regex patterns

**Prettier:**
- ✓ Formats multiple file types (js, css, json, yml, md)
- ✓ Detects formatting changes via non-empty output

**Stylelint:**
- ✓ Handles both `.css` and `.scss` files
- ✓ Works with both `./bin/stylelint` and `yarn stylelint`

## Expected Behavior

The scripts follow a four-tier output strategy:

### Tier 0: No files to check (exit 0)
```
rubocop: N/A
```
Output: Gray "N/A" when no files of the relevant type are changed

### Tier 1: No changes needed (exit 0)
```
rubocop: ✓
```
Output: Green check when files are compliant

### Tier 2: Auto-corrections applied (exit 0)
```
Inspecting 2 files
CC

Offenses:
...

rubocop: ✓
```
Output: Full linter output + green check (for LLM feedback)

### Tier 3: Manual fixes required (exit 2, stderr)
```
Inspecting 2 files
.C

Offenses:
app/models/user.rb:15:7: C: Metrics/MethodLength: ...

rubocop: ✗
```
Output: Full linter output + red X to stderr (blocks execution)

## Adding New Tests

To test a new script:

1. Create fixture files in `tests/fixtures/`
2. Create a new `.bats` file following existing patterns
3. Implement mocks for the tool commands
4. Test all three output tiers (clean, auto-fixed, errors)
5. Run tests: `bats tests/your-new-test.bats`

## Continuous Integration

These tests can be integrated into CI/CD:

```bash
# In your CI script
brew install bats-core
cd ~/.claude/scripts
bats tests/*.bats
```

## Troubleshooting

### Tests fail with "command not found"

Check that mocks are being created in `$MOCK_DIR` and that PATH is set correctly in setup.

### Tests modify real files

Tests should use `setup_test_repo()` to create isolated temporary directories. Check that `cd "$TEST_REPO"` is happening before file operations.

### Fixtures not found

Fixture paths use absolute paths like `$HOME/.claude/scripts/tests/fixtures/`. Ensure fixtures exist at these locations.

## Contributing

When modifying the hook scripts:

1. Run tests before committing: `bats tests/*.bats`
2. Update tests if behavior changes
3. Add new tests for new functionality
4. Ensure all tests pass

## Resources

- [bats-core documentation](https://bats-core.readthedocs.io/)
- [Bash testing best practices](https://github.com/bats-core/bats-core#writing-tests)

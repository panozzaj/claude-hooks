# Hook Script Output Examples

This document shows the actual output you'll see from the linter hook scripts in different scenarios.

## Output Format Summary

All scripts follow a consistent four-tier output pattern:

| Scenario | Output | Exit Code | Color |
|----------|--------|-----------|-------|
| No relevant files | `toolname: N/A` | 0 | Gray |
| All clean | `toolname: ✓` | 0 | Green |
| Auto-fixed | `[linter output]`<br>`toolname: ✓` | 0 | Green |
| Manual fixes needed | `[linter output]`<br>`toolname: ✗` | 2 | Red |

## Example Outputs

### Scenario 1: No Relevant Files Changed

When you modify a `.txt` file but the hook checks for `.rb` files:

```
rubocop: N/A
haml: N/A
eslint: N/A
prettier: N/A
stylelint: N/A
```

**Result:** All hooks exit cleanly, no linters run.

---

### Scenario 2: Clean Code (No Issues)

When your code is already compliant:

```
rubocop: ✓
haml: ✓
eslint: ✓
```

**Result:** Quiet success, execution continues.

---

### Scenario 3: Auto-Corrected Issues

When linters fix issues automatically:

**RuboCop:**
```
Inspecting 2 files
CC

Offenses:

app/models/user.rb:5:1: C: [Corrected] Layout/TrailingWhitespace: Trailing whitespace detected.
app/models/user.rb:10:3: C: [Corrected] Style/StringLiterals: Prefer single-quoted strings.

2 files inspected, 2 offenses detected, 2 offenses corrected

rubocop: ✓
```

**ESLint:**
```
/path/to/app.js
  5:1  error  Expected indentation of 2 spaces but found 4  indent

✖ 1 problem (1 error, 0 warnings)
  1 error and 0 warnings potentially fixable with the `--fix` option.

eslint: ✓
```

**Result:** Files are modified, output shown for LLM awareness, execution continues.

---

### Scenario 4: Manual Fixes Required

When issues can't be auto-corrected:

**RuboCop:**
```
Inspecting 2 files
.C

Offenses:

app/models/user.rb:15:7: C: Metrics/MethodLength: Method has too many lines. [12/10]
  def process_data
  ^^^^^^^^^^^^^^^

2 files inspected, 1 offense detected

rubocop: ✗
```

**ESLint:**
```
/path/to/app.js
  10:5  error  'unusedVar' is assigned a value but never used  no-unused-vars

✖ 1 problem (1 error, 0 warnings)

eslint: ✗
```

**HAML:**
```
Syntax error in app/views/users/show.html.haml:
  Illegal nesting: nesting within plain text is illegal.

haml: ✗
```

**Result:** Execution blocked (exit 2), Claude sees the errors and can fix them.

---

## Combined Output Example

When editing multiple file types at once:

```
rubocop: ✓
haml: N/A
eslint: ✓
prettier: ✓
stylelint: N/A
```

This tells you:
- Ruby files: clean ✓
- HAML files: none changed (N/A)
- JavaScript: clean ✓
- Formattable files: clean ✓
- CSS/SCSS: none changed (N/A)

---

## Verbose Mode

Add `--verbose` flag for detailed file detection:

```
Changed Ruby files detected:
  app/models/user.rb
  app/services/processor.rb

Running RuboCop with auto-correct (--force-exclusion respects .rubocop.yml exclusions)...

Inspecting 2 files
..

2 files inspected, no offenses detected

rubocop: ✓
```

**Use case:** Debugging why a file isn't being checked.

---

## Color Reference

- **Green ✓** - Success (clean or auto-fixed)
- **Red ✗** - Failure (manual fixes needed)
- **Gray N/A** - Not applicable (no files to check)
- **Yellow** - Warning messages (only in verbose mode)

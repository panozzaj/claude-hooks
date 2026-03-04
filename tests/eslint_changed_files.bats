#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/eslint_changed_files"

  # Disable eslint_d so tests use the mock eslint
  export NO_ESLINT_D=1

  # Create mock eslint command in node_modules/.bin (where the script looks first)
  MOCK_DIR="$TEST_REPO/node_modules/.bin"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock eslint
create_eslint_mock() {
  local exit_code=$1
  local output_file=$2

  # Create the actual eslint mock in node_modules/.bin
  cat > "$MOCK_DIR/eslint" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/eslint"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "eslint: N/A" ]]
}

@test "shows only green check when no warnings or errors" {
  # Create JS file
  mkdir -p app/javascript/controllers
  echo "console.log('test');" > "app/javascript/controllers/user_controller.js"

  # Mock eslint to return success with no output
  create_eslint_mock 0 "$HOME/.claude/scripts/tests/fixtures/eslint_success_no_warnings.txt"

  run "$SCRIPT_PATH" app/javascript/controllers/user_controller.js

  [ "$status" -eq 0 ]

  # Should only show the green check
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "eslint: ✓" ]]
}

@test "shows output and green check when auto-fixes applied" {
  # Create JS file
  mkdir -p app/javascript/controllers
  echo "console.log('test');" > "app/javascript/controllers/user_controller.js"

  # Mock eslint to return success with fix messages
  create_eslint_mock 0 "$HOME/.claude/scripts/tests/fixtures/eslint_success_with_fixes.txt"

  run "$SCRIPT_PATH" app/javascript/controllers/user_controller.js

  [ "$status" -eq 0 ]

  # Should show the output since fixes were made
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "error" ]]
  [[ "$output_stripped" =~ "eslint: ✓" ]]
}

@test "exits 2 and shows output when unfixable errors found" {
  # Create JS file
  mkdir -p app/javascript/controllers
  echo "console.log('test');" > "app/javascript/controllers/user_controller.js"

  # Mock eslint to return failure
  create_eslint_mock 1 "$HOME/.claude/scripts/tests/fixtures/eslint_failure_unfixable.txt"

  run "$SCRIPT_PATH" app/javascript/controllers/user_controller.js

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "no-unused-vars" ]]
  [[ "$output_stripped" =~ "eslint: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create JS file
  mkdir -p app/javascript/controllers
  echo "console.log('test');" > "app/javascript/controllers/user_controller.js"

  # Mock eslint to return success
  create_eslint_mock 0 "$HOME/.claude/scripts/tests/fixtures/eslint_success_no_warnings.txt"

  run "$SCRIPT_PATH" --verbose app/javascript/controllers/user_controller.js

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed JavaScript files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple JS files
  echo "console.log('user');" > "user.js"
  echo "console.log('post');" > "post.js"

  # Mock eslint to return success
  create_eslint_mock 0 "$HOME/.claude/scripts/tests/fixtures/eslint_success_no_warnings.txt"

  run "$SCRIPT_PATH" user.js post.js

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "eslint: ✓" ]]
}

@test "passes --fix flag to eslint" {
  # Create JS file
  mkdir -p app/javascript/controllers
  echo "console.log('test');" > "app/javascript/controllers/user_controller.js"

  # Create a mock that records arguments
  cat > "$MOCK_DIR/eslint" << 'EOF'
#!/bin/bash
echo "eslint called with: $@" > /tmp/eslint_args.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/eslint"

  run "$SCRIPT_PATH" app/javascript/controllers/user_controller.js

  [ "$status" -eq 0 ]

  # Check that --fix was passed
  [ -f /tmp/eslint_args.txt ]
  args=$(cat /tmp/eslint_args.txt)
  [[ "$args" =~ "--fix" ]]

  rm -f /tmp/eslint_args.txt
}

# --- eslint_d daemon tests ---

@test "uses eslint_d when available and not disabled" {
  unset NO_ESLINT_D

  # Create a mock eslint_d
  cat > "$MOCK_DIR/eslint_d" << 'EOF'
#!/bin/bash
echo "eslint_d called with: $@" > /tmp/eslint_d_args.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/eslint_d"

  echo "console.log('test');" > "app.js"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]
  [ -f /tmp/eslint_d_args.txt ]
  args=$(cat /tmp/eslint_d_args.txt)
  [[ "$args" =~ "--fix" ]]
  [[ "$args" =~ "app.js" ]]

  rm -f /tmp/eslint_d_args.txt
}

@test "skips eslint_d when NO_ESLINT_D is set" {
  export NO_ESLINT_D=1

  # Create both mocks
  cat > "$MOCK_DIR/eslint_d" << 'EOF'
#!/bin/bash
echo "eslint_d called" > /tmp/eslint_d_called.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/eslint_d"
  create_eslint_mock 0 ""

  echo "console.log('test');" > "app.js"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]
  # eslint_d should NOT have been called
  [ ! -f /tmp/eslint_d_called.txt ]

  rm -f /tmp/eslint_d_called.txt
}

@test "skips eslint_d when ./tmp/no-eslint-d exists" {
  unset NO_ESLINT_D
  mkdir -p tmp
  touch tmp/no-eslint-d

  # Create both mocks
  cat > "$MOCK_DIR/eslint_d" << 'EOF'
#!/bin/bash
echo "eslint_d called" > /tmp/eslint_d_called.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/eslint_d"
  create_eslint_mock 0 ""

  echo "console.log('test');" > "app.js"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]
  # eslint_d should NOT have been called
  [ ! -f /tmp/eslint_d_called.txt ]

  rm -f /tmp/eslint_d_called.txt
}

@test "shows install hint when eslint_d not available and not suppressed" {
  unset NO_ESLINT_D
  rm -f "$MOCK_DIR/eslint_d"

  create_eslint_mock 0 ""
  echo "console.log('test');" > "app.js"

  # Remove eslint_d from PATH but keep system paths for basic commands
  CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v nvm | tr '\n' ':')
  run bash -c "PATH='$MOCK_DIR:$TEST_REPO/node_modules/.bin:$CLEAN_PATH' $SCRIPT_PATH app.js"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "eslint_d is not installed" ]]
}

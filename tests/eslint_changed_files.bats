#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/eslint_changed_files"

  # Create mock eslint command
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR/bin"
  export PATH="$MOCK_DIR/bin:$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock eslint
create_eslint_mock() {
  local exit_code=$1
  local output_file=$2

  # Create the actual eslint mock
  cat > "$MOCK_DIR/bin/eslint" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/bin/eslint"

  # Also mock yarn since the script prefers "yarn eslint"
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
# Handle yarn --silent eslint
if [ "$1" = "--silent" ]; then
  shift
fi
# If called with "eslint", just pass through to our mock eslint
if [ "$1" = "eslint" ]; then
  shift
  exec eslint "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"
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
  cat > "$MOCK_DIR/bin/eslint" << 'EOF'
#!/bin/bash
echo "eslint called with: $@" > /tmp/eslint_args.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/bin/eslint"

  # Also need to mock yarn
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
if [ "$1" = "--silent" ]; then
  shift
fi
if [ "$1" = "eslint" ]; then
  shift
  exec eslint "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"

  run "$SCRIPT_PATH" app/javascript/controllers/user_controller.js

  [ "$status" -eq 0 ]

  # Check that --fix was passed
  [ -f /tmp/eslint_args.txt ]
  args=$(cat /tmp/eslint_args.txt)
  [[ "$args" =~ "--fix" ]]

  rm -f /tmp/eslint_args.txt
}

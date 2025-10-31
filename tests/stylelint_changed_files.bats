#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/stylelint_changed_files"

  # Create mock stylelint command
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR/bin"
  export PATH="$MOCK_DIR/bin:$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock stylelint
create_stylelint_mock() {
  local exit_code=$1
  local output_file=$2

  # Create the actual stylelint mock
  cat > "$MOCK_DIR/bin/stylelint" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/bin/stylelint"

  # Also mock yarn since the script prefers "yarn stylelint"
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
# If called with "stylelint", just pass through to our mock stylelint
if [ "$1" = "stylelint" ]; then
  shift
  exec stylelint "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: N/A" ]]
}

@test "shows only green check when no warnings or errors" {
  # Create CSS file
  mkdir -p app/assets/stylesheets
  echo "body { margin: 0; }" > "app/assets/stylesheets/application.css"

  # Mock stylelint to return success with no output
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  run "$SCRIPT_PATH" app/assets/stylesheets/application.css

  [ "$status" -eq 0 ]

  # Should only show the green check
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: ✓" ]]
}

@test "shows output and green check when auto-fixes applied" {
  # Create CSS file
  mkdir -p app/assets/stylesheets
  echo "body { margin: 0; }" > "app/assets/stylesheets/application.css"

  # Mock stylelint to return success with fix messages
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_with_fixes.txt"

  run "$SCRIPT_PATH" app/assets/stylesheets/application.css

  [ "$status" -eq 0 ]

  # Should show the output since fixes were made
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "error" ]]
  [[ "$output_stripped" =~ "stylelint: ✓" ]]
}

@test "exits 2 and shows output when unfixable errors found" {
  # Create CSS file
  mkdir -p app/assets/stylesheets
  echo "body { margin: 0; }" > "app/assets/stylesheets/application.css"

  # Mock stylelint to return failure
  create_stylelint_mock 1 "$HOME/.claude/scripts/tests/fixtures/stylelint_failure_unfixable.txt"

  run "$SCRIPT_PATH" app/assets/stylesheets/application.css

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "property-no-unknown" ]]
  [[ "$output_stripped" =~ "stylelint: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create CSS file
  mkdir -p app/assets/stylesheets
  echo "body { margin: 0; }" > "app/assets/stylesheets/application.css"

  # Mock stylelint to return success
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  run "$SCRIPT_PATH" --verbose app/assets/stylesheets/application.css

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed CSS/SCSS files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple files
  echo "body { margin: 0; }" > "app.css"
  echo ".button { padding: 10px; }" > "components.scss"

  # Mock stylelint to return success
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  run "$SCRIPT_PATH" app.css components.scss

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: ✓" ]]
}

@test "passes --fix flag to stylelint" {
  # Create CSS file
  mkdir -p app/assets/stylesheets
  echo "body { margin: 0; }" > "app/assets/stylesheets/application.css"

  # Create a mock that records arguments
  cat > "$MOCK_DIR/bin/stylelint" << 'EOF'
#!/bin/bash
echo "stylelint called with: $@" > /tmp/stylelint_args.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/bin/stylelint"

  # Also need to mock yarn
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
if [ "$1" = "stylelint" ]; then
  shift
  exec stylelint "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"

  run "$SCRIPT_PATH" app/assets/stylesheets/application.css

  [ "$status" -eq 0 ]

  # Check that --fix was passed
  [ -f /tmp/stylelint_args.txt ]
  args=$(cat /tmp/stylelint_args.txt)
  [[ "$args" =~ "--fix" ]]

  rm -f /tmp/stylelint_args.txt
}

@test "handles both .css and .scss files" {
  # Create both types
  echo "body { margin: 0; }" > "application.css"
  echo ".button { padding: 10px; }" > "components.scss"

  # Mock stylelint
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  run "$SCRIPT_PATH" application.css components.scss

  [ "$status" -eq 0 ]
}

@test "hook mode: shows N/A when JSON contains non-CSS file" {
  # Mock stylelint
  create_stylelint_mock 0 ""

  # Simulate Claude Code hook with a non-CSS file
  run bash -c "echo '{\"inputs\": {\"file_path\": \"app/models/user.rb\"}}' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: N/A" ]]
}

@test "hook mode: runs stylelint on CSS file from JSON" {
  # Create CSS file
  echo "body { margin: 0; }" > "app.css"

  # Mock stylelint
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  # Simulate Claude Code hook with CSS file
  run bash -c "echo '{\"inputs\": {\"file_path\": \"app.css\"}}' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: ✓" ]]
}

@test "hook mode: handles tool_response.filePath field" {
  # Create SCSS file
  echo ".button { padding: 10px; }" > "components.scss"

  # Mock stylelint
  create_stylelint_mock 0 "$HOME/.claude/scripts/tests/fixtures/stylelint_success_no_warnings.txt"

  # Simulate Claude Code hook with alternative field name
  run bash -c "echo '{\"response\": {\"filePath\": \"components.scss\"}}' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "stylelint: ✓" ]]
}

#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/prettier_changed_files"

  # Create mock prettier command
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR/bin"
  export PATH="$MOCK_DIR/bin:$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock prettier
create_prettier_mock() {
  local exit_code=$1
  local output_file=$2

  # Create the actual prettier mock
  cat > "$MOCK_DIR/bin/prettier" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/bin/prettier"

  # Also mock yarn since the script prefers "yarn prettier"
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
# If called with "prettier", just pass through to our mock prettier
if [ "$1" = "prettier" ]; then
  shift
  exec prettier "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: N/A" ]]
}

@test "shows only green check when no formatting changes needed" {
  # Create formattable file
  mkdir -p app
  echo "console.log('test');" > "app.js"

  # Mock prettier to return success with no output (no files formatted)
  create_prettier_mock 0 "$HOME/.claude/scripts/tests/fixtures/prettier_success_no_changes.txt"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Should only show the green check
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: ✓" ]]
}

@test "shows output and green check when files formatted" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Mock prettier to return success with formatted file list
  create_prettier_mock 0 "$HOME/.claude/scripts/tests/fixtures/prettier_success_with_formatting.txt"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Should show the output since formatting was done
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "user_controller.js" ]]
  [[ "$output_stripped" =~ "prettier: ✓" ]]
}

@test "exits 2 and shows output when formatting errors found" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Mock prettier to return failure
  create_prettier_mock 1 "$HOME/.claude/scripts/tests/fixtures/prettier_failure.txt"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "SyntaxError" ]]
  [[ "$output_stripped" =~ "prettier: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Mock prettier to return success
  create_prettier_mock 0 "$HOME/.claude/scripts/tests/fixtures/prettier_success_no_changes.txt"

  run "$SCRIPT_PATH" --verbose app.js

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple files
  echo "console.log('user');" > "user.js"
  echo "body { margin: 0; }" > "style.css"

  # Mock prettier to return success
  create_prettier_mock 0 "$HOME/.claude/scripts/tests/fixtures/prettier_success_no_changes.txt"

  run "$SCRIPT_PATH" user.js style.css

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: ✓" ]]
}

@test "passes --write flag to prettier" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Create a mock that records arguments
  cat > "$MOCK_DIR/bin/prettier" << 'EOF'
#!/bin/bash
echo "prettier called with: $@" > /tmp/prettier_args.txt
exit 0
EOF
  chmod +x "$MOCK_DIR/bin/prettier"

  # Also need to mock yarn
  cat > "$MOCK_DIR/yarn" << 'EOF'
#!/bin/bash
if [ "$1" = "prettier" ]; then
  shift
  exec prettier "$@"
fi
EOF
  chmod +x "$MOCK_DIR/yarn"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Check that --write was passed
  [ -f /tmp/prettier_args.txt ]
  args=$(cat /tmp/prettier_args.txt)
  [[ "$args" =~ "--write" ]]

  rm -f /tmp/prettier_args.txt
}

@test "formats multiple file types (js, css, json, yml, md)" {
  # Create files of different types
  echo "console.log('test');" > "app.js"
  echo "body { margin: 0; }" > "styles.css"
  echo '{"key": "value"}' > "config.json"
  echo "key: value" > "config.yml"
  echo "# Title" > "README.md"

  # Mock prettier
  create_prettier_mock 0 "$HOME/.claude/scripts/tests/fixtures/prettier_success_no_changes.txt"

  run "$SCRIPT_PATH" app.js styles.css config.json config.yml README.md

  [ "$status" -eq 0 ]
}

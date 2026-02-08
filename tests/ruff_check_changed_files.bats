#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  SCRIPT_PATH="$SCRIPTS_DIR/ruff_check_changed_files"

  # Create mock directory
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock ruff command
create_ruff_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/ruff" << MOCK_EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
MOCK_EOF
  chmod +x "$MOCK_DIR/ruff"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: N/A" ]]
}

@test "shows N/A for non-Python file via JSON input" {
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.rs\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: N/A" ]]
}

@test "shows N/A when file does not exist" {
  create_ruff_mock 0 ""

  run "$SCRIPT_PATH" nonexistent.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: N/A (file not found)" ]]
}

@test "shows only green check when no issues found" {
  echo "x = 1" > test.py

  create_ruff_mock 0 ""

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: ✓" ]]
}

@test "exits 2 and shows output when unfixable issues found" {
  echo "import os" > test.py

  create_ruff_mock 1 "$FIXTURES_DIR/ruff_check_failure.txt"

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 2 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "F401" ]]
  [[ "$output_stripped" =~ "ruff: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  echo "x = 1" > test.py

  create_ruff_mock 0 ""

  run "$SCRIPT_PATH" --verbose test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Python files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  echo "x = 1" > user.py
  echo "y = 2" > post.py

  create_ruff_mock 0 ""

  run "$SCRIPT_PATH" user.py post.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: ✓" ]]
}

@test "processes .py files from JSON input" {
  echo "x = 1" > test.py

  create_ruff_mock 0 ""

  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: ✓" ]]
}

@test "handles filePath field in JSON input" {
  echo "x = 1" > test.py

  create_ruff_mock 0 ""

  run bash -c 'echo "{\"tool_response\": {\"filePath\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: ✓" ]]
}

@test "skips when ruff is not found" {
  # Don't create a ruff mock - ensure it's not available
  # Remove any existing mock directory from PATH
  export PATH=$(echo "$PATH" | sed "s|$MOCK_DIR:||")

  echo "x = 1" > test.py

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff: skipped (ruff not found)" ]]
}

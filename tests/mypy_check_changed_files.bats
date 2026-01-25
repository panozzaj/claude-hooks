#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/mypy_check_changed_files"

  # Create mock directory for mypy
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock mypy
create_mypy_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/mypy" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/mypy"
}

# Helper to create a mock uv that delegates to our mock mypy
create_uv_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/uv" << EOF
#!/bin/bash
# Skip 'run --quiet --with mypy' args and execute the rest
shift  # run
shift  # --quiet
shift  # --with
shift  # mypy
# Now \$@ should be: mypy [args]
if [ "\$1" = "mypy" ]; then
  shift
  if [ -n "$output_file" ] && [ -f "$output_file" ]; then
    cat "$output_file"
  fi
  exit $exit_code
fi
exit 1
EOF
  chmod +x "$MOCK_DIR/uv"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: N/A" ]]
}

@test "shows N/A when file does not exist" {
  run "$SCRIPT_PATH" nonexistent.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: N/A (file not found)" ]]
}

@test "shows only green check when no type errors" {
  # Create Python file
  mkdir -p app/models
  echo "def hello() -> str: return 'world'" > "app/models/user.py"

  # Mock uv to return success
  create_uv_mock 0 ""

  run "$SCRIPT_PATH" app/models/user.py

  [ "$status" -eq 0 ]

  # Should only show the green check
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: ✓" ]]
}

@test "exits 2 and shows output when type errors found" {
  # Create Python file
  mkdir -p app/models
  echo "def hello() -> int: return 'world'" > "app/models/user.py"

  # Mock uv to return failure with error output
  create_uv_mock 1 "$HOME/.claude/scripts/tests/fixtures/mypy_failure.txt"

  run "$SCRIPT_PATH" app/models/user.py

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "error:" ]]
  [[ "$output_stripped" =~ "mypy: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create Python file
  mkdir -p app/models
  echo "x: int = 1" > "app/models/user.py"

  # Mock uv to return success
  create_uv_mock 0 ""

  run "$SCRIPT_PATH" --verbose app/models/user.py

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Python files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple Python files
  echo "x: int = 1" > "user.py"
  echo "y: str = 'hello'" > "post.py"

  # Mock uv to return success
  create_uv_mock 0 ""

  run "$SCRIPT_PATH" user.py post.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: ✓" ]]
}

@test "only processes .py files from JSON input" {
  # Mock receiving JSON with a non-Python file
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.js\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: N/A" ]]
}

@test "processes .py files from JSON input" {
  # Create Python file
  echo "x: int = 1" > "test.py"

  # Mock uv to return success
  create_uv_mock 0 ""

  # Mock receiving JSON with a Python file
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "mypy: ✓" ]]
}

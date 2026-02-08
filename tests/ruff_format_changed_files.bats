#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  SCRIPT_PATH="$SCRIPTS_DIR/ruff_format_changed_files"

  # Create mock directory
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock ruff command that handles both check and format subcommands
create_ruff_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/ruff" << MOCK_EOF
#!/bin/bash
# Handle 'ruff format' and 'ruff format -o' subcommands
if [ "\$1" = "format" ]; then
  shift
  # Check for --quiet flag with -o (diff check mode)
  if [ "\$1" = "--quiet" ]; then
    shift
    file="\$1"
    shift
    if [ "\$1" = "-o" ]; then
      # Copy input file to output (no changes)
      cp "\$file" "\$2"
      exit 0
    fi
  fi
  if [ -n "$output_file" ] && [ -f "$output_file" ]; then
    cat "$output_file"
  fi
  exit $exit_code
fi
exit 0
MOCK_EOF
  chmod +x "$MOCK_DIR/ruff"
}

# Helper for ruff mock that simulates formatting changes
create_ruff_mock_with_changes() {
  local exit_code=$1

  cat > "$MOCK_DIR/ruff" << 'MOCK_EOF'
#!/bin/bash
if [ "$1" = "format" ]; then
  shift
  if [ "$1" = "--quiet" ]; then
    shift
    file="$1"
    shift
    if [ "$1" = "-o" ]; then
      # Write a different version to the output file to simulate changes
      echo "# formatted" > "$2"
      exit 0
    fi
  fi
  # Regular format call - success
  exit 0
fi
exit 0
MOCK_EOF
  chmod +x "$MOCK_DIR/ruff"
}

# Helper for ruff mock that fails on format
create_ruff_mock_failure() {
  local output_file=$1

  cat > "$MOCK_DIR/ruff" << MOCK_EOF
#!/bin/bash
if [ "\$1" = "format" ]; then
  shift
  if [ "\$1" = "--quiet" ]; then
    shift
    file="\$1"
    shift
    if [ "\$1" = "-o" ]; then
      cp "\$file" "\$2"
      exit 0
    fi
  fi
  if [ -n "$output_file" ] && [ -f "$output_file" ]; then
    cat "$output_file"
  fi
  exit 1
fi
exit 0
MOCK_EOF
  chmod +x "$MOCK_DIR/ruff"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: N/A" ]]
}

@test "shows N/A for non-Python file via JSON input" {
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.rs\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: N/A" ]]
}

@test "shows N/A when file does not exist" {
  create_ruff_mock 0 ""

  run "$SCRIPT_PATH" nonexistent.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: N/A (file not found)" ]]
}

@test "shows only green check when no formatting changes needed" {
  echo "x = 1" > test.py

  create_ruff_mock 0 "$FIXTURES_DIR/ruff_format_success.txt"

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: ✓" ]]
}

@test "shows reformatted output and green check when changes applied" {
  echo "x=1" > test.py

  create_ruff_mock_with_changes 0

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Ruff reformatted:" ]]
  [[ "$output_stripped" =~ "ruff-fmt: ✓" ]]
}

@test "respects --verbose flag and shows file detection info" {
  echo "x = 1" > test.py

  create_ruff_mock 0 "$FIXTURES_DIR/ruff_format_success.txt"

  run "$SCRIPT_PATH" --verbose test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Python files detected:" ]]
}

@test "processes .py files from JSON input" {
  echo "x = 1" > test.py

  create_ruff_mock 0 "$FIXTURES_DIR/ruff_format_success.txt"

  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: ✓" ]]
}

@test "handles filePath field in JSON input" {
  echo "x = 1" > test.py

  create_ruff_mock 0 "$FIXTURES_DIR/ruff_format_success.txt"

  run bash -c 'echo "{\"tool_response\": {\"filePath\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: ✓" ]]
}

@test "skips when ruff is not found" {
  # Remove mock directory from PATH
  export PATH=$(echo "$PATH" | sed "s|$MOCK_DIR:||")

  echo "x = 1" > test.py

  run "$SCRIPT_PATH" test.py

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "ruff-fmt: skipped (ruff not found)" ]]
}

#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  SCRIPT_PATH="$SCRIPTS_DIR/gofmt_changed_files"

  # Create mock directory
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock gofmt command
create_gofmt_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/gofmt" << MOCK_EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
MOCK_EOF
  chmod +x "$MOCK_DIR/gofmt"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: N/A" ]]
}

@test "shows N/A for non-Go file via JSON input" {
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: N/A" ]]
}

@test "shows N/A when file does not exist" {
  create_gofmt_mock 0 ""

  run "$SCRIPT_PATH" nonexistent.go

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: N/A (file not found)" ]]
}

@test "shows only green check when formatting is clean" {
  echo 'package main' > main.go

  create_gofmt_mock 0 "$FIXTURES_DIR/gofmt_success.txt"

  run "$SCRIPT_PATH" main.go

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: ✓" ]]
}

@test "exits 2 and shows output when gofmt fails" {
  echo 'package main; if' > main.go

  create_gofmt_mock 1 "$FIXTURES_DIR/gofmt_failure.txt"

  run "$SCRIPT_PATH" main.go

  [ "$status" -eq 2 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "expected declaration" ]]
  [[ "$output_stripped" =~ "gofmt: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  echo 'package main' > main.go

  create_gofmt_mock 0 "$FIXTURES_DIR/gofmt_success.txt"

  run "$SCRIPT_PATH" --verbose main.go

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Go files detected:" ]]
}

@test "processes .go files from JSON input" {
  echo 'package main' > main.go

  create_gofmt_mock 0 "$FIXTURES_DIR/gofmt_success.txt"

  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"main.go\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: ✓" ]]
}

@test "handles filePath field in JSON input" {
  echo 'package main' > main.go

  create_gofmt_mock 0 "$FIXTURES_DIR/gofmt_success.txt"

  run bash -c 'echo "{\"tool_response\": {\"filePath\": \"main.go\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "gofmt: ✓" ]]
}

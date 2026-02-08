#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  SCRIPT_PATH="$SCRIPTS_DIR/cargo_fmt_changed_files"

  # Create mock directory
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"

  # Create Cargo.toml so the script can find the project root
  echo '[package]' > "$TEST_REPO/Cargo.toml"
  echo 'name = "test"' >> "$TEST_REPO/Cargo.toml"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock cargo command
create_cargo_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/cargo" << MOCK_EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
MOCK_EOF
  chmod +x "$MOCK_DIR/cargo"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: N/A" ]]
}

@test "shows N/A for non-Rust file via JSON input" {
  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"test.py\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: N/A" ]]
}

@test "shows N/A when no Cargo.toml found" {
  # Remove the Cargo.toml
  rm "$TEST_REPO/Cargo.toml"

  mkdir -p src
  echo 'fn main() {}' > src/main.rs

  create_cargo_mock 0 ""

  run "$SCRIPT_PATH" src/main.rs

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: N/A (no Cargo.toml found)" ]]
}

@test "shows only green check when formatting is clean" {
  mkdir -p src
  echo 'fn main() {}' > src/main.rs

  create_cargo_mock 0 "$FIXTURES_DIR/cargo_fmt_success.txt"

  run "$SCRIPT_PATH" src/main.rs

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: ✓" ]]
}

@test "exits 2 and shows output when cargo fmt fails" {
  mkdir -p src
  echo 'fn main() { let x = 5' > src/main.rs

  create_cargo_mock 1 "$FIXTURES_DIR/cargo_fmt_failure.txt"

  run "$SCRIPT_PATH" src/main.rs

  [ "$status" -eq 2 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "error:" ]]
  [[ "$output_stripped" =~ "cargo fmt: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  mkdir -p src
  echo 'fn main() {}' > src/main.rs

  create_cargo_mock 0 "$FIXTURES_DIR/cargo_fmt_success.txt"

  run "$SCRIPT_PATH" --verbose src/main.rs

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Rust files detected:" ]]
}

@test "processes .rs files from JSON input" {
  mkdir -p src
  echo 'fn main() {}' > src/main.rs

  create_cargo_mock 0 "$FIXTURES_DIR/cargo_fmt_success.txt"

  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"src/main.rs\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: ✓" ]]
}

@test "handles filePath field in JSON input" {
  mkdir -p src
  echo 'fn main() {}' > src/main.rs

  create_cargo_mock 0 "$FIXTURES_DIR/cargo_fmt_success.txt"

  run bash -c 'echo "{\"tool_response\": {\"filePath\": \"src/main.rs\"}}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "cargo fmt: ✓" ]]
}

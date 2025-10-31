#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/haml_check_changed_files"

  # Create mock check_haml_syntax command
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR/bin/scripts"
  export PATH="$MOCK_DIR/bin/scripts:$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock check_haml_syntax
create_haml_checker_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/bin/scripts/check_haml_syntax" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/bin/scripts/check_haml_syntax"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "haml: N/A" ]]
}

@test "shows only green check when HAML syntax is valid" {
  # Create HAML file
  mkdir -p app/views/users
  echo "%h1 Title" > "app/views/users/show.html.haml"

  # Mock check_haml_syntax to return success
  create_haml_checker_mock 0 "$HOME/.claude/scripts/tests/fixtures/haml_success.txt"

  run "$SCRIPT_PATH" app/views/users/show.html.haml

  [ "$status" -eq 0 ]

  # Should only show the green check, not the full output
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "haml: ✓" ]]
}

@test "exits 2 and shows output when HAML syntax errors found" {
  # Create HAML file
  mkdir -p app/views/users
  echo "%h1 Title" > "app/views/users/show.html.haml"

  # Mock check_haml_syntax to return failure
  create_haml_checker_mock 1 "$HOME/.claude/scripts/tests/fixtures/haml_failure.txt"

  run "$SCRIPT_PATH" app/views/users/show.html.haml

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Syntax error" ]]
  [[ "$output_stripped" =~ "haml: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create HAML file
  mkdir -p app/views/users
  echo "%h1 Title" > "app/views/users/show.html.haml"

  # Mock check_haml_syntax to return success
  create_haml_checker_mock 0 "$HOME/.claude/scripts/tests/fixtures/haml_success.txt"

  run "$SCRIPT_PATH" --verbose app/views/users/show.html.haml

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed HAML files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple HAML files
  mkdir -p views
  echo "%h1 Users" > "views/users.html.haml"
  echo "%h1 Posts" > "views/posts.html.haml"

  # Mock check_haml_syntax to return success
  create_haml_checker_mock 0 "$HOME/.claude/scripts/tests/fixtures/haml_success.txt"

  run "$SCRIPT_PATH" views/users.html.haml views/posts.html.haml

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  # Should have haml: ✓ in the output (may have other text)
  [[ "$output_stripped" =~ "haml: ✓" ]]
}

@test "skips non-existent files with warning in verbose mode" {
  # Create a file then delete it
  echo "%h1 Title" > "deleted.html.haml"
  rm "deleted.html.haml"

  # Mock check_haml_syntax
  create_haml_checker_mock 0 "$HOME/.claude/scripts/tests/fixtures/haml_success.txt"

  run "$SCRIPT_PATH" --verbose deleted.html.haml

  [ "$status" -eq 0 ]

  # Should show warning about skipped file in verbose mode
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Skipping non-existent file" ]]
}

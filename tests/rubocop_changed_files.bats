#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/rubocop_changed_files"

  # Create mock rubocop command
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock rubocop
create_rubocop_mock() {
  local exit_code=$1
  local output_file=$2

  cat > "$MOCK_DIR/rubocop" << EOF
#!/bin/bash
if [ -n "$output_file" ] && [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit $exit_code
EOF
  chmod +x "$MOCK_DIR/rubocop"
}

# Helper to create bundle exec wrapper
create_bundle_mock() {
  cat > "$MOCK_DIR/bundle" << 'EOF'
#!/bin/bash
# Ignore "exec" and just run rubocop
shift  # remove "exec"
shift  # remove "rubocop"
exec rubocop "$@"
EOF
  chmod +x "$MOCK_DIR/bundle"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: N/A" ]]
}

@test "shows only green check when no offenses detected" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Mock rubocop to return success with no offenses
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  run "$SCRIPT_PATH" app/models/user.rb

  [ "$status" -eq 0 ]

  # Should only show the green check, not the full output
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: ✓" ]]
}

@test "shows output and green check when auto-corrections made" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Mock rubocop to return success with corrections
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_with_corrections.txt"
  create_bundle_mock

  run "$SCRIPT_PATH" app/models/user.rb

  [ "$status" -eq 0 ]

  # Should show the output since corrections were made
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "2 offenses corrected" ]]
  [[ "$output_stripped" =~ "rubocop: ✓" ]]
}

@test "exits 2 and shows output when unautocorrectable offenses found" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Mock rubocop to return failure
  create_rubocop_mock 1 "$HOME/.claude/scripts/tests/fixtures/rubocop_failure_uncorrectable.txt"
  create_bundle_mock

  run "$SCRIPT_PATH" app/models/user.rb

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Metrics/MethodLength" ]]
  [[ "$output_stripped" =~ "rubocop: ✗" ]]
}

@test "respects --verbose flag and shows file info" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Mock rubocop to return success with no offenses
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  run "$SCRIPT_PATH" --verbose app/models/user.rb

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info (before running rubocop)
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed Ruby files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple Ruby files
  echo "class User; end" > "user.rb"
  echo "class Post; end" > "post.rb"

  # Mock rubocop to return success
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  run "$SCRIPT_PATH" user.rb post.rb

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: ✓" ]]
}

@test "passes --force-exclusion flag to rubocop" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Create a mock that records arguments
  cat > "$MOCK_DIR/rubocop" << 'EOF'
#!/bin/bash
echo "rubocop called with: $@" > /tmp/rubocop_args.txt
echo "Inspecting 1 file"
echo "."
echo ""
echo "1 file inspected, no offenses detected"
exit 0
EOF
  chmod +x "$MOCK_DIR/rubocop"
  create_bundle_mock

  run "$SCRIPT_PATH" app/models/user.rb

  [ "$status" -eq 0 ]

  # Check that --force-exclusion was passed
  [ -f /tmp/rubocop_args.txt ]
  args=$(cat /tmp/rubocop_args.txt)
  [[ "$args" =~ "--force-exclusion" ]]

  rm -f /tmp/rubocop_args.txt
}

@test "hook mode: shows N/A when JSON contains non-Ruby file" {
  # Create mock rubocop
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  # Create JSON for a JavaScript file
  HOOK_JSON='{"session_id":"test","cwd":"'$TEST_REPO'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'$TEST_REPO'/app.js"}}'

  run bash -c "echo '$HOOK_JSON' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: N/A" ]]
}

@test "hook mode: runs rubocop on Ruby file from JSON" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Create mock rubocop
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  # Create JSON for the Ruby file
  HOOK_JSON='{"session_id":"test","cwd":"'$TEST_REPO'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"'$TEST_REPO'/app/models/user.rb"}}'

  run bash -c "echo '$HOOK_JSON' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: ✓" ]]
}

@test "hook mode: handles tool_response.filePath field" {
  # Create a Ruby file
  mkdir -p app/models
  echo "class User; end" > "app/models/user.rb"

  # Create mock rubocop
  create_rubocop_mock 0 "$HOME/.claude/scripts/tests/fixtures/rubocop_success_no_offenses.txt"
  create_bundle_mock

  # Create JSON using filePath instead of file_path
  HOOK_JSON='{"session_id":"test","cwd":"'$TEST_REPO'","hook_event_name":"PostToolUse","tool_name":"Edit","tool_response":{"filePath":"'$TEST_REPO'/app/models/user.rb"}}'

  run bash -c "echo '$HOOK_JSON' | $SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "rubocop: ✓" ]]
}

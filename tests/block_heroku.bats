#!/usr/bin/env bats
#
# Tests for block_heroku PreToolUse hook
#
# Hook receives JSON via stdin with format:
#   {"tool_name": "Bash", "tool_input": {"command": "..."}}

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/PreToolUse/block_heroku"
}

# Helper to invoke script with JSON input
run_hook() {
  local tool_name="$1"
  local command="$2"
  echo "{\"tool_name\":\"$tool_name\",\"tool_input\":{\"command\":\"$command\"}}" | "$SCRIPT"
}

# -----------------------------------------------------------------------------
# Tests: Non-Bash tools (should pass through)
# -----------------------------------------------------------------------------

@test "ignores non-Bash tools" {
  run run_hook "Read" "heroku apps"
  [ "$status" -eq 0 ]
}

@test "ignores empty tool_name" {
  run run_hook "" "heroku apps"
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Tests: Blocked heroku commands
# -----------------------------------------------------------------------------

@test "blocks 'heroku' with no args" {
  run run_hook "Bash" "heroku"
  [ "$status" -eq 2 ]
  [[ "$output" == *"safe-heroku"* ]]
}

@test "blocks 'heroku apps'" {
  run run_hook "Bash" "heroku apps"
  [ "$status" -eq 2 ]
  [[ "$output" == *"safe-heroku"* ]]
}

@test "blocks 'heroku config -a myapp'" {
  run run_hook "Bash" "heroku config -a myapp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"safe-heroku"* ]]
}

@test "blocks 'heroku logs --tail'" {
  run run_hook "Bash" "heroku logs --tail"
  [ "$status" -eq 2 ]
  [[ "$output" == *"safe-heroku"* ]]
}

# -----------------------------------------------------------------------------
# Tests: Allowed commands (safe-heroku and others)
# -----------------------------------------------------------------------------

@test "allows 'safe-heroku apps'" {
  run run_hook "Bash" "safe-heroku apps"
  [ "$status" -eq 0 ]
}

@test "allows 'safe-heroku config -a myapp'" {
  run run_hook "Bash" "safe-heroku config -a myapp"
  [ "$status" -eq 0 ]
}

@test "allows unrelated commands" {
  run run_hook "Bash" "git status"
  [ "$status" -eq 0 ]
}

@test "allows commands containing heroku in path" {
  run run_hook "Bash" "/usr/local/bin/safe-heroku apps"
  [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Tests: Edge cases
# -----------------------------------------------------------------------------

@test "does not block 'heroku-cli' (different command)" {
  run run_hook "Bash" "heroku-cli apps"
  [ "$status" -eq 0 ]
}

@test "does not block 'myheroku' (different command)" {
  run run_hook "Bash" "myheroku apps"
  [ "$status" -eq 0 ]
}

@test "handles empty command gracefully" {
  run run_hook "Bash" ""
  [ "$status" -eq 0 ]
}

@test "handles invalid JSON gracefully" {
  run bash -c 'echo "not json" | '"$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "handles missing tool_input gracefully" {
  run bash -c 'echo "{\"tool_name\":\"Bash\"}" | '"$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "handles tty stdin gracefully" {
  # Simulate no stdin by not piping anything
  run "$SCRIPT" < /dev/null
  [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

setup() {
  export TEST_REPO=$(mktemp -d)
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/common/cooldown"
  # Use a unique TMPDIR so tests don't collide
  export TMPDIR="$TEST_REPO/tmp"
  mkdir -p "$TMPDIR"
}

teardown() {
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
}

@test "check exits 0 (ok to proceed) when no prior block" {
  run "$SCRIPT_PATH" check "session123" "test_hook"

  [ "$status" -eq 0 ]
}

@test "check exits 1 (in cooldown) after a recent record" {
  "$SCRIPT_PATH" record "session123" "test_hook"

  run "$SCRIPT_PATH" check "session123" "test_hook"

  [ "$status" -eq 1 ]
}

@test "check exits 0 when cooldown has expired" {
  # Write a timestamp 400 seconds in the past
  COOLDOWN_FILE="$TMPDIR/claude_stop_session123_test_hook"
  echo $(( $(date +%s) - 400 )) > "$COOLDOWN_FILE"

  run "$SCRIPT_PATH" check "session123" "test_hook"

  [ "$status" -eq 0 ]
}

@test "check respects custom cooldown duration" {
  "$SCRIPT_PATH" record "session123" "test_hook"

  # 1 second cooldown - should still be in cooldown
  run "$SCRIPT_PATH" check "session123" "test_hook" 1
  [ "$status" -eq 1 ]

  # Wait and check again
  sleep 2
  run "$SCRIPT_PATH" check "session123" "test_hook" 1
  [ "$status" -eq 0 ]
}

@test "different session IDs have independent cooldowns" {
  "$SCRIPT_PATH" record "session_A" "test_hook"

  # session_A should be in cooldown
  run "$SCRIPT_PATH" check "session_A" "test_hook"
  [ "$status" -eq 1 ]

  # session_B should NOT be in cooldown
  run "$SCRIPT_PATH" check "session_B" "test_hook"
  [ "$status" -eq 0 ]
}

@test "different hook names have independent cooldowns" {
  "$SCRIPT_PATH" record "session123" "hook_A"

  # hook_A should be in cooldown
  run "$SCRIPT_PATH" check "session123" "hook_A"
  [ "$status" -eq 1 ]

  # hook_B should NOT be in cooldown
  run "$SCRIPT_PATH" check "session123" "hook_B"
  [ "$status" -eq 0 ]
}

@test "check exits 0 when session_id is empty" {
  run "$SCRIPT_PATH" check "" "test_hook"

  [ "$status" -eq 0 ]
}

@test "check exits 0 when hook_name is empty" {
  run "$SCRIPT_PATH" check "session123" ""

  [ "$status" -eq 0 ]
}

@test "respects STOP_HOOK_COOLDOWN env var" {
  "$SCRIPT_PATH" record "session123" "test_hook"

  # Default 300s cooldown - should be blocked
  run "$SCRIPT_PATH" check "session123" "test_hook"
  [ "$status" -eq 1 ]

  # Override to 0 seconds - should pass
  export STOP_HOOK_COOLDOWN=0
  run "$SCRIPT_PATH" check "session123" "test_hook"
  [ "$status" -eq 0 ]
}

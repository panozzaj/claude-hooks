#!/usr/bin/env bats

setup() {
  # Create a temporary directory for testing
  export TEST_REPO=$(mktemp -d)

  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/PreToolUse/jj_snapshot"

  # Create mock directory
  MOCK_DIR="$TEST_REPO/.mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
}

# Helper to create a mock jj command
create_jj_mock() {
  cat > "$MOCK_DIR/jj" << 'MOCK_EOF'
#!/bin/bash
# Track invocations using script's own directory
INVOC_DIR="$(dirname "$0")"
echo "$@" >> "$INVOC_DIR/jj.invocations"
if [ "$1" = "root" ]; then
  echo "/fake/jj/root"
  exit 0
fi
if [ "$1" = "status" ]; then
  exit 0
fi
exit 0
MOCK_EOF
  chmod +x "$MOCK_DIR/jj"
}

@test "exits silently when jj is not installed" {
  # Don't create jj mock - ensure it's not available
  export PATH=$(echo "$PATH" | sed "s|$MOCK_DIR:||")

  cd "$TEST_REPO"

  run bash -c 'echo "{\"cwd\": \"'$TEST_REPO'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits silently when not in a jj repo" {
  # Create jj mock that fails for 'jj root' (not a repo)
  cat > "$MOCK_DIR/jj" << 'MOCK_EOF'
#!/bin/bash
if [ "$1" = "root" ]; then
  echo "Error: There is no jj repo in \".\"" >&2
  exit 1
fi
exit 0
MOCK_EOF
  chmod +x "$MOCK_DIR/jj"

  cd "$TEST_REPO"

  run bash -c 'echo "{\"cwd\": \"'$TEST_REPO'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "runs jj status when in a jj repo" {
  create_jj_mock

  cd "$TEST_REPO"

  run bash -c 'echo "{\"cwd\": \"'$TEST_REPO'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Check that jj was called with root and status
  [ -f "$MOCK_DIR/jj.invocations" ]
  invocations=$(cat "$MOCK_DIR/jj.invocations")
  [[ "$invocations" =~ "root" ]]
  [[ "$invocations" =~ "status" ]]
}

@test "produces no output on success" {
  create_jj_mock

  cd "$TEST_REPO"

  run bash -c 'echo "{\"cwd\": \"'$TEST_REPO'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uses cwd from JSON input" {
  create_jj_mock

  # Run from a different directory but pass TEST_REPO as cwd
  run bash -c 'echo "{\"cwd\": \"'$TEST_REPO'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
}

@test "handles missing cwd in JSON gracefully" {
  # No jj installed, no cwd - should exit cleanly
  export PATH=$(echo "$PATH" | sed "s|$MOCK_DIR:||")

  run bash -c 'echo "{\"tool_name\": \"Edit\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
}

@test "handles empty stdin gracefully" {
  export PATH=$(echo "$PATH" | sed "s|$MOCK_DIR:||")

  run "$SCRIPT_PATH" < /dev/null

  [ "$status" -eq 0 ]
}

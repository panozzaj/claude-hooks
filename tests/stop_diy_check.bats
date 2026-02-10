#!/usr/bin/env bats

setup() {
  export TEST_REPO=$(mktemp -d)
  # Separate temp dir for mock backups (outside any git repo under test)
  export MOCK_BACKUP_DIR=$(mktemp -d)
  # Isolate cooldown files per test
  export TMPDIR="$TEST_REPO/tmp"
  mkdir -p "$TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/Stop/stop_diy_check"
  FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
}

teardown() {
  restore_llm_classify
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
  if [ -n "$MOCK_BACKUP_DIR" ] && [ -d "$MOCK_BACKUP_DIR" ]; then
    rm -rf "$MOCK_BACKUP_DIR"
  fi
}

# Helper to create a mock llm_classify that returns a fixed response
create_llm_classify_mock() {
  local response="$1"
  local llm_classify_dir="$BATS_TEST_DIRNAME/../scripts/common"

  cp "$llm_classify_dir/llm_classify" "$MOCK_BACKUP_DIR/llm_classify.bak"

  cat > "$llm_classify_dir/llm_classify" << MOCK_EOF
#!/bin/bash
cat > /dev/null
echo "$response"
exit 0
MOCK_EOF
  chmod +x "$llm_classify_dir/llm_classify"
}

# Helper to create a mock llm_classify that fails
create_llm_classify_mock_fail() {
  local llm_classify_dir="$BATS_TEST_DIRNAME/../scripts/common"

  cp "$llm_classify_dir/llm_classify" "$MOCK_BACKUP_DIR/llm_classify.bak"

  cat > "$llm_classify_dir/llm_classify" << 'MOCK_EOF'
#!/bin/bash
cat > /dev/null
exit 1
MOCK_EOF
  chmod +x "$llm_classify_dir/llm_classify"
}

restore_llm_classify() {
  local llm_classify_dir="$BATS_TEST_DIRNAME/../scripts/common"
  if [ -f "$MOCK_BACKUP_DIR/llm_classify.bak" ]; then
    cp "$MOCK_BACKUP_DIR/llm_classify.bak" "$llm_classify_dir/llm_classify"
    chmod +x "$llm_classify_dir/llm_classify"
  fi
}

@test "exits 0 when stop_hook_active is true (re-entrancy guard)" {
  run bash -c 'echo "{\"stop_hook_active\": true, \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when stdin is a terminal (no input)" {
  run "$SCRIPT_PATH" < /dev/null

  [ "$status" -eq 0 ]
}

@test "exits 0 when transcript_path is missing" {
  run bash -c 'echo "{\"stop_hook_active\": false}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when transcript file does not exist" {
  run bash -c 'echo "{\"stop_hook_active\": false, \"transcript_path\": \"/nonexistent/path.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when last message has no text content (tool_use only)" {
  create_llm_classify_mock "NO"

  run bash -c 'echo "{\"stop_hook_active\": false, \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_tool_use_only.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when LLM classifies as NO" {
  create_llm_classify_mock "NO"

  run bash -c 'echo "{\"stop_hook_active\": false, \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_clean.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "outputs block JSON when LLM classifies as YES" {
  create_llm_classify_mock "YES: restart the server with fireup restart"

  run bash -c 'echo "{\"stop_hook_active\": false, \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("restart the server")'
}

@test "exits 0 when LLM is unreachable (graceful degradation)" {
  create_llm_classify_mock_fail

  run bash -c 'echo "{\"stop_hook_active\": false, \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "second block is suppressed by cooldown for same session" {
  create_llm_classify_mock "YES: restart the server"

  # First call should block
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_cooldown_test\", \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'

  # Second call with same session_id should be suppressed
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_cooldown_test\", \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cooldown does not affect different sessions" {
  create_llm_classify_mock "YES: restart the server"

  # Block for session A
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_A\", \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"
  echo "$output" | jq -e '.decision == "block"'

  # Session B should still block
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_B\", \"transcript_path\": \"'"$FIXTURES_DIR"'/transcript_diy_restart.jsonl\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

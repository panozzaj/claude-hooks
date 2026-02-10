#!/usr/bin/env bats

setup() {
  export TEST_REPO=$(mktemp -d)
  # Separate temp dir for mock backups (outside the git repo)
  export MOCK_BACKUP_DIR=$(mktemp -d)
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/Stop/stop_auto_commit"
  FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

  # Set up a real git repo for tests that need one
  cd "$TEST_REPO"
  git init --initial-branch=main > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "initial" > README.md
  git add README.md
  git commit -m "Initial commit" > /dev/null 2>&1
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
  run bash -c 'echo "{\"stop_hook_active\": true, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when stdin is empty" {
  run "$SCRIPT_PATH" < /dev/null

  [ "$status" -eq 0 ]
}

@test "exits 0 when cwd is missing" {
  run bash -c 'echo "{\"stop_hook_active\": false}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when cwd does not exist" {
  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"/nonexistent/path\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when cwd is not a git repo" {
  NON_GIT_DIR=$(mktemp -d)

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$NON_GIT_DIR"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]

  rm -rf "$NON_GIT_DIR"
}

@test "exits 0 when git working directory is clean" {
  create_llm_classify_mock "YES"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when only tmp/ files changed" {
  create_llm_classify_mock "YES"
  mkdir -p "$TEST_REPO/tmp"
  echo "debug" > "$TEST_REPO/tmp/debug.log"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when only .playwright-mcp/ files changed" {
  create_llm_classify_mock "YES"
  mkdir -p "$TEST_REPO/.playwright-mcp"
  echo "screenshots" > "$TEST_REPO/.playwright-mcp/screenshot.png"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when only node_modules/ files changed" {
  create_llm_classify_mock "YES"
  mkdir -p "$TEST_REPO/node_modules/foo"
  echo "module" > "$TEST_REPO/node_modules/foo/index.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "outputs block JSON when LLM classifies changes as ready to commit" {
  create_llm_classify_mock "YES"
  echo "updated content" >> "$TEST_REPO/README.md"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("uncommitted changes")'
  echo "$output" | jq -e '.reason | test("README.md")'
}

@test "exits 0 when LLM classifies changes as NOT ready to commit" {
  create_llm_classify_mock "NO"
  echo "updated content" >> "$TEST_REPO/README.md"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when LLM is unreachable (graceful degradation)" {
  create_llm_classify_mock_fail
  echo "updated content" >> "$TEST_REPO/README.md"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lists multiple changed files in block reason" {
  create_llm_classify_mock "YES"
  echo "change1" >> "$TEST_REPO/README.md"
  echo "new file" > "$TEST_REPO/app.rb"
  echo "another" > "$TEST_REPO/lib.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

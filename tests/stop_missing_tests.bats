#!/usr/bin/env bats

setup() {
  export TEST_REPO=$(mktemp -d)
  # Isolate cooldown files per test
  export TMPDIR="$TEST_REPO/tmp"
  mkdir -p "$TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/Stop/stop_missing_tests"

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
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
}

# --- Guards ---

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
  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Should allow (exit 0, no output) ---

@test "allows when only config/docs files changed" {
  echo "updated" >> "$TEST_REPO/README.md"
  echo "config: true" > "$TEST_REPO/config.yml"
  echo '{"key": "value"}' > "$TEST_REPO/settings.json"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only migration files changed" {
  mkdir -p "$TEST_REPO/db/migrate"
  echo "class AddColumn" > "$TEST_REPO/db/migrate/20240101_add_column.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only style/template files changed" {
  echo "body { color: red; }" > "$TEST_REPO/app.css"
  echo "<div>hello</div>" > "$TEST_REPO/index.html"
  echo ".header { font-size: 14px; }" > "$TEST_REPO/styles.scss"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when source + test files both changed" {
  echo "def foo; end" > "$TEST_REPO/app.rb"
  echo "describe" > "$TEST_REPO/app_spec.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when source + test files in test directory both changed" {
  mkdir -p "$TEST_REPO/tests"
  echo "def foo; end" > "$TEST_REPO/app.rb"
  echo "test case" > "$TEST_REPO/tests/test_app.py"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only test files changed" {
  echo "describe" > "$TEST_REPO/app_spec.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only files in excluded dirs changed (scripts/, bin/)" {
  mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/bin"
  echo "script" > "$TEST_REPO/scripts/deploy.rb"
  echo "binary" > "$TEST_REPO/bin/run.sh"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only .github/ files changed" {
  mkdir -p "$TEST_REPO/.github/workflows"
  echo "on: push" > "$TEST_REPO/.github/workflows/ci.yml"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when only config/ directory files changed" {
  mkdir -p "$TEST_REPO/config"
  echo "Rails.application.configure" > "$TEST_REPO/config/application.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows when db/schema.rb changed" {
  mkdir -p "$TEST_REPO/db"
  echo "ActiveRecord::Schema" > "$TEST_REPO/db/schema.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Test file detection patterns ---

@test "detects _test.go as test file" {
  echo "func main()" > "$TEST_REPO/main.go"
  echo "func TestMain()" > "$TEST_REPO/main_test.go"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detects .test.js as test file" {
  echo "export default" > "$TEST_REPO/app.js"
  echo "describe" > "$TEST_REPO/app.test.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detects .spec.ts as test file" {
  echo "export class" > "$TEST_REPO/app.ts"
  echo "it should" > "$TEST_REPO/app.spec.ts"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detects test_*.py as test file" {
  echo "def main():" > "$TEST_REPO/app.py"
  echo "def test_main():" > "$TEST_REPO/test_app.py"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detects __tests__/ directory as test" {
  mkdir -p "$TEST_REPO/__tests__"
  echo "export default" > "$TEST_REPO/app.js"
  echo "test" > "$TEST_REPO/__tests__/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detects spec/ directory as test" {
  mkdir -p "$TEST_REPO/spec/models"
  echo "class User" > "$TEST_REPO/user.rb"
  echo "RSpec.describe" > "$TEST_REPO/spec/models/user_spec.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Should block ---

@test "blocks when source files changed without tests" {
  echo "def foo; end" > "$TEST_REPO/app.rb"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("stop_missing_tests")'
  echo "$output" | jq -e '.reason | test("app.rb")'
  echo "$output" | jq -e '.reason | test("add tests")'
}

@test "blocks when multiple source files changed without tests" {
  echo "class User" > "$TEST_REPO/user.rb"
  echo "class Post" > "$TEST_REPO/post.rb"
  echo "export default" > "$TEST_REPO/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  # Should list the changed files
  echo "$output" | jq -e '.reason | test("user.rb|post.rb|app.js")'
}

@test "blocks for .py source file without tests" {
  echo "def main():" > "$TEST_REPO/main.py"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("main.py")'
}

@test "blocks for .tsx source file without tests" {
  echo "export const App = () => <div/>" > "$TEST_REPO/App.tsx"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("App.tsx")'
}

@test "blocks when source + excluded files changed but no tests" {
  echo "def foo; end" > "$TEST_REPO/app.rb"
  echo "updated" >> "$TEST_REPO/README.md"
  echo "body { color: red; }" > "$TEST_REPO/styles.css"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("app.rb")'
}

@test "truncates file list when more than 5 source files" {
  for i in $(seq 1 7); do
    echo "class C$i" > "$TEST_REPO/file$i.rb"
  done

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("and [0-9]+ more")'
}

# --- Cooldown ---

@test "second block is suppressed by cooldown for same session" {
  echo "def foo; end" > "$TEST_REPO/app.rb"

  # First call should block
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_test_cooldown\", \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'

  # Second call with same session_id should be suppressed
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_test_cooldown\", \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cooldown does not affect different sessions" {
  echo "def foo; end" > "$TEST_REPO/app.rb"

  # Block for session A
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_A\", \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"
  echo "$output" | jq -e '.decision == "block"'

  # Session B should still block
  run bash -c 'echo "{\"stop_hook_active\": false, \"session_id\": \"sess_B\", \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

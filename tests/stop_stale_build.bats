#!/usr/bin/env bats

setup() {
  export TEST_REPO=$(mktemp -d)
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../scripts/Stop/stop_stale_build"

  # Set up a directory with some files
  cd "$TEST_REPO"
  mkdir -p src dist
  echo "source code" > src/app.js
  echo "source style" > src/style.css
}

teardown() {
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
}

@test "exits 0 when stop_hook_active is true (re-entrancy guard)" {
  run bash -c 'echo "{\"stop_hook_active\": true, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when stdin is empty" {
  run "$SCRIPT_PATH" dist/bundle.js < /dev/null

  [ "$status" -eq 0 ]
}

@test "exits 0 when cwd is missing" {
  run bash -c 'echo "{\"stop_hook_active\": false}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when cwd does not exist" {
  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"/nonexistent/path\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when no artifact paths provided" {
  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exits 0 when artifact is up to date" {
  # Create artifact AFTER source files
  sleep 1
  echo "built" > "$TEST_REPO/dist/bundle.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "blocks when artifact is stale (source newer)" {
  # Create artifact first
  echo "built" > "$TEST_REPO/dist/bundle.js"
  sleep 1
  # Then modify source
  echo "updated source" > "$TEST_REPO/src/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("stale")'
  echo "$output" | jq -e '.reason | test("bundle.js")'
}

@test "blocks when artifact does not exist" {
  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.reason | test("not found")'
}

@test "handles multiple artifacts - one stale" {
  # Create both artifacts
  echo "css built" > "$TEST_REPO/dist/style.css"
  echo "js built" > "$TEST_REPO/dist/bundle.js"
  sleep 1
  # Modify source so both are stale
  echo "updated" > "$TEST_REPO/src/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js dist/style.css'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

@test "exits 0 when multiple artifacts all up to date" {
  sleep 1
  echo "js built" > "$TEST_REPO/dist/bundle.js"
  echo "css built" > "$TEST_REPO/dist/style.css"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js dist/style.css'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores files in excluded directories (node_modules, tmp, .git)" {
  # Create artifact
  echo "built" > "$TEST_REPO/dist/bundle.js"
  sleep 1
  # Create newer files in excluded dirs only
  mkdir -p "$TEST_REPO/node_modules/pkg" "$TEST_REPO/tmp" "$TEST_REPO/.git/objects"
  echo "module" > "$TEST_REPO/node_modules/pkg/index.js"
  echo "temp" > "$TEST_REPO/tmp/debug.log"
  echo "obj" > "$TEST_REPO/.git/objects/abc"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "includes modified source file names in reason" {
  echo "built" > "$TEST_REPO/dist/bundle.js"
  sleep 1
  echo "updated" > "$TEST_REPO/src/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' dist/bundle.js'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.reason | test("app.js")'
}

@test "handles absolute artifact paths" {
  echo "built" > "$TEST_REPO/dist/bundle.js"
  sleep 1
  echo "updated" > "$TEST_REPO/src/app.js"

  run bash -c 'echo "{\"stop_hook_active\": false, \"cwd\": \"'"$TEST_REPO"'\"}" | '"$SCRIPT_PATH"' '"$TEST_REPO"'/dist/bundle.js'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
}

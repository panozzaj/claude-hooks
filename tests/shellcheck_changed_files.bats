#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  SCRIPT_PATH="$SCRIPTS_DIR/shellcheck_changed_files"
}

teardown() {
  teardown_test_repo
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: N/A" ]]
}

@test "shows N/A for non-shell files" {
  echo "console.log('hello');" > "app.js"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: N/A" ]]
}

@test "shows green check for clean .sh file" {
  cat > "clean.sh" << 'SCRIPT'
#!/bin/bash
echo "hello world"
SCRIPT

  run "$SCRIPT_PATH" clean.sh

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

@test "shows green check for clean file with bash shebang but no extension" {
  cat > "myscript" << 'SCRIPT'
#!/bin/bash
echo "hello world"
SCRIPT

  run "$SCRIPT_PATH" myscript

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

@test "shows green check for clean file with sh shebang" {
  cat > "myscript" << 'SCRIPT'
#!/bin/sh
echo "hello world"
SCRIPT

  run "$SCRIPT_PATH" myscript

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

@test "exits 2 and shows errors for problematic shell script" {
  cat > "bad.sh" << 'SCRIPT'
#!/bin/bash
echo $UNQUOTED_VAR
SCRIPT

  run "$SCRIPT_PATH" bad.sh

  [ "$status" -eq 2 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "SC2086" ]]
  [[ "$output_stripped" =~ "shellcheck:" ]]
}

@test "handles multiple files" {
  cat > "good.sh" << 'SCRIPT'
#!/bin/bash
echo "hello"
SCRIPT
  cat > "also_good.sh" << 'SCRIPT'
#!/bin/bash
echo "world"
SCRIPT

  run "$SCRIPT_PATH" good.sh also_good.sh

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

@test "respects --verbose flag" {
  cat > "clean.sh" << 'SCRIPT'
#!/bin/bash
echo "hello"
SCRIPT

  run "$SCRIPT_PATH" --verbose clean.sh

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed shell files detected:" ]]
  [[ "$output_stripped" =~ "clean.sh" ]]
}

@test "shows N/A for nonexistent files" {
  run "$SCRIPT_PATH" nonexistent.sh

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: N/A" ]]
}

@test "detects .bash extension" {
  cat > "script.bash" << 'SCRIPT'
#!/bin/bash
echo "hello"
SCRIPT

  run "$SCRIPT_PATH" script.bash

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

@test "reads file_path from STDIN JSON (hook mode)" {
  cat > "hook_test.sh" << 'SCRIPT'
#!/bin/bash
echo "hello"
SCRIPT

  run bash -c 'echo "{\"tool_input\": {\"file_path\": \"hook_test.sh\"}}" | "$1"' _ "$SCRIPT_PATH"

  [ "$status" -eq 0 ]
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "shellcheck: ✓" ]]
}

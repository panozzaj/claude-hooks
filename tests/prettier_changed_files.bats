#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_repo

  # Store path to the script being tested
  SCRIPT_PATH="$SCRIPTS_DIR/prettier_changed_files"

  # Create mock prettier command in node_modules/.bin (where the script looks first)
  MOCK_DIR="$TEST_REPO/node_modules/.bin"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

# Helper to create a mock prettier that simulates real prettier behavior
# Args: $1 = exit_code, $2 = should_format (true/false)
create_prettier_mock() {
  local exit_code=$1
  local should_format=$2

  # Create the actual prettier mock that simulates prettier's behavior
  cat > "$MOCK_DIR/prettier" << 'EOF'
#!/bin/bash
# Simulate prettier behavior:
# - Without --write: output formatted content to stdout
# - With --write: modify file in place, output "file.js Xms"

if [[ "$*" =~ "--write" ]]; then
  # --write mode: modify files and output summary
  for file in "$@"; do
    if [[ "$file" != "--write" && -f "$file" ]]; then
      if [ "$SHOULD_FORMAT" = "true" ]; then
        # Simulate formatting by adding spaces
        sed -i.bak "s/console\.log('\([^']*\)');/console.log( '\1' );/" "$file" 2>/dev/null || true
      fi
      echo "$file 15ms"
    fi
  done
else
  # Default mode: output formatted content to stdout
  for file in "$@"; do
    if [ -f "$file" ]; then
      if [ "$SHOULD_FORMAT" = "true" ]; then
        # Output formatted version
        sed "s/console\.log('\([^']*\)');/console.log( '\1' );/" "$file"
      else
        # Output unchanged (file is already formatted)
        cat "$file"
      fi
    fi
  done
fi
exit $EXIT_CODE
EOF

  # Pass variables to the mock
  sed -i.bak "s/\$SHOULD_FORMAT/$should_format/" "$MOCK_DIR/prettier"
  sed -i.bak "s/\$EXIT_CODE/$exit_code/" "$MOCK_DIR/prettier"
  chmod +x "$MOCK_DIR/prettier"
}

@test "shows N/A when called with no file arguments" {
  run "$SCRIPT_PATH"

  [ "$status" -eq 0 ]

  # Should show N/A since no files provided
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: N/A" ]]
}

@test "shows only green check when no formatting changes needed" {
  # Create already-formatted file
  mkdir -p app
  echo "console.log('test');" > "app.js"

  # Mock prettier to return success with no formatting needed (exit 0, should_format=false)
  create_prettier_mock 0 false

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Should only show the green check
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: ✓" ]]
}

@test "shows output and green check when files formatted" {
  # Create file with unformatted content
  echo "console.log('test');" > "app.js"

  # Mock prettier with formatting needed (exit 0, should_format=true)
  create_prettier_mock 0 true

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Should show the formatted files output and the diff
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Prettier reformatted" ]]
  [[ "$output_stripped" =~ "app.js" ]]
  [[ "$output_stripped" =~ "prettier: ✓" ]]
}

@test "exits 2 and shows output when formatting errors found" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Mock prettier to return failure with syntax error
  cat > "$MOCK_DIR/prettier" << 'EOF'
#!/bin/bash
echo "[error] app.js: SyntaxError: Unexpected token (1:5)" >&2
exit 1
EOF
  chmod +x "$MOCK_DIR/prettier"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 2 ]

  # Should show output on stderr
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "SyntaxError" ]]
  [[ "$output_stripped" =~ "prettier: ✗" ]]
}

@test "respects --verbose flag and shows file detection info" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Mock prettier to return success (no formatting needed)
  create_prettier_mock 0 false

  run "$SCRIPT_PATH" --verbose app.js

  [ "$status" -eq 0 ]

  # In verbose mode, should show the file detection info
  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" =~ "Changed files detected:" ]]
}

@test "handles multiple files passed as arguments" {
  # Create multiple files
  echo "console.log('user');" > "user.js"
  echo "body { margin: 0; }" > "style.css"

  # Mock prettier to return success (no formatting needed)
  create_prettier_mock 0 false

  run "$SCRIPT_PATH" user.js style.css

  [ "$status" -eq 0 ]

  output_stripped=$(echo "$output" | strip_colors)
  [[ "$output_stripped" == "prettier: ✓" ]]
}

@test "passes --write flag to prettier" {
  # Create file
  echo "console.log('test');" > "app.js"

  # Create a mock that records arguments and simulates formatting
  cat > "$MOCK_DIR/prettier" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "--write" ]]; then
  echo "prettier called with: $@" > /tmp/prettier_args.txt
  echo "app.js 15ms"
  exit 0
else
  # Output formatted version (different from original)
  echo "console.log( 'test' );"
  exit 0
fi
EOF
  chmod +x "$MOCK_DIR/prettier"

  run "$SCRIPT_PATH" app.js

  [ "$status" -eq 0 ]

  # Check that --write was passed
  [ -f /tmp/prettier_args.txt ]
  args=$(cat /tmp/prettier_args.txt)
  [[ "$args" =~ "--write" ]]

  rm -f /tmp/prettier_args.txt
}

@test "formats multiple file types (js, css, json, yml, md)" {
  # Create files of different types
  echo "console.log('test');" > "app.js"
  echo "body { margin: 0; }" > "styles.css"
  echo '{"key": "value"}' > "config.json"
  echo "key: value" > "config.yml"
  echo "# Title" > "README.md"

  # Mock prettier (no formatting needed)
  create_prettier_mock 0 false

  run "$SCRIPT_PATH" app.js styles.css config.json config.yml README.md

  [ "$status" -eq 0 ]
}

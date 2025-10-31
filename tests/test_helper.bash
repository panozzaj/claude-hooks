#!/bin/bash
# Test helper functions for bats tests

# Path to the scripts being tested (relative to tests directory)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/PostToolUse" && pwd)"

# Create a temporary git repository for testing
setup_test_repo() {
  export TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init --initial-branch=main > /dev/null 2>&1
  git config user.email "test@example.com"
  git config user.name "Test User"
}

# Clean up test repository
teardown_test_repo() {
  if [ -n "$TEST_REPO" ] && [ -d "$TEST_REPO" ]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
}

# Create a mock command that records its invocation
create_mock() {
  local command_name=$1
  local exit_code=${2:-0}
  local output_file=${3:-}

  local mock_dir="$TEST_REPO/.mocks"
  mkdir -p "$mock_dir"

  local mock_script="$mock_dir/$command_name"
  cat > "$mock_script" << 'EOF'
#!/bin/bash
# Record invocation
echo "$@" >> "$MOCK_INVOCATIONS"

# Output from file if specified
if [ -n "$MOCK_OUTPUT_FILE" ] && [ -f "$MOCK_OUTPUT_FILE" ]; then
  cat "$MOCK_OUTPUT_FILE"
fi

exit $MOCK_EXIT_CODE
EOF
  chmod +x "$mock_script"

  # Set up environment for this mock
  export MOCK_EXIT_CODE=$exit_code
  export MOCK_INVOCATIONS="$mock_dir/${command_name}.invocations"
  export MOCK_OUTPUT_FILE="$output_file"

  # Prepend mock directory to PATH
  export PATH="$mock_dir:$PATH"

  echo "$mock_script"
}

# Get number of times a mock was invoked
mock_invocation_count() {
  local command_name=$1
  local invocation_file="$TEST_REPO/.mocks/${command_name}.invocations"

  if [ -f "$invocation_file" ]; then
    wc -l < "$invocation_file" | tr -d ' '
  else
    echo "0"
  fi
}

# Get the arguments passed to a mock on a specific invocation (1-indexed)
mock_invocation_args() {
  local command_name=$1
  local invocation_number=$2
  local invocation_file="$TEST_REPO/.mocks/${command_name}.invocations"

  if [ -f "$invocation_file" ]; then
    sed -n "${invocation_number}p" "$invocation_file"
  fi
}

# Create a test file and mark it as changed in git
create_changed_file() {
  local filepath=$1
  local content=${2:-"# test content"}

  mkdir -p "$(dirname "$filepath")"
  echo "$content" > "$filepath"
  git add "$filepath"
  git commit -m "Add $filepath" > /dev/null 2>&1

  # Now modify it to make it show up in git diff
  echo "$content" >> "$filepath"
}

# Helper to strip ANSI color codes from output
strip_colors() {
  sed 's/\x1b\[[0-9;]*m//g'
}

#!/bin/bash
# Common boilerplate for PostToolUse hook scripts.
#
# Usage: at the top of each hook, set HOOK_NAME and FILE_PATTERN, then source this file:
#
#   set -e
#   HOOK_NAME="eslint"
#   FILE_PATTERN='\.(js|jsx|ts|tsx)$'
#   SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPTS_DIR/hook_common.bash"
#
# After sourcing, these variables are available:
#   CHANGED_FILES  - space-separated list of matching files (non-empty, or script already exited)
#   VERBOSE        - "true" if -v/--verbose was passed
#   SHOW_TIME      - "true" if --time was passed
#   FILES_ARG      - array of non-flag arguments
#
# These functions are available:
#   elapsed_suffix - returns " 123ms" string if --time, empty otherwise
#   hook_status    - prints "toolname: ✓/✗/N/A [time]" and exits
#
# These color variables are available:
#   GREEN, RED, GRAY, NC

_HOOK_START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Parse flags
VERBOSE=false
SHOW_TIME=false
FILES_ARG=()
for arg in "$@"; do
  if [ "$arg" = "-v" ] || [ "$arg" = "--verbose" ]; then
    VERBOSE=true
  elif [ "$arg" = "--time" ]; then
    SHOW_TIME=true
  else
    FILES_ARG+=("$arg")
  fi
done

elapsed_suffix() {
  if [ "$SHOW_TIME" = true ]; then
    local end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    echo " $((end_ms - _HOOK_START_MS))ms"
  fi
}

# Print status line and exit.
# Usage: hook_status pass|fail|na [message]
#   hook_status pass        -> "eslint: ✓ [time]"  exit 0
#   hook_status fail        -> "eslint: ✗ [time]"  exit 2 (to stderr)
#   hook_status na          -> "eslint: N/A [time]" exit 0
#   hook_status na "reason" -> "eslint: N/A (reason) [time]" exit 0
hook_status() {
  local status=$1
  local message=${2:-}

  case "$status" in
    pass)
      echo -e "${HOOK_NAME}: ${GREEN}✓${NC}$(elapsed_suffix)"
      exit 0
      ;;
    fail)
      echo -e "${HOOK_NAME}: ${RED}✗${NC}$(elapsed_suffix)" >&2
      exit 2
      ;;
    na)
      if [ -n "$message" ]; then
        echo -e "${HOOK_NAME}: ${GRAY}N/A (${message})${NC}$(elapsed_suffix)"
      else
        echo -e "${HOOK_NAME}: ${GRAY}N/A${NC}$(elapsed_suffix)"
      fi
      exit 0
      ;;
  esac
}

# --- Determine file to check ---

CHANGED_FILES=""

if [ ${#FILES_ARG[@]} -gt 0 ]; then
  CHANGED_FILES="${FILES_ARG[*]}"
else
  # Hook mode: read JSON from STDIN
  if [ ! -t 0 ]; then
    HOOK_JSON=$(cat)

    FILE_PATH=$(echo "$HOOK_JSON" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)

    if [ -z "$FILE_PATH" ]; then
      FILE_PATH=$(echo "$HOOK_JSON" | grep -o '"filePath"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"filePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
    fi

    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" =~ $FILE_PATTERN ]]; then
      CHANGED_FILES="$FILE_PATH"
    fi
  fi
fi

if [ -z "$CHANGED_FILES" ]; then
  hook_status na
fi

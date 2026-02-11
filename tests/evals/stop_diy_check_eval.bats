#!/usr/bin/env bats
#
# Eval tests for stop_diy_check: pre-filter + LLM prompt.
#
# These tests call the REAL llm_classify (requires ollama running with gemma3:4b).
# They are non-deterministic but should pass reliably with temperature 0.
#
# Run with: ./tests/run-evals
# Do NOT include in ./tests/run-tests (unit tests only).

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../scripts"
STOP_DIY_CHECK="$SCRIPT_DIR/Stop/stop_diy_check"
LLM_CLASSIFY="$SCRIPT_DIR/common/llm_classify"

# The system prompt from stop_diy_check (keep in sync)
read -r -d '' SYSTEM_PROMPT << 'PROMPT_EOF' || true
You are classifying whether an AI assistant message is telling the USER to go perform an action that the AI could do itself.

Answer YES: <action> ONLY if the message contains an explicit instruction directed at the user to perform a task (e.g. "you need to run X", "please restart Y", "run this command").

Answer NO if:
- The AI is describing work IT already completed ("I fixed X", "the typo has been corrected")
- The AI is narrating what IT will do next ("let me verify", "now I will run")
- The AI is summarizing results ("all tests pass", "clean compile")
- The AI is describing the state of things without asking the user to act

Respond ONLY with YES: <action> or NO.
PROMPT_EOF

setup() {
  if ! command -v llm &> /dev/null; then
    skip "llm CLI not installed"
  fi
  export FIXTURES_DIR="$BATS_TEST_DIRNAME/../fixtures"
  export TMPDIR
  TMPDIR=$(mktemp -d)
}

teardown() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}

# --- Helpers: LLM-only classification ---

classify() {
  echo "$1" | "$LLM_CLASSIFY" --system "$SYSTEM_PROMPT" 2>/dev/null || true
}

assert_llm_yes() {
  local result
  result=$(classify "$1")
  if [[ ! "$result" =~ ^YES ]]; then
    echo "Expected YES but got: $result"
    echo "Input: $1"
    return 1
  fi
}

assert_llm_no() {
  local result
  result=$(classify "$1")
  if [[ ! "$result" =~ ^NO ]]; then
    echo "Expected NO but got: $result"
    echo "Input: $1"
    return 1
  fi
}

# --- Helpers: full-script (pre-filter + LLM) classification ---

make_transcript() {
  local text="$1"
  local file="$TMPDIR/transcript.jsonl"
  # Escape text for JSON
  local escaped
  escaped=$(echo "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
  cat > "$file" << EOF
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"test"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":${escaped}}]}}
EOF
  echo "$file"
}

run_full_script() {
  local transcript
  transcript=$(make_transcript "$1")
  echo "{\"stop_hook_active\": false, \"transcript_path\": \"$transcript\"}" | "$STOP_DIY_CHECK"
}

assert_script_blocks() {
  local output
  output=$(run_full_script "$1")
  if ! echo "$output" | jq -e '.decision == "block"' > /dev/null 2>&1; then
    echo "Expected block but got: $output"
    echo "Input: $1"
    return 1
  fi
}

assert_script_allows() {
  local output
  output=$(run_full_script "$1")
  if [ -n "$output" ]; then
    echo "Expected no output (allow) but got: $output"
    echo "Input: $1"
    return 1
  fi
}

# ============================================================
# LLM prompt evals: YES cases (should block)
# ============================================================

@test "LLM YES: explicit 'you need to restart'" {
  assert_llm_yes "I've updated the server configuration file. Now you need to restart the server by running fireup restart to apply the changes."
}

@test "LLM YES: 'run the database migrations'" {
  assert_llm_yes "You'll need to run the database migrations with rails db:migrate and then restart the server."
}

@test "LLM YES: 'Use /reload'" {
  assert_llm_yes "Use /reload to pick up the new Claude Code hooks."
}

@test "LLM YES: 'Please run bundle exec'" {
  assert_llm_yes "Please run bundle exec rails db:migrate to apply the migration."
}

@test "LLM YES: 'You should restart'" {
  assert_llm_yes "You should restart the development server to pick up the config changes."
}

@test "LLM YES: 'restart the app with fireup'" {
  assert_llm_yes "After that, restart the app with fireup restart and check the logs."
}

# ============================================================
# LLM prompt evals: NO cases (completed work, narration, summaries)
# ============================================================

@test "LLM NO: clean compile summary" {
  assert_llm_no "Clean compile. The TUI dashboard changes (active-only sidebar, help popup, new session launching, tmux pane switching) and the hooks setup are all in good shape."
}

@test "LLM NO: fixed a typo" {
  assert_llm_no "I've fixed the typo in the README. The word 'recieve' has been corrected to 'receive'."
}

@test "LLM NO: narrating next step ('let me verify')" {
  assert_llm_no "Now let me verify the latest code changes compile. That was pending from before the hooks setup."
}

@test "LLM NO: all tests pass" {
  assert_llm_no "All 161 tests pass. The implementation is complete."
}

@test "LLM NO: ran tests and they pass" {
  assert_llm_no "I ran the tests and they all pass. The feature is working correctly."
}

@test "LLM NO: committed changes" {
  assert_llm_no "Done! I've committed all the changes in two atomic commits."
}

@test "LLM NO: build succeeded summary" {
  assert_llm_no "The build succeeded with no warnings. Here's a summary of what changed:"
}

# ============================================================
# Full-script evals: pre-filter catches testing/verification
# (These would fail as LLM-only but pass with the pre-filter)
# ============================================================

@test "SCRIPT ALLOWS: asking user to test with keyboard shortcut" {
  assert_script_allows "App is up (1.7s rebuild). Now please test — record a short phrase with Alt+X (stream mode OFF), then I'll check the logs to see how many times stop_recording and paste are called."
}

@test "SCRIPT ALLOWS: asking user to try it out" {
  assert_script_allows "The feature is implemented. Try it out and let me know if the behavior matches what you expected."
}

@test "SCRIPT ALLOWS: asking user to verify UI" {
  assert_script_allows "I've updated the CSS. Can you check if the sidebar looks correct on your screen?"
}

# ============================================================
# Full-script evals: YES cases still block through full pipeline
# ============================================================

@test "SCRIPT BLOCKS: 'you need to restart the server'" {
  assert_script_blocks "I've updated the server configuration file. Now you need to restart the server by running fireup restart to apply the changes."
}

@test "SCRIPT BLOCKS: 'run the database migrations'" {
  assert_script_blocks "You'll need to run the database migrations with rails db:migrate and then restart the server."
}

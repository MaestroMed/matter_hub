#!/usr/bin/env bash
# mind-iterate.sh — one autonomous MIND iteration.
#
# Designed to be invoked by launchd / cron / a /loop session. Runs the
# `mind-iterator` agent via the Claude Code CLI in headless mode,
# captures its output, and appends a one-line summary to
# mind/MIND_CRON_LOG.md.
#
# Usage:
#   ./mind-iterate.sh            # one iteration
#
# Environment:
#   ANTHROPIC_API_KEY    must be set in the parent shell or in
#                        ~/.claude/.env so the CLI can authenticate
#
# Exit codes:
#   0 — iteration completed (shipped or cleanly blocked)
#   1 — CLI invocation failed
#   2 — repo state unexpected

set -euo pipefail

REPO="/Users/mehdinafaa/Developer/matter_hub"
LOG="$REPO/mind/MIND_CRON_LOG.md"
TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"

cd "$REPO"

# Sanity: must be on the iteration branch.
BRANCH="$(git rev-parse --abbrev-ref HEAD || echo unknown)"
if [ "$BRANCH" != "claude/new-iphone-project-YFDF7" ]; then
    echo "$TS  ❌ wrong branch: $BRANCH" >> "$LOG"
    exit 2
fi

# Prompt for the headless CLI invocation. The agent reads its own
# operating manual at .claude/agents/mind-iterator.md.
PROMPT='Run one MIND iteration following the manual at
.claude/agents/mind-iterator.md. Pick the lowest-numbered ⏳ version
in mind/ULTRAPLAN.md, implement, test, build, vision-verify, commit,
push, mark ✅. Report the result.'

# Output capture.
OUT="$(mktemp -t mind-iter.XXXXXX)"
trap 'rm -f "$OUT"' EXIT

# Headless run. `claude --print` runs non-interactively, prints once,
# exits. `--dangerously-skip-permissions` (or `-p` if Mehdi prefers
# explicit approval) lets the agent run shell/edit/write without
# blocking on each tool call.
if command -v claude >/dev/null 2>&1; then
    claude \
        --print \
        --dangerously-skip-permissions \
        "$PROMPT" > "$OUT" 2>&1 || true
else
    echo "$TS  ❌ claude CLI not on PATH" >> "$LOG"
    exit 1
fi

# Extract a one-line summary from the agent output. The mind-iterator
# manual specifies that the final line of its report starts with
# "Status:".
STATUS="$(grep -E '^\s*Status:' "$OUT" | tail -1 | sed 's/^\s*//' || echo 'Status: no report')"
COMMIT="$(git log -1 --pretty=format:'%h %s')"

printf '%s  %s  (HEAD: %s)\n' "$TS" "$STATUS" "$COMMIT" >> "$LOG"
echo "$TS  $STATUS"

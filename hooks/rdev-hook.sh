#!/usr/bin/env bash
# Claude Code hook for remote-dev projects (those with .remote-dev.toml).
#   rdev-hook.sh session  — SessionStart: run `rdev up --quiet`, inject real status + workflow rules
#   rdev-hook.sh prompt   — UserPromptSubmit: local-only check (sync state, uncollected jobs); silent when healthy
#   rdev-hook.sh guard    — PreToolUse(Bash): deny direct ssh/scp/sftp to the dev host
# Optional 2nd arg: claude (default) | codex. Codex started by Claude Code (codex plugin) inherits
# CLAUDECODE / CODEX_COMPANION_SESSION_ID; it is a delegated editor: no rdev, no status checks.
input=$(cat)
delegated=0
[[ ${2:-claude} == codex && -n ${CLAUDECODE:-}${CODEX_COMPANION_SESSION_ID:-} ]] && delegated=1
cwd=$(jq -r '.cwd // empty' <<<"$input"); cwd=${cwd:-$PWD}

root=""; d=$cwd
while [[ $d != / && -n $d ]]; do
  [[ -f $d/.remote-dev.toml ]] && { root=$d; break; }
  d=$(dirname "$d")
done
[[ -n $root ]] || exit 0
cfg() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"#[:space:]]*).*/\1/p" "$root/.remote-dev.toml" | head -1; }
host=$(cfg host); session=$(cfg mutagen)
name=$(cfg name); name=${name:-$(basename "$root")}; name=$(tr 'A-Z' 'a-z' <<<"$name" | tr -c 'a-z0-9_\n-' '-')
RDEV=$(command -v rdev 2>/dev/null || echo "$HOME/.local/bin/rdev")
tmo() { local s=$1; shift; perl -e '$t = shift; alarm $t; exec @ARGV; exit 127' "$s" "$@"; }
ctx() { jq -n --arg e "$1" --arg m "$2" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$m}}'; }

case $1 in
  session)
    if ((delegated)); then
      ctx SessionStart "This is a remote-dev project ($root, server $host) and you were started by Claude Code as a delegated agent. Edit code locally only (mutagen syncs it). Do NOT run rdev, mutagen, herdr, ssh/scp, or git write operations; Claude Code runs server-side builds/tests and Git, so report what should be verified instead."
      exit 0
    fi
    status=$(cd "$root" && tmo 15 "$RDEV" up --quiet 2>&1) || status="${status:-rdev up timed out (network?)} — remote commands may fail until it recovers; re-run: rdev up"
    ctx SessionStart "This is a remote-dev project ($root, server $host). Load the remote-dev skill. Rules: edit files locally (mutagen syncs them); run every server-side command with rdev '<cmd>'; Git is local only (never on the server); agents you delegate to (e.g. Codex via the codex plugin) only edit code locally; never ssh to $host directly.
Current status (rdev up):
$status"
    ;;
  prompt)
    ((delegated)) && exit 0
    msgs=()
    list=$(tmo 5 mutagen sync list "$session" 2>/dev/null)
    st=$(sed -n 's/^Status: //p' <<<"$list" | head -1)
    case $st in
      "") msgs+=("mutagen session '$session' not readable — run: rdev up") ;;
      Disconnected*|Connecting*|*Paused*|Halted*) msgs+=("sync is not connected (status: $st); local edits are queued and remote commands will fail fast until it reconnects — check with: rdev up") ;;
    esac
    grep -q '^Conflicts:' <<<"$list" && msgs+=("mutagen has sync conflicts — resolve before running remote commands (mutagen sync list $session)")
    jobs=$(awk -F'\t' '$2=="running"{printf "%s (%s); ", $1, $3}' "$HOME/.cache/rdev/$name.jobs" 2>/dev/null)
    [[ -n $jobs ]] && msgs+=("uncollected rdev jobs: ${jobs%; } — collect with rdev --wait <token> (do not re-run them blindly)")
    ((${#msgs[@]})) && ctx UserPromptSubmit "remote-dev: $(printf '%s\n' "${msgs[@]}")"
    ;;
  guard)
    [[ -n $host ]] || exit 0
    cmd=$(jq -r '.tool_input.command // empty | if type == "array" then join("; ") else . end' <<<"$input")
    if ((delegated)) && grep -qE "(^|[;&|\(\`])[[:space:]]*([^[:space:];&|]*/)?(rdev|mutagen|herdr)([[:space:]]|$)" <<<"$cmd"; then
      jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"You were started by Claude Code as a delegated agent in a remote-dev project: edit code locally only. Do not run rdev/mutagen/herdr; Claude Code runs server-side commands. Report what needs verifying instead."}}'
      exit 0
    fi
    if grep -qE "(^|[;&|\(])[[:space:]]*(ssh|scp|sftp)([[:space:]][^;&|]*)?[[:space:]@]${host}([[:space:]:]|$)" <<<"$cmd"; then
      jq -n --arg r "Direct ssh/scp to $host is disabled in this remote-dev project. Use: rdev '<cmd>' (runs in the persistent herdr pane after a mutagen flush). Files are synced by mutagen, so edit locally instead of copying." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    fi
    ;;
esac
exit 0

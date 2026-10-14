#!/usr/bin/env bash
# Feed each line of guard-cases.txt to the PreToolUse guard of hooks/rdev-hook.sh.
# Lines before "#EXPECT-DENY" must be allowed, lines after it must be denied.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../hooks/rdev-hook.sh"
proj=$(mktemp -d); trap 'rm -rf "$proj"' EXIT
printf 'host = "devbox"\nmachine = "devbox"\nremote_path = "/srv/myproj"\nmutagen = "myproj"\n' >"$proj/.remote-dev.toml"

expect=allow fail=0 n=0
while IFS= read -r line; do
  [[ -z $line ]] && continue
  [[ $line == "#EXPECT-DENY" ]] && { expect=deny; continue; }
  out=$(jq -n --arg c "$line" --arg d "$proj" '{cwd:$d, tool_input:{command:$c}}' |
    env -u CLAUDECODE -u CODEX_COMPANION_SESSION_ID bash "$hook" guard)
  got=allow; [[ $(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null) == deny ]] && got=deny
  n=$((n + 1))
  [[ $got == "$expect" ]] || { echo "FAIL ($expect, got $got): $line"; fail=1; }
done <"$here/guard-cases.txt"
((fail)) || echo "ok: $n guard cases"
exit $fail

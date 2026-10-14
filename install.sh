#!/usr/bin/env bash
# Install agent-over-ssh by symlinking it into place (re-run safely; existing files not managed by it are left alone).
#   ./install.sh            bin -> ~/.local/bin, skill -> ~/.claude/skills and ~/.codex/skills (if present)
#   BIN_DIR=/usr/local/bin ./install.sh
# Hooks are not wired automatically: the script prints the JSON to merge into your settings.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}

link() { # link SRC DEST
  local src=$1 dest=$2
  if [[ -L $dest && $(readlink "$dest") == "$src" ]]; then echo "ok       $dest"; return; fi
  if [[ -e $dest || -L $dest ]]; then echo "skipped  $dest (exists; move it away to let agent-over-ssh manage it)"; return; fi
  mkdir -p "$(dirname "$dest")"; ln -s "$src" "$dest"; echo "linked   $dest -> $src"
}

for t in jq perl ssh mutagen herdr; do command -v "$t" >/dev/null || echo "warning: '$t' not found on PATH"; done

link "$repo/bin/rdev" "$BIN_DIR/rdev"
link "$repo/bin/remote-dev-init" "$BIN_DIR/remote-dev-init"
link "$repo/skills/remote-dev" "$HOME/.claude/skills/remote-dev"
[[ -d $HOME/.codex ]] && link "$repo/skills/remote-dev" "$HOME/.codex/skills/remote-dev"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: add $BIN_DIR to your PATH" ;; esac

hook="$repo/hooks/rdev-hook.sh"
cat <<MSG

Next: wire the hooks (merge into the existing "hooks" object).
  Claude Code (~/.claude/settings.json): see examples/claude-settings.hooks.json
  Codex (~/.codex/hooks.json):           see examples/codex-hooks.json
Use this hook path in both: $hook
MSG

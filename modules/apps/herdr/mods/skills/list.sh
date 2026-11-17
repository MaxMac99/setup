#!/bin/sh
# Every skill Claude Code loads, one per line: source <TAB> name <TAB> description <TAB> SKILL.md.
# ~/.claude/skills (a nix symlinkJoin: Anthropic's collection plus our own) and
# the skills of enabled plugins. A name already listed is skipped.

front() { # name and description from a SKILL.md's frontmatter; folded descriptions joined
  awk '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && /^name:/ { sub(/^name:[ \t]*/, ""); name = $0; folding = 0; next }
    inside && /^description:/ {
      sub(/^description:[ \t]*/, ""); desc = $0; folding = (desc == ">" || desc == "|" || desc == ">-" || desc == "|-")
      if (folding) desc = ""; next }
    inside && folding && /^[ \t]/ { sub(/^[ \t]+/, ""); desc = desc (desc == "" ? "" : " ") $0; next }
    inside { folding = 0 }
    END { gsub(/\t/, " ", desc); printf "%s\t%s", name, desc }
  ' "$1"
}

seen=" "
emit() { # source, SKILL.md
  line=$(front "$2")
  name=${line%%"	"*}
  [ -n "$name" ] || name=$(basename "$(dirname "$2")")
  case "$seen" in *" $name "*) return ;; esac
  seen="$seen$name "
  printf '%s\t%s\t%s\n' "$1" "$line" "$2"
}

for f in "$HOME"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$(readlink -f "$(dirname "$f")")" in
    *-claude-skills/*) src="Anthropic" ;;
    *-source/skills/*) src="Plugins" ;;
    *) src="Eigene" ;;
  esac
  emit "$src" "$f"
done

# Enabled plugins' own skills.
settings="$HOME/.claude/settings.json" installed="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$settings" ] && [ -f "$installed" ] && command -v jq >/dev/null; then
  jq -r --slurpfile s "$settings" '
    (.plugins // .) | to_entries[]
    | select($s[0].enabledPlugins[.key] == true)
    | (.value | if type == "array" then .[0] else . end).installPath' "$installed" |
  while IFS= read -r dir; do
    for f in "$dir"/skills/*/SKILL.md; do [ -f "$f" ] && emit "Plugins" "$f"; done
  done
fi

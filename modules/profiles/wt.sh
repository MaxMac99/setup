# wt - worktree helper.
#
# Layout convention (agents MUST follow this too):
#   ~/projects/<repo>/            standard clone, the daily IDE window
#   ~/projects/<repo>/.work/<repo>-<branch>/   one worktree per workstream
#
# direnv auto-allows everything under ~/projects, so a fresh worktree needs
# no `direnv allow`; nix-direnv provides the environment on first `cd`.

set -euo pipefail

PROJECTS_ROOT="${WT_PROJECTS_ROOT:-$HOME/projects}"

usage() {
	cat <<'EOF'
usage:
  wt new [repo] <branch> [base]   worktree at <repo>/.work/<repo>-<branch>
  wt list [repo]                  worktrees with branch and dirty state
  wt prune [repo] [-y]            remove worktrees whose branch is merged

<repo> is optional: with no argument the current directory's repo is used
(linked worktrees resolve to their main checkout). A repo may be given as a
full path or as a name to look up under ~/projects (override with
WT_PROJECTS_ROOT).
EOF
}

die() {
	echo "wt: $*" >&2
	exit 1
}

is_repo() {
	[ -e "$1/.git" ]
}

# find_repo <name> - resolve a repo name to a directory under PROJECTS_ROOT.
find_repo() {
	local repo="$1" matches match
	if is_repo "$PROJECTS_ROOT/$repo"; then
		printf '%s\n' "$PROJECTS_ROOT/$repo"
		return 0
	fi
	# Read everything before picking the first line: `head -n 1` would close
	# the pipe early and fail the pipeline under `set -o pipefail`.
	matches="$(find "$PROJECTS_ROOT" -maxdepth 2 -type d -name "$repo" 2>/dev/null | while IFS= read -r d; do
		if is_repo "$d"; then
			printf '%s\n' "$d"
		fi
	done)"
	match="${matches%%$'\n'*}"
	if [ -n "$match" ]; then
		printf '%s\n' "$match"
	else
		die "no repo '$repo' under $PROJECTS_ROOT"
	fi
}

# resolve_target [repo] - print the repo directory to operate on.
#   no argument    the repo containing $PWD; die if cwd is not inside a git
#                  repo. A linked worktree resolves to its main checkout so
#                  .work/ and the worktree name anchor on the primary clone.
#   path argument  used as-is (must be a git repo).
#   bare name      looked up under PROJECTS_ROOT via find_repo.
resolve_target() {
	local target="${1:-}" top common main
	if [ -z "$target" ]; then
		top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" ||
			die "not inside a git repo (run from a repo checkout, or pass a repo name/path)"
		common="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
			common="$(git -C "$top" rev-parse --git-common-dir)"
		main="$(dirname "$common")"
		# Normal-clone convention puts the main checkout at the common dir's
		# parent; if that is not a repo, fall back to the cwd toplevel.
		if is_repo "$main"; then
			printf '%s\n' "$main"
		else
			printf '%s\n' "$top"
		fi
		return 0
	fi
	case "$target" in
	*/*)
		is_repo "$target" || die "not a git repo: $target"
		printf '%s\n' "$target"
		;;
	*) find_repo "$target" ;;
	esac
}

# worktree_branches <repo_dir> - print "<worktree_path>\t<branch>" for every
# linked worktree. The primary worktree is always the first porcelain entry;
# skip it there rather than by path comparison (symlinked roots like
# /var -> /private/var make the paths disagree).
worktree_branches() {
	local repo_dir="$1"
	git -C "$repo_dir" worktree list --porcelain | awk '
		/^worktree / { n++; if (n > 1) path = substr($0, 10) }
		/^branch /   { if (n > 1) print path "\t" substr($0, 8) }
	' | while IFS=$'\t' read -r wt branch; do
		if [ "$wt" != "$repo_dir" ]; then
			printf '%s\t%s\n' "$wt" "${branch#refs/heads/}"
		fi
	done
}

cmd_new() {
	local repo="" branch="" base=""
	case $# in
	1) branch="$1" ;;
	2) repo="$1" branch="$2" ;;
	3) repo="$1" branch="$2" base="$3" ;;
	*) usage >&2
		exit 1 ;;
	esac
	local repo_dir wt_dir wt_name
	repo_dir="$(resolve_target "$repo")"
	wt_name="$(basename "$repo_dir")-$(printf '%s' "$branch" | tr '/ ' '--')"
	wt_dir="$repo_dir/.work/$wt_name"

	mkdir -p "$repo_dir/.work"
	# Git's progress chatter goes to stderr so `$(wt new …)` yields only the path.
	if [ -n "${base:-}" ]; then
		git -C "$repo_dir" worktree add -b "$branch" "$wt_dir" "$base" 1>&2
	elif git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$repo_dir" worktree add "$wt_dir" "$branch" 1>&2
	else
		git -C "$repo_dir" worktree add -b "$branch" "$wt_dir" 1>&2
	fi

	# Best-effort prewarm; never fatal.
	if [ -f "$wt_dir/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
		(cd "$wt_dir" && cargo fetch) >/dev/null 2>&1 || true
	fi

	echo "$wt_dir"
}

cmd_list() {
	local target="${1:-}"
	local repos repo_dir wt branch dirty
	repos="$(resolve_target "$target")"
	while IFS= read -r repo_dir; do
		[ -n "$repo_dir" ] || continue
		while IFS=$'\t' read -r wt branch; do
			dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
			printf '%s\t%s\t%s%s\n' "$(basename "$repo_dir")" "$(basename "$wt")" "${branch:-detached}" \
				"$([ "$dirty" -gt 0 ] && printf ' (%s dirty)' "$dirty")"
		done < <(worktree_branches "$repo_dir")
	done <<<"$repos"
}

default_base() {
	local repo_dir="$1" base
	for base in main master; do
		if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$base"; then
			printf '%s\n' "$base"
			return 0
		fi
	done
	printf '%s\n' "$(git -C "$repo_dir" branch --show-current)"
}

cmd_prune() {
	local assume_no=false target=""
	local arg
	for arg in "$@"; do
		case "$arg" in
		-y) assume_no=true ;;
		*) target="$arg" ;;
		esac
	done

	local repos repo_dir wt branch base
	repos="$(resolve_target "$target")"
	while IFS= read -r repo_dir; do
		[ -n "$repo_dir" ] || continue
		base="$(default_base "$repo_dir")"
		while IFS=$'\t' read -r wt branch; do
			[ -n "$branch" ] || continue
			if ! git -C "$repo_dir" merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
				continue
			fi
			if ! $assume_no; then
				printf 'remove %s (merged into %s)? [y/N] ' "$wt" "$base"
				read -r answer || true
				[ "$answer" = "y" ] || continue
			fi
			if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
				echo "wt: skipping $wt (has uncommitted changes)" >&2
				continue
			fi
			git -C "$repo_dir" worktree remove "$wt"
			git -C "$repo_dir" branch -d "$branch" || true
		done < <(worktree_branches "$repo_dir")
	done <<<"$repos"
}

[ $# -ge 1 ] || usage
command="$1"
shift
case "$command" in
new) cmd_new "$@" ;;
list) cmd_list "$@" ;;
prune) cmd_prune "$@" ;;
-h | --help) usage ;;
*) usage ;;
esac

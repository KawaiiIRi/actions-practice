#!/usr/bin/env bash
# このスクリプト自体を変更した場合は、初回だけ手動でコミットして現在ブランチへpushする。
# git status
# git add publish-workflow.sh test1.yml
# git diff --cached --name-only
# git commit -m "Update workflow publishing script"
# git pull --rebase
# git push
# Publish one workflow file to the currently checked-out branch.
set -euo pipefail

readonly REMOTE_NAME="origin"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
REPOSITORY_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || exit 1
readonly SCRIPT_DIR
readonly REPOSITORY_ROOT
readonly WORKFLOW_DIRECTORY="$REPOSITORY_ROOT/.github/workflows"

die() {
  echo "Error: $*" >&2
  exit 1
}

show_usage() {
  cat <<'USAGE'
Usage:
  bash publish-workflow.sh <workflow-file-path> [commit message]

Example:
  bash publish-workflow.sh ./test1.yml "2026082300commit: Update for Env Variables Testing"
USAGE
}

validate_script_location() {
  [[ "$SCRIPT_DIR" == "$WORKFLOW_DIRECTORY" ]] || \
    die "This script must be placed in .github/workflows."
}

resolve_workflow_file() {
  local supplied_path="$1"
  local resolved_directory
  local resolved_file

  [[ "$supplied_path" == *.yml || "$supplied_path" == *.yaml ]] || \
    die "The first argument must be a .yml or .yaml file."

  resolved_directory="$(cd -- "$(dirname -- "$supplied_path")" && pwd -P)" || \
    die "Cannot resolve the directory for '$supplied_path'."
  resolved_file="$resolved_directory/$(basename -- "$supplied_path")"

  [[ -f "$resolved_file" ]] || die "'$supplied_path' does not exist or is not a file."
  [[ "$resolved_directory" == "$WORKFLOW_DIRECTORY" ]] || \
    die "The target file must be directly inside .github/workflows."

  printf '%s\n' "$resolved_file"
}

validate_repository_state() {
  git -C "$REPOSITORY_ROOT" remote get-url "$REMOTE_NAME" >/dev/null || \
    die "Remote '$REMOTE_NAME' is not configured."
}

get_current_branch() {
  local current_branch
  current_branch="$(git -C "$REPOSITORY_ROOT" branch --show-current)"

  [[ -n "$current_branch" ]] || \
    die "Cannot publish while HEAD is detached. Check out a branch first."

  printf '%s\n' "$current_branch"
}

assert_only_target_is_changed() {
  local target_path="$1"
  local changed_path
  local has_unrelated_changes=false

  while IFS= read -r changed_path; do
    [[ "$changed_path" == "$target_path" ]] && continue
    echo "Error: Uncommitted change outside the target file: $changed_path" >&2
    has_unrelated_changes=true
  done < <(
    {
      git -C "$REPOSITORY_ROOT" diff --name-only
      git -C "$REPOSITORY_ROOT" diff --cached --name-only
      git -C "$REPOSITORY_ROOT" ls-files --others --exclude-standard
    } | sort -u
  )

  [[ "$has_unrelated_changes" == false ]] || \
    die "Commit, stash, or discard the listed changes before continuing."
}

show_target_diff() {
  local target_path="$1"
  local target_file="$2"

  echo "== git diff $target_path =="
  if git -C "$REPOSITORY_ROOT" ls-files --error-unmatch -- "$target_path" >/dev/null 2>&1; then
    git -C "$REPOSITORY_ROOT" diff -- "$target_path"
  else
    git diff --no-index /dev/null "$target_file" || true
  fi
}

has_upstream_branch() {
  git -C "$REPOSITORY_ROOT" rev-parse \
    --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
}

sync_and_push_current_branch() {
  local current_branch="$1"

  if has_upstream_branch; then
    git -C "$REPOSITORY_ROOT" pull --rebase
    git -C "$REPOSITORY_ROOT" push
  else
    git -C "$REPOSITORY_ROOT" push \
      --set-upstream "$REMOTE_NAME" "$current_branch"
  fi
}

commit_and_push() {
  local target_path="$1"
  local commit_message="$2"
  local current_branch="$3"

  git -C "$REPOSITORY_ROOT" add -- "$target_path"

  if git -C "$REPOSITORY_ROOT" diff --cached --quiet -- "$target_path"; then
    echo "No changes to commit in $target_path."
    return 0
  fi

  git -C "$REPOSITORY_ROOT" commit -m "$commit_message" -- "$target_path"
  sync_and_push_current_branch "$current_branch"
  echo "Published to $current_branch: $target_path"
}

main() {
  [[ $# -ge 1 && $# -le 2 ]] || {
    show_usage >&2
    exit 1
  }

  local workflow_file_path="$1"
  local target_file
  local target_path
  local commit_message
  local current_branch

  validate_script_location
  target_file="$(resolve_workflow_file "$workflow_file_path")"
  target_path="${target_file#"$REPOSITORY_ROOT/"}"
  commit_message="${2:-$(date +'%Y%m%d%H%M')commit: Update $(basename -- "$target_file")}"
  validate_repository_state
  current_branch="$(get_current_branch)"

  echo "== current branch: $current_branch =="
  echo "== git status =="
  git -C "$REPOSITORY_ROOT" status --short
  assert_only_target_is_changed "$target_path"
  show_target_diff "$target_path" "$target_file"
  commit_and_push "$target_path" "$commit_message" "$current_branch"
}

main "$@"

#!/usr/bin/env bash
# install.sh — Install one or all localization skills into Claude and/or Codex
#
# Usage:
#   ./install.sh                                     # interactive: pick target, install all
#   ./install.sh --target claude                     # install all to Claude
#   ./install.sh --target codex                      # install all to Codex
#   ./install.sh --target both                       # install all to both
#   ./install.sh localization-workflow --target codex  # single skill to Codex
#   ./install.sh --list                              # list available skills

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude/skills"
CODEX_DIR="${HOME}/.codex/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

SKILLS=(
  # Orchestrator
  localization-workflow

  # Sub-skills invoked by localization-workflow
  babel-figma-screenshots
  content-scoring-framework
  jira-reader
  monday-localizer
  smartling-job-manager
  smartling-post-auth
  smartling-tag-manager

  # Standalone
  localization-keys-creator
  localization-slack-on-call
)

list_skills() {
  echo "Available skills:"
  for skill in "${SKILLS[@]}"; do
    echo "  - $skill"
  done
}

install_skill() {
  local skill="$1"
  local dest_root="$2"
  local src="${REPO_DIR}/${skill}"
  local dest="${dest_root}/${skill}"

  if [[ ! -d "$src" ]]; then
    echo "❌  Unknown skill: $skill"
    echo ""
    list_skills
    exit 1
  fi

  mkdir -p "$dest"
  rsync -a --delete --exclude='.DS_Store' "${src}/" "${dest}/"
  echo "✅  Installed: $skill → ${dest}"
}

install_to_targets() {
  local skill="$1"  # empty = all
  local targets=("${@:2}")

  for target in "${targets[@]}"; do
    local dest_root
    case "$target" in
      claude) dest_root="$CLAUDE_DIR" ;;
      codex)  dest_root="$CODEX_DIR"  ;;
    esac

    if [[ -n "$skill" ]]; then
      install_skill "$skill" "$dest_root"
    else
      echo "Installing all skills into ${dest_root}/"
      echo ""
      for s in "${SKILLS[@]}"; do
        install_skill "$s" "$dest_root"
      done
    fi
  done
}

pick_target_interactively() {
  echo "Install for:"
  echo "  [1] Claude  (~/.claude/skills/)"
  echo "  [2] Codex   (~/.codex/skills/)"
  echo "  [3] Both"
  echo ""
  read -rp "Choice [1/2/3]: " choice
  case "$choice" in
    1) echo "claude" ;;
    2) echo "codex"  ;;
    3) echo "both"   ;;
    *) echo "❌  Invalid choice: $choice" >&2; exit 1 ;;
  esac
}

# --- Parse args ---
SKILL_ARG=""
TARGET_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      list_skills
      exit 0
      ;;
    --target)
      TARGET_ARG="$2"
      shift 2
      ;;
    --target=*)
      TARGET_ARG="${1#--target=}"
      shift
      ;;
    -*)
      echo "❌  Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      SKILL_ARG="$1"
      shift
      ;;
  esac
done

# Resolve target
if [[ -z "$TARGET_ARG" ]]; then
  TARGET_ARG="$(pick_target_interactively)"
fi

case "$TARGET_ARG" in
  claude) TARGETS=("claude") ;;
  codex)  TARGETS=("codex")  ;;
  both)   TARGETS=("claude" "codex") ;;
  *)
    echo "❌  Unknown target: $TARGET_ARG (use claude, codex, or both)" >&2
    exit 1
    ;;
esac

install_to_targets "$SKILL_ARG" "${TARGETS[@]}"

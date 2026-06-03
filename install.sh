#!/usr/bin/env bash
# install.sh — Install one or all localization skills into ~/.claude/skills/
#
# Usage:
#   ./install.sh                          # install all skills
#   ./install.sh localization-workflow    # install a single skill
#   ./install.sh --list                   # list available skills

set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

SKILLS=(
  babel-figma-screenshots
  localization-keys-creator
  localization-slack-on-call
  localization-workflow
  smartling-tag-manager
)

list_skills() {
  echo "Available skills:"
  for skill in "${SKILLS[@]}"; do
    echo "  - $skill"
  done
}

install_skill() {
  local skill="$1"
  local src="${REPO_DIR}/${skill}"
  local dest="${SKILLS_DIR}/${skill}"

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

# Parse args
if [[ $# -eq 0 ]]; then
  echo "Installing all skills into ${SKILLS_DIR}/"
  echo ""
  for skill in "${SKILLS[@]}"; do
    install_skill "$skill"
  done
elif [[ "$1" == "--list" ]]; then
  list_skills
else
  install_skill "$1"
fi

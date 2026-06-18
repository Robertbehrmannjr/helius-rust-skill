#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.claude/skills/helius-rust-skill}"

echo "Installing helius-rust-skill to $TARGET_DIR..."

mkdir -p "$TARGET_DIR"
cp -r "$SKILL_DIR/skill" "$TARGET_DIR/"
cp -r "$SKILL_DIR/rules" "$TARGET_DIR/"
cp "$SKILL_DIR/README.md" "$TARGET_DIR/"

echo "Done. Add to your CLAUDE.md:"
echo ""
echo "  ## Helius + Rust"
echo "  Skill: .claude/skills/helius-rust-skill/skill/SKILL.md"
echo "  Rules: .claude/skills/helius-rust-skill/rules/helius-rust.md"

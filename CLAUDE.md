# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The Godot 4.4 game lives in `Age of Gold Game/`. Read `Age of Gold Game/CLAUDE.md` (commands, architecture, gotchas) and `Age of Gold Game/tests/CONTRACT.md` (shared autoload APIs, test conventions) before changing it. Run Godot commands with `--path "Age of Gold Game"`, or from inside that directory.

This directory holds:
- **Design docs:** `AgeofGold-MansaMusa'sLegacy.md` is the full game design. `Salt Famine.md`, `Inflation Debate.md`, `Mosque Crisis.md` and `Tuareg Negotiation.md` are event scripts. `AoG-openage.md` is an older openage-engine plan that the Godot project replaced.
- **Asset generators:** the `create_*.py` scripts (Pillow/numpy, seeded) produce every PNG and WAV under `Age of Gold Game/assets/`. To change an asset, edit and re-run its script, then run `~/Godot_v4.4-stable_linux.arm64 --headless --path "Age of Gold Game" --import`. Never hand-edit a generated asset.

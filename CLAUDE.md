# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A 2D historical RTS prototype set in the 14th-century Mali Empire, built with **Godot 4.4** (GDScript). The Godot project is at the repository root (`project.godot` here). The game starts at `ui/MainMenu.tscn`; skirmish is `res://main.tscn`.

Read `tests/CONTRACT.md` (shared autoload APIs, test conventions) before changing shared systems.

Alongside the Godot project, this directory also holds:
- **Design docs:** `AgeofGold-MansaMusa'sLegacy.md` is the full game design. `Salt Famine.md`, `Inflation Debate.md`, `Mosque Crisis.md` and `Tuareg Negotiation.md` are event scripts. `AoG-openage.md` is an older openage-engine plan that the Godot project replaced.
- **Asset generators:** the `create_*.py` scripts (Pillow/numpy, seeded) produce every PNG and WAV under `assets/`. To change an asset, edit and re-run its script, then re-import (see below). Never hand-edit a generated asset. `create_placeholders.py` generates the placeholder PNG icons in `assets/ui/`.

## Commands

There is no build system or linter. The Godot editor binary is `~/Godot_v4.4-stable_linux.arm64` (Raspberry Pi / ARM64). It is not on `PATH`, so call it by its full path. Run Godot commands from the repository root (or pass `--path .`):

- Run the game: `~/Godot_v4.4-stable_linux.arm64 --path .`
- Open the editor: `~/Godot_v4.4-stable_linux.arm64 --path . -e`
- Headless check that scripts parse: `~/Godot_v4.4-stable_linux.arm64 --headless --path . --quit` (reports GDScript parse errors)
- Re-import assets after regenerating them: `~/Godot_v4.4-stable_linux.arm64 --headless --path . --import`
- Run all tests: `bash tests/run_all.sh` (all suites, ~1 min; `tests/` has a `.gdignore`)
- Run one test: `timeout 300 ~/Godot_v4.4-stable_linux.arm64 --headless --fixed-fps 60 --path . -s tests/<area>/test_<area>.gd`. A new test must also be added to the `TESTS` list in `tests/run_all.sh`.

## Architecture

- **Data flow**: gameplay code changes `GameData.<resource>` directly, and the UI (`ui/GameUI.gd`) listens to the `*_changed` signals to update labels. Keep to this pattern: add a new resource as a clamped setter with a signal in `GameData`, then connect to it in the UI.
- GDScript is indented with **tabs** (Godot's default; the editor converts indentation to tabs on save). Never indent with spaces: GDScript rejects mixed indentation.

## Current state

As of 2026-09-28 the game is feature-complete against the design doc's core systems, and every scene loads with no errors.

- **Start and scenes:**
  - The game starts at `ui/MainMenu.tscn` (the `run/main_scene`), which offers Campaign and a mode picker (`ui/ModeSelect`): Skirmish (`main.tscn`), Trans-Saharan Showdown and Scholars of Sankore.
  - Showdown and Scholars (`modes/`) are single-player versions of the design doc's multiplayer modes. They extend `ai/RivalModeBase.gd` (which extends `MissionBase.gd`) and pit the player against three `ai/AIEmpire.gd` rivals. Each empire keeps its own resources, separate from `GameData`. An `AIController` makes its decisions and can be swapped for another controller with the same interface.
  - The AI difficulty lives in a static var on `ai/AISettings.gd`, because `GameSession.start()` resets every autoload.
  - Campaign mission select is backed by `missions/MissionRegistry.gd`. Progress is saved in `user://campaign.cfg`.
  - The missions are Mission 1 (Bambuk mines), Mission 2 (Salt of the Sahara) and Mission 7 (Pilgrimage Paradox).
- **Controls:**
  - WASD to move, Space to attack, B for the build bar, T for the tech panel, P to pause, M to mute.
  - 1/2/3 choose in dilemmas. E is debug gold.
- **Shared APIs:** `tests/CONTRACT.md` is the source of truth for the autoload APIs, groups, modifier keys, UI layout regions and test conventions. Read it before changing shared systems.

Gotchas:
- **Starting or restarting a game:** always use `GameSession.start(scene)`, never `change_scene_to_file`. It resets every autoload.
  - Delayed effects (timers, awaits, building bonus removal) must check `GameData.generation` so they don't leak into the next game. See `DilemmaManager._after` and `Building._clear_effects`.
- **Purchases:** go through `GameData.spend()` / `format_cost()` so inflation (`gold_price_mult`) applies.
  - `EconomyManager` rewrites `gold_price_mult` every frame from gold held, so exact-cost tests must pin it.
- **Unit stats:** set them in `_init()`, **not** `_ready()`, because `health` is `@onready := max_health`. Put behaviour in `_physics_process`; Unit uses `_process` for its timers.
- **Freed targets:** a callback that can receive a freed node must use an untyped parameter. `is_instance_valid()` on a typed parameter errors first.
- **Rival buildings** (`rival/RivalBuilding.gd`) extend `Unit` and never move. They sit in `"enemies"` so existing attack code hits them. Code that iterates `"enemies"` must skip `"rival_buildings"` where "unit" behaviour is assumed (conversion, fleeing).
- **Pausing:** DilemmaDialog, PauseMenu and `VictoryManager.declare_*` all pause the tree.
  - Tests that aren't about events or victory set `DilemmaManager.auto_triggers_enabled = false` and `VictoryManager.skirmish_conditions_enabled = false`.
  - A test that isn't about the rival faction frees `RivalBase`.
  - Test scripts must not name `class_name` types: they compile before the autoloads exist.
- **Scaled numbers:** design-doc numbers are scaled for the prototype, with the doc's original next to each constant. For example, Economic victory needs 100 ingots against the doc's 10,000.
- **Not implemented:**
  - Campaign missions 3–6, 8 and 9.
  - Multiplayer.
  - Fog of war (the Desert Scout's "+4 LOS" is reinterpreted as marking enemies).
  - Save/load of a game in progress.
  - Y-sorting between units and buildings.

`MansaDialogue.jsx`/`.tsx` are identical React snippets that sketch gold-dependent Mansa dialogue lines. They are not used by the Godot project.

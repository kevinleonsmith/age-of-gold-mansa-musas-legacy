# Age of Gold: Mansa Musa's Legacy

A 2D historical real-time strategy prototype set in the 14th-century **Mali Empire**, built with **Godot 4.4** (GDScript). It blends *Age of Empires*–style RTS mechanics with the economics, faith, and diplomacy of Mansa Musa's golden age — gold-dust mining, trans-Saharan salt routes, Timbuktu manuscripts, and the legendary 1324 Hajj.

> Mansa Musa (c. 1280–1337), ruler of Mali, is often called the wealthiest person in history. This game turns his gold monopoly, salt trade, and pilgrimage into playable systems.

---

## Requirements

- **Godot 4.4** — the ARM64 editor binary used for development is `~/Godot_v4.4-stable_linux.arm64` (Raspberry Pi / ARM64). On other platforms, use the matching Godot 4.4 build for your OS. It is not on `PATH`, so it's called by full path in the commands below.
- **Python 3** with **Pillow** and **numpy** — only needed if you want to regenerate art/audio assets (see [Assets](#assets)).

## Getting started

Clone the repo, then generate Godot's import cache (it is intentionally **not** committed — the `.godot/` folder is gitignored). Run Godot commands from the repository root (`--path .`):

```bash
~/Godot_v4.4-stable_linux.arm64 --headless --path . --import
```

Running headless prints harmless `progress_dialog.cpp … canceled` warnings — those are cosmetic and can be ignored. The import is complete when `.godot/imported/` is populated.

### Run the game

```bash
# Launch (starts at the main menu)
~/Godot_v4.4-stable_linux.arm64 --path .

# Open in the editor
~/Godot_v4.4-stable_linux.arm64 --path . -e

# Headless check that all scripts parse
~/Godot_v4.4-stable_linux.arm64 --headless --path . --quit
```

The game opens on `ui/MainMenu.tscn`, offering the **Campaign** and a **mode picker**: Skirmish (`main.tscn`), Trans-Saharan Showdown, and Scholars of Sankore.

### Controls

| Key | Action |
|-----|--------|
| **WASD** | Move |
| **Space** | Attack |
| **B** | Build bar |
| **T** | Tech panel |
| **P** | Pause |
| **M** | Mute |
| **1 / 2 / 3** | Choose in dilemmas |
| **E** | Debug: add gold |

## Gameplay

- **Resources:** Gold Dust (primary currency, refined into Gold Ingots), Salt Blocks, and Manuscripts.
- **Three Ages:** Sand Chiefdoms → Mali Ascendancy → Golden Hajj, each unlocking new units, techs, and wonders.
- **Economy:** an inflation model (`EconomyManager`) drives gold prices from how much gold you hold; purchases route through `GameData.spend()` so inflation applies.
- **Events & dilemmas:** scripted crises (salt famine, inflation debate, mosque crisis, Tuareg negotiation) with branching outcomes.
- **Victory conditions:** Economic Domination, Cultural Victory, and Military Conquest (numbers are scaled down from the design doc for prototype play).

### Campaign missions

Implemented: **Mission 1** (Bambuk mines), **Mission 2** (Salt of the Sahara), **Mission 7** (Pilgrimage Paradox). Progress is saved to `user://campaign.cfg`.

### Modes

**Trans-Saharan Showdown** and **Scholars of Sankore** are single-player takes on the design doc's multiplayer modes: you face three AI rivals (`ai/AIEmpire.gd`), each managing its own resources via a swappable `AIController`.

## Project layout

The Godot project lives at the repository root (`project.godot` is here):

```
Age of Gold: Mansa Musa's Legacy/   # repo root == Godot project root
├─ project.godot
├─ main.tscn                  # skirmish scene
├─ autoload/                  # singletons: GameData, EconomyManager, TechManager, …
├─ ai/                        # AI empires, controllers, rival mode base
├─ buildings/ entities/       # buildings and units
├─ missions/ modes/           # campaign missions and game modes
├─ rival/ systems/ ui/        # rival faction, systems, and UI
├─ assets/                    # generated PNG + WAV assets (do not hand-edit)
├─ tests/                     # headless SceneTree test suites (+ CONTRACT.md)
├─ create_*.py                # seeded asset generators (Pillow / numpy)
├─ *.md                       # design docs and event scripts
└─ LICENSE                    # Apache 2.0
```

### Autoload singletons

`GameData`, `AgeManager`, `TechManager`, `EconomyManager`, `DilemmaManager`, `VictoryManager`, `AudioManager`, `GameSession`, `SaveManager`. See `tests/CONTRACT.md` for their public APIs — it is the source of truth for shared systems.

## Assets

Every PNG and WAV under `assets/` is produced by a seeded generator script (`create_*.py`) using Pillow/numpy — **never hand-edit a generated asset**. To change one, edit its script, re-run it, then re-import:

```bash
python3 create_<name>.py
~/Godot_v4.4-stable_linux.arm64 --headless --path . --import
```

## Tests

There is no build system or linter. Tests are headless SceneTree scripts covering combat, economy, tech, events, conversion, campaign, rival modes, and more:

```bash
# from the repository root
bash tests/run_all.sh          # all suites (~1 min)

# run a single suite
timeout 300 ~/Godot_v4.4-stable_linux.arm64 --headless --fixed-fps 60 \
  --path . -s tests/<area>/test_<area>.gd
```

Read `tests/CONTRACT.md` before changing shared systems, and add any new test to the `TESTS` list in `tests/run_all.sh`.

## Development notes

- GDScript is indented with **tabs** — never spaces (mixed indentation is rejected).
- Always start/restart a game with `GameSession.start(scene)` (it resets every autoload), never `change_scene_to_file`.
- Set unit stats in `_init()`, not `_ready()`.
- **Not yet implemented:** campaign missions 3–6, 8, 9; true multiplayer; fog of war; save/load of an in-progress game; Y-sorting between units and buildings.

The full design — resources, tech tree, unit roster, campaign scripts, and economic model — lives in `AgeofGold-MansaMusa'sLegacy.md`, with individual event scripts in `Salt Famine.md`, `Inflation Debate.md`, `Mosque Crisis.md`, and `Tuareg Negotiation.md`.

## License

Licensed under the **Apache License 2.0**. See [LICENSE](LICENSE).

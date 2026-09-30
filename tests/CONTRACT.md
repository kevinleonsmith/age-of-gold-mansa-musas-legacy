# Age of Gold: shared contract for parallel agents (Phase 4)

Project: "/home/kls-sce/Age of Gold: Mansa Musa's Legacy" (call it P). Read `P/CLAUDE.md` first.
Godot binary: `~/Godot_v4.4-stable_linux.arm64`. Design doc: `P/AgeofGold-MansaMusa'sLegacy.md`.

Several agents build in parallel. **Edit only the files you own.** If you need a change in a file you
don't own, report it instead of making it. Keep every public signature listed here stable.

## Coding rules
- GDScript is indented with **TABS only**. Scenes are Godot 4 `format=3` (copy the style of existing
  `.tscn` files). New scenes get a unique invented `uid://...` and string ext_resource ids.
- Unit stats go in `_init()`, not `_ready()` (Unit's `health` is `@onready := max_health`).
- Connect signals in code, not in `[connection]` entries.
- A callback that can receive a freed node must not have a typed parameter: `is_instance_valid()`
  on a typed parameter errors before it runs. Use an untyped parameter.
- Delayed effects (timers, awaits) that change global state must check that `GameData.generation`
  is unchanged before applying (see `DilemmaManager._after`).
- New PNGs: generate them with your own Pillow script `P/../create_<area>_sprites.py`, in the style of
  `assets/sprites/*.png` (see `P/../create_sprites.py`), then run `--import` once. Composite a preview
  PNG in your scratch dir, look at it with the Read tool, and iterate once if it looks poor.
- **Don't edit `main.tscn`, `project.godot` or `tests/run_all.sh`.** The coordinator integrates after
  you finish: your scenes go into main, project settings change, and your test is added to run_all.
  Tell the coordinator what to add.

## Tests
- Existing suite: `bash P/tests/run_all.sh` (about 30–60 s). It must stay green; run it before you
  report. If a test for another area breaks because of your change, fix your code, or report it if
  the test's assumption is outdated.
- Write your own test at `P/tests/<area>/test_<area>.gd`:
  - `extends SceneTree`, logic in `_initialize`, tabs.
  - Load `res://main.tscn` with `change_scene_to_file`, then `await process_frame` twice.
  - Set `DilemmaManager.auto_triggers_enabled = false` unless you test events: dilemmas pause the tree.
  - Remove `SpawnManager` if random enemies interfere.
  - Access autoloads via `root.get_node("GameData")`.
  - **Don't name class_name types** (`Unit`, `Caravan`, `Building`, ...) in test scripts: the test
    compiles before autoloads exist. Use `load("res://...gd")` and `is_instance_of`.
  - Print `PASS: ...` / `FAIL: ...` lines, and finish with `RESULT: OK (0 failures)` or
    `RESULT: FAILED (n failures)`.
- Run a single test with `timeout 300 ~/Godot_v4.4-stable_linux.arm64 --headless --fixed-fps 60 --path "P" -s "P/tests/<area>/test_<area>.gd"`.
- Parse check: `timeout 120 ~/Godot_v4.4-stable_linux.arm64 --headless --path "P" --quit` must print
  no errors from your files.

## Autoloads (all exist)
- **GameData**:
  - Resources `gold`, `salt`, `manuscripts`, `ingots`, with `<name>_changed` signals. `income_per_second`.
  - Costs: `can_afford`, `spend(cost) -> bool`, `scaled_cost`, `format_cost`, `add_resources`,
    `get_amount`. **All purchases go through `spend()`**, and prices are shown with `format_cost()`.
  - Modifiers: `get_modifier(key, default := 1.0)`, `set_modifier`, `multiply_modifier`, `add_modifier`,
    signal `modifiers_changed(key, value)`.
  - `generation` and `reset()`.
- **AgeManager**:
  - `AGES` {SAND_CHIEFDOMS, MALI_ASCENDANCY, GOLDEN_HAJJ}, `current_age`, `age_changed(new_age)`.
  - `is_unlocked(age)`, `can_advance()`, `advance_age()`, `get_unmet_requirements()`,
    `get_age_short_name()`, `reset()`.
  - Advancing needs buildings: I→II needs 5 houses + 1 mosque; II→III needs 3 mosques + 2 gold
    ResourceNodes in the scene.
- **TechManager**:
  - `is_researched(id)`, `grant_tech(id)`, `can_research`, `start_research`, `get_all_techs`,
    `reset()`.
  - Signals `tech_researched(id)`, `research_started(id)`.
- **EconomyManager**:
  - `price_index` (1.0 stable, up to 3.0), `get_inflation_state()` ("Stable" <1.25, "Rising" <1.75,
    "Crisis").
  - `mint_ingot()`, `distribute_gold(amount)`, `send_caravan(at, parent)`, `rival_gold`,
    `drain_rival_gold()`, `is_rivals_collapsed()`, `reset()`.
  - Signals `price_index_changed`, `rivals_collapsed`.
- **DilemmaManager**:
  - `is_active()`, `trigger(id)`, `auto_triggers_enabled`, `reset()`.
  - Signals `dilemma_started`, `dilemma_resolved`.
  - While a dilemma is active the tree is paused by DilemmaDialog.
- **VictoryManager** (Game-flow agent fills in; API stable, see the file):
  - `declare_victory(id, title, text)`, `declare_defeat(id, title, text)`, `is_game_over`.
  - Signals `game_won` / `game_lost`.
  - `skirmish_conditions_enabled` (missions set it false).
  - Objectives: `set_objectives([{id, text, optional?}])`, `set_objective_text`, `complete_objective`,
    `is_objective_done`, signal `objectives_changed`.
- **AudioManager** (Audio agent fills in):
  - `play_sfx(name, at = null)`, `play_music(track)`, `reset()`.
  - Unknown names are ignored silently, so any system may call it.
  - SFX names: hit, death, build_place, research_done, age_up, coin, caravan_deliver, dilemma_open,
    convert, click, victory, defeat, horn, error.
  - Tracks: sand_chiefdoms, mali_ascendancy, golden_hajj, menu.
- **GameSession**: `reset_all()` resets every autoload; `start(scene_path)` unpauses, resets and loads a
  scene. Use `start()` for New Game / Retry / mission launch. (Player death in skirmish currently
  reloads the scene without a reset; the Game-flow agent decides the new behaviour.)

## Units and groups
- `entities/Unit.gd` (`class_name Unit`, CharacterBody2D):
  - Exports `max_health`, `attack_damage`, `attack_range`, `attack_cooldown`.
  - `try_attack`, `take_damage`, `heal`, `_on_died()`, `apply_morale_boost`, `apply_poison(dps, dur)`,
    `find_nearest_in_group`.
  - Signals `died`, `health_changed`.
  - Unit uses `_process`; put behaviour in `_physics_process`.
- Groups:
  - `"player"` (+ `"allies"`); `"allies"`: every friendly unit; `"enemies"`; `"caravans"`;
    `"converted"`.
  - **new** `"hero"`: Golden Mansa. **new** `"camel"`: units unaffected by sandstorms (CamelLancer,
    Caravan, DesertScout).
- Buildings (`buildings/Building.gd`, `class_name Building`, StaticBody2D):
  - `take_damage(amount)`, `is_destroyed`, signal `destroyed`.
  - Groups `"buildings"` and `"building_<type>"`: house, mosque, market, outpost, great_mosque,
    salt_cathedral.
  - `ui/BuildMenu` has `place_building(type, pos)`.
- **new** Rival faction groups (Rival agent): `"rival_camps"`, `"rival_wonders"`, `"rival_buildings"`.
  Rival buildings have `take_damage(amount)`, `is_destroyed` and signal `destroyed`.
- Trade posts: `"trade_posts"` (TradePost: `post_name`, `trade_good`).
- Enemy conversion: `if enemy.has_method("convert_to_ally"): enemy.convert_to_ally()`.

## Modifier keys (default → meaning)
- `gold_price_mult` 1: inflation.
- `ally_attack_mult` 1, `ally_damage_taken_mult` 1, `poison_dps` 0, `enemy_hp_drain` 0.
- `harvest_mult` 1, `salt_harvest_mult` 1, `research_time_mult` 1, `building_hp_mult` 1,
  `building_cost_mult` 1.
- `caravan_cargo_mult` 1, `caravan_speed_mult` 1, `caravan_damage_taken_mult` 1.
- `enemy_spawn_rate_mult` 1 (0 pauses spawning), `conversion_speed_mult` 1.
- `converted_count` 0 (additive count of converted enemies).
- **new** `sandstorm_slow_mult` 1: movement speed multiplier for the Player and EnemyAI (and any
  non-"camel" unit you own) during a sandstorm.

## Input actions (in project.godot)
- `move_*`: WASD / arrows. `attack`: Space. `interact`: E (debug gold).
- `toggle_tech`: T. `toggle_build`: B. `cancel`: Esc. **new** `pause`: P.
- Anything else: handle raw key events, and say so in your report.

## Screen layout (1152x648). Keep your UI in your region.
- GameUI: top-left, about 0–700 × 0–110.
- EconomyPanel: top-right, 340 wide, about 0–230 tall.
- BuildMenu: bottom-left bar.
- TechPanel: right side, toggled with T; "Tech (T)" button bottom-right.
- Toasts: bottom-center.
- DilemmaDialog: centered modal (layer 20).
- **new**:
  - UnitMenu: left edge, vertical, between y≈120 and the build bar.
  - Objectives HUD: right edge, below EconomyPanel (y≈240).
  - Pause and End screens: full-screen overlays (layer 30+).

---
# Phase 5 additions

## New shared pieces (coordinator-owned; already in place)
- **MissionRegistry**:
  - It now lists mission1–mission9 plus the bonus `scholars_revolt`. The bonus is unlocked by mission4 and doesn't gate the story; `get_next` skips it.
  - Scene paths are `res://missions/Mission<N>.tscn` and `res://missions/ScholarsRevolt.tscn`.
  - Persistent campaign flags: `MissionRegistry.set_flag(key, value)` / `get_flag(key, default)`. Example: `"salt_famine"` is set when Mission 5 is lost; later missions read it.
  - Registry text is coordinator-owned. Send wording changes in your report.
- **Unit**: new export `vision_radius := 260.0`, the fog-of-war reveal radius for allies. Set it in `_init()` for special units (e.g. Desert Scout 520, "+4 LOS").
- **SaveManager** autoload stub (Save agent fills it in): `has_save(slot)`, `save_game(slot) -> bool`, `load_game(slot) -> bool`, signals `game_saved`, `game_loaded`.

## Conventions for phase 5
- **Mission scenes** (copy `missions/Mission2.tscn` for structure):
  - Extend `missions/MissionBase.gd` by path. **Don't edit MissionBase.gd**: the Save agent adds save hooks there. Ask the coordinator for anything else you need in it.
  - Include the standard UI instances: GameUI, BuildMenu, TechPanel, EconomyPanel, Toasts, DilemmaDialog, UnitMenu, ObjectivesHUD, PauseMenu, EndScreen.
  - The coordinator adds FogOfWar and Minimap to every scene after the Fog agent finishes. Don't reference them.
  - **Y-sort**: set `y_sort_enabled = true` on the scene root and on every world container that holds units, buildings or resources (Resources, Buildings, Enemies, TradePosts, RivalBase, …). Keep the terrain TileMapLayer's `z_index = -10`.
  - Mission-specific state that must survive save/load: implement `get_mission_state() -> Dictionary` and `load_mission_state(d: Dictionary)` in your mission script. Plain data only: numbers, strings, arrays, dicts, Vector2.
- **Save hooks on entities**: the Save agent may **append** `get_save_state() -> Dictionary` / `load_save_state(d: Dictionary)` methods to entity and building scripts. Other agents must not remove them. Append-only, no reformatting.
- **Fog visibility**: FogOfWar hides hostile nodes by setting `visible` on members of `"enemies"` / `"rival_buildings"`. Never rely on `visible` for gameplay logic.
- **One-off rewards**: an agent may append a new tech to `TechManager._init()` (one `_add(...)` call) only if its brief says so.

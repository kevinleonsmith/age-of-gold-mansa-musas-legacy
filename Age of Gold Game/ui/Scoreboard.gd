# Rival-mode scoreboard (res://ui/Scoreboard.gd, scene ui/Scoreboard.tscn)
# Small panel at the top centre (x 360-720, y 112), clear of GameUI and the
# EconomyPanel. One row per side: colour swatch, name, then nodes + score
# (Showdown) or manuscript-tech progress (Scholars). Reads the rows from the
# current mode (group "rival_mode": get_scoreboard_kind / _title / _rows).
# Modes can add their own controls under the rows with add_footer().
extends CanvasLayer

const REFRESH_INTERVAL := 0.5
const MenuThemeScript := preload("res://ui/MenuTheme.gd")
const PANEL_POS := Vector2(360, 112)
const PANEL_WIDTH := 360.0

var panel: PanelContainer
var title_label: Label
var grid: GridContainer
var footer: VBoxContainer
var _refresh_left := 0.0
var _row_texts: Array = []

func _ready() -> void:
	layer = 4
	add_to_group("scoreboard")
	_build()
	refresh()

func _build() -> void:
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.theme = MenuThemeScript.get_theme()
	var style := MenuThemeScript.box(Color(MenuThemeScript.INDIGO, 0.78), MenuThemeScript.GOLD_DARK, 1, 6, 6.0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.position = PANEL_POS
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	title_label = MenuThemeScript.label("", 13, MenuThemeScript.GOLD, 3)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	footer = VBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 3)
	box.add_child(footer)

func add_footer(control: Control) -> void:
	footer.add_child(control)

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		refresh()

func _mode() -> Node:
	return get_tree().get_first_node_in_group("rival_mode")

# Rebuilds the rows from the mode.
func refresh() -> void:
	var mode := _mode()
	if mode == null or grid == null:
		return
	var kind: String = mode.get_scoreboard_kind()
	title_label.text = mode.get_scoreboard_title()
	var rows: Array = mode.get_scoreboard_rows()
	var needed := rows.size() * grid.columns
	while grid.get_child_count() < needed:
		_add_cell(grid.get_child_count() % grid.columns)
	while grid.get_child_count() > needed:
		var last := grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(last)
		last.queue_free()
	_row_texts = []
	for i in rows.size():
		var row: Dictionary = rows[i]
		var cells := []
		for c in grid.columns:
			cells.append(grid.get_child(i * grid.columns + c))
		(cells[0] as ColorRect).color = row["color"]
		var name_text: String = row["name"]
		if String(row.get("status", "")) != "":
			name_text += " (%s)" % row["status"]
		var a := ""
		var b := ""
		if kind == "scholars":
			a = "Techs %d/%d" % [int(row["techs"]), int(row["target"])]
			b = "[" + "#".repeat(int(row["techs"])) + "-".repeat(maxi(int(row["target"]) - int(row["techs"]), 0)) + "]"
			if float(row.get("progress", 0.0)) > 0.0:
				b += " %d%%" % int(float(row["progress"]) * 100.0)
		else:
			a = "Nodes %d" % int(row["nodes"])
			b = "Score %d" % int(row["score"])
			if float(row.get("hold", 0.0)) > 0.0:
				b += " hold %ds" % int(row["hold"])
		(cells[1] as Label).text = name_text
		(cells[2] as Label).text = a
		(cells[3] as Label).text = b
		var col: Color = MenuThemeScript.GOLD if row.get("is_player", false) else MenuThemeScript.SAND
		if String(row.get("status", "")) != "":
			col = MenuThemeScript.MUTED
		(cells[1] as Label).add_theme_color_override("font_color", col)
		_row_texts.append("%s | %s | %s" % [name_text, a, b])

func _add_cell(column: int) -> void:
	if column == 0:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(swatch)
		return
	var l := MenuThemeScript.label("", 13, MenuThemeScript.SAND, 2)
	if column == 1:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)

# One "name | a | b" string per row (tests / debugging).
func get_row_texts() -> Array:
	return _row_texts.duplicate()

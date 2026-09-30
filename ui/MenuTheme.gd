# Shared menu theme (res://ui/MenuTheme.gd)
# Gold on dark indigo / laterite, built from StyleBoxFlat in code. Used by the
# main menu, pause menu, end screen and objectives HUD.
class_name MenuTheme
extends RefCounted

const GOLD := Color(1.0, 0.82, 0.3)
const GOLD_DARK := Color(0.72, 0.52, 0.14)
const INDIGO := Color(0.09, 0.07, 0.19)
const INDIGO_LIGHT := Color(0.16, 0.12, 0.3)
const LATERITE := Color(0.55, 0.24, 0.12)
const LATERITE_LIGHT := Color(0.7, 0.33, 0.16)
const SAND := Color(0.96, 0.9, 0.76)
const MUTED := Color(0.72, 0.66, 0.58)
const GOOD := Color(0.55, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.35)

static var _theme: Theme = null

static func box(bg: Color, border: Color, border_width := 2, radius := 6, margin := 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

# Panel style for a framed menu box (indigo with a gold border).
static func panel_box(alpha := 0.94) -> StyleBoxFlat:
	var style := box(Color(INDIGO, alpha), GOLD_DARK, 2, 8, 16.0)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	return style

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font_size = 17
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("panel", "Panel", panel_box())

	var normal := box(LATERITE, GOLD_DARK, 2, 6, 8.0)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = LATERITE_LIGHT
	hover.border_color = GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.4, 0.17, 0.08)
	pressed.border_color = GOLD
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.22, 0.18, 0.24)
	disabled.border_color = Color(0.4, 0.36, 0.4)
	var focus := box(Color(0, 0, 0, 0), GOLD, 2, 6, 8.0)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", SAND)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_focus_color", "Button", SAND)
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.52))

	theme.set_color("font_color", "Label", SAND)
	theme.set_color("font_outline_color", "Label", Color(0.05, 0.03, 0.08))

	var bar_bg := box(Color(0.05, 0.04, 0.1), GOLD_DARK, 1, 3, 0.0)
	var bar_fill := box(GOLD, GOLD, 0, 3, 0.0)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", INDIGO)

	theme.set_color("default_color", "RichTextLabel", SAND)
	theme.set_stylebox("separator", "HSeparator", box(GOLD_DARK, GOLD_DARK, 0, 0, 0.0))
	theme.set_constant("separation", "HSeparator", 12)
	_theme = theme
	return theme

# A Label with the given size / colour, for building UI in code.
static func label(text: String, size := 17, color := SAND, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	return l

static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]

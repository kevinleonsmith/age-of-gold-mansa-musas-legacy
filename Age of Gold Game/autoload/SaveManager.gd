# Save / load a game in progress (res://autoload/SaveManager.gd)
# STUB: the Save agent fills this in; keep these signatures.
extends Node

signal game_saved(slot: String)
signal game_loaded(slot: String)

func has_save(_slot: String = "quicksave") -> bool:
	return false

func save_game(_slot: String = "quicksave") -> bool:
	return false

func load_game(_slot: String = "quicksave") -> bool:
	return false

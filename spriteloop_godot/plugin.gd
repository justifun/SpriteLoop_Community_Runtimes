@tool
extends EditorPlugin

const SpriteLoopImporter = preload("res://addons/spriteloop/spriteloop_importer.gd")
const SpriteLoopPlayerScript = preload("res://addons/spriteloop/spriteloop_player_2d.gd")

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = SpriteLoopImporter.new()
	add_import_plugin(_importer)
	var icon := get_editor_interface().get_editor_theme().get_icon("Sprite2D", "EditorIcons")
	add_custom_type("SpriteLoopPlayer2D", "Node2D", SpriteLoopPlayerScript, icon)


func _exit_tree() -> void:
	remove_custom_type("SpriteLoopPlayer2D")
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null

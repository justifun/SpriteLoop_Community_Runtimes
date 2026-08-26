@tool
class_name SpriteLoopPlayer2D
extends Node2D

## Plays a multipart animation imported from a SpriteLoop .spla package.
##
## The node previews the first animation frame in the 2D editor. At runtime it
## exposes playback, skin, variant, state-blend rendering, event, and query APIs.

signal package_loaded
signal load_failed(message: String)
signal frame_changed(frame: int)
signal animation_looped(animation_id: String)
signal animation_finished(animation_id: String)
signal animation_event(animation_id: String, frame: int, source_frame: int, event_name: String, data: String)

enum LoopMode {
	FROM_PACKAGE,
	LOOP,
	ONCE,
}

@export_group("Package")
@export var sprite_loop: SpriteLoopResource:
	set(value):
		if sprite_loop == value:
			return
		_disconnect_package()
		sprite_loop = value
		_connect_package()
		_reload_package()

@export_group("Playback")
@export var default_animation: String = ""
@export var autoplay: bool = true
@export_enum("From Package", "Loop", "Once") var loop_mode: int = LoopMode.FROM_PACKAGE
@export_range(0.0, 16.0, 0.01, "or_greater") var playback_speed: float = 1.0
@export var emit_authored_events: bool = true

@export_group("Display")
@export var center_on_origin: bool = true:
	set(value):
		center_on_origin = value
		if _frame_index >= 0:
			_apply_frame(_frame_index, false)
@export var preview_first_frame: bool = true:
	set(value):
		preview_first_frame = value
		queue_redraw()

var _package_data: Dictionary = {}
var _parts: Array = []
var _variants: Array = []
var _states: Array = []
var _skins: Array = []
var _animations: Array = []
var _part_by_id: Dictionary = {}
var _part_by_key_or_name: Dictionary = {}
var _variant_by_id: Dictionary = {}
var _state_by_id: Dictionary = {}
var _skin_by_id: Dictionary = {}
var _skin_by_name: Dictionary = {}
var _animation_by_id: Dictionary = {}
var _animation_by_name: Dictionary = {}
var _manual_variants: Dictionary = {}
var _render_items: Array = []
var _part_transforms: Dictionary = {}
var _animation_index: int = -1
var _skin_index: int = -1
var _frame_index: int = -1
var _elapsed: float = 0.0
var _playing: bool = false
var _paused: bool = false
var _ready_complete: bool = false
var _last_error: String = ""


func _ready() -> void:
	_ready_complete = true
	_connect_package()
	_reload_package()


func _exit_tree() -> void:
	_disconnect_package()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _playing or _animation_index < 0 or playback_speed <= 0.0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frames.is_empty():
		return
	var fps: float = animation["fps"]
	var duration := float(frames.size()) / fps
	var previous_elapsed := _elapsed
	var target_elapsed := previous_elapsed + delta * playback_speed
	var previous_step := int(floor(previous_elapsed * fps))
	var target_step := int(floor(target_elapsed * fps))

	if _effective_loop(animation):
		var crossed_frames := maxi(0, target_step - previous_step)
		for step in range(1, crossed_frames + 1):
			var entered_frame := posmod(previous_step + step, frames.size())
			if entered_frame == 0:
				animation_looped.emit(animation["id"])
			_emit_frame_events(entered_frame)
		_elapsed = fposmod(target_elapsed, duration)
		_apply_frame(clampi(int(floor(_elapsed * fps)), 0, frames.size() - 1), false)
		return

	var clamped_elapsed := minf(target_elapsed, duration)
	var next_frame := clampi(int(floor(clamped_elapsed * fps)), 0, frames.size() - 1)
	for entered_frame in range(previous_step + 1, next_frame + 1):
		_emit_frame_events(entered_frame)
	_elapsed = clamped_elapsed
	_apply_frame(next_frame, false)
	if target_elapsed >= duration:
		_playing = false
		_paused = false
		_update_processing()
		animation_finished.emit(animation["id"])


func _draw() -> void:
	if not is_loaded():
		return
	if Engine.is_editor_hint() and not preview_first_frame:
		return
	for item in _render_items:
		var image_data: Dictionary = item["image"]
		var texture := sprite_loop.get_texture(image_data["asset_path"])
		if texture == null:
			continue
		var points: PackedVector2Array = _transform_image_corners(item["frame_part"], image_data)
		var uv: Rect2 = image_data["uv"]
		var uvs := PackedVector2Array([
			Vector2(uv.position.x, uv.position.y),
			Vector2(uv.end.x, uv.position.y),
			Vector2(uv.end.x, uv.end.y),
			Vector2(uv.position.x, uv.end.y),
		])
		var frame_part: Dictionary = item["frame_part"]
		var tint: Color = frame_part["tint"]
		var color := Color(tint.r, tint.g, tint.b, frame_part["opacity"] * item["alpha"])
		var colors := PackedColorArray([color, color, color, color])
		draw_polygon(points, colors, uvs, texture)


## Starts an animation selected by ID or display name. An empty reference selects
## the configured default animation, or the package's first animation.
func play(animation_reference: String = "", playback_loop_mode: int = LoopMode.FROM_PACKAGE,
		restart: bool = true) -> bool:
	if not is_loaded():
		return false
	var reference := animation_reference
	if reference.is_empty():
		reference = default_animation
	if reference.is_empty() and not _animations.is_empty():
		reference = _animations[0]["id"]
	var index := _resolve_animation(reference)
	if index < 0:
		_set_error("SpriteLoop: animation '%s' was not found." % reference)
		return false
	var changed := index != _animation_index
	_animation_index = index
	loop_mode = clampi(playback_loop_mode, LoopMode.FROM_PACKAGE, LoopMode.ONCE)
	if changed or restart:
		_elapsed = 0.0
		_apply_frame(0, false)
	_playing = true
	_paused = false
	_update_processing()
	return true


func pause() -> void:
	if not _playing:
		return
	_playing = false
	_paused = true
	_update_processing()


func resume() -> void:
	if not _paused or _animation_index < 0:
		return
	_paused = false
	_playing = true
	_update_processing()


func stop() -> void:
	_playing = false
	_paused = false
	_update_processing()


func set_animation_frame(frame: int, emit_events: bool = false) -> void:
	if _animation_index < 0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frames.is_empty():
		return
	var clamped_frame := clampi(frame, 0, frames.size() - 1)
	_elapsed = float(clamped_frame) / float(animation["fps"])
	_apply_frame(clamped_frame, emit_events)


func set_animation_time(seconds: float, emit_events: bool = false) -> void:
	if _animation_index < 0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frames.is_empty():
		return
	var fps: float = animation["fps"]
	var duration := float(frames.size()) / fps
	_elapsed = fposmod(seconds, duration) if _effective_loop(animation) else clampf(seconds, 0.0, duration)
	_apply_frame(clampi(int(floor(_elapsed * fps)), 0, frames.size() - 1), emit_events)


func set_animation_progress(progress: float, emit_events: bool = false) -> void:
	if _animation_index < 0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frames.is_empty():
		return
	var normalized := clampf(progress, 0.0, 1.0)
	var target_frame := mini(int(floor(normalized * frames.size())), frames.size() - 1)
	set_animation_frame(target_frame, emit_events)


func set_skin(skin_reference: String) -> bool:
	var index := _resolve_skin(skin_reference)
	if index < 0:
		_set_error("SpriteLoop: skin '%s' was not found." % skin_reference)
		return false
	_skin_index = index
	if _frame_index >= 0:
		_apply_frame(_frame_index, false)
	return true


func set_variant(part_reference: String, variant_reference: String) -> bool:
	var part_index := _resolve_part(part_reference)
	var variant_index := _resolve_variant_for_part(part_index, variant_reference)
	if part_index < 0 or variant_index < 0:
		_set_error("SpriteLoop: variant '%s' is not valid for part '%s'." % [variant_reference, part_reference])
		return false
	_manual_variants[part_index] = variant_index
	if _frame_index >= 0:
		_apply_frame(_frame_index, false)
	return true


func clear_variant(part_reference: String) -> bool:
	var part_index := _resolve_part(part_reference)
	if part_index < 0 or not _manual_variants.erase(part_index):
		return false
	if _frame_index >= 0:
		_apply_frame(_frame_index, false)
	return true


func clear_variants() -> void:
	_manual_variants.clear()
	if _frame_index >= 0:
		_apply_frame(_frame_index, false)


func is_loaded() -> bool:
	return not _package_data.is_empty()


func is_playing() -> bool:
	return _playing


func is_paused() -> bool:
	return _paused


func get_package_name() -> String:
	return _package_data.get("name", "")


func get_current_animation_id() -> String:
	return _animations[_animation_index]["id"] if _animation_index >= 0 else ""


func get_current_animation_name() -> String:
	return _animations[_animation_index]["name"] if _animation_index >= 0 else ""


func get_current_skin_id() -> String:
	return _skins[_skin_index]["id"] if _skin_index >= 0 else ""


func get_current_skin_name() -> String:
	return _skins[_skin_index]["name"] if _skin_index >= 0 else ""


func get_current_frame() -> int:
	return _frame_index


func get_animation_time() -> float:
	return _elapsed


func get_animation_duration() -> float:
	if _animation_index < 0:
		return 0.0
	var animation: Dictionary = _animations[_animation_index]
	return float(animation["frames"].size()) / float(animation["fps"])


func get_animation_progress() -> float:
	var duration := get_animation_duration()
	return clampf(_elapsed / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func get_animation_count() -> int:
	return _animations.size()


func get_animation_id(index: int) -> String:
	return _animations[index]["id"] if index >= 0 and index < _animations.size() else ""


func get_animation_name(index: int) -> String:
	return _animations[index]["name"] if index >= 0 and index < _animations.size() else ""


func get_frame_count() -> int:
	return _animations[_animation_index]["frames"].size() if _animation_index >= 0 else 0


func get_skin_count() -> int:
	return _skins.size()


func get_skin_id(index: int) -> String:
	return _skins[index]["id"] if index >= 0 and index < _skins.size() else ""


func get_skin_name(index: int) -> String:
	return _skins[index]["name"] if index >= 0 and index < _skins.size() else ""


func get_part_count() -> int:
	return _parts.size()


func get_part_id(index: int) -> String:
	return _parts[index]["id"] if index >= 0 and index < _parts.size() else ""


func get_part_name(index: int) -> String:
	return _parts[index]["name"] if index >= 0 and index < _parts.size() else ""


func get_part_transform(part_reference: String) -> Transform2D:
	var index := _resolve_part(part_reference)
	return _part_transforms.get(index, Transform2D.IDENTITY)


func get_variant_count() -> int:
	return _variants.size()


func get_variant_id(index: int) -> String:
	return _variants[index]["id"] if index >= 0 and index < _variants.size() else ""


func get_variant_name(index: int) -> String:
	return _variants[index]["name"] if index >= 0 and index < _variants.size() else ""


func get_variant_part_id(index: int) -> String:
	if index < 0 or index >= _variants.size():
		return ""
	return _parts[_variants[index]["part_index"]]["id"]


func get_last_error() -> String:
	return _last_error


func _connect_package() -> void:
	if sprite_loop != null and not sprite_loop.changed.is_connected(_on_package_changed):
		sprite_loop.changed.connect(_on_package_changed)


func _disconnect_package() -> void:
	if sprite_loop != null and sprite_loop.changed.is_connected(_on_package_changed):
		sprite_loop.changed.disconnect(_on_package_changed)


func _on_package_changed() -> void:
	_reload_package()


func _reload_package() -> void:
	_clear_runtime_data()
	if sprite_loop == null:
		queue_redraw()
		return
	var manifest := sprite_loop.get_manifest()
	if manifest.is_empty():
		_set_error("SpriteLoop: the assigned package has no valid manifest.")
		load_failed.emit(_last_error)
		queue_redraw()
		return
	_package_data = _normalize_manifest(manifest)
	if _package_data.is_empty():
		load_failed.emit(_last_error)
		queue_redraw()
		return
	_initialize_playback()
	package_loaded.emit()


func _clear_runtime_data() -> void:
	_package_data.clear()
	_parts.clear()
	_variants.clear()
	_states.clear()
	_skins.clear()
	_animations.clear()
	_part_by_id.clear()
	_part_by_key_or_name.clear()
	_variant_by_id.clear()
	_state_by_id.clear()
	_skin_by_id.clear()
	_skin_by_name.clear()
	_animation_by_id.clear()
	_animation_by_name.clear()
	_manual_variants.clear()
	_render_items.clear()
	_part_transforms.clear()
	_animation_index = -1
	_skin_index = -1
	_frame_index = -1
	_elapsed = 0.0
	_playing = false
	_paused = false
	_last_error = ""
	_update_processing()


func _initialize_playback() -> void:
	_skin_index = 0 if not _skins.is_empty() else -1
	if _animations.is_empty():
		queue_redraw()
		return
	var index := _resolve_animation(default_animation)
	if index < 0:
		index = 0
	_animation_index = index
	_elapsed = 0.0
	_apply_frame(0, false)
	_playing = _ready_complete and not Engine.is_editor_hint() and autoplay
	_paused = false
	_update_processing()


func _update_processing() -> void:
	set_process(_ready_complete and not Engine.is_editor_hint() and _playing)


func _set_error(message: String) -> void:
	_last_error = message
	push_error(message)


func _normalize_manifest(manifest: Dictionary) -> Dictionary:
	if str(manifest.get("format", "")) != "spla":
		_set_error("SpriteLoop: the assigned resource is not an SPLA package.")
		return {}
	if int(manifest.get("version", 0)) != 1:
		_set_error("SpriteLoop: only SPLA manifest version 1 is supported.")
		return {}
	var raw_canvas: Variant = manifest.get("canvas", {})
	if not raw_canvas is Dictionary:
		_set_error("SpriteLoop: the manifest canvas is invalid.")
		return {}
	var canvas_width := _number(raw_canvas.get("width"), 0.0)
	var canvas_height := _number(raw_canvas.get("height"), 0.0)
	if canvas_width <= 0.0 or canvas_height <= 0.0:
		_set_error("SpriteLoop: canvas width and height must be positive.")
		return {}
	var raw_parts: Variant = manifest.get("parts", null)
	var raw_animations: Variant = manifest.get("animations", null)
	if not (raw_parts is Array) or not (raw_animations is Array):
		_set_error("SpriteLoop: manifest parts and animations must be arrays.")
		return {}

	for index in range(raw_parts.size()):
		var raw_part: Variant = raw_parts[index]
		if not raw_part is Dictionary:
			raw_part = {}
		var id := _string(raw_part.get("id"))
		if id.is_empty():
			_set_error("SpriteLoop: part %d has no ID." % index)
			return {}
		if _part_by_id.has(id):
			_set_error("SpriteLoop: duplicate part ID '%s'." % id)
			return {}
		var asset_path := SpriteLoopResource.normalize_asset_path(_string(raw_part.get("asset")))
		var key := _string(raw_part.get("key"), _string(raw_part.get("name"), id))
		var name := _string(raw_part.get("name"), key)
		var uv := _normalize_uv(raw_part)
		if not _last_error.is_empty():
			return {}
		var pivot: Variant = raw_part.get("pivot", {})
		if not pivot is Dictionary:
			pivot = {}
		var part := {
			"index": index,
			"id": id,
			"key": key,
			"name": name,
			"kind": _string(raw_part.get("kind"), "image" if not asset_path.is_empty() else "empty"),
			"asset_path": asset_path,
			"width": maxf(0.0, _number(raw_part.get("width"), 0.0)),
			"height": maxf(0.0, _number(raw_part.get("height"), 0.0)),
			"pivot_x": _number(pivot.get("x"), 0.0),
			"pivot_y": _number(pivot.get("y"), 0.0),
			"draw_order": _integer(raw_part.get("drawOrder"), index),
			"visible": raw_part.get("visible", true) != false,
			"uv": uv,
		}
		_parts.append(part)
		_part_by_id[id] = index
		_add_folded(_part_by_key_or_name, key, index)
		_add_folded(_part_by_key_or_name, name, index)

	var raw_variants: Variant = manifest.get("variants", [])
	if raw_variants is Array:
		for raw_variant in raw_variants:
			if not raw_variant is Dictionary:
				continue
			var part_index := _resolve_part(_string(raw_variant.get("part")))
			if part_index < 0:
				continue
			var asset_path := SpriteLoopResource.normalize_asset_path(_string(raw_variant.get("asset")))
			if asset_path.is_empty():
				continue
			var part: Dictionary = _parts[part_index]
			var index := _variants.size()
			var key := _string(raw_variant.get("key"), _string(raw_variant.get("name"), "variant_%d" % index))
			var name := _string(raw_variant.get("name"), key)
			var uv := _normalize_uv(raw_variant)
			if not _last_error.is_empty():
				return {}
			var variant := {
				"index": index,
				"id": _string(raw_variant.get("id"), "variant_%d" % index),
				"key": key,
				"name": name,
				"part_index": part_index,
				"asset_path": asset_path,
				"width": maxf(0.0, _number(raw_variant.get("width"), part["width"])),
				"height": maxf(0.0, _number(raw_variant.get("height"), part["height"])),
				"pivot_x": part["pivot_x"] - _number(raw_variant.get("offsetX"), 0.0),
				"pivot_y": part["pivot_y"] - _number(raw_variant.get("offsetY"), 0.0),
				"rotation": _number(raw_variant.get("rotation"), 0.0),
				"z_offset": _integer(raw_variant.get("zOffset"), 0),
				"uv": uv,
			}
			_variants.append(variant)
			_add_exact(_variant_by_id, variant["id"], index)

	var raw_states: Variant = manifest.get("states", [])
	if raw_states is Array:
		for raw_state in raw_states:
			if not raw_state is Dictionary:
				continue
			var part_index := _resolve_part(_string(raw_state.get("part")))
			if part_index < 0:
				continue
			var index := _states.size()
			var key := _string(raw_state.get("key"), _string(raw_state.get("name"), "state_%d" % index))
			var state := {
				"index": index,
				"id": _string(raw_state.get("id"), "state_%d" % index),
				"key": key,
				"name": _string(raw_state.get("name"), key),
				"part_index": part_index,
			}
			_states.append(state)
			_add_exact(_state_by_id, state["id"], index)

	var raw_skins: Variant = manifest.get("skins", [])
	if raw_skins is Array:
		for raw_skin_index in range(raw_skins.size()):
			var raw_skin: Variant = raw_skins[raw_skin_index]
			if not raw_skin is Dictionary:
				raw_skin = {}
			var id := _string(raw_skin.get("id"), "skin_%d" % raw_skin_index)
			var skin := {
				"index": _skins.size(),
				"id": id,
				"name": _string(raw_skin.get("name"), id),
				"overrides": {},
			}
			var raw_overrides: Variant = raw_skin.get("parts", {})
			if raw_overrides is Dictionary:
				for part_reference in raw_overrides:
					var part_index := _resolve_part(_string(part_reference))
					if part_index < 0:
						continue
					var raw_override: Variant = raw_overrides[part_reference]
					if not raw_override is Dictionary:
						raw_override = {}
					var override := {
						"variant_index": _resolve_variant_for_part(part_index, _string(raw_override.get("variant"))),
						"has_visible": raw_override.has("visible"),
						"visible": raw_override.get("visible", true) != false,
						"state_variants": {},
					}
					var raw_state_variants: Variant = raw_override.get("states", {})
					if raw_state_variants is Dictionary:
						for state_reference in raw_state_variants:
							var state_index := _resolve_state_for_part(part_index, _string(state_reference))
							var variant_index := _resolve_variant_for_part(part_index, _string(raw_state_variants[state_reference]))
							if state_index >= 0 and variant_index >= 0:
								override["state_variants"][state_index] = variant_index
					skin["overrides"][part_index] = override
			_skins.append(skin)
			_add_exact(_skin_by_id, skin["id"], skin["index"])
			_add_folded(_skin_by_name, skin["name"], skin["index"])

	if _skins.is_empty():
		var default_skin := {"index": 0, "id": "default", "name": "Default", "overrides": {}}
		_skins.append(default_skin)
		_skin_by_id["default"] = 0
		_skin_by_name["default"] = 0

	for raw_animation_index in range(raw_animations.size()):
		var raw_animation: Variant = raw_animations[raw_animation_index]
		if not raw_animation is Dictionary:
			raw_animation = {}
		var id := _string(raw_animation.get("id"), "animation_%d" % raw_animation_index)
		var animation := {
			"index": _animations.size(),
			"id": id,
			"name": _string(raw_animation.get("name"), id),
			"fps": maxf(0.0001, _number(raw_animation.get("fps"), 24.0)),
			"loop": raw_animation.get("loop", false) == true,
			"frames": [],
		}
		var raw_frames: Variant = raw_animation.get("frames", [])
		if raw_frames is Array:
			for raw_frame_index in range(raw_frames.size()):
				var raw_frame: Variant = raw_frames[raw_frame_index]
				if not raw_frame is Dictionary:
					raw_frame = {}
				var frame := {
					"index": _integer(raw_frame.get("index"), raw_frame_index),
					"source_frame": _integer(raw_frame.get("sourceFrame"), raw_frame_index),
					"parts": [],
					"events": [],
				}
				var raw_frame_parts: Variant = raw_frame.get("parts", [])
				if raw_frame_parts is Array:
					for raw_frame_part in raw_frame_parts:
						if not raw_frame_part is Dictionary:
							continue
						var part_index := _resolve_part(_string(raw_frame_part.get("part")))
						if part_index < 0:
							continue
						frame["parts"].append({
							"part_index": part_index,
							"z_offset": _integer(raw_frame_part.get("zOffset"), 0),
							"x": _number(raw_frame_part.get("x"), 0.0),
							"y": _number(raw_frame_part.get("y"), 0.0),
							"rotation": _number(raw_frame_part.get("rotation"), 0.0),
							"skew_x": _number(raw_frame_part.get("skewX"), 0.0),
							"skew_y": _number(raw_frame_part.get("skewY"), 0.0),
							"scale_x": _number(raw_frame_part.get("scaleX"), 1.0),
							"scale_y": _number(raw_frame_part.get("scaleY"), 1.0),
							"opacity": clampf(_number(raw_frame_part.get("opacity"), 1.0), 0.0, 1.0),
							"tint": _normalize_tint(raw_frame_part.get("tint")),
							"state_index": _resolve_state_for_part(part_index, _state_reference(raw_frame_part, false)),
							"next_state_index": _resolve_state_for_part(part_index, _state_reference(raw_frame_part, true)),
							"state_mix": _state_mix(raw_frame_part),
						})
				var raw_events: Variant = raw_frame.get("events", [])
				if raw_events is Array:
					for raw_event in raw_events:
						if raw_event is Dictionary:
							frame["events"].append({
								"name": _string(raw_event.get("name")),
								"data": _string(raw_event.get("data")),
							})
				animation["frames"].append(frame)
		animation["frames"].sort_custom(_sort_frames)
		_animations.append(animation)
		_add_exact(_animation_by_id, animation["id"], animation["index"])
		_add_folded(_animation_by_name, animation["name"], animation["index"])

	return {
		"name": _string(manifest.get("name")),
		"canvas_width": canvas_width,
		"canvas_height": canvas_height,
	}


func _normalize_uv(raw_item: Dictionary) -> Rect2:
	var atlas: Variant = raw_item.get("atlas", null)
	if not atlas is Dictionary:
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var texture_width := _number(atlas.get("textureWidth"), 0.0)
	var texture_height := _number(atlas.get("textureHeight"), 0.0)
	var width := _number(atlas.get("width"), 0.0)
	var height := _number(atlas.get("height"), 0.0)
	if texture_width <= 0.0 or texture_height <= 0.0 or width <= 0.0 or height <= 0.0:
		_set_error("SpriteLoop: invalid texture-atlas metadata in the manifest.")
		return Rect2()
	var x := clampf(_number(atlas.get("x"), 0.0) / texture_width, 0.0, 1.0)
	var y := clampf(_number(atlas.get("y"), 0.0) / texture_height, 0.0, 1.0)
	return Rect2(x, y, clampf(width / texture_width, 0.0, 1.0 - x), clampf(height / texture_height, 0.0, 1.0 - y))


func _normalize_tint(value: Variant) -> Color:
	if value is Array:
		return Color(
			clampf(_number(value[0] if value.size() > 0 else null, 1.0), 0.0, 1.0),
			clampf(_number(value[1] if value.size() > 1 else null, 1.0), 0.0, 1.0),
			clampf(_number(value[2] if value.size() > 2 else null, 1.0), 0.0, 1.0),
		)
	if value is Dictionary:
		return Color(
			clampf(_number(value.get("r"), 1.0), 0.0, 1.0),
			clampf(_number(value.get("g"), 1.0), 0.0, 1.0),
			clampf(_number(value.get("b"), 1.0), 0.0, 1.0),
		)
	return Color.WHITE


func _state_reference(raw_frame_part: Dictionary, next: bool) -> String:
	var raw_state: Variant = raw_frame_part.get("state", null)
	if raw_state is Dictionary:
		return _string(raw_state.get("next" if next else "current", raw_state.get("id", "") if not next else ""))
	return _string(raw_frame_part.get("nextState" if next else "state"))


func _state_mix(raw_frame_part: Dictionary) -> float:
	var raw_state: Variant = raw_frame_part.get("state", null)
	var value: Variant = raw_state.get("mix", 0.0) if raw_state is Dictionary else raw_frame_part.get("stateMix", 0.0)
	return clampf(_number(value, 0.0), 0.0, 1.0)


func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		var number := float(value)
		return number if is_finite(number) else fallback
	return fallback


func _integer(value: Variant, fallback: int) -> int:
	return int(_number(value, float(fallback)))


func _string(value: Variant, fallback: String = "") -> String:
	return fallback if value == null else str(value)


func _add_exact(lookup: Dictionary, key: String, value: int) -> void:
	if not key.is_empty() and not lookup.has(key):
		lookup[key] = value


func _add_folded(lookup: Dictionary, key: String, value: int) -> void:
	var folded := key.to_lower()
	if not folded.is_empty() and not lookup.has(folded):
		lookup[folded] = value


func _sort_frames(left: Dictionary, right: Dictionary) -> bool:
	return left["index"] < right["index"]


func _resolve_animation(reference: String) -> int:
	if reference.is_empty():
		return -1
	if _animation_by_id.has(reference):
		return _animation_by_id[reference]
	return _animation_by_name.get(reference.to_lower(), -1)


func _resolve_skin(reference: String) -> int:
	if reference.is_empty():
		return -1
	if _skin_by_id.has(reference):
		return _skin_by_id[reference]
	return _skin_by_name.get(reference.to_lower(), -1)


func _resolve_part(reference: String) -> int:
	if reference.is_empty():
		return -1
	if _part_by_id.has(reference):
		return _part_by_id[reference]
	return _part_by_key_or_name.get(reference.to_lower(), -1)


func _resolve_variant_for_part(part_index: int, reference: String) -> int:
	if part_index < 0 or reference.is_empty():
		return -1
	if _variant_by_id.has(reference):
		var exact_index: int = _variant_by_id[reference]
		if _variants[exact_index]["part_index"] == part_index:
			return exact_index
	var folded := reference.to_lower()
	for variant in _variants:
		if variant["part_index"] == part_index and (variant["key"].to_lower() == folded or variant["name"].to_lower() == folded):
			return variant["index"]
	return -1


func _resolve_state_for_part(part_index: int, reference: String) -> int:
	if part_index < 0 or reference.is_empty():
		return -1
	if _state_by_id.has(reference):
		var exact_index: int = _state_by_id[reference]
		if _states[exact_index]["part_index"] == part_index:
			return exact_index
	var folded := reference.to_lower()
	for state in _states:
		if state["part_index"] == part_index and (state["key"].to_lower() == folded or state["name"].to_lower() == folded):
			return state["index"]
	return -1


func _base_image(part: Dictionary) -> Dictionary:
	return {
		"asset_path": part["asset_path"],
		"uv": part["uv"],
		"width": part["width"],
		"height": part["height"],
		"pivot_x": part["pivot_x"],
		"pivot_y": part["pivot_y"],
		"rotation": 0.0,
		"z_offset": 0,
		"variant_index": -1,
	}


func _variant_image(variant: Dictionary) -> Dictionary:
	return {
		"asset_path": variant["asset_path"],
		"uv": variant["uv"],
		"width": variant["width"],
		"height": variant["height"],
		"pivot_x": variant["pivot_x"],
		"pivot_y": variant["pivot_y"],
		"rotation": variant["rotation"],
		"z_offset": variant["z_offset"],
		"variant_index": variant["index"],
	}


func _resolve_image(part: Dictionary, skin: Dictionary, state_index: int) -> Dictionary:
	var part_index: int = part["index"]
	if _manual_variants.has(part_index):
		return _variant_image(_variants[_manual_variants[part_index]])
	var overrides: Dictionary = skin.get("overrides", {})
	if overrides.has(part_index):
		var override: Dictionary = overrides[part_index]
		var state_variants: Dictionary = override["state_variants"]
		if state_index >= 0 and state_variants.has(state_index):
			return _variant_image(_variants[state_variants[state_index]])
		if override["variant_index"] >= 0:
			return _variant_image(_variants[override["variant_index"]])
	return _base_image(part)


func _apply_frame(frame: int, emit_events: bool) -> void:
	if _animation_index < 0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frame < 0 or frame >= frames.size():
		return
	var changed := frame != _frame_index
	_frame_index = frame
	_build_render_items(frames[frame])
	queue_redraw()
	if changed:
		frame_changed.emit(frame)
	if emit_events:
		_emit_frame_events(frame)


func _build_render_items(frame: Dictionary) -> void:
	_render_items.clear()
	_part_transforms.clear()
	var skin: Dictionary = _skins[_skin_index] if _skin_index >= 0 else {}
	var sequence := 0
	for frame_part in frame["parts"]:
		var part_index: int = frame_part["part_index"]
		var part: Dictionary = _parts[part_index]
		_part_transforms[part_index] = _frame_part_transform(frame_part)
		if part["kind"] == "empty" or part["asset_path"].is_empty():
			continue
		var overrides: Dictionary = skin.get("overrides", {})
		var override: Dictionary = overrides.get(part_index, {})
		var visible: bool = override.get("visible", part["visible"]) if override.get("has_visible", false) else part["visible"]
		if not visible or frame_part["opacity"] <= 0.0:
			continue
		var first_image := _resolve_image(part, skin, frame_part["state_index"])
		var second_image: Variant = null
		if frame_part["next_state_index"] >= 0 and frame_part["state_mix"] > 0.0:
			second_image = _resolve_image(part, skin, frame_part["next_state_index"])
		var same_image: bool = (
			second_image is Dictionary
			and second_image["asset_path"] == first_image["asset_path"]
			and second_image["variant_index"] == first_image["variant_index"]
		)
		var first_alpha: float = 1.0 - frame_part["state_mix"] if second_image is Dictionary and not same_image else 1.0
		if not first_image["asset_path"].is_empty() and first_alpha > 0.0:
			_render_items.append({
				"frame_part": frame_part,
				"part_index": part_index,
				"image": first_image,
				"alpha": first_alpha,
				"order": part["draw_order"] + frame_part["z_offset"] + first_image["z_offset"],
				"sequence": sequence,
			})
			sequence += 1
		if second_image is Dictionary and not same_image and not second_image["asset_path"].is_empty() and frame_part["state_mix"] > 0.0:
			_render_items.append({
				"frame_part": frame_part,
				"part_index": part_index,
				"image": second_image,
				"alpha": frame_part["state_mix"],
				"order": part["draw_order"] + frame_part["z_offset"] + second_image["z_offset"],
				"sequence": sequence,
			})
			sequence += 1
	_render_items.sort_custom(_sort_render_items)


func _sort_render_items(left: Dictionary, right: Dictionary) -> bool:
	if left["order"] != right["order"]:
		return left["order"] < right["order"]
	if left["part_index"] != right["part_index"]:
		return left["part_index"] < right["part_index"]
	return left["sequence"] < right["sequence"]


func _frame_part_transform(frame_part: Dictionary) -> Transform2D:
	var rotation := deg_to_rad(frame_part["rotation"])
	var cos_rotation := cos(rotation)
	var sin_rotation := sin(rotation)
	var skew_x := tan(deg_to_rad(frame_part["skew_x"]))
	var skew_y := tan(deg_to_rad(frame_part["skew_y"]))
	var scale_x: float = frame_part["scale_x"]
	var scale_y: float = frame_part["scale_y"]
	var x_axis := Vector2(
		scale_x * cos_rotation - skew_y * scale_x * sin_rotation,
		scale_x * sin_rotation + skew_y * scale_x * cos_rotation,
	)
	var y_axis := Vector2(
		skew_x * scale_y * cos_rotation - scale_y * sin_rotation,
		skew_x * scale_y * sin_rotation + scale_y * cos_rotation,
	)
	return Transform2D(x_axis, y_axis, Vector2(frame_part["x"], frame_part["y"]) + _canvas_offset())


func _transform_image_corners(frame_part: Dictionary, image_data: Dictionary) -> PackedVector2Array:
	var left: float = -image_data["pivot_x"]
	var top: float = -image_data["pivot_y"]
	var right: float = image_data["width"] - image_data["pivot_x"]
	var bottom: float = image_data["height"] - image_data["pivot_y"]
	var rotation := deg_to_rad(frame_part["rotation"] + image_data["rotation"])
	var cos_rotation := cos(rotation)
	var sin_rotation := sin(rotation)
	var skew_x := tan(deg_to_rad(frame_part["skew_x"]))
	var skew_y := tan(deg_to_rad(frame_part["skew_y"]))
	var offset := Vector2(frame_part["x"], frame_part["y"]) + _canvas_offset()
	var result := PackedVector2Array()
	for corner in [Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]:
		var scaled_x: float = corner.x * float(frame_part["scale_x"])
		var scaled_y: float = corner.y * float(frame_part["scale_y"])
		var skewed_x: float = scaled_x + skew_x * scaled_y
		var skewed_y: float = skew_y * scaled_x + scaled_y
		result.append(offset + Vector2(
			skewed_x * cos_rotation - skewed_y * sin_rotation,
			skewed_x * sin_rotation + skewed_y * cos_rotation,
		))
	return result


func _canvas_offset() -> Vector2:
	if not center_on_origin:
		return Vector2.ZERO
	return Vector2(-float(_package_data["canvas_width"]) * 0.5, -float(_package_data["canvas_height"]) * 0.5)


func _effective_loop(animation: Dictionary) -> bool:
	return loop_mode == LoopMode.LOOP or (loop_mode == LoopMode.FROM_PACKAGE and animation["loop"])


func _emit_frame_events(frame: int) -> void:
	if not emit_authored_events or _animation_index < 0:
		return
	var animation: Dictionary = _animations[_animation_index]
	var frames: Array = animation["frames"]
	if frame < 0 or frame >= frames.size():
		return
	var frame_data: Dictionary = frames[frame]
	for event_data in frame_data["events"]:
		animation_event.emit(animation["id"], frame, frame_data["source_frame"], event_data["name"], event_data["data"])

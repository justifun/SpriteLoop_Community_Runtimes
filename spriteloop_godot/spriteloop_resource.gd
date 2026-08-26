@tool
class_name SpriteLoopResource
extends Resource

## Imported data for one SpriteLoop .spla package.
##
## The editor importer stores the manifest and only the referenced image files.
## Decoded ImageTextures are cached on this shared Resource, so multiple players
## using the same package do not decode duplicate textures.

@export_storage var source_file: String = ""
@export_storage var manifest_json: String = ""
@export_storage var asset_bytes: Dictionary = {}

var _manifest_cache: Dictionary = {}
var _texture_cache: Dictionary = {}


func set_package(p_source_file: String, p_manifest_json: String, p_asset_bytes: Dictionary) -> void:
	source_file = p_source_file
	manifest_json = p_manifest_json
	asset_bytes = p_asset_bytes.duplicate()
	clear_runtime_cache()
	emit_changed()


func get_manifest() -> Dictionary:
	if not _manifest_cache.is_empty():
		return _manifest_cache
	if manifest_json.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(manifest_json)
	if parsed is Dictionary:
		_manifest_cache = parsed
	return _manifest_cache


func get_texture(asset_path: String) -> Texture2D:
	var normalized_path := normalize_asset_path(asset_path)
	if normalized_path.is_empty():
		return null
	if _texture_cache.has(normalized_path):
		return _texture_cache[normalized_path] as Texture2D
	if not asset_bytes.has(normalized_path):
		return null

	var bytes: PackedByteArray = asset_bytes[normalized_path]
	var image := Image.new()
	var error := _load_image_buffer(image, bytes, normalized_path.get_extension().to_lower())
	if error != OK:
		push_error("SpriteLoop: could not decode '%s' from '%s'." % [normalized_path, source_file])
		return null

	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = normalized_path.get_file().get_basename()
	_texture_cache[normalized_path] = texture
	return texture


func clear_runtime_cache() -> void:
	_manifest_cache.clear()
	_texture_cache.clear()


static func normalize_asset_path(path: String) -> String:
	var normalized_parts := PackedStringArray()
	for segment in path.replace("\\", "/").split("/", false):
		if segment == "." or segment.is_empty():
			continue
		if segment == "..":
			return ""
		normalized_parts.append(segment)
	return "/".join(normalized_parts)


static func _load_image_buffer(image: Image, bytes: PackedByteArray, extension: String) -> Error:
	match extension:
		"png":
			return image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			return image.load_jpg_from_buffer(bytes)
		"webp":
			return image.load_webp_from_buffer(bytes)
		_:
			var error := image.load_png_from_buffer(bytes)
			if error == OK:
				return OK
			error = image.load_jpg_from_buffer(bytes)
			if error == OK:
				return OK
			return image.load_webp_from_buffer(bytes)


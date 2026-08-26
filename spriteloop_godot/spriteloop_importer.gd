@tool
extends EditorImportPlugin

const SpriteLoopResourceScript = preload("res://addons/spriteloop/spriteloop_resource.gd")


func _get_importer_name() -> String:
	return "justifun.spriteloop"


func _get_visible_name() -> String:
	return "SpriteLoop Package"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["spla"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	# Script classes are not native ClassDB types, so the importer advertises the
	# built-in base type. The saved resource still carries SpriteLoopResource's
	# script and loads as SpriteLoopResource at runtime.
	return "Resource"


func _get_priority() -> float:
	return 1.0


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(source_file: String, save_path: String, _options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var archive := ZIPReader.new()
	var error := archive.open(source_file)
	if error != OK:
		return _import_error(source_file, "could not open the SPLA ZIP archive", error)

	var entries: Dictionary = {}
	for archive_path in archive.get_files():
		var normalized_path := SpriteLoopResourceScript.normalize_asset_path(archive_path)
		if not normalized_path.is_empty() and not archive_path.ends_with("/"):
			entries[normalized_path.to_lower()] = archive_path

	if not entries.has("manifest.json"):
		archive.close()
		return _import_error(source_file, "the archive does not contain manifest.json", ERR_FILE_NOT_FOUND)

	var manifest_bytes := archive.read_file(entries["manifest.json"])
	var manifest_json := manifest_bytes.get_string_from_utf8()
	var parser := JSON.new()
	error = parser.parse(manifest_json)
	if error != OK:
		archive.close()
		var detail := "invalid manifest JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		return _import_error(source_file, detail, ERR_PARSE_ERROR)
	if not parser.data is Dictionary:
		archive.close()
		return _import_error(source_file, "manifest.json must contain a JSON object", ERR_INVALID_DATA)

	var manifest: Dictionary = parser.data
	error = _validate_manifest(manifest)
	if error != OK:
		archive.close()
		return _import_error(source_file, "only a valid SPLA manifest version 1 is supported", error)

	var referenced_assets: Dictionary = {}
	for collection_name in ["parts", "variants"]:
		var collection: Variant = manifest.get(collection_name, [])
		if not (collection is Array):
			continue
		for raw_item in collection:
			if not raw_item is Dictionary:
				continue
			var raw_path := str(raw_item.get("asset", ""))
			if raw_path.is_empty():
				continue
			var normalized_path := SpriteLoopResourceScript.normalize_asset_path(raw_path)
			if normalized_path.is_empty():
				archive.close()
				return _import_error(source_file, "unsafe asset path '%s'" % raw_path, ERR_INVALID_DATA)
			referenced_assets[normalized_path] = true

	var imported_assets: Dictionary = {}
	for asset_path in referenced_assets:
		var lookup_key: String = asset_path.to_lower()
		if not entries.has(lookup_key):
			archive.close()
			return _import_error(source_file, "referenced image '%s' is missing" % asset_path, ERR_FILE_NOT_FOUND)
		var bytes := archive.read_file(entries[lookup_key])
		if bytes.is_empty():
			archive.close()
			return _import_error(source_file, "referenced image '%s' is empty" % asset_path, ERR_FILE_CORRUPT)
		var image := Image.new()
		error = SpriteLoopResourceScript._load_image_buffer(image, bytes, asset_path.get_extension().to_lower())
		if error != OK:
			archive.close()
			return _import_error(source_file, "referenced image '%s' could not be decoded" % asset_path, error)
		imported_assets[asset_path] = bytes

	archive.close()
	var resource = SpriteLoopResourceScript.new()
	resource.set_package(source_file, manifest_json, imported_assets)
	return ResourceSaver.save(resource, "%s.%s" % [save_path, _get_save_extension()], ResourceSaver.FLAG_COMPRESS)


func _validate_manifest(manifest: Dictionary) -> Error:
	if str(manifest.get("format", "")) != "spla" or int(manifest.get("version", 0)) != 1:
		return ERR_INVALID_DATA
	var canvas: Variant = manifest.get("canvas", {})
	if not canvas is Dictionary:
		return ERR_INVALID_DATA
	if float(canvas.get("width", 0.0)) <= 0.0 or float(canvas.get("height", 0.0)) <= 0.0:
		return ERR_INVALID_DATA
	if not (manifest.get("parts", null) is Array) or not (manifest.get("animations", null) is Array):
		return ERR_INVALID_DATA
	return OK


func _import_error(source_file: String, message: String, error: Error) -> Error:
	push_error("SpriteLoop: failed to import '%s': %s." % [source_file, message])
	return error

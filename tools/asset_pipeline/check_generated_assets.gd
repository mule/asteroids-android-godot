extends SceneTree


const MANIFEST_PATH := "res://assets/generated/manifest.json"


func _init() -> void:
	var failures: Array[String] = []
	var manifest := _load_manifest()
	if manifest.is_empty():
		quit(1)
		return

	for asset: Dictionary in manifest.get("assets", []):
		var resource := load("res://" + str(asset.get("output_path", "")))
		if resource == null:
			failures.append("failed to load asset " + str(asset.get("output_path", "")))
			continue
		if resource.get("asset_id") != StringName(str(asset.get("asset_id", ""))):
			failures.append("asset_id mismatch for " + str(asset.get("output_path", "")))
		if resource.has_method("is_primary_polygon_valid") and not resource.is_primary_polygon_valid():
			failures.append("invalid primary polygon for " + str(asset.get("output_path", "")))

	for material: Dictionary in manifest.get("materials", []):
		var resource := load("res://" + str(material.get("output_path", "")))
		if resource == null:
			failures.append("failed to load material " + str(material.get("output_path", "")))
			continue
		if resource.get("material_id") != StringName(str(material.get("material_id", ""))):
			failures.append("material_id mismatch for " + str(material.get("output_path", "")))

	for failure: String in failures:
		printerr(failure)
	if failures.is_empty():
		print("OK generated asset resources load")
		quit(0)
	else:
		quit(1)


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		printerr("missing " + MANIFEST_PATH)
		return {}

	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		printerr("invalid " + MANIFEST_PATH)
		return {}
	return parsed

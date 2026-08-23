extends SceneTree


const GALLERY_SCENE := "res://scenes/tools/AssetGallery.tscn"


func _init() -> void:
	var packed_scene := load(GALLERY_SCENE) as PackedScene
	if packed_scene == null:
		printerr("failed to load " + GALLERY_SCENE)
		quit(1)
		return

	var gallery := packed_scene.instantiate()
	root.add_child(gallery)
	await process_frame

	var failures: Array[String] = []
	if gallery.records.size() < 6:
		failures.append("expected generated records from manifest")
	for category in ["ship", "asteroid", "bullet", "celestial", "station"]:
		if gallery._records_for_category(category).is_empty():
			failures.append("missing category " + category)
	if gallery.preview_grid.get_child_count() < 1:
		failures.append("preview grid did not build cards")
	if gallery.detail_label.text.is_empty():
		failures.append("detail panel is empty")

	for failure: String in failures:
		printerr(failure)
	if failures.is_empty():
		print("OK asset gallery loads generated records")
		quit(0)
	else:
		quit(1)

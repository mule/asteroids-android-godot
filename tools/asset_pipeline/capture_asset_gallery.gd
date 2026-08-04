extends SceneTree


const GALLERY_SCENE := "res://scenes/tools/AssetGallery.tscn"
const DEFAULT_OUTPUT := "res://art/generated/asset_gallery_contact_sheet.png"


func _init() -> void:
	var output_path := _get_output_path()
	var packed_scene := load(GALLERY_SCENE) as PackedScene
	if packed_scene == null:
		printerr("failed to load " + GALLERY_SCENE)
		quit(1)
		return

	root.size = Vector2i(1280, 900)
	var gallery := packed_scene.instantiate()
	root.add_child(gallery)
	await process_frame
	await process_frame

	var texture := root.get_texture()
	if texture == null:
		printerr("gallery capture requires a rendering display driver; headless mode has no viewport texture")
		quit(1)
		return

	var image := texture.get_image()
	if image == null:
		printerr("gallery capture requires a rendering display driver; headless mode has no viewport image")
		quit(1)
		return

	var error := image.save_png(output_path)
	if error == OK:
		print("Wrote " + output_path)
		quit(0)
	else:
		printerr("failed to write " + output_path + ": " + str(error))
		quit(1)


func _get_output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return DEFAULT_OUTPUT

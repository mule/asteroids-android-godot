extends Control


const DEFAULT_MANIFEST_PATH := "res://assets/generated/manifest.json"
const CATEGORY_ORDER := ["ship", "asteroid", "bullet", "celestial", "station"]
const CATEGORY_LABELS := {
	"ship": "Ships",
	"asteroid": "Asteroids",
	"bullet": "Bullets",
	"celestial": "Celestial",
	"station": "Stations",
}


class AssetRecord:
	var asset_id := ""
	var category := ""
	var output_path := ""
	var source_path := ""
	var resource: Resource
	var error := ""


class GalleryPreview:
	extends Control

	var asset: Resource
	var record: AssetRecord
	var rotation_active := true
	var show_collision := true
	var show_bounds := true
	var rotation_angle := 0.0
	var preview_scale := 1.0
	var phone_scale := false
	var rotating := false
	var background_color := Color(0.02, 0.025, 0.035, 1.0)
	var contrast_color := Color(0.84, 0.86, 0.78, 1.0)

	func _ready() -> void:
		custom_minimum_size = Vector2(170, 148)
		set_process(true)

	func _process(delta: float) -> void:
		if rotating and rotation_active:
			rotation_angle = wrapf(rotation_angle + delta * 0.75, 0.0, TAU)
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), background_color)
		draw_rect(Rect2(Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y)), contrast_color)
		if asset == null:
			_draw_centered_text("missing")
			return

		var bounds := _polygon_bounds(asset.primary_polygon)
		if bounds.size == Vector2.ZERO:
			_draw_centered_text("invalid")
			return

		var draw_scale := minf((size.x * 0.36) / maxf(bounds.size.x, 1.0), (size.y * 0.58) / maxf(bounds.size.y, 1.0))
		draw_scale *= preview_scale
		if phone_scale:
			draw_scale *= 0.42

		var draw_center := size * 0.5

		var primary := _transform_polygon(asset.primary_polygon, bounds, draw_scale, draw_center)
		draw_colored_polygon(primary, asset.fill_color)
		draw_polyline(primary + PackedVector2Array([primary[0]]), asset.outline_color if asset.outline_width > 0.0 else Color(1, 1, 1, 0.28), maxf(asset.outline_width, 1.0))

		for secondary: Resource in asset.secondary_polygons:
			if secondary == null or not secondary.visible_by_default:
				continue
			var secondary_polygon := _transform_polygon(secondary.polygon, bounds, draw_scale, draw_center)
			draw_colored_polygon(secondary_polygon, secondary.fill_color)
			draw_polyline(secondary_polygon + PackedVector2Array([secondary_polygon[0]]), Color(1, 1, 1, 0.22), 1.0)

		if show_collision:
			if asset.use_collision_polygon and asset.collision_polygon.size() >= 3:
				var collision_polygon := _transform_polygon(asset.collision_polygon, bounds, draw_scale, draw_center)
				draw_polyline(collision_polygon + PackedVector2Array([collision_polygon[0]]), Color(0.2, 1.0, 0.76, 0.9), 1.5)
			elif asset.collision_radius > 0.0:
				draw_arc(_transform_point(Vector2.ZERO, bounds, draw_scale, draw_center), asset.collision_radius * draw_scale, 0.0, TAU, 72, Color(0.2, 1.0, 0.76, 0.9), 1.5)

		if show_bounds:
			var corners := PackedVector2Array([
				_transform_point(bounds.position, bounds, draw_scale, draw_center),
				_transform_point(Vector2(bounds.end.x, bounds.position.y), bounds, draw_scale, draw_center),
				_transform_point(bounds.end, bounds, draw_scale, draw_center),
				_transform_point(Vector2(bounds.position.x, bounds.end.y), bounds, draw_scale, draw_center),
				_transform_point(bounds.position, bounds, draw_scale, draw_center),
			])
			draw_polyline(corners, Color(1.0, 0.78, 0.2, 0.9), 1.5)

	func _draw_centered_text(text: String) -> void:
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, (size - text_size) * 0.5 + Vector2(0.0, text_size.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.35, 0.3))

	func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
		if polygon.is_empty():
			return Rect2()
		var min_point := polygon[0]
		var max_point := polygon[0]
		for point: Vector2 in polygon:
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)
		return Rect2(min_point, max_point - min_point)

	func _transform_polygon(
		polygon: PackedVector2Array,
		bounds: Rect2,
		draw_scale: float,
		draw_center: Vector2
	) -> PackedVector2Array:
		var transformed := PackedVector2Array()
		for point: Vector2 in polygon:
			transformed.append(_transform_point(point, bounds, draw_scale, draw_center))
		return transformed

	func _transform_point(point: Vector2, bounds: Rect2, draw_scale: float, draw_center: Vector2) -> Vector2:
		return (point - bounds.get_center()).rotated(rotation_angle) * draw_scale + draw_center


var records: Array[AssetRecord] = []
var selected_category := "ship"
var selected_asset_id := ""
var rotation_active := true
var show_collision := true
var show_bounds := true
var category_buttons: Dictionary = {}
var preview_grid: GridContainer
var diagnostics_label: Label
var detail_label: Label
var pause_button: Button
var collision_button: Button
var bounds_button: Button
var manifest_path := DEFAULT_MANIFEST_PATH


func _ready() -> void:
	_apply_user_args()
	records = _load_asset_records()
	if records.any(func(record: AssetRecord) -> bool: return record.category == "asteroid"):
		selected_category = "asteroid"
	selected_asset_id = _first_asset_id_for_category(selected_category)
	_build_ui()
	_refresh_gallery()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _apply_user_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)

	for category in CATEGORY_ORDER:
		var button := Button.new()
		button.text = CATEGORY_LABELS[category]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(112, 44)
		button.pressed.connect(_on_category_pressed.bind(category))
		toolbar.add_child(button)
		category_buttons[category] = button

	toolbar.add_child(_toolbar_spacer())
	pause_button = _make_toggle_button("Pause", _on_pause_toggled)
	collision_button = _make_toggle_button("Collision", _on_collision_toggled)
	bounds_button = _make_toggle_button("Bounds", _on_bounds_toggled)
	toolbar.add_child(pause_button)
	toolbar.add_child(collision_button)
	toolbar.add_child(bounds_button)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	preview_grid = GridContainer.new()
	preview_grid.columns = 2
	preview_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_grid.add_theme_constant_override("h_separation", 10)
	preview_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(preview_grid)

	var details := PanelContainer.new()
	details.custom_minimum_size = Vector2(300, 0)
	body.add_child(details)

	var details_box := VBoxContainer.new()
	details_box.add_theme_constant_override("separation", 10)
	details.add_child(details_box)

	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_box.add_child(detail_label)

	diagnostics_label = Label.new()
	diagnostics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostics_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	details_box.add_child(diagnostics_label)


func _toolbar_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _make_toggle_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = true
	button.custom_minimum_size = Vector2(104, 44)
	button.toggled.connect(callback)
	return button


func _refresh_gallery() -> void:
	for category in category_buttons:
		category_buttons[category].button_pressed = category == selected_category
	pause_button.button_pressed = rotation_active
	collision_button.button_pressed = show_collision
	bounds_button.button_pressed = show_bounds

	for child in preview_grid.get_children():
		child.queue_free()

	var category_records := _records_for_category(selected_category)
	if category_records.is_empty():
		_add_diagnostic_card("No generated assets for " + selected_category)
	for record in category_records:
		preview_grid.add_child(_build_asset_card(record))

	_update_detail_panel()


func _build_asset_card(record: AssetRecord) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 360)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(record.asset_id))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var title := Label.new()
	title.text = record.asset_id
	title.clip_text = true
	box.add_child(title)

	var meta := Label.new()
	meta.text = _asset_summary(record)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meta)

	var previews := GridContainer.new()
	previews.columns = 2
	previews.size_flags_vertical = Control.SIZE_EXPAND_FILL
	previews.add_theme_constant_override("h_separation", 8)
	previews.add_theme_constant_override("v_separation", 8)
	box.add_child(previews)

	previews.add_child(_build_preview_stack("Canonical", record, false, false))
	previews.add_child(_build_preview_stack("Rotating", record, true, false))
	previews.add_child(_build_preview_stack("Gameplay", record, false, false, 0.78))
	previews.add_child(_build_preview_stack("Phone", record, false, true, 0.78))
	return card


func _build_preview_stack(
	label_text: String,
	record: AssetRecord,
	rotating: bool,
	phone_scale: bool,
	scale_multiplier: float = 1.0
) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var preview := GalleryPreview.new()
	preview.record = record
	preview.asset = record.resource
	preview.rotating = rotating
	preview.phone_scale = phone_scale
	preview.preview_scale = scale_multiplier
	preview.rotation_active = rotation_active
	preview.show_collision = show_collision
	preview.show_bounds = show_bounds
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(preview)
	return box


func _add_diagnostic_card(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.custom_minimum_size = Vector2(360, 120)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_grid.add_child(label)


func _update_detail_panel() -> void:
	var selected := _selected_record()
	var diagnostic_lines: Array[String] = []
	for record in records:
		if record.error != "":
			diagnostic_lines.append(record.asset_id + ": " + record.error)
	diagnostics_label.text = "\n".join(diagnostic_lines)

	if selected == null:
		detail_label.text = "No asset selected."
		return

	var bounds := _bounds_for(selected.resource)
	var material_ids := _material_ids_for(selected.resource)
	detail_label.text = "\n".join([
		selected.asset_id,
		"Category: " + selected.category,
		"Bounds: " + _format_vector(bounds.size),
		"Source: " + selected.source_path,
		"Resource: " + selected.output_path,
		"Materials: " + ", ".join(material_ids),
		"Collision: " + _collision_summary(selected.resource),
		"Tags: " + ", ".join(Array(selected.resource.tags)),
	])


func _load_asset_records() -> Array[AssetRecord]:
	var loaded_records: Array[AssetRecord] = []
	var manifest := _load_manifest()
	for entry in manifest.get("assets", []):
		var record := AssetRecord.new()
		record.asset_id = str(entry.get("asset_id", "unknown"))
		record.category = str(entry.get("category", "unknown"))
		record.output_path = str(entry.get("output_path", ""))
		record.source_path = str(entry.get("source_path", ""))
		if record.output_path == "":
			record.error = "manifest entry has no output_path"
		else:
			record.resource = load("res://" + record.output_path)
			if record.resource == null:
				record.error = "resource failed to load"
			elif not record.resource.has_method("is_primary_polygon_valid") or not record.resource.is_primary_polygon_valid():
				record.error = "resource primary polygon is invalid"
		loaded_records.append(record)

	loaded_records.sort_custom(func(a: AssetRecord, b: AssetRecord) -> bool:
		if a.category == b.category:
			return a.asset_id < b.asset_id
		return CATEGORY_ORDER.find(a.category) < CATEGORY_ORDER.find(b.category)
	)
	return loaded_records


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(manifest_path):
		return {"assets": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if parsed is Dictionary:
		return parsed
	return {"assets": []}


func _records_for_category(category: String) -> Array[AssetRecord]:
	var matches: Array[AssetRecord] = []
	for record in records:
		if record.category == category:
			matches.append(record)
	return matches


func _first_asset_id_for_category(category: String) -> String:
	for record in records:
		if record.category == category:
			return record.asset_id
	return ""


func _selected_record() -> AssetRecord:
	for record in records:
		if record.asset_id == selected_asset_id:
			return record
	return null


func _on_category_pressed(category: String) -> void:
	selected_category = category
	selected_asset_id = _first_asset_id_for_category(category)
	_refresh_gallery()


func _on_pause_toggled(enabled: bool) -> void:
	rotation_active = enabled
	_refresh_gallery()


func _on_collision_toggled(enabled: bool) -> void:
	show_collision = enabled
	_refresh_gallery()


func _on_bounds_toggled(enabled: bool) -> void:
	show_bounds = enabled
	_refresh_gallery()


func _on_card_input(event: InputEvent, asset_id: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		selected_asset_id = asset_id
		_update_detail_panel()
	elif event is InputEventScreenTouch and event.pressed:
		selected_asset_id = asset_id
		_update_detail_panel()


func _asset_summary(record: AssetRecord) -> String:
	if record.resource == null:
		return record.category + " | " + record.error
	var bounds := _bounds_for(record.resource)
	return record.category + " | " + _format_vector(bounds.size) + " | " + _collision_summary(record.resource)


func _bounds_for(asset: Resource) -> Rect2:
	if asset == null:
		return Rect2()
	var polygon: PackedVector2Array = asset.primary_polygon
	if polygon.is_empty():
		return Rect2()
	var min_point := polygon[0]
	var max_point := polygon[0]
	for point: Vector2 in polygon:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
	return Rect2(min_point, max_point - min_point)


func _format_vector(value: Vector2) -> String:
	return str(roundi(value.x)) + "x" + str(roundi(value.y))


func _collision_summary(asset: Resource) -> String:
	if asset == null:
		return "missing"
	if asset.use_collision_polygon:
		return "polygon " + str(asset.collision_polygon.size()) + " pts"
	if asset.collision_radius > 0.0:
		return "circle r" + str(roundi(asset.collision_radius))
	return "none"


func _material_ids_for(asset: Resource) -> Array[String]:
	var material_ids: Array[String] = []
	if asset == null:
		return material_ids
	if asset.material_definition != null:
		material_ids.append(str(asset.material_definition.material_id))
	for secondary: Resource in asset.secondary_polygons:
		if secondary != null and secondary.material_definition != null:
			material_ids.append(str(secondary.material_definition.material_id))
	return material_ids

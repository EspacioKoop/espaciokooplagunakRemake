extends SceneTree
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("RUNTIME_ASSET_FAIL " + label)

func run() -> void:
	var rows = RuntimeAssetLibrary.entries()
	check(rows.size() == 78, "all registered models present")
	var seen = {}
	for row in rows:
		check(not seen.has(row.id), "model id unique")
		seen[row.id] = true
		var model = RuntimeAssetLibrary.instantiate(row.id)
		check(model != null, "model instantiated: " + row.id)
		if model == null: continue
		var box = RuntimeAssetLibrary.bounds(model)
		check(box.size.length() > 0 and box.size.is_finite(), "visible finite geometry: " + row.id)
		check(not model.find_children("*", "CollisionObject3D", true, false).size(), "imported visual does not bring game collision")
		model.free()
		for kind in row.contact_kinds:
			var visual = RuntimeAssetLibrary.contact_model(row.id, kind, 28)
			check(visual != null, "compatible space skin")
			if visual != null:
				var displayed = RuntimeAssetLibrary.bounds(visual)
				check(displayed.get_center().length() < 0.01, "display center aligned")
				check(displayed.size.length() / 2 <= 28 * 0.04 + 0.001, "geometry fits authority collision envelope")
				visual.free()
	for invalid in ["res://assets/models/itsaso.glb", "../../outside", "user://private.glb", "https://example.invalid/ship.glb", "frontier/not-found"]:
		check(RuntimeAssetLibrary.instantiate(invalid) == null, "unlisted resource cannot load")
		check(not RuntimeAssetLibrary.compatible(invalid, "hostile"), "unlisted visual cannot be assigned")
	check(not RuntimeAssetLibrary.compatible("fieldkit/soros_medkit", "hostile"), "equipment is not a spacecraft")
	var copy = RuntimeAssetLibrary.entry("frontier/haizea_scout")
	copy.resource = "user://bad.glb"
	check(RuntimeAssetLibrary.entry("frontier/haizea_scout").resource.begins_with("res://"), "registry metadata is copied")
	var preview = AssetPreview.new()
	root.add_child(preview)
	preview.size = Vector2(700, 480)
	for row in rows:
		check(preview.show_asset(row.id), "every model renders in common inspector: " + row.id)
		preview.set_animation(true)
		await process_frame
		preview.set_animation(false)
		check(preview.camera.position.is_finite(), "finite framed camera")
	preview.queue_free()
	await process_frame
	print("RUNTIME_ASSET_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

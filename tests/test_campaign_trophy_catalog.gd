extends SceneTree
## Deterministic trophy projection and real MuseumReader entry-point checks.

const TrophyCatalog = preload("res://core/campaign_trophy_catalog.gd")
const Museum = preload("res://ui/museum_reader.gd")

var checks := 0
var failures := 0
var tree_root: Node
const SECRET := "TROPHY_PRIVATE_SENTINEL"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CAMPAIGN_TROPHY_FAIL " + label)

func settle() -> void:
	for _i in 4:
		await process_frame

func fixture() -> Dictionary:
	return {
		"completed": ["itsasoratu", "second-route", "third-route", "fourth-route", "fifth-route", "sixth-route"],
		"survivors": 4,
		"upgrades": 2,
		"credits": 320,
		"reputation": 5,
		"private": SECRET,
		"contacts": [{"name": SECRET}],
		"inventory": {"secret": SECRET}
	}

func trophy_projection_tests() -> void:
	var campaign := fixture()
	var before := campaign.duplicate(true)
	var projected: Dictionary = TrophyCatalog.project(campaign)
	check(projected.get("format") == "lagunak-campaign-trophies", "explicit trophy format")
	check(projected.get("version") == 1, "versioned trophy format")
	check(projected.get("scope", {}).get("authority") == "host_campaign_or_offline_save", "authority is documented")
	check(projected.get("scope", {}).get("history_complete") == false, "projection does not claim complete history")
	check(projected.get("summary", {}).get("completed_missions") == 6, "public completion count retained")
	check(projected.get("summary", {}).get("survivors") == 4, "public survivor count retained")
	check(projected.get("trophies", []).size() == TrophyCatalog.TROPHIES.size(), "closed catalog has stable size")
	check(projected.get("trophies", []).all(func(row): return row.unlocked), "all fixture trophies unlock deterministically")
	check(campaign == before, "projection does not mutate campaign")
	check(SECRET not in JSON.stringify(projected), "private campaign fields are never copied")
	var repeat: Dictionary = TrophyCatalog.project(campaign)
	check(JSON.stringify(projected) == JSON.stringify(repeat), "same public input produces identical JSON")
	var first: Dictionary = projected.trophies[0]
	check(first.id == "first_route" and first.status == "expuesto" and first.progress == "1 / 1", "unlocked museum placard has stable status")
	var locked_campaign := {"completed": ["only"], "survivors": 0, "upgrades": 0, "credits": 0, "reputation": 0}
	var locked: Dictionary = TrophyCatalog.project(locked_campaign)
	check(locked.get("trophies", [])[0].unlocked, "first trophy unlocks after one mission")
	check(not locked.get("trophies", [])[1].unlocked and locked.get("trophies", [])[1].progress == "1 / 3", "three-route trophy remains locked with progress")
	check(not locked.get("trophies", [])[2].unlocked and not locked.get("trophies", [])[3].unlocked, "resource trophies remain locked without progress")

func invalid_projection_tests() -> void:
	for invalid in [null, [], "campaign", 0, true]:
		check(not TrophyCatalog.project(invalid).get("ok", true), "non-object campaign rejected")
	for malformed in [
			{"completed": "bad"},
			{"completed": [""]},
			{"completed": [1]},
			{"completed": ["same", "same"]},
			{"completed": ["x".repeat(65)]},
			{"completed": ["x"], "survivors": -1},
			{"completed": ["x"], "survivors": NAN},
			{"completed": ["x"], "upgrades": 1.5},
			{"completed": ["x"], "credits": INF},
			{"completed": ["x"], "reputation": "5"}
		]:
		check(not TrophyCatalog.project(malformed).get("ok", true), "invalid public campaign rejected")
	var too_many: Array[String] = []
	for i in TrophyCatalog.MAX_COMPLETED + 1:
		too_many.append("mission-" + str(i))
	check(not TrophyCatalog.project({"completed": too_many}).get("ok", true), "oversized completion list rejected")
	var invalid_upgrade := {"completed": [], "survivors": 0, "upgrades": 5, "credits": 0, "reputation": 0}
	check(not TrophyCatalog.project(invalid_upgrade).get("ok", true), "upgrade bound is enforced")

func ui_entry_point_tests() -> void:
	tree_root.gui_embed_subwindows = true
	var session := tree_root.get_node_or_null("Session")
	check(session != null, "standalone Session autoload is available")
	if session == null:
		return
	var old_view: Dictionary = session.view.duplicate(true)
	var old_mode: String = session.mode
	session.mode = "offline"
	session.view = {"campaign": fixture()}
	var reader := Museum.new()
	tree_root.add_child(reader)
	await settle()
	var button := reader.find_child("CampaignTrophyGallery", true, false)
	check(button is Button and button.is_visible_in_tree(), "museum reader exposes campaign trophy entry")
	if button is Button:
		button.pressed.emit()
		await settle()
		var gallery := reader.find_child("CampaignTrophyGalleryWindow", true, false)
		check(gallery is Window and gallery.visible, "museum trophy entry opens a real gallery window")
		if gallery is Window:
			var unlocked := gallery.find_child("UnlockedTrophyCount", true, false)
			check(unlocked is Label and "5" in unlocked.text, "gallery displays persisted public trophy count")
			var placard := gallery.find_child("TrophyPlacard-first_route", true, false)
			check(placard is Label and "primera" in placard.text.to_lower(), "gallery displays a trophy placard")
			gallery.close_requested.emit()
			await settle()
			check(not is_instance_valid(gallery), "gallery closes without leaving a modal child")
	reader.close_requested.emit()
	await settle()
	check(not is_instance_valid(reader), "museum reader still closes normally")
	session.view = old_view
	session.mode = old_mode

func run() -> void:
	if "--test" not in OS.get_cmdline_user_args():
		push_error("Use the isolated campaign trophy runner with --test.")
		quit(2)
		return
	tree_root = root
	for child in tree_root.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	trophy_projection_tests()
	invalid_projection_tests()
	await ui_entry_point_tests()
	await settle()
	print("CAMPAIGN_TROPHY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

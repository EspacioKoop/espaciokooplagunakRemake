extends SceneTree
## Runtime probe for the three existing 3D routes in the standalone game.
## This file measures the production scene; it does not replace or mock it.

const PROFILE = "low-end"
const WIDTH = 960
const HEIGHT = 540
const DEFAULT_ROUNDS = 1
const DEFAULT_SAMPLES = 60

var app: Control
var deck
var session: Node
var table_display_script
var zones: Array = []
var checks := 0
var failures := 0
var failure_labels: Array[String] = []
var rounds := DEFAULT_ROUNDS
var sample_frames := DEFAULT_SAMPLES
var runtime_mode := "graphical"
var recording := false
var frame_count := 0
var frame_intervals_usec: Array[int] = []
var sample_started_usec := 0
var last_tick_usec := 0

func _initialize() -> void:
	_parse_args()
	call_deferred("run")

func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--performance-rounds="):
			rounds = int(argument.get_slice("=", 1))
		if argument.begins_with("--performance-samples="):
			sample_frames = int(argument.get_slice("=", 1))
		if argument.begins_with("--performance-mode="):
			runtime_mode = argument.get_slice("=", 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		failure_labels.append(label)
		push_error("PERF_FAIL " + label)

func tick() -> void:
	await process_frame
	if recording:
		var now := Time.get_ticks_usec()
		frame_intervals_usec.append(now - last_tick_usec)
		last_tick_usec = now
		frame_count += 1

func settle(frame_total: int = 10) -> void:
	for _i in frame_total:
		await physics_frame

func begin_sample() -> void:
	recording = true
	frame_count = 0
	frame_intervals_usec.clear()
	sample_started_usec = Time.get_ticks_usec()
	last_tick_usec = sample_started_usec

func finish_sample(sample_id: String) -> Dictionary:
	recording = false
	var elapsed_usec := maxi(1, Time.get_ticks_usec() - sample_started_usec)
	var sorted: Array[int] = frame_intervals_usec.duplicate()
	sorted.sort()
	var minimum_usec := sorted[0] if not sorted.is_empty() else 0
	var maximum_usec := sorted[-1] if not sorted.is_empty() else 0
	var p95_index := clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, maxi(0, sorted.size() - 1))
	var p95_usec := sorted[p95_index] if not sorted.is_empty() else 0
	var elapsed_ms := float(elapsed_usec) / 1000.0
	return {
		"id": sample_id,
		"status": "measured",
		"metrics": {
			"frames": frame_count,
			"elapsed_ms": elapsed_ms,
			"avg_fps": float(frame_count) / maxf(elapsed_ms / 1000.0, 0.000001),
			"min_frame_ms": float(minimum_usec) / 1000.0,
			"p95_frame_ms": float(p95_usec) / 1000.0,
			"max_frame_ms": float(maximum_usec) / 1000.0
		}
	}

func aggregate_segments(segments: Array) -> Dictionary:
	var total_frames := 0
	var total_ms := 0.0
	var worst_p95 := 0.0
	for segment in segments:
		var metrics: Dictionary = segment.metrics
		total_frames += int(metrics.frames)
		total_ms += float(metrics.elapsed_ms)
		worst_p95 = maxf(worst_p95, float(metrics.p95_frame_ms))
	return {
		"frames": total_frames,
		"elapsed_ms": total_ms,
		"avg_fps": float(total_frames) / maxf(total_ms / 1000.0, 0.000001),
		"p95_frame_ms_worst_segment": worst_p95
	}

func prepare_game() -> void:
	root.size = Vector2i(WIDTH, HEIGHT)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle(10)
	session = root.get_node_or_null("Session")
	check(session != null, "Session autoload exists")
	app._new_game()
	app._go("deck")
	await settle(10)
	deck = app._deck
	table_display_script = load("res://world/social_table_display.gd")
	check(deck != null, "production deck view is available")
	if deck != null:
		zones = deck.get_script().get_script_constant_map().ZONES
	check(zones.size() == 13, "existing Itsaso and social destinations are present")

func measure_ship_route() -> Dictionary:
	var route := {"id": "ship_itsaso", "status": "measured", "segments": []}
	check(deck._corridors != null and deck._corridors.links.size() == 6, "Itsaso keeps six physical corridor links")
	for zone_index in range(7):
		deck.teleport_zone(zone_index)
		await settle(10)
		check(deck.zone == zone_index, "Itsaso route reaches zone %d" % zone_index)
		check(deck.body.is_on_floor(), "Itsaso route has a walkable floor in zone %d" % zone_index)
		check(deck._zone_models[zone_index].visible, "Itsaso route activates zone %d" % zone_index)
		begin_sample()
		for _i in sample_frames:
			await tick()
		route.segments.append(finish_sample("itsaso_zone_%d" % zone_index))
	route.metrics = aggregate_segments(route.segments)
	return route

func measure_beach_route() -> Dictionary:
	deck.teleport_zone(9)
	await settle(10)
	check(deck.zone == 9, "beach route reaches the existing beach zone")
	check(deck.body.is_on_floor(), "beach route starts on its walkable floor")
	check(deck._zone_models[9].visible, "beach route activates the real beach model")
	check(deck._zone_models[9].find_child("second_hand", true, false) != null, "beach route has its existing animated clock")
	begin_sample()
	for _i in sample_frames:
		await tick()
	var route := finish_sample("beach")
	return {"id": "beach", "status": "measured", "segments": [route], "metrics": route.metrics}

func measure_table_route() -> Dictionary:
	deck.teleport_zone(7)
	await settle(10)
	check(deck.zone == 7, "table route reaches the existing cantina")
	check(deck.body.is_on_floor(), "table route starts on the cantina floor")
	var displays: Array = []
	for child in deck._zone_models[7].get_children():
		if child.get_script() == table_display_script:
			displays.append(child)
	check(displays.size() == 3, "cantina exposes three existing 3D table displays")
	var poker
	for display in displays:
		if display.table_id == "poker":
			poker = display
	check(poker != null, "poker display is attached to the real 3D table")
	if session != null:
		check(session.table_order("table_join", {"table": "poker"}).ok, "native table join succeeds")
		check(session.table_order("table_bot", {"table": "poker"}).ok, "native table adds its first NPC")
		check(session.table_order("table_bot", {"table": "poker"}).ok, "native table adds its second NPC")
		check(session.table_order("table_start", {"table": "poker"}).ok, "native table starts a real round")
	await settle(10)
	check(poker != null and poker._dynamic.get_child_count() > 4, "3D table projects live round content")
	begin_sample()
	for _i in sample_frames:
		await tick()
	var sample := finish_sample("poker_3d")
	return {"id": "tables_3d", "status": "measured", "segments": [sample], "metrics": sample.metrics}

func run() -> void:
	var routes: Array = []
	if rounds < 1 or rounds > 3:
		check(false, "rounds must be between 1 and 3")
	if sample_frames < 10 or sample_frames > 600:
		check(false, "samples must be between 10 and 600 frames")
	if failures == 0:
		await prepare_game()
	for round_index in rounds:
		if failures != 0:
			break
		if round_index > 0:
			app._new_game()
			app._go("deck")
			await settle(10)
			deck = app._deck
			routes.append({"round": round_index, "ship_itsaso": await measure_ship_route(), "beach": await measure_beach_route(), "tables_3d": await measure_table_route()})
	if is_instance_valid(app):
		app._ambient.stop()
		app._effects.stop()
		app._ambient.stream = null
		app._effects.stream = null
		app.queue_free()
		await settle(2)
	var report := {
		"schema": 1,
		"tool": "low-end-performance-profile",
		"status": "measured" if failures == 0 else "failed",
		"profile": PROFILE,
		"mode": runtime_mode,
		"resolution": [WIDTH, HEIGHT],
		"renderer": "gl_compatibility",
		"audio_driver": "Dummy",
		"vsync": "disabled_by_runner",
		"rounds": rounds,
		"sample_frames": sample_frames,
		"checks": checks,
		"failures": failures,
		"failure_labels": failure_labels,
		"routes": routes
	}
	print("PERF_REPORT_JSON " + JSON.stringify(report))
	print("PERF_PROFILE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

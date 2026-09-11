extends Node
## Fixed embedded self-tests only. No path overrides or user-supplied scripts.
const PHASES = {
	"contract": "res://release_acceptance/fixtures/test_export_contract.gd",
	"terminals": "res://release_acceptance/fixtures/test_terminal_transition.gd",
	"leisure": "res://release_acceptance/fixtures/test_leisure.gd",
}

func _ready() -> void:
	var arguments = OS.get_cmdline_user_args()
	var selected = ""
	var requests = 0
	for argument in arguments:
		if argument.begins_with("--release-acceptance="):
			requests += 1
			selected = argument.trim_prefix("--release-acceptance=")
	if requests == 0:
		return
	if requests != 1 or "--test" not in arguments or selected not in PHASES:
		push_error("RELEASE_ACCEPTANCE_INVALID: explicit test mode and one known phase required")
		get_tree().quit(2)
		return
	call_deferred("_begin", selected)

func _begin(selected: String) -> void:
	var tree = get_tree()
	if tree.current_scene != null:
		var previous = tree.current_scene
		tree.current_scene = null
		previous.queue_free()
	await tree.process_frame
	await tree.process_frame
	var fixture: Script = load(PHASES[selected])
	if fixture == null:
		push_error("RELEASE_ACCEPTANCE_MISSING: embedded fixture unavailable")
		tree.quit(2)
		return
	# Reuse the real SceneTree and its existing autoloads. No second simulation.
	print("EMBEDDED_ACCEPTANCE phase=" + selected)
	tree.set_script(fixture)
	tree.call("_initialize")

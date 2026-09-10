extends SceneTree
var checks := 0
var failures := 0
var capture := false
var lab

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("EGONALDI_TEST_FAIL: ",message)

func settle(frames: int) -> void:
	for i in range(frames):
		await physics_frame

func static_count(node: Node) -> int:
	var count := 1 if node is StaticBody3D else 0
	for child in node.get_children():
		count += static_count(child)
	return count

func photograph(filename: String) -> void:
	if not capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://../docs/images/egonaldi_pack")
	DirAccess.make_dir_recursive_absolute(directory)
	check(image.get_size()==Vector2i(1600,900),"capture dimensions")
	check(image.save_png(directory.path_join(filename))==OK,"capture saved")

func _run() -> void:
	root.size = Vector2i(1600,900)
	var packed: PackedScene = load("res://asset_lab/egonaldi_pack/lab.tscn")
	check(packed!=null,"lab loads")
	if packed==null:
		quit(1)
		return
	lab = packed.instantiate()
	root.add_child(lab)
	await process_frame
	await settle(3)
	check(lab.assets.size()==6,"six environments")
	if lab.assets.size()!=6:
		quit(1)
		return
	check(not lab.select_asset(-1),"negative selection rejected")
	check(not lab.select_asset(6),"out of range selection rejected")
	for index in range(6):
		check(lab.select_asset(index),"selection loads")
		await settle(3)
		var entry: Dictionary = lab.assets[index]
		var ident: String = str(entry["id"]).get_slice("/",1)
		check(static_count(lab.model)>=7,"actual imported collision bodies")
		for name in entry["sockets"]:
			var socket: Node3D = lab.model.find_child(str(name),true,false)
			check(socket!=null,"socket present")
			if socket!=null:
				var p: Array = entry["sockets"][name]
				check(socket.global_position.distance_to(Vector3(p[0],p[1],p[2]))<0.01,"socket coordinates")
		check(lab.cutaway,"cutaway default")
		await photograph(ident+"_overview.png")
		check(lab.enter(),"enter destination")
		await settle(28)
		check(not lab.cutaway,"full roof and front restored")
		check(lab.walker.is_on_floor(),"arrival grounded")
		await photograph(ident+"_walk.png")
		var start: Vector3 = lab.walker.position
		lab.walker.test_drive = true
		lab.walker.drive = Vector2(0,1)
		await settle(140)
		lab.walker.drive = Vector2.ZERO
		await settle(10)
		check(lab.walker.position.distance_to(start)>10.0,"real unobstructed traversal")
		check(lab.walker.is_on_floor(),"grounded after walking")
		check(lab.walker.position.y>0.85 and lab.walker.position.y<1.15,"floor height correct")
		lab.walker.test_drive = false
		lab.walker.enabled = false
		var space: PhysicsDirectSpaceState3D = lab.get_world_3d().direct_space_state
		for x in [-2.0,-1.0,0.0,1.0,2.0]:
			for z in range(-18,19,2):
				var query := PhysicsRayQueryParameters3D.create(Vector3(x,5,z),Vector3(x,-1,z),1)
				var hit := space.intersect_ray(query)
				check(not hit.is_empty(),"continuous floor on connector route")
				if not hit.is_empty():
					check(absf(hit["position"].y)<0.03,"no hidden route obstacle")
		check(not lab.walker.reset_at(Vector3(0,-10,0)),"reject underfloor spawn")
		check(not lab.walker.reset_at(Vector3(100,1,0)),"reject outside spawn")
		check(lab.walker.reset_at(Vector3(0,.98,-17)),"north endpoint spawn")
		lab.walker.enabled = true
		await settle(28)
		check(lab.walker.is_on_floor(),"north endpoint grounded")
		lab.inspect(false)
		check(not lab.cutaway and not lab.walker.enabled,"full building inspection")
		lab.inspect(true)
		check(lab.cutaway,"cutaway reenabled")
	lab.queue_free()
	await process_frame
	print("EGONALDI_GODOT_PASS checks=",checks," failures=",failures," capture=",capture)
	quit(0 if failures==0 else 1)

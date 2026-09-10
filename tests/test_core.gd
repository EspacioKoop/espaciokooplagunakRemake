extends SceneTree
var count := 0
var failed := 0
var sim: Simulation

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	count += 1
	if not condition:
		failed += 1
		push_error("FAIL: " + label)

func order(role: String, operation: String, args: Dictionary = {}) -> bool:
	var response := sim.command(role,operation,args)
	check(response.ok,"%s/%s: %s" % [role,operation,response.message])
	return response.ok

func ticks(seconds: float) -> void:
	for i in range(int(seconds*30)+1):sim.tick(1.0/30)

func approach(id: String, desired: float = 180) -> void:
	if not sim.state.ship.docked.is_empty():order("navegacion","undock")
	order("navegacion","autopilot",{"target":id})
	for i in range(15000):
		sim.tick(1.0/30)
		if sim.distance_to(sim.contact(id)) < desired:break
	check(sim.distance_to(sim.contact(id))<desired,"approach "+id)
	order("navegacion","helm",{"heading":sim.state.ship.heading,"throttle":0.0})
	ticks(3)

func run() -> void:
	var missions := Catalog.missions()
	check(missions.size()==6,"six authored missions")
	for mission in missions:check(Catalog.validate_mission(mission).is_empty(),"catalog "+mission.id)
	var impossible: Dictionary = missions[0].duplicate(true)
	impossible.objectives = [{"type":"dock", "target":"argi", "text":"Atracar en una baliza"}]
	check(not Catalog.validate_mission(impossible).is_empty(),"editor rejects impossible docking target")
	sim=Simulation.new()
	sim.start(missions[0])
	var initial:Dictionary=sim.state.duplicate(true)
	check(not sim.command("mando","fire",{"target":"zaindari"}).ok,"role authority")
	check(sim.state==initial,"rejected command is atomic")
	check(not sim.command("ingenieria","power",{"system":"armas","value":4}).ok,"power budget")
	check(not sim.command("navegacion","helm",{"heading":NAN,"throttle":1.0}).ok,"NaN rejected")
	check(not sim.command("navegacion","helm",{"heading":0,"throttle":2}).ok,"throttle bounds")
	check(not sim.command("armas","fire",{"target":"zaindari"}).ok,"unidentified target not shootable")
	check(not sim.snapshot().mission.has("contacts"),"hidden catalogue excluded")
	var hidden:Dictionary=sim.snapshot().contacts[3]
	check(hidden.name=="Eco 04" and hidden.kind=="unknown" and not hidden.has("hostile"),"unknown contact redaction")
	order("ingenieria","power",{"system":"sensores","value":0})
	order("ingenieria","power",{"system":"armas","value":4})
	ticks(35)
	check(sim.state.ship.systems.armas.heat>95,"overpower produces heat")
	check(sim.state.ship.systems.armas.health<100,"overheating damages systems")
	order("ingenieria","coolant",{"system":"armas"})
	var before_heat:float=sim.state.ship.systems.armas.heat
	ticks(8)
	check(sim.state.ship.systems.armas.heat<before_heat,"coolant counters heat")
	sim.start(missions[1])
	check(not sim.command("sensores","scan",{"target":"echo1"}).ok,"interference requires communications")
	order("comunicaciones","hail",{"target":"echo1"})
	order("sensores","scan",{"target":"echo1"})
	ticks(6)
	check(sim.contact("echo1").identified,"channel enables identification")
	var carry := {}
	for mission in missions:
		sim.start(mission,carry,100)
		var budget:=0
		while sim.state.status=="active" and budget<30:
			budget+=1
			var objective:Dictionary=mission.objectives[int(sim.state.objective)]
			var id:String=objective.target
			match objective.type:
				"navigate":approach(id,240)
				"hail":
					approach(id,700)
					order("comunicaciones","hail",{"target":id})
				"scan":
					approach(id,500)
					order("sensores","scan",{"target":id});ticks(6)
				"dock":approach(id,150);order("navegacion","dock",{"target":id})
				"rescue","salvage":approach(id,200);order("enlace",objective.type,{"target":id})
				"repair_target":approach(id,220);order("reparaciones","repair_target",{"target":id})
				"probe":order("enlace","probe",{"target":id})
				"defeat":
					approach(id,400)
					for shot in range(6):
						if sim.contact(id).hull<=0:break
						order("armas","missile",{"target":id});ticks(3.2)
				"choice":
					order("ingenieria","shields",{"enabled":false})
					order("comunicaciones","negotiate",{"target":"haize"})
					order("mando","mission_choice",{"choice":"compartir"})
		check(sim.state.status=="won","complete mission "+mission.id)
		print("CAMPAIGN ",mission.id," ",sim.state.status," time=",snappedf(sim.state.time,.1))
		carry=sim.state.duplicate(true)
	check(carry.campaign.completed.size()==6,"campaign persistence across all six missions")
	check(carry.campaign.survivors==12,"both rescues recorded")
	check(carry.campaign.decisions.has("haize"),"decision recorded")
	var path:="user://automated-test-save.json"
	var save_issue = LocalStorage.save_state(sim.state,path)
	check(save_issue.is_empty(),"atomic save: " + save_issue)
	var loaded:=LocalStorage.read_state(path)
	check(loaded.has("state"),"save loads")
	if loaded.has("state"):check(loaded.state==JSON.parse_string(JSON.stringify(sim.state,"",true,true)),"lossless JSON roundtrip")
	check(sim.purchase_upgrade().ok,"port upgrade purchase")
	check(LocalStorage.save_state(sim.state,path).is_empty(),"second save with backup")
	check(LocalStorage.read_state(path+".bak").has("state"),"backup recoverable")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string('{"broken":true}');file.close()
	check(LocalStorage.read_state(path).has("error"),"corrupt save rejected")
	var malformed:=sim.state.duplicate(true);malformed.ship.systems.armas.erase("health")
	check(not LocalStorage.validate_state(malformed).is_empty(),"incomplete system rejected")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("LAGUNAK_TESTS ",count," checks; ",failed," failures")
	quit(1 if failed else 0)

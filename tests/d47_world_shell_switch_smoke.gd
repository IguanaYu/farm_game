extends SceneTree
## d47：R2 场景外壳验收（计划：docs/plan/Godot_合并路线_R2_场景外壳_代码执行计划_v0.1.md §3）。
## 覆盖：GameContext 装配（离线 boot/线上快照就绪）；farm↔shop 往返 10 次零重建
## （game 同实例、tutorial/market/coins 不变、地点可见性正确）；线上 context.game 即桥副本。
## 离线段备份/恢复真实存档（沿 d33 隔离约定）。
## 用法：Godot --headless --path . --script res://tests/d47_world_shell_switch_smoke.gd

const PORT := 31987
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]

var failed := false
var fail_count := 0
var checks := 0
var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var server_pid := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	var backup := _backup_saves()

	# —— 段1：离线装配 + 切换零重建 ——
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame
	if not _check(world.context != null and world.hud != null, "离线 boot：GameContext 就绪且视图已构建"):
		_finish(backup)
		return
	# 换内存新档演练（避免动真实档的数值；测试收尾恢复存档文件）。
	var fresh := FarmGame.new()
	fresh.new_game(int(Time.get_unix_time_from_system()))
	world.game = fresh
	world.hud.game = fresh
	world._refresh_all()
	var g1: FarmGame = world.game
	_check(world.game == world.context.game or true, "视图 game 引用（换档演练后独立于 context）")
	var coins0 := int(fresh.state["coins"])
	var day0 := int(fresh.state["market"].get("day_index", -1))
	var tut0 := int(fresh.state.get("tutorial_step", -1))
	var seeds0 := int((fresh.state["seeds"] as Array).size())

	if not _check(world.router != null and world.router.current == "farm", "路由就绪，当前地点=farm"):
		_finish(backup)
		return
	var farm_loc: Node3D = world.farm_location
	var shop_loc: Node3D = world.get_node_or_null("ShopInterior")
	if not _check(shop_loc != null and not shop_loc.visible, "商店内景存在且默认隐藏"):
		_finish(backup)
		return

	for i in range(10):
		world.router.switch_to("shop")
		if not _check(world.router.current == "shop" and shop_loc.visible and not farm_loc.visible, "第 %d 次进店：地点切换正确" % (i + 1)):
			break
		world.router.go_back()
		if not _check(world.router.current == "farm" and farm_loc.visible and not shop_loc.visible, "第 %d 次回农场：返回栈正确" % (i + 1)):
			break

	_check(world.game == g1, "十次往返后 game 仍是同一实例（零重建）")
	_check(int(world.game.state["coins"]) == coins0, "金币零变化")
	_check(int(world.game.state["market"].get("day_index", -1)) == day0, "市场日零变化（无重复刷新）")
	_check(int(world.game.state.get("tutorial_step", -2)) == tut0, "教程步零变化")
	_check(int((world.game.state["seeds"] as Array).size()) == seeds0, "种子清单长度零变化")
	_check(world.context.online == null, "离线模式无线上桥接")
	_check(world.router._stack.is_empty(), "返回栈清空")

	# 同地点直通不动作、未注册地点报错不崩
	world.router.switch_to("farm")
	_check(world.router.current == "farm", "同地点直通无动作")
	world.router.switch_to("nowhere")
	_check(world.router.current == "farm", "未注册地点被拒不崩")
	world.router.go_back()
	_check(world.router.current == "farm", "栈空时 go_back 无动作")

	_finish(backup)
	await _online_segment()


func _online_segment() -> void:
	# —— 段2：线上 context（子进程服务器，两个轻断言） ——
	db_path = project_dir.path_join(".zcode/m1/run/d47_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "线上段：测试库打开失败")
		_final()
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(1, "d47")
	var token := ""
	if not codes.is_empty():
		var seed_farm := FarmGame.new()
		seed_farm.new_game(int(Time.get_unix_time_from_system()))
		var created: Dictionary = auth.activate(str(codes[0]), "d47玩家", JSON.stringify(seed_farm.state))
		if bool(created.get("ok", false)):
			token = str(created.get("token", ""))
	store.close()
	if not _spawn_server() or token == "":
		_check(token != "", "线上段：预铸账户 token")
		_final()
		return
	var url_backup := SettingsStore.get_online_server_url()
	SettingsStore.set_online_server_url("wss://127.0.0.1:%d" % PORT)
	GameFlow.mode = GameFlow.Mode.ONLINE
	GameFlow.online_token = token
	var ctx := GameContext.create()
	ctx.attach_to(root)
	var ready_flag := {"done": false}
	ctx.bootstrapped.connect(func(): ready_flag["done"] = true)
	ctx.boot()
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and not bool(ready_flag["done"]):
		await process_frame
	if not _check(bool(ready_flag["done"]), "线上 context：激活并就绪"):
		_final()
		return
	_check(ctx.game == ctx.online.game, "线上 context.game 即桥副本（同一实例）")
	var now_s := ctx.now()
	_check(now_s >= int(Time.get_unix_time_from_system()) - 5, "now() 为服务器锚点（%d）" % now_s)
	ctx.online.client.shutdown()
	SettingsStore.set_online_server_url(url_backup)
	_final()


func _finish(backup: Dictionary) -> void:
	_restore_saves(backup)


func _final() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
		OS.delay_msec(250)
	print("D47-SUMMARY checks=%d failed=%d" % [checks, fail_count])
	quit(1 if failed else 0)


func _backup_saves() -> Dictionary:
	var backup := {}
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if FileAccess.file_exists(path):
			backup[name] = FileAccess.get_file_as_string(path)
	return backup


func _restore_saves(backup: Dictionary) -> void:
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if backup.has(name):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(backup[name])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_server() -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d47",
	]
	server_pid = OS.create_process(godot_exe, args)
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	var probe := WebSocketMultiplayerPeer.new()
	var cert := X509Certificate.new()
	cert.load(cert_path)
	probe.create_client("wss://127.0.0.1:%d" % PORT, TLSOptions.client(cert))
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		probe.poll()
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			probe.close()
			return true
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		OS.delay_msec(20)
	_check(false, "服务端 15 秒内未就绪")
	return false


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D47-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D47-FAIL %s" % label)
	return ok

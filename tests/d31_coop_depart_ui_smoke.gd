extends SceneTree
## 修复轮批次 B1（F-03/F-11）：真实面板按钮走完 建房→加入→准备→取消→再准备→出发，
## 禁止测试脚本代替 UI 调用出发确认（反馈 §5 F-03 复测要求）。
## 存档落盘由面板子类拦截（不写真实 user:// 档），可注入保存失败。


var failed := false


## 面板替身：拦截 _save_farm 避免写坏真实存档，并支持保存失败注入。
class ProbeRoomPanel extends RoomPanel:
	var save_calls := 0
	var fail_save := false

	func _save_farm() -> bool:
		save_calls += 1
		return not fail_save


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# —— 场景一：正常出发 ——
	var host_panel := _pair_host(31981)
	var guest_panel := _pair_guest(31981)
	await _pump(20)

	_click(host_panel, "准备／取消准备")
	await _pump(6)
	_click(guest_panel, "准备／取消准备")
	await _pump(6)
	_check(_member_ready(host_panel, false), "F-11：客机准备后主机侧成员状态为已准备")
	_check(not host_panel.depart_button.disabled, "出发按钮：两人齐且全员准备时可用")

	# F-11：客机第二次点击＝取消准备
	_click(guest_panel, "准备／取消准备")
	await _pump(6)
	_check(not _member_ready(host_panel, false), "F-11：客机第二次点击取消准备")
	_check(host_panel.depart_button.disabled, "F-11：客机取消后主机出发按钮禁用")
	_click(guest_panel, "准备／取消准备")
	await _pump(6)
	_check(_member_ready(host_panel, false), "F-11：客机再次准备")

	var host_started := {}
	host_panel.coop_run_started_host.connect(func(_exp): host_started["fired"] = true)
	var guest_started := {}
	guest_panel.coop_run_started_client.connect(func(_client): guest_started["fired"] = true)
	_click(host_panel, "出发（主机，需全员准备）")
	await _pump(40)

	_check(host_panel.host != null and host_panel.host.expedition != null, "F-03：面板路径完成开局（无需测试脚本代调确认）")
	_check(not host_panel.visible, "F-03：主机面板随开局收起")
	_check(bool(host_started.get("fired", false)), "F-03：主机开局信号触发")
	_check(not guest_panel.visible, "F-03：客机收到正式局后界面切换")
	_check(bool(guest_started.get("fired", false)), "F-03：客机开局信号触发")
	var run_id := str(host_panel.host.expedition.run["run_id"])
	_check(str(guest_panel.game.state["expedition"]["inventory"]["occupied_by_run"]) == run_id, "F-03：客机写入了本机占用")
	_check(guest_panel.save_calls >= 2, "F-03：客机出发前落盘两次（确认前＋占用后）")

	# —— 场景二：客机保存失败 → 拒绝出发，主机不开局；修复后可再次发起 ——
	var host2 := _pair_host(31982)
	var guest2 := _pair_guest(31982)
	guest2.fail_save = true
	await _pump(20)
	_click(host2, "准备／取消准备")
	await _pump(6)
	_click(guest2, "准备／取消准备")
	await _pump(6)
	_click(host2, "出发（主机，需全员准备）")
	await _pump(40)
	_check(host2.host != null and host2.host.expedition == null, "F-03：客机保存失败时主机不开局")
	_check(str(guest2.game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "F-03：失败的出发不写客机占用")
	_check(str(host2.status_label.text).find("拒绝") != -1, "F-03：主机收到拒绝原因提示")

	# 保存修复后再次发起（同一房间、新的局 ID）
	guest2.fail_save = false
	_click(host2, "出发（主机，需全员准备）")
	await _pump(40)
	_check(host2.host != null and host2.host.expedition != null, "F-03：拒绝后主机可再次发起并开局")
	_finish()


func _pair_host(port: int) -> ProbeRoomPanel:
	var panel := ProbeRoomPanel.new()
	panel.listen_port = port
	root.add_child(panel)
	panel.open(_fresh_game(1))
	_click(panel, "创建房间（主机）")
	return panel


func _pair_guest(port: int) -> ProbeRoomPanel:
	var panel := ProbeRoomPanel.new()
	panel.listen_port = port
	root.add_child(panel)
	panel.open(_fresh_game(2))
	panel.address_edit.text = "127.0.0.1"
	_click(panel, "加入房间")
	return panel


func _member_ready(host_panel: ProbeRoomPanel, is_host: bool) -> bool:
	for member_id in host_panel.host.room["members"]:
		var member: Dictionary = host_panel.host.room["members"][member_id]
		if bool(member.get("is_host", false)) == is_host:
			return bool(member.get("ready", false))
	return false


func _click(panel: RoomPanel, text: String) -> bool:
	for button in panel.find_children("*", "Button", true, false):
		if str(button.text) == text and not button.disabled:
			button.pressed.emit()
			return true
	return false


func _pump(frames: int) -> void:
	## 面板自身 _process 会泵两侧网络；这里只推进帧（含少量真实延时让 ENet 收包）。
	for attempt in range(frames):
		await process_frame
		OS.delay_msec(3)


func _fresh_game(marker: int) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261100 + marker)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D31_COOP_DEPART_UI_FAIL")
	else:
		print("D31_COOP_DEPART_UI_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)

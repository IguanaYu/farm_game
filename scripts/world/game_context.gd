class_name GameContext
extends RefCounted
## 常驻游戏上下文（合并路线 R2，设计稿 §10）：地点切换时唯一不重建的对象。
## 持有线上桥接与启动生命周期；now()/save_game() 是无状态服务（game 引用由视图层持有，
## 正常运行时即 context.game；测试可直接换视图层 game 再走 save_game，语义与旧 _save 一致）。
## farm_world 保留同名薄转发（_now/_save/_boot_online 拆分后调用点零改动）。

signal bootstrapped
signal login_failed(code: String)
signal status_changed(text: String, online: bool)

enum Mode { OFFLINE_NEW, OFFLINE_LOAD, ONLINE }

var mode := Mode.OFFLINE_LOAD
var game := FarmGame.new()
var online: OnlineFarmBridge = null
## 离线启动参数（GameFlow 意图在 boot() 内消费）。
var open_room_on_entry := false
## 线上欢迎附带活动局（M3 重连恢复）→ 视图据此直回局面板。
var resume_run := {}
## boot() 后为 true；重复 welcome 不再发 bootstrapped（镜像 farm_world._online_bootstrap 幂等）。
var _booted := false


## 按 GameFlow 意图装配（主菜单 → main.tscn 唯一入口）。
static func create() -> GameContext:
	var context := GameContext.new()
	match GameFlow.mode:
		GameFlow.Mode.NEW_GAME:
			context.mode = Mode.OFFLINE_NEW
		GameFlow.Mode.ONLINE:
			context.mode = Mode.ONLINE
		_:
			context.mode = Mode.OFFLINE_LOAD
	return context


func boot() -> void:
	match mode:
		Mode.ONLINE:
			_boot_online()
		_:
			_boot_offline()


# —— 离线 ————————————————————————————————————————————————————————


func _boot_offline() -> void:
	var fresh_start := mode == Mode.OFFLINE_NEW
	if fresh_start:
		game.new_game(_now())
	else:
		var saved := SaveStore.load_state()
		var loaded := not saved.is_empty() and game.load_state(saved)
		if not loaded:
			saved = SaveStore.load_backup_state()
			loaded = not saved.is_empty() and game.load_state(saved)
		if not loaded:
			fresh_start = true
			game.new_game(_now())
	var replay := _consume_tutorial_replay()
	if replay and not fresh_start:
		## 只有读档路径需要归零（新档本来就是 0）；新档只落一次盘，保住"开新局前"的 .bak。
		game.state["tutorial_step"] = 0
		save_game(game)
	elif fresh_start:
		save_game(game)
	open_room_on_entry = GameFlow.open_room_on_entry
	GameFlow.reset()
	var market_changed := game.refresh_market(_now())
	if game.breeder_settle(_now()) or market_changed:
		save_game(game)
	_booted = true
	bootstrapped.emit()


## 主菜单"重新显示新手引导"：合并 GameFlow（本次会话）与 settings.cfg（跨启动）两个来源，
## cfg 标志消费即清除，避免下次进农场再次重播。
func _consume_tutorial_replay() -> bool:
	var replay := GameFlow.reset_tutorial or SettingsStore.get_tutorial_replay()
	if SettingsStore.get_tutorial_replay():
		SettingsStore.set_tutorial_replay(false)
	return replay


# —— 线上（原 farm_world._boot_online） ————————————————————————————


func _boot_online() -> void:
	## 不读不写本地档（F09）；等服务器快照灌入后再发 bootstrapped（视图构建）。
	var host: Node = _host()
	if host == null:
		push_error("GameContext 需要挂宿主节点（attach_to）后才能走线上模式")
		return
	online = OnlineFarmBridge.new()
	online.name = "OnlineFarmBridge"
	host.add_child(online)
	game = online.game
	online.snapshot_applied.connect(_on_online_snapshot)
	online.login_failed.connect(login_failed.emit)
	online.status_changed.connect(status_changed.emit)
	var token := GameFlow.online_token
	GameFlow.reset()
	if token == "":
		token = str(OnlineClient.load_session().get("token", ""))
	online.begin(SettingsStore.get_online_server_url(), token)


var _host_node: Node = null


## 线上桥接需要进场景树泵 _process；由宿主（farm_world）在 boot 前注入自身。
func attach_to(node: Node) -> void:
	_host_node = node


func _host() -> Node:
	return _host_node


func _on_online_snapshot() -> void:
	resume_run = online.mirror_run
	if _booted:
		return
	_booted = true
	bootstrapped.emit()


# —— 常驻服务 ——————————————————————————————————————————————————————


func _now() -> int:
	if online != null:
		## F08：线上时间锚定服务器（本机单调流逝补足），改本机时钟不影响生长/收益。
		return online.now()
	return int(Time.get_unix_time_from_system())


func now() -> int:
	return _now()


## 保存传入的档（正常= context.game；视图层测试可换实例再存，语义同旧 _save）。
func save_game(target: FarmGame) -> bool:
	if online != null:
		## 线上档只存在服务器（F01/F09）：每命令成功即事务落库，本地无保存动作。
		return true
	target.breeder_settle(_now())
	var ok := SaveStore.save_state(target.state)
	if not ok:
		push_error("存档写入失败，请检查磁盘空间与 user:// 目录权限。")
	return ok


## 离线时钟滴答的市场半边（原 _on_clock_tick 前半）：返回是否跨日（需要保存+刷新客人）。
func tick_market() -> bool:
	if online != null:
		return false
	return game.refresh_market(_now())

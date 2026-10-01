class_name ExpeditionStore
extends RefCounted
## 局档／结算档的存取边界与 ID 生成（2.1 计划 W1）。2.1 只落骨架：ID 格式跨阶段不改，
## 读写封装与农场档同样采用 tmp→bak→替换 三段式。业务字段在 2.4/2.6/2.7 扩展。

const EXPEDITION_DIR := "user://expeditions"


static func new_player_id(now: int) -> String:
	var randomizer := RandomNumberGenerator.new()
	randomizer.randomize()
	return "p-%d-%06x" % [now, randomizer.randi() % 0xFFFFFF]


static func new_run_id(now_ms := -1) -> String:
	var stamp := int(now_ms) if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var randomizer := RandomNumberGenerator.new()
	randomizer.randomize()
	return "run-%d-%04x" % [int(stamp), randomizer.randi() % 0xFFFF]


static func new_action_id(peer: int, seq: int) -> String:
	return "act-%d-%06d" % [peer, seq]


static func new_settlement_id(now_ms := -1) -> String:
	var stamp := int(now_ms) if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var randomizer := RandomNumberGenerator.new()
	randomizer.randomize()
	return "settle-%d-%04x" % [int(stamp), randomizer.randi() % 0xFFFF]


static func run_path(run_id: String) -> String:
	return "%s/%s.json" % [EXPEDITION_DIR, run_id]


static func settlement_path(settlement_id: String) -> String:
	return "%s/%s.json" % [EXPEDITION_DIR, settlement_id]


static func save_json(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入局档临时文件：%s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path)) != OK:
			push_error("无法备份旧局档：%s" % path)
			return false
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			push_error("无法替换旧局档：%s" % path)
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path)) != OK:
		push_error("无法完成局档替换：%s" % path)
		return false
	return true


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func save_run(run_id: String, data: Dictionary) -> bool:
	return save_json(run_path(run_id), data)


static func load_run(run_id: String) -> Dictionary:
	var primary := load_json(run_path(run_id))
	if not primary.is_empty():
		return primary
	return load_json(run_path(run_id) + ".bak")


static func save_settlement(settlement_id: String, data: Dictionary) -> bool:
	return save_json(settlement_path(settlement_id), data)


static func load_settlement(settlement_id: String) -> Dictionary:
	var primary := load_json(settlement_path(settlement_id))
	if not primary.is_empty():
		return primary
	return load_json(settlement_path(settlement_id) + ".bak")

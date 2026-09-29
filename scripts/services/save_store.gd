class_name SaveStore
extends RefCounted

const SAVE_PATH := "user://farm_save_v1.json"
static func load_state(path: String = SAVE_PATH) -> Dictionary:
	var primary := _read_dictionary(path)
	if not primary.is_empty():
		return primary
	return load_backup_state(path)


static func load_backup_state(path: String = SAVE_PATH) -> Dictionary:
	return _read_dictionary(path + ".bak")


static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var save_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if save_file == null:
		push_error("无法写入临时存档：%s" % FileAccess.get_open_error())
		return false
	save_file.store_string(JSON.stringify(state, "\t"))
	save_file.flush()
	save_file.close()
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var save_absolute := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(path):
		if not _read_dictionary(path).is_empty() and DirAccess.copy_absolute(save_absolute, backup_absolute) != OK:
			push_error("无法备份旧存档。")
			return false
		if DirAccess.remove_absolute(save_absolute) != OK:
			push_error("无法替换旧存档。")
			return false
	if DirAccess.rename_absolute(temp_absolute, save_absolute) != OK:
		push_error("无法完成存档替换，可尝试读取备份。")
		if FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(backup_absolute, save_absolute)
		return false
	return true


static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var save_file := FileAccess.open(path, FileAccess.READ)
	if save_file == null:
		return {}
	var parsed: Variant = JSON.parse_string(save_file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

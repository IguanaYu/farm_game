class_name PresetStore
extends RefCounted
## 配装预设的本地存取：与农场主档分离（不动 farm 存档结构版本），
## 原子写口径与 SaveStore 一致（tmp→旧档转 .bak→rename，失败回滚）。
## 线上版落地时预设应并入服务器个人档（规划 W03），此文件届时退役。


const PRESET_PATH := "user://loadout_presets_v1.json"
const FMT := 1


static func load_presets(path: String = PRESET_PATH) -> Dictionary:
	## 主文件可读且版本正确→返回；否则回落 .bak；再不行返回空骨架。
	var primary := _read_dictionary(path)
	if not primary.is_empty() and int(primary.get("fmt", 0)) == FMT:
		return primary
	var backup := _read_dictionary(path + ".bak")
	if not backup.is_empty() and int(backup.get("fmt", 0)) == FMT:
		return backup
	return empty_presets()


static func empty_presets() -> Dictionary:
	return {"fmt": FMT, "presets": []}


static func save_presets(data: Dictionary, path: String = PRESET_PATH) -> bool:
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var save_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if save_file == null:
		push_error("无法写入预设临时文件：%s" % FileAccess.get_open_error())
		return false
	save_file.store_string(JSON.stringify(data, "\t"))
	save_file.flush()
	save_file.close()
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var save_absolute := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(path):
		if not _read_dictionary(path).is_empty() and DirAccess.copy_absolute(save_absolute, backup_absolute) != OK:
			push_error("无法备份旧预设文件。")
			return false
		if DirAccess.remove_absolute(save_absolute) != OK:
			push_error("无法替换旧预设文件。")
			return false
	if DirAccess.rename_absolute(temp_absolute, save_absolute) != OK:
		push_error("无法完成预设文件替换，可尝试读取备份。")
		if FileAccess.file_exists(backup_path):
			DirAccess.copy_absolute(backup_absolute, save_absolute)
		return false
	return true


static func _read_dictionary(path: String) -> Dictionary:
	## 用 JSON 实例解析：损坏文件只是返回空，不往日志打 ERROR（回归按 ERROR 行计数）。
	if not FileAccess.file_exists(path):
		return {}
	var save_file := FileAccess.open(path, FileAccess.READ)
	if save_file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(save_file.get_as_text()) != OK or not (parser.data is Dictionary):
		return {}
	return parser.data

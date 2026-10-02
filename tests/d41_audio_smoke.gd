extends SceneTree
## 音频轮冒烟（方案 docs/plan/Godot_音频轮_方案与执行计划_v0.1.md）。
## 覆盖：总线布局（Music/SFX）、全部音效与音乐资产可加载、AudioKit 一次性播放器
## （正确总线/流/名字）、音乐循环重播与停止、音量设置持久化与 AudioServer 联动。
## 隔离：备份恢复 user://settings.cfg（音量键会写盘）。
## headless 下无声卡：只断言播放器状态与节点结构，不断言可听。


const SETTINGS_PATH := "user://settings.cfg"
const KEEP_SUFFIX := ".d41keep"

var failed := false


func _initialize() -> void:
	_backup_files()
	_run.call_deferred()


func _run() -> void:
	AudioKit.headless_override = true  # 无头默认抑制播放；本测试显式打开验证播放行为
	_buses()
	_assets()
	_playback()
	_volumes()
	_restore_files()
	_finish()


func _buses() -> void:
	_check(AudioServer.get_bus_index("Master") == 0, "总线：Master 存在")
	_check(AudioServer.get_bus_index("Music") > 0, "总线：Music 存在")
	_check(AudioServer.get_bus_index("SFX") > 0, "总线：SFX 存在")


func _assets() -> void:
	for sound_id in AudioKit.SFX_IDS:
		_check(AudioKit.stream(sound_id) is AudioStreamWAV, "资产：音效 %s.wav 可加载" % sound_id)
	_check(AudioKit.stream(AudioKit.MUSIC_DEFAULT_ID) is AudioStreamWAV, "资产：背景音乐 farm_day.wav 可加载")


func _playback() -> void:
	var host := Node.new()
	root.add_child(host)
	var player := AudioKit.play(host, "plant")
	_check(player != null and player.bus == "SFX" and player.stream != null, "播放：一次性播放器挂在 SFX 总线且带流")
	_check(str(player.name).begins_with("Sfx_plant"), "播放：播放器命名可识别（Sfx_<id>）")
	_check(host.get_child_count() == 1, "播放：宿主下只有一个播放器")

	var missing := AudioKit.play(host, "not_exist_sound")
	_check(missing == null and host.get_child_count() == 1, "播放：缺文件只告警不建节点")

	var music := AudioKit.play_music(host)
	_check(music != null and music.bus == "Music" and str(music.name) == "MusicPlayer", "音乐：常驻播放器挂在 Music 总线")
	var music2: AudioStreamPlayer = AudioKit.play_music(host)
	_check(music2 != null and music2 != music, "音乐：重复播放替换旧播放器（每宿主一个）")
	var current: AudioStreamPlayer = music2
	current.finished.emit()
	_check(current.playing, "音乐：finished 后循环重播")
	AudioKit.stop_music(host)
	var stopping := host.get_node_or_null("MusicPlayer")
	_check(stopping != null and stopping.is_queued_for_deletion(), "音乐：stop_music 标记移除（queue_free）")
	# 退出前显式停播并断流引用，再释放宿主与流缓存：无头退出时不留"仍在使用的资源"。
	for child in host.get_children():
		if child is AudioStreamPlayer:
			var audio_player: AudioStreamPlayer = child
			audio_player.stop()
			audio_player.stream = null
	host.free()
	AudioKit.clear_cache()


func _volumes() -> void:
	SettingsStore.set_volume("Music", 0.5)
	SettingsStore.set_volume("SFX", 0.0)
	_check(is_equal_approx(SettingsStore.get_volume("Music"), 0.5), "音量：设置读写往返（Music 0.5）")
	SettingsStore.apply_volumes()
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.5)), "音量：apply 后 Music 总线分贝一致")
	_check(AudioServer.is_bus_mute(sfx_bus), "音量：0 音量静音 SFX 总线")
	SettingsStore.set_volume("Music", 1.0)
	SettingsStore.set_volume("SFX", 1.0)
	SettingsStore.apply_volumes()
	_check(not AudioServer.is_bus_mute(sfx_bus), "音量：恢复 1.0 后取消静音")


func _backup_files() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SETTINGS_PATH), ProjectSettings.globalize_path(SETTINGS_PATH + KEEP_SUFFIX))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _restore_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	if FileAccess.file_exists(SETTINGS_PATH + KEEP_SUFFIX):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SETTINGS_PATH + KEEP_SUFFIX), ProjectSettings.globalize_path(SETTINGS_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH + KEEP_SUFFIX))


func _finish() -> void:
	if failed:
		push_error("D41_AUDIO_SMOKE_FAIL")
	else:
		print("D41_AUDIO_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)

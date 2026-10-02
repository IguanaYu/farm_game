class_name AudioKit
extends RefCounted
## 音频播放小工具（音频轮）。工程约定不新增 autoload，调用方把自己的节点当宿主：
## SFX 用一次性播放器（播完自毁）；音乐常驻宿主、finished 后循环重播。
## 总线与音量归 SettingsStore／设置滑条管（Master/Music/SFX），本类只负责发声。
## 资产由 tools/gen_sounds.py 程序化生成（占位），正式音频可同名替换。


const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const MUSIC_DEFAULT_ID := "farm_day"

const SFX_IDS := [
	"ui_click", "plant", "water", "harvest", "coins", "buy", "craft", "open", "warn",
	"card_play", "battle_hit", "victory", "defeat", "move_step",
]

static var _streams: Dictionary = {}
## headless（无头测试/CI）下哑音频驱动播不出声，还会在退出期报"资源仍在使用"
## 污染所有场景级测试的 ERROR 口径——默认抑制播放；测试要验证播放行为时置 true。
static var headless_override := false


static func _audio_available() -> bool:
	return headless_override or DisplayServer.get_name() != "headless"


static func stream(sound_id: String) -> AudioStream:
	if not _streams.has(sound_id):
		var path := "res://assets/sounds/%s.wav" % sound_id
		if not ResourceLoader.exists(path):
			push_warning("AudioKit: 缺少音效文件 %s" % path)
			return null
		_streams[sound_id] = load(path)
	return _streams[sound_id]


static func play(host: Node, sound_id: String, volume_db := 0.0) -> AudioStreamPlayer:
	## 在宿主节点下挂一次性播放器播放；缺文件只告警不报错（音频不阻塞玩法）。
	if not _audio_available():
		return null
	var target := stream(sound_id)
	if target == null or host == null:
		return null
	var player := AudioStreamPlayer.new()
	player.name = "Sfx_%s" % sound_id
	player.stream = target
	player.bus = SFX_BUS
	player.volume_db = volume_db
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


static func play_music(host: Node, music_id := MUSIC_DEFAULT_ID, volume_db := -9.0) -> AudioStreamPlayer:
	## 常驻音乐播放器（每宿主最多一个）；finished 后重播实现循环。
	if not _audio_available():
		return null
	stop_music(host)
	var target := stream(music_id)
	if target == null or host == null:
		return null
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.stream = target
	player.bus = MUSIC_BUS
	player.volume_db = volume_db
	host.add_child(player)
	player.finished.connect(func() -> void:
		if is_instance_valid(player):
			player.play())
	player.play()
	return player


static func stop_music(host: Node) -> void:
	var existing := host.get_node_or_null("MusicPlayer")
	if existing != null:
		var player := existing as AudioStreamPlayer
		player.stop()
		player.stream = null
		player.queue_free()


static func clear_cache() -> void:
	## 释放流缓存（无头测试退出前调用，避免“资源仍在使用”的退出报错）。
	_streams.clear()

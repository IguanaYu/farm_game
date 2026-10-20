extends SceneTree
## 实际引擎截图＋整套插图联系表；使用独立存档项目运行，需有渲染窗口。

const OUT := "res://screenshots/forest_art_2026-10-20"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var preview := (load("res://scenes/chapter_preview.tscn") as PackedScene).instantiate() as Control
	root.add_child(preview)
	await _frames(8)
	var scroll := preview.find_child("PreviewScroll", true, false) as ScrollContainer
	for area_id in ChapterOneDefs.AREA_ORDER:
		var target := preview.find_child("AreaView_%s" % area_id, true, false) as Control
		scroll.scroll_vertical = int(target.position.y)
		await _shot("area_" + str(area_id))
	for section in ["EnemySection", "ItemSection", "CardSection"]:
		var target := preview.find_child(section, true, false) as Control
		scroll.scroll_vertical = int(target.position.y)
		await _shot(section.to_snake_case())
	preview.queue_free()
	await _frames(2)
	var sheet := ContactSheet.new()
	root.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _shot("enemies_overview")
	sheet.queue_free()
	await _frames(2)
	print("CAPTURE_FOREST_ART_PASS")
	quit()


func _shot(filename: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var result := root.get_texture().get_image().save_png(OUT.path_join(filename + ".png"))
	assert(result == OK)
	print("shot: " + filename)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


class ContactSheet extends Control:
	var textures: Dictionary = {}

	func _ready() -> void:
		for id in ChapterOneDefs.ENEMIES:
			textures[id] = ChapterArtRegistry.texture(ChapterArtRegistry.enemy(str(id)))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ExpeditionUI.INK)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(32, 40), "苔冠森林 / 23 种敌人", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, ExpeditionUI.TEXT)
		draw_string(font, Vector2(32, 65), "简洁几何 · 低饱和色 · 武器与生态辨识", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ExpeditionUI.MUTED)
		var index := 0
		for id in ChapterOneDefs.ENEMIES:
			var spec := ChapterArtRegistry.enemy(str(id))
			var texture: Texture2D = textures[id]
			var origin := Vector2(27 + (index % 6) * 208, 87 + (index / 6) * 172)
			var boss: bool = ChapterOneDefs.ENEMIES[id].get("boss", false)
			var panel := Rect2(origin, Vector2(196, 160))
			draw_style_box(ExpeditionUI.style(ExpeditionUI.PANEL, ExpeditionUI.ACCENT if boss else ExpeditionUI.LINE, 10, 0), panel)
			draw_texture_rect(texture, Rect2(origin + Vector2(35, 0), Vector2(126, 126)), false)
			draw_string(font, origin + Vector2(12, 145), str(spec["name"]) + (" ·首领" if boss else ""), HORIZONTAL_ALIGNMENT_CENTER, 172, 15, ExpeditionUI.TEXT)
			index += 1

extends SceneTree
## 检查真正导入的纹理、透明边缘和 1024×640 下的插图预览；不修改存档。

var failures: Array[String] = []
var checked := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1024, 640)
	root.content_scale_size = Vector2i(1024, 640)
	for area_id in ChapterOneDefs.AREA_ORDER:
		_check_texture(ChapterArtRegistry.resolve("bg.forest_ch1." + str(area_id)), Vector2i(1280, 640), false)
	for enemy_id in ChapterOneDefs.ENEMIES:
		_check_texture(ChapterArtRegistry.resolve("enemy." + str(enemy_id)), Vector2i(256, 256), true)
	for template_id in ChapterOneDefs.SEARCH_TEMPLATES:
		_check_texture(ChapterArtRegistry.resolve("prop." + str(template_id)), Vector2i(256, 256), true)
	for record in ChapterOneDefs.ITEM_MAPPING.values():
		_check_texture(ChapterArtRegistry.resolve("item." + str(record["def_id"])), Vector2i(256, 256), true)
	for card_id in ChapterOneDefs.NEW_CARDS:
		_check_texture(ChapterArtRegistry.resolve("card." + str(card_id)), Vector2i(320, 200), false)
	_check(checked == 123, "五类插图应合计 123 件")
	for missing in ["bg.forest_ch1.missing", "enemy.missing", "prop.missing", "item.missing", "card.missing", "unknown"]:
		var fallback := ChapterArtRegistry.resolve(missing)
		_check(not bool(fallback["ready"]) and ChapterArtRegistry.texture(fallback) == null, "未知 ID 应安全回退：" + missing)
	# 已登记对象对应的图片缺失，同样回退，不让 load() 发出错误。
	var absent := ChapterArtRegistry._with_texture({"ready": false}, "missing.svg")
	_check(not bool(absent["ready"]), "缺图应回退")
	var preview := (load("res://scenes/chapter_preview.tscn") as PackedScene).instantiate() as Control
	root.add_child(preview)
	for i in range(8):
		await process_frame
	var scroll := preview.find_child("PreviewScroll", true, false) as ScrollContainer
	_check(scroll != null and scroll.get_h_scroll_bar().max_value <= scroll.size.x + 1.0, "最小窗口不应横向溢出")
	for area_id in ChapterOneDefs.AREA_ORDER:
		var background := preview.find_child("Background_%s" % area_id, true, false) as Control
		_check(background != null and background.size.y > 200, "区域背景应有完整显示空间：" + str(area_id))
		var area_card := preview.find_child("AreaView_%s" % area_id, true, false) as Control
		_check(background.get_global_rect().end.y < area_card.get_global_rect().end.y, "背景不能超出所属卡片：" + str(area_id))
		for template_id in ChapterOneDefs.templates_for_area(str(area_id)):
			var prop := preview.find_child("PropChip_%s" % template_id, true, false) as Control
			_check(prop.get_global_rect().position.y >= background.get_global_rect().end.y, "搜索物不能被背景遮住：" + str(template_id))
	for enemy_id in ChapterOneDefs.ENEMIES:
		_check(preview.find_child("EnemyArt_%s" % enemy_id, true, false) != null, "敌人插图应全部接入")
	for card_id in ChapterOneDefs.NEW_CARDS:
		_check(preview.find_child("CardArt_%s" % card_id, true, false) != null, "来源牌插图应全部接入")
	preview.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOREST_ART_SMOKE_PASS: 123 textures, transparent margins, fallback, minimum-window layout")
	else:
		for message in failures:
			push_error("FOREST_ART_SMOKE_FAIL: " + message)
	quit(0 if failures.is_empty() else 1)


func _check_texture(spec: Dictionary, expected_size: Vector2i, transparent: bool) -> void:
	var id := str(spec.get("art_id", "?"))
	var texture := ChapterArtRegistry.texture(spec)
	_check(bool(spec["ready"]) and texture != null, "纹理未就绪：" + id)
	if texture == null:
		return
	checked += 1
	_check(Vector2i(texture.get_size()) == expected_size, "纹理尺寸不符：" + id)
	var image := texture.get_image()
	_check(image != null and not image.is_empty(), "纹理内容为空：" + id)
	if image != null and transparent:
		_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(expected_size.x - 1, expected_size.y - 1).a == 0.0, "透明边缘不符：" + id)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

extends SceneTree
## 森林第一章 P0：内容登记、占位回退、内容开关与出发构造链路参数预留。

const ISOLATED_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak", "farm_save_v1.json.tmp"]

var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for filename in ISOLATED_FILES:
		var path: String = "user://" + filename
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameFlow.reset()
	## headless 下 root.size=0（d54 坑）：布局断言前先显式给窗口尺寸。
	root.size = Vector2i(1024, 640)
	root.content_scale_size = Vector2i(1024, 640)

	# —— 登记表自检：数量、归属、前缀、跨表引用（附录 A 全量） ————————————
	var problems: Array = ChapterOneDefs.validate_registrations()
	_check(problems.is_empty(), "登记表自检通过：%s" % ("；".join(problems)))
	_check(ChapterOneDefs.AREAS.size() == 5, "五区：共 5 区")
	_check(ChapterOneDefs.SEARCH_TEMPLATES.size() == 43, "搜索模板：共 43 类")
	_check(ChapterOneDefs.templates_for_area("trail").size() == 10, "古道：10 类")
	_check(ChapterOneDefs.templates_for_area("temple").size() == 9, "神殿：9 类")
	_check(ChapterOneDefs.templates_for_area("tower").size() == 8, "废塔：8 类")
	_check(ChapterOneDefs.templates_for_area("camp").size() == 8, "营地：8 类")
	_check(ChapterOneDefs.templates_for_area("wetland").size() == 8, "湿地：8 类")
	_check(ChapterOneDefs.ENEMIES.size() == 23, "敌人：共 23 个")
	_check(ChapterOneDefs.enemies_for_batch(2).size() == 11, "P2 批次：9 常规＋2 强敌")
	_check(ChapterOneDefs.enemies_for_batch(6).size() == 12, "P6 批次：9 常规＋3 强敌")
	var boss_count := 0
	for enemy_id in ChapterOneDefs.ENEMIES:
		if bool(ChapterOneDefs.ENEMIES[enemy_id]["boss"]):
			boss_count += 1
	_check(boss_count == 5, "区域强敌：5 个")
	_check(ChapterOneDefs.ITEM_MAPPING.size() == 36, "物品映射：36 条")
	_check(ChapterOneDefs.NEW_CARDS.size() == 16 and ChapterOneDefs.REUSED_CARDS.size() == 11, "牌登记：16 新增＋11 复用")

	# —— 复用与新增边界：复用项存在、新增项不撞名 ————————————
	for design_no in ChapterOneDefs.ITEM_MAPPING:
		var record: Dictionary = ChapterOneDefs.ITEM_MAPPING[design_no]
		if bool(record["reuse"]):
			_check(ItemDefs.is_known_item(str(record["def_id"])), "复用物品 %s=%s 已存在" % [design_no, str(record["def_id"])])
		else:
			_check(not ItemDefs.is_known_item(str(record["def_id"])), "新增物品 %s 未提前写入 ItemDefs（P1 落地）" % design_no)
	for card_id in ChapterOneDefs.REUSED_CARDS:
		_check(CardDefs.CARDS.has(card_id), "复用牌 %s 已存在" % card_id)
	for card_id in ChapterOneDefs.NEW_CARDS:
		_check(not CardDefs.CARDS.has(card_id), "新增牌 %s 未提前写入 CardDefs（P1 落地）" % card_id)
	_check(CardDefs.CARDS.size() == 19, "旧牌表未被 P0 改动：仍为 19 个模板")

	# —— 内容开关与版本检查 ————————————
	_check(ChapterOneDefs.departure_problem("") == "", "出发检查：空内容集（旧洞窟）放行")
	_check(ChapterOneDefs.departure_problem(ChapterOneDefs.CONTENT_SET) != "", "出发检查：森林出发在开关打开前被拒绝")
	_check(ChapterOneDefs.departure_problem(ChapterOneDefs.CONTENT_SET, 2).contains("版本"), "出发检查：内容版本不一致有明确原因")
	_check(ChapterOneDefs.departure_problem("cave_ch2").contains("未知内容集"), "出发检查：未知内容集拒绝")
	_check(ChapterOneDefs.recovery_problem(ChapterOneDefs.CONTENT_SET, ChapterOneDefs.CONTENT_VERSION) == "", "恢复检查：森林已有局不受出发开关影响")
	_check(ChapterOneDefs.recovery_problem(ChapterOneDefs.CONTENT_SET, 2) != "", "恢复检查：版本不支持的森林局明确拒绝")

	# —— 出发构造链路（本地单人）：拒绝路径不写占用、不留局 ————————————
	var farm := FarmGame.new()
	farm.new_game(int(Time.get_unix_time_from_system()))
	var blocked := ExpeditionGame.depart(farm, int(Time.get_unix_time_from_system()), ChapterOneDefs.CONTENT_SET)
	_check(not bool(blocked["ok"]), "单人出发：森林被开关拒绝")
	_check(str(blocked["reason"]).contains("尚未开放"), "单人出发：拒绝原因是开关未开")
	_check(str(farm.state["expedition"].get("active_run_ref", "")) == "", "单人出发：拒绝后未留下活动局占用")
	var unknown := ExpeditionGame.depart(farm, int(Time.get_unix_time_from_system()), "cave_ch2")
	_check(not bool(unknown["ok"]) and str(unknown["reason"]).contains("未知内容集"), "单人出发：未知内容集拒绝")

	# —— 纯构造层：content_set 写入与缺省行为（compose_run 不落盘） ————————————
	var stamped := ExpeditionGame.compose_run(farm, {}, "run-p0-stamp", 1750000000, false, "测试", ChapterOneDefs.CONTENT_SET)
	_check(str(stamped["content_set"]) == ChapterOneDefs.CONTENT_SET, "compose_run：森林局写入 content_set")
	_check(int(stamped["content_version"]) == ChapterOneDefs.CONTENT_VERSION, "compose_run：森林局写入 content_version")
	var legacy := ExpeditionGame.compose_run(farm, {}, "run-p0-legacy", 1750000000, false, "测试")
	_check(not legacy.has("content_set"), "compose_run：旧洞窟局不写 content_set（缺省即旧内容）")

	# —— 占位回退：全部资源 ID 可解析，未知 ID 走统一回退 ————————————
	for area_id in ChapterOneDefs.AREA_ORDER:
		var bg := ChapterArtRegistry.background(str(area_id))
		_check(str(bg["shape"]) == "background" and bg["base"] is Color, "占位背景：%s 可解析" % area_id)
	var prop_ok := true
	for template_id in ChapterOneDefs.SEARCH_TEMPLATES:
		var spec: Dictionary = ChapterArtRegistry.prop(template_id)
		if str(spec["art_id"]) != template_id or not (spec["base"] is Color):
			prop_ok = false
			push_error("  FAIL: 占位搜索物 %s 解析异常" % template_id)
	var enemy_ok := true
	for enemy_id in ChapterOneDefs.ENEMIES:
		var spec: Dictionary = ChapterArtRegistry.enemy(enemy_id)
		if str(spec["art_id"]) != enemy_id or str(spec.get("shape", "")) == "":
			enemy_ok = false
			push_error("  FAIL: 占位敌人 %s 解析异常" % enemy_id)
	_check(prop_ok, "占位搜索物：43 类全部可解析")
	_check(enemy_ok, "占位敌人：23 个全部可解析")
	var first := ChapterArtRegistry.prop("trail_hollow_log")
	var second := ChapterArtRegistry.prop("trail_hollow_log")
	_check(str(first["shape"]) == str(second["shape"]), "占位解析：同一模板结果稳定")
	var fallback: Dictionary = ChapterArtRegistry.resolve("totally_unknown_id")
	_check(not bool(fallback["ready"]) and fallback["base"] is Color, "缺图回退：未知资源 ID 返回统一占位")
	_check(str(ChapterArtRegistry.prop("trail_beehive")["shape"]) == "nest", "占位形状：蜂巢走 nest 轮廓")

	# —— 预览场景：五区卡片与返回入口存在 ————————————
	var preview: Control = (load("res://scenes/chapter_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	await _frames(2)
	for area_id in ChapterOneDefs.AREA_ORDER:
		var view := preview.find_child("AreaView_%s" % area_id, true, false) as Control
		_check(view != null, "预览：五区卡片 %s 存在" % area_id)
		if view != null:
			var chip_count := 0
			for template_id in ChapterOneDefs.templates_for_area(str(area_id)):
				if preview.find_child("PropChip_%s" % template_id, true, false) != null:
					chip_count += 1
			_check(chip_count == ChapterOneDefs.templates_for_area(str(area_id)).size(), "预览：%s 的搜索物芯片齐全" % area_id)
	_check(preview.find_child("BackButton", true, false) != null, "预览：返回主菜单按钮存在")
	var note := preview.find_child("DepartureNote", true, false) as Label
	_check(note != null and str(note.text).contains("未打开"), "预览：标明出发开关状态")
	preview.queue_free()
	await _frames(1)

	# —— 主菜单开发入口：测试模式下可见，默认隐藏 ————————————
	var menu: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(2)
	var forest_button := menu.find_child("ForestPreviewButton", true, false) as Button
	_check(forest_button != null, "主菜单：森林预览按钮存在")
	_check(forest_button != null and not forest_button.visible, "主菜单：默认（测试模式关）不显示森林预览")
	var corner := menu.find_child("TestModeCorner", true, false) as Control
	_check(corner != null and corner.get_global_rect().end.x <= root.size.x, "主菜单：加高后的测试角仍在窗口内")
	menu.queue_free()
	await _frames(1)

	if failed:
		push_error("FOREST_DEFS_SMOKE_FAIL")
	else:
		print("FOREST_DEFS_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

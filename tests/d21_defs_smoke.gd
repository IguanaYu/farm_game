extends SceneTree
## 2.1-W1/W2：规则基线常量、格子几何、物品与牌定义表一致性。


var failed := false


func _initialize() -> void:
	_check(ExpeditionBaseline.MAX_HP == 40, "基线：最大生命 40")
	_check(ExpeditionBaseline.ENERGY_PER_TURN == 3, "基线：每回合 3 能量")
	_check(ExpeditionBaseline.DRAW_PER_TURN == 5, "基线：每回合抽 5 张")
	_check(ExpeditionBaseline.HAND_LIMIT == 10, "基线：手牌上限 10")
	_check(ExpeditionBaseline.CONTAINER_SIZE["chest"] == Vector2i(3, 4), "基线：胸挂 3×4")
	_check(ExpeditionBaseline.CONTAINER_SIZE["pack"] == Vector2i(4, 4), "基线：背包 4×4")
	_check(ExpeditionBaseline.CONTAINER_SIZE["safe"] == Vector2i(1, 2), "基线：保险箱 1×2")
	_check(ExpeditionBaseline.JOIN_ROUND["chest"] == 1 and ExpeditionBaseline.JOIN_ROUND["pack"] == 2 and ExpeditionBaseline.JOIN_ROUND["safe"] == 3, "基线：容器加入回合 1/2/3")
	_check(ExpeditionBaseline.PROTO_RULES_VERSION.begins_with("d2-baseline-"), "基线：规则版本锚点存在")

	var plain: Array = ExpeditionBaseline.cells_of(Vector2i(2, 2), Vector2i(0, 0), false)
	_check(plain.size() == 4, "几何：2×2 占 4 格")
	var rotated: Array = ExpeditionBaseline.cells_of(Vector2i(1, 3), Vector2i(1, 1), true)
	_check(rotated == [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "几何：1×3 旋转后横放")

	var occupied := {"1,0": 5}
	_check(not ExpeditionBaseline.can_place("chest", Vector2i(2, 1), Vector2i(2, 0), false, {}), "几何：越界放置被拒绝")
	_check(not ExpeditionBaseline.can_place("chest", Vector2i(1, 1), Vector2i(1, 0), false, occupied), "几何：与占用格重叠被拒绝")
	_check(ExpeditionBaseline.can_place("chest", Vector2i(1, 1), Vector2i(0, 0), false, occupied), "几何：空位可放置")
	_check(ExpeditionBaseline.can_place("chest", Vector2i(1, 1), Vector2i(1, 0), false, occupied, 5), "几何：忽略自身实例后可放回原位")

	_check(ItemDefs.validate_definitions().is_empty(), "定义表：占格数=牌数、牌引用全部有效")
	var kit: Array = ItemDefs.basic_kit_ids()
	_check(kit.size() == 3, "基础套装：共 3 件")
	var total_cards := 0
	var total_cells := 0
	for def_id in kit:
		var def := ItemDefs.get_item(def_id)
		_check(not bool(def["sellable"]), "基础套装：%s 不可出售" % def_id)
		_check(not bool(def["safe_allowed"]), "基础套装：%s 不可放保险箱" % def_id)
		total_cards += def["cards"].size()
		total_cells += def["size"].x * def["size"].y
	_check(total_cards == 8 and total_cells == 8, "基础套装：合计 8 格／8 张牌")
	var demo_count := 0
	for def_id in ItemDefs.ITEMS:
		if bool(ItemDefs.ITEMS[def_id]["demo"]):
			demo_count += 1
			_check(def_id.begins_with("demo_"), "演示物品：%s 以 demo_ 前缀隔离" % def_id)
	_check(demo_count >= 2, "演示物品：至少 2 件")
	var big_demo := ItemDefs.get_item("demo_ore")
	_check(big_demo["size"] == Vector2i(2, 2) and bool(big_demo["sellable"]), "演示货物：大体积且值钱（值钱但拖累战斗）")
	_check(CardDefs.CARDS.size() == 12, "牌模板：12 个效果模板已注册")
	for card_id in ["slash", "heavy_strike", "shield_up", "cover", "brace", "deep_breath", "observe", "expose", "venom_stab", "drink_potion", "heavy_cargo", "first_aid"]:
		_check(CardDefs.CARDS.has(card_id), "牌模板：%s 存在" % card_id)

	if failed:
		push_error("D21_DEFS_SMOKE_FAIL")
	else:
		print("D21_DEFS_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)

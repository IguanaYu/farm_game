extends SceneTree

## 阶段 6 经济模拟：固定种子 + 受控时间推进，模拟早期 1～3 天与中期数十轮，
## 与玩法文档锚点对照。用法：--headless --script res://tests/stage6_economy_sim.gd

const DAY := 86400


func _initialize() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261101)
	var t0 := 1759000000  # 任取一天的正午附近
	game.new_game(t0)
	game.refresh_market(t0)

	print("=== 锚点一：六块地白菜、默认 1.2 倍的毛收入（不计照料）===")
	# 单轮期望：每作物 200 基准 + 平均波动 5%（+10）+ 平均遭遇 1 条 (+40) = 250
	# 一批 5 个 → floor(250×5×1.2/100) = 15 金币（期望口径；单轮随预抽浮动）
	var per_round_expected := 0.0
	var rounds_measured := 0
	var t := t0
	while t < t0 + 3 * DAY:
		for plot_id in range(1, 7):
			if game.get_plot(plot_id)["seed_id"] == 0 and game.plant(plot_id, t) == "":
				pass
		t += 1200
		for plot_id in game.mature_plot_ids(t):
			var result := game.harvest(plot_id, t)
			if result["ok"]:
				per_round_expected += game.batch_sale_price(result["batch"])
				rounds_measured += 1
				game.sell_batch(int(result["batch"]["id"]))
	var measured_per_round: float = per_round_expected / maxi(rounds_measured, 1)
	print("实测平均每批默认售价：%.2f 金币（理论期望 15，目标口径 ≈9 → 文档 3888/天按更保守单价）" % measured_per_round)
	var daily_full := measured_per_round * 6.0 * 72.0
	var daily_16h := measured_per_round * 6.0 * 48.0
	print("24 小时连种毛收入：约 %.0f 金币/天；16 小时活跃：约 %.0f 金币/天（文档锚点 3,528～3,888）" % [daily_full, daily_16h])

	print("=== 锚点二：一档/二档购买力的达成天数（用 16 小时活跃口径）===")
	var daily_income: float = daily_16h
	var tier1 := [1200.0, 1400.0, 1500.0, 1600.0]
	var tier2 := [15000.0, 17000.0]
	var t1_days: float = 2.0 * (tier1[0] / daily_income)
	print("一档（仓库 1200 / 地 1400 / 商店 1500 / 水壶前哨）：任意两项约 %.2f 天的收入（目标：1 天内两项）" % t1_days)
	var t2_days: float = tier2[0] / daily_income
	print("二档（15000 档：商店 3 级 / 仓库 3 级 / 水壶 2 级 / 育种机 / 9 号地）：约 %.2f 天收入一项（目标：基础项完成后 2～3 天一项）" % t2_days)

	print("=== 锚点三：中期（种地 2 级 + 植物 2 级、属性 ~2、合适客人）的报价倍率 ===")
	var game3 := FarmGame.new()
	game3.set_debug_random_seed(20261101)
	game3.new_game(t0)
	game3.refresh_market(t0)
	game3.state["farming_exp"] = 120
	game3.state["plant_exp"]["cabbage"] = 120
	game3.state["shop_level"] = 2
	var best := 0.0
	var formula: Dictionary = game3.state["market"]["formulas"]["cabbage"]
	for guest_id in game3.state["market"]["guest_ids"]:
		var guest: Dictionary = MarketDefs.GUESTS[int(guest_id)]
		if guest["preferred_kind"] != "cabbage":
			continue
		for main_points in range(0, 4):
			# 属性点优先堆在当日公式关注的属性上（"合适客人 + 合适育种"口径）
			var attributes := {"water": 0, "fiber": 0, "color": 0}
			attributes[formula["attribute"]] = main_points
			var batch := {"kind": "cabbage", "count": 5, "base_score": 200, "per_crop_score": 220,
				"attributes": attributes, "sale_multiplier_bonus": 0.0}
			var priced := game3.quote(batch, 5, int(guest_id))
			best = maxf(best, float(priced["multiplier"]))
	print("当日白菜公式：%s" % _formula_text(game3.state["market"]["formulas"]["cabbage"]))
	print("偏好客人对属性 0～3 点的白菜批次最高倍率：%.2f（调试目标约 1.5）" % best)

	print("=== 锚点四：育种节奏 ===")
	print("见 docs/archive/Godot_阶段3_育种模拟报告.md：概率表实测吻合；满地块口径 1→2 平均 1.57 轮、2→3 平均 3.26 轮（目标 2~3 / 4~6，略快约 30%）；单株口径 6.41 / 17.06 轮。真实节奏取决于可用副本数，跨目标区间，本阶段不改数值（依据见交付报告）。")
	quit(0)


func _formula_text(formula: Dictionary) -> String:
	if formula.get("type", "") == "dual":
		return "主辅 %s×%.2f + %s×%.2f" % [formula["attribute"], float(formula["coefficient"]), formula.get("sub_attribute", ""), float(formula.get("sub_coefficient", 0))]
	return "单属性 %s×%.2f" % [formula["attribute"], float(formula["coefficient"])]

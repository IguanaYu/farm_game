extends SceneTree

## 生成阶段 2 交付要求的收获算例：固定时间与固定随机结果，输出可手工核对的分数明细。
## 用法：--headless --script res://tests/stage2_worked_example.gd

const T := 1759000000


func _initialize() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20260930)
	game.new_game(T)
	game.state["fertilizers"]["basic"] = 1
	game.plant(1, T)
	game.water(1, T + 300)
	game.apply_fertilizer(1, "basic", T + 600)
	var cabbage := game.harvest(1, T + 1200)

	game.state["seeds"].append({"id": 900, "kind": "carrot", "traits": []})
	game.state["fertilizers"]["golden"] = 1
	game.state["farming_exp"] = 120
	game.state["plant_exp"]["carrot"] = 840
	game.plant(2, T, "carrot")
	var plot := game.get_plot(2)
	plot["preroll"]["fluctuation_pct"] = 7
	plot["preroll"]["encounters"] = [{"tier": 40, "offset": 1800}, {"tier": 10, "offset": 4200}]
	game.water(2, T + 600)
	game.water(2, T + 4200)
	game.apply_fertilizer(2, "golden", T + 300)
	var carrot := game.harvest(2, T + 7200)

	print("=== 白菜算例（新档、等级 1、浇 1 段、基础肥料） ===")
	_dump(cabbage, game)
	print("=== 胡萝卜算例（种地 2 级 + 植物 3 级快照、浇 2 段、金克拉、波动 7%、遭遇 +40/+10） ===")
	_dump(carrot, game)
	quit(0)


func _dump(result: Dictionary, game: FarmGame) -> void:
	var batch: Dictionary = result["batch"]
	var breakdown: Dictionary = batch["score_breakdown"]
	print("播种时间 %d，收获时间 %d" % [batch["planted_at"], batch["harvested_at"]])
	print("随机预抽：新种子 %d 粒，波动 %d%%，遭遇档位 %s" % [
		result["seeds"],
		breakdown["fluctuation_pct"],
		str(breakdown["encounter_tiers"]),
	])
	print("基准 %d + 等级 %d + 波动 %d + 浇水 %d + 肥料 %d + 遭遇 %d = 每作物 %d 分" % [
		breakdown["base"], breakdown["level_bonus"], breakdown["fluctuation_bonus"],
		breakdown["water_bonus"], breakdown["fertilizer_bonus"], breakdown["encounter_bonus"],
		breakdown["per_crop_score"],
	])
	print("整批 %d × %d = %d 分；默认售价 = floor(%d × 1.2 / 100) = %d 金币" % [
		breakdown["per_crop_score"], breakdown["crop_count"], breakdown["batch_total"],
		breakdown["batch_total"], game.batch_sale_price(batch),
	])
	print("经验 +%d（种地 %d/植物 %d 各一份）" % [result["exp_gain"], result["exp_gain"], result["exp_gain"]])
	print("经历条目数 %d" % result["events"].size())

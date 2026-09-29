extends SceneTree

## 阶段 3 育种模拟报告生成器。固定种子大量模拟，输出实测概率与目标节奏的对比。
## 用法：--headless --script res://tests/stage3_breeding_sim.gd

const LINEAGES := 2000
const RATE_SAMPLES := 50000


func _initialize() -> void:
	var game := FarmGame.new()
	game.new_game(1000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261030
	print("=== 概率实测（样本 %d 粒后代）===" % RATE_SAMPLES)
	var kept := 0
	var upgraded := 0
	var got_new := 0
	var parent_one: Array = [{"effect": "water_guarantee", "tier": 0}]
	for sample in range(RATE_SAMPLES):
		var child := game._generate_child_traits(parent_one, true, false, rng)
		for entry in child:
			if entry["effect"] == "water_guarantee":
				kept += 1
				if entry["tier"] == 1:
					upgraded += 1
				break
	for sample in range(RATE_SAMPLES):
		if not game._generate_child_traits([], true, false, rng).is_empty():
			got_new += 1
	print("保种·继承保留率：%.3f（目标 0.80）" % (float(kept) / RATE_SAMPLES))
	print("保种·保底1→2升档率（按保留计）：%.3f（目标 0.08）" % (float(upgraded) / kept))
	print("0条时新词条率（无变异）：%.3f（目标 0.70）" % (float(got_new) / RATE_SAMPLES))

	print("=== 目标节奏模拟（%d 条谱系；保种肥料；一轮 = 种满 6 块地约 15 粒后代取最优）===" % LINEAGES)
	var rounds_1_to_2 := 0.0
	var rounds_2_to_3 := 0.0
	var finished_2_to_3 := 0
	for lineage in range(LINEAGES):
		var traits: Array = [{"effect": "water_guarantee", "tier": 0}]
		var rounds := 0
		while _water_tier(traits) < 1 and rounds < 200:
			rounds += 1
			traits = _best_child(game, traits, rng)
		rounds_1_to_2 += rounds
		if _water_tier(traits) >= 1:
			rounds = 0
			while _water_tier(traits) < 2 and rounds < 500:
				rounds += 1
				traits = _best_child(game, traits, rng)
			if _water_tier(traits) >= 2:
				rounds_2_to_3 += rounds
				finished_2_to_3 += 1
	print("水分保底 1→2 平均 %.2f 轮（目标 2~3 轮）" % (rounds_1_to_2 / LINEAGES))
	print("水分保底 2→3 平均 %.2f 轮（目标 4~6 轮；%d/%d 条谱系在 500 轮内完成）" % [rounds_2_to_3 / maxi(finished_2_to_3, 1), finished_2_to_3, LINEAGES])
	print("配置：继承 80/30；升档 保底 8%/3% 倾向 8%/8%/3%（保种），普通减半；新词条 70/30/10/1，变异 +10pp")
	quit(0)


func _water_tier(traits: Array) -> int:
	for entry in traits:
		if entry["effect"] == "water_guarantee":
			return int(entry["tier"])
	return -1


func _best_child(game: FarmGame, parent: Array, rng: RandomNumberGenerator) -> Array:
	## 一轮 = 种满 6 块地：6 块 × 每块 2~3 粒（各 50%）≈ 15 粒后代，挑水分保底档位最高（其次品质）的一粒。
	## 若没有任何后代继承到词条，视为用备份原种再种一轮（不丢失谱系）。
	var best: Array = []
	var best_key := -1
	for plot_index in range(6):
		var children_count := 2 if rng.randf() < 0.5 else 3
		for child_index in range(children_count):
			var child := game._generate_child_traits(parent, true, false, rng)
			var key := (_water_tier(child) + 1) * 100 + BreedingDefs.quality_score(child)
			if key > best_key:
				best = child
				best_key = key
	if _water_tier(best) < 0:
		return parent
	return best

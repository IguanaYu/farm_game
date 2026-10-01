extends SceneTree
## 2.9：经济模拟（总计划 §12.2 口径）——基础／普通／高成本三种出发方式的
## 成本-收益对比，规则层数值推演（固定期望口径，非随机模拟；数值为初值待试玩）。


func _initialize() -> void:
	var report: Array = []
	report.append("=== 第二大阶段经济模拟（2.9）：三种出发方式（第一层·第 4 排撤离口径）===")

	## 撤离预期收益：第一层到第 4 排的节点收益期望（个人二选一取较高值 + 公共 1 件 + 采集 3 选）。
	## 用池内物品平均可售价值估算（设计初值口径）。
	var battle_avg := _pool_best_avg(ExpeditionDefs.BATTLE_PERSONAL_POOL)
	var public_avg := _pool_avg(ExpeditionDefs.BATTLE_PUBLIC_POOL)
	var gather_avg := _pool_avg(ExpeditionDefs.GATHER_POOL) * 3.0
	var run_gain := battle_avg + public_avg + gather_avg
	report.append("第一层至第 4 排期望可售收益 ≈ %.0f 金币（战斗 %.0f＋公共 %.0f＋采集 %.0f；均为池均值初值）" % [run_gain, battle_avg, public_avg, gather_avg])

	## 三种出发配置。
	var profiles := {
		"基础装（免费）": {"carry_value": 0, "potion": 0, "risk_note": "8 张牌小牌组"},
		"普通装（铜剑＋药水）": {"carry_value": 40 + 6, "potion": 1, "risk_note": "多 1 张重击"},
		"高成本装（铁剑＋摆件）": {"carry_value": 90 + 90, "potion": 0, "risk_note": "收益高、负担重"},
	}
	for profile_name in profiles:
		var profile: Dictionary = profiles[profile_name]
		var death_loss := int(profile["carry_value"])
		var net_extract := run_gain  ## 撤离：带入返还，新增=收益
		var net_death := -death_loss  ## 死亡：损失带入（新增也没拿到）
		report.append("%s：撤离净收益 ≈ %+.0f ｜ 死亡净损失 ≈ %d ｜ 携带风险：%s" % [
			profile_name, net_extract, death_loss, str(profile["risk_note"])])

	## 制作套利核算（2.5 设计 §9 算例复核）。
	var sword_cost := 3 * 8 + 2 * 6 + 8  ## 铜片3×8 + 纤维2×6 + 8 金币（材料按可售机会成本）
	report.append("铜剑制作总成本视角 ≈ %d vs 售价 40 → 非套利（装备价值在体验）" % sword_cost)
	var soup_value := 2 * 40 + 2  ## 白菜2个按基准分粗算可售 ≈40/个 + 2 金币
	report.append("白菜汤成本视角 ≈ %d vs 售价 4 → 亏（定位是补给不是套利）" % soup_value)

	## 断言（口径检查而非数值硬卡）。
	var ok := run_gain > 0 and run_gain < 200
	if ok:
		report.append("结论：第一层短途撤离收益为正且有限（%.0f），死亡损失与携带正相关——符合『撤离是决策』的设计意图。" % run_gain)
		print("D29_ECONOMY_SIM_PASS")
	else:
		push_error("D29_ECONOMY_SIM_FAIL：收益口径异常 %.1f" % run_gain)
		print("D29_ECONOMY_SIM_FAIL")
	var output := "\n".join(report)
	print(output)
	var file := FileAccess.open("user://d29_economy_sim_output.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(output)
		file.close()
	quit(0 if ok else 1)


func _pool_avg(pool: Array) -> float:
	if pool.is_empty():
		return 0.0
	var total := 0.0
	for def_id in pool:
		total += int(ItemDefs.get_item(str(def_id)).get("base_value", 0))
	return total / float(pool.size())


func _pool_best_avg(pool: Array) -> float:
	## 二选一取较高：期望 ≈ 池内前二均值（简化口径）。
	var values: Array = []
	for def_id in pool:
		values.append(int(ItemDefs.get_item(str(def_id)).get("base_value", 0)))
	values.sort()
	values.reverse()
	if values.size() < 2:
		return _pool_avg(pool)
	return (float(values[0]) + float(values[1])) / 2.0

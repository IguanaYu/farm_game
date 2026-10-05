class_name LoadoutPresets
extends RefCounted
## 配装预设（交付遗留项）：保存/命名/切换多套战备配装方案。
## 纯逻辑：不读时钟、不碰文件（存取走 PresetStore）、不碰 UI。
## 预设记录装备槽（fmt 2 起）与三个容器内真实（非演示）实例的槽位、容器、格位与旋转；
## 应用＝先清空（含卸下装备）再逐件精确复原，个别物品缺失或放不下时逐件降级，不整单失败。
## fmt 1 旧预设没有 equipment 段：按“只复原三容器”兼容读取。


const FMT := 2
const MAX_PRESETS := 12
const NAME_MAX_CHARS := 12


static func capture(inventory: InventoryGame) -> Dictionary:
	## 快照当前装备槽与三容器内的非演示物品（按 equipped→chest→pack→safe 顺序）。
	var items: Array = []
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in inventory.loadout_list(container):
			if bool(instance.get("demo", false)):
				continue
			items.append({
				"instance_id": int(instance["instance_id"]),
				"def_id": str(instance["def_id"]),
				"container": container,
				"cell": [int(instance["cell"][0]), int(instance["cell"][1])],
				"rotated": bool(instance.get("rotated", false)),
			})
	var equipment: Array = []
	for instance in inventory.equipped_list():
		if bool(instance.get("demo", false)):
			continue
		equipment.append({
			"instance_id": int(instance["instance_id"]),
			"def_id": str(instance["def_id"]),
			"slot": str(instance.get("slot", "")),
		})
	return {"fmt": FMT, "items": items, "equipment": equipment}


static func apply(inventory: InventoryGame, preset: Dictionary) -> Dictionary:
	## 按预设复原装备槽与三容器：先全部放回仓库（含卸下装备），再逐件精确放回；
	## 放不下降级为自动找位，实例不存在或只剩演示计“缺失”，两者都不阻塞其余物品。
	if inventory.is_run_occupied():
		return _result(false, "物品正在探险中，不能调整战备")
	if not (preset.get("items", []) is Array):
		return _result(false, "预设内容损坏")
	inventory.clear_loadout()
	var applied := 0
	var relocated := 0
	var missing: Array = []
	var blocked: Array = []
	for entry in preset.get("items", []):
		var instance := inventory.find_instance(int(entry.get("instance_id", -1)))
		if instance.is_empty() or bool(instance.get("demo", false)):
			missing.append(_display_name(entry))
			continue
		var cell_entry: Array = entry.get("cell", [0, 0])
		var placed := inventory.place_at(int(entry["instance_id"]), str(entry["container"]),
				Vector2i(int(cell_entry[0]), int(cell_entry[1])), bool(entry["rotated"]))
		if placed["ok"]:
			applied += 1
			continue
		var moved := inventory.move_to_loadout(int(entry["instance_id"]), str(entry["container"]))
		if moved["ok"]:
			relocated += 1
		else:
			blocked.append(_display_name(entry))
	for entry in preset.get("equipment", []):
		var instance := inventory.find_instance(int(entry.get("instance_id", -1)))
		if instance.is_empty() or bool(instance.get("demo", false)):
			missing.append(_display_name(entry))
			continue
		var equipped := inventory.equip(int(entry["instance_id"]), str(entry.get("slot", "")))
		if equipped["ok"]:
			applied += 1
		else:
			blocked.append(_display_name(entry))
	return {"ok": true, "reason": "", "applied": applied, "relocated": relocated,
			"missing": missing, "blocked": blocked}


static func report(result: Dictionary, preset_name: String) -> String:
	## 拼一句给玩家看的反馈；部分成功也要说清缺了什么。
	if not result["ok"]:
		return str(result["reason"])
	var parts: Array = ["已应用「%s」：%d 件就位" % [preset_name, int(result["applied"])]]
	if int(result["relocated"]) > 0:
		parts.append("%d 件自动换位" % int(result["relocated"]))
	for trouble in [["missing", "缺失"], ["blocked", "放不下留在仓库"]]:
		var names: Array = result[trouble[0]]
		if names.is_empty():
			continue
		var counts := {}
		for item_name in names:
			counts[item_name] = int(counts.get(item_name, 0)) + 1
		var shown: Array = []
		for item_name in counts:
			shown.append("%s×%d" % [item_name, counts[item_name]])
		parts.append("%s：%s" % [trouble[1], "、".join(shown)])
	return "，".join(parts) + "。"


static func normalize_name(raw: String, fallback_index: int) -> String:
	## 空名自动编号；超长截断。fallback_index 从 1 起（调用方传 presets.size() + 1）。
	var name := raw.strip_edges()
	if name == "":
		name = "预设 %d" % fallback_index
	return name.substr(0, NAME_MAX_CHARS)


static func _display_name(entry: Dictionary) -> String:
	## 优先用当前定义名；定义已下架时退回 def_id，保证报告可读。
	var def := ItemDefs.get_item(str(entry.get("def_id", "")))
	if def.is_empty():
		return str(entry.get("def_id", "?"))
	return str(def.get("name", entry.get("def_id")))


static func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "applied": 0, "relocated": 0, "missing": [], "blocked": []}

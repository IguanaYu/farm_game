class_name FarmGame
extends RefCounted

const SAVE_VERSION := 1
const PLOT_COUNT := 6
const GROW_SECONDS := 20 * 60
const CROP_BASE_SCORE := 200
const CROP_COUNT := 5
const SEED_PRICE := 10

var state: Dictionary = {}
var roll_randomizer := RandomNumberGenerator.new()


func _init() -> void:
	roll_randomizer.randomize()


func set_debug_random_seed(value: int) -> void:
	roll_randomizer.seed = value


func new_game(now: int) -> void:
	state = {
		"version": SAVE_VERSION,
		"next_id": 1,
		"coins": 0,
		"plots": [],
		"seeds": [],
		"crop_batches": []
	}
	for plot_index in range(PLOT_COUNT):
		state["plots"].append({
			"id": plot_index + 1,
			"seed_id": 0,
			"planted_at": 0,
			"ready_at": 0,
			"roll_seed": 0
		})
	for seed_index in range(PLOT_COUNT):
		state["seeds"].append(_new_seed())
	state["created_at"] = now


func load_state(saved: Dictionary) -> bool:
	if saved.get("version", -1) != SAVE_VERSION:
		return false
	if not saved.get("plots") is Array or not saved.get("seeds") is Array or not saved.get("crop_batches") is Array:
		return false
	if saved["plots"].size() != PLOT_COUNT:
		return false
	if not _is_number(saved.get("coins")) or not _is_number(saved.get("next_id")):
		return false
	if saved["coins"] < 0 or saved["next_id"] < 1:
		return false
	for plot in saved["plots"]:
		if not plot is Dictionary:
			return false
		for field in ["id", "seed_id", "planted_at", "ready_at", "roll_seed"]:
			if not _is_number(plot.get(field)):
				return false
	for seed in saved["seeds"]:
		if not seed is Dictionary or not _is_number(seed.get("id")) or seed.get("kind") != "cabbage":
			return false
	for batch in saved["crop_batches"]:
		if not batch is Dictionary:
			return false
		for field in ["id", "plot_id", "count", "base_score"]:
			if not _is_number(batch.get(field)):
				return false
	state = saved.duplicate(true)
	state["coins"] = int(state["coins"])
	state["next_id"] = int(state["next_id"])
	for plot in state["plots"]:
		for field in ["id", "seed_id", "planted_at", "ready_at", "roll_seed"]:
			plot[field] = int(plot[field])
	for seed in state["seeds"]:
		seed["id"] = int(seed["id"])
	for batch in state["crop_batches"]:
		for field in ["id", "plot_id", "count", "base_score"]:
			batch[field] = int(batch[field])
	return true


func get_plot(plot_id: int) -> Dictionary:
	if plot_id < 1 or plot_id > PLOT_COUNT:
		return {}
	return state["plots"][plot_id - 1]


func is_ready(plot_id: int, now: int) -> bool:
	var plot := get_plot(plot_id)
	return not plot.is_empty() and plot["seed_id"] != 0 and now >= plot["ready_at"]


func plant(plot_id: int, now: int) -> String:
	var plot := get_plot(plot_id)
	if plot.is_empty():
		return "找不到这块地。"
	if plot["seed_id"] != 0:
		return "这块地正在生长，成熟后才能收获。"
	if state["seeds"].is_empty():
		return "没有种子了。请到商店购买。"
	var seed: Dictionary = state["seeds"].pop_front()
	plot["seed_id"] = seed["id"]
	plot["planted_at"] = now
	plot["ready_at"] = now + GROW_SECONDS
	plot["roll_seed"] = int(roll_randomizer.randi())
	return ""


func harvest(plot_id: int, now: int) -> Dictionary:
	var plot := get_plot(plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		return {"ok": false, "message": "这块地还没有作物。"}
	if now < plot["ready_at"]:
		return {"ok": false, "message": "作物还没成熟。"}
	var randomizer := RandomNumberGenerator.new()
	randomizer.seed = plot["roll_seed"]
	var gained_seeds: int = randomizer.randi_range(2, 3)
	var batch := {
		"id": _take_id(),
		"plot_id": plot_id,
		"kind": "cabbage",
		"count": CROP_COUNT,
		"base_score": CROP_BASE_SCORE,
		"planted_at": plot["planted_at"],
		"harvested_at": now
	}
	state["crop_batches"].append(batch)
	for seed_index in range(gained_seeds):
		state["seeds"].append(_new_seed())
	plot["seed_id"] = 0
	plot["planted_at"] = 0
	plot["ready_at"] = 0
	plot["roll_seed"] = 0
	return {"ok": true, "batch": batch.duplicate(true), "seeds": gained_seeds}


func buy_seeds(quantity: int) -> String:
	if quantity <= 0:
		return "购买数量必须大于零。"
	var total_price: int = quantity * SEED_PRICE
	if state["coins"] < total_price:
		return "金币不足，需要 %d 金币。" % total_price
	state["coins"] -= total_price
	for seed_index in range(quantity):
		state["seeds"].append(_new_seed())
	return ""


func batch_sale_price(batch: Dictionary) -> int:
	# 整笔计价额先合计，再除以 100 向下取整。
	return int(floor(float(batch["count"] * batch["base_score"]) * 1.2 / 100.0))


func sell_batch(batch_id: int) -> Dictionary:
	for index in range(state["crop_batches"].size()):
		var batch: Dictionary = state["crop_batches"][index]
		if batch["id"] == batch_id:
			var price := batch_sale_price(batch)
			state["crop_batches"].remove_at(index)
			state["coins"] += price
			return {"ok": true, "coins": price}
	return {"ok": false, "message": "找不到这批作物。"}


func sell_all_batches() -> int:
	var total_score := 0
	for batch in state["crop_batches"]:
		total_score += batch["count"] * batch["base_score"]
	var earned := int(floor(float(total_score) * 1.2 / 100.0))
	state["crop_batches"].clear()
	state["coins"] += earned
	return earned


func _new_seed() -> Dictionary:
	return {"id": _take_id(), "kind": "cabbage", "traits": []}


func _take_id() -> int:
	var result: int = state["next_id"]
	state["next_id"] = result + 1
	return result


func _is_number(value: Variant) -> bool:
	return value is int or value is float

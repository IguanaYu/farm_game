extends SceneTree

## 阶段 4 测试：每日客人（北京时间边界、锁定、跳日）、报价公式与取整、拆批出售、
## 折扣与批量、扩地十块、水壶 2 级、存档 v3→v4 迁移。

const TEST_SAVE := "user://stage4_market_save.json"

var failed := false


func _initialize() -> void:
	for test in [
		_test_day_boundary_and_locks,
		_test_quotes_and_rounding,
		_test_split_sale,
		_test_discount_and_bulk,
		_test_plot_expansion,
		_test_can2,
		_test_v3_to_v4_migration,
	]:
		if failed:
			break
		test.call()
	_cleanup()
	if failed:
		print("STAGE4_MARKET_FAIL")
		quit(1)
	else:
		print("STAGE4_MARKET_PASS")
		quit(0)


func _fresh_game(now := 1759000000) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261010)
	game.new_game(now)
	return game


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("STAGE4_MARKET_FAIL: " + message)
	failed = true


func _next_midnight(unix: int) -> int:
	## 下一个北京时间零点的 unix 时刻。
	var day := MarketDefs.day_index(unix)
	return (day + 1) * 86400 - MarketDefs.BEIJING_OFFSET_SECONDS


func _test_day_boundary_and_locks() -> void:
	var t := 1759000000
	var game := _fresh_game(t)
	var market: Dictionary = game.state["market"]
	_check(market["guest_ids"].size() == 3, "each day draws exactly three guests")
	_check(not market["formulas"]["cabbage"].is_empty() and not market["formulas"]["carrot"].is_empty(), "both plants get a daily formula")
	# 同一天内重复刷新不重抽
	var guests_today: Array = market["guest_ids"].duplicate()
	var formula_today: Dictionary = market["formulas"]["cabbage"].duplicate(true)
	game.refresh_market(t + 3600)
	_check(game.state["market"]["guest_ids"] == guests_today, "same day keeps the same guests")
	_check(game.state["market"]["formulas"]["cabbage"] == formula_today, "same day keeps the same formula")
	_check(SaveStore.save_state(game.state, TEST_SAVE), "market save works")
	var reloaded := FarmGame.new()
	_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "market reload works")
	_check(reloaded.state["market"]["guest_ids"] == guests_today, "reload keeps today's guests")
	# 23:59:59 与次日 00:00:00 交界
	var midnight := _next_midnight(t)
	game.refresh_market(midnight - 1)
	_check(game.state["market"]["guest_ids"] == guests_today, "23:59:59 still counts as the old day")
	game.refresh_market(midnight)
	_check(game.state["market"]["day_index"] == MarketDefs.day_index(midnight), "00:00:00 starts the new day")
	_check(game.state["market"]["guest_ids"].size() == 3, "new day draws three guests again")
	# 跳过多日只显示当前日
	var later := midnight + 5 * 86400
	game.refresh_market(later)
	_check(game.state["market"]["day_index"] == MarketDefs.day_index(later), "skipping days shows only the current day")
	_check(game.state["market"]["guest_ids"].size() == 3, "no backlog of past guests")
	# 锁客人：商店 2 级，锁今天出现的客人，次日持续出现
	var game2 := _fresh_game(t)
	game2.state["coins"] = 1500
	_check(game2.upgrade_shop() == "" and int(game2.state["shop_level"]) == 2, "shop upgrades to level 2")
	var lock_target: int = int(game2.state["market"]["guest_ids"][0])
	_check(game2.request_lock_guest(lock_target) == "", "locking a today guest works at shop level 2")
	_check(game2.request_lock_guest(99) != "", "cannot lock a guest not appearing today")
	var mid2 := _next_midnight(t)
	game2.refresh_market(mid2)
	_check(lock_target in game2.state["market"]["guest_ids"], "locked guest appears the next day")
	game2.refresh_market(mid2 + 86400)
	_check(lock_target in game2.state["market"]["guest_ids"], "locked guest keeps appearing")
	# 换锁在次日生效
	var other: int = int(game2.state["market"]["guest_ids"][1])
	_check(game2.request_lock_guest(other) == "", "switching the lock is accepted")
	game2.refresh_market(mid2 + 2 * 86400)
	_check(other in game2.state["market"]["guest_ids"], "new lock takes effect the next midnight")
	# 锁公式：商店 3 级 + 已锁客人；类型与属性固定，系数重抽
	game2.state["coins"] = 15000
	_check(game2.upgrade_shop() == "" and int(game2.state["shop_level"]) == 3, "shop upgrades to level 3")
	var preferred_kind: String = MarketDefs.GUESTS[other]["preferred_kind"]
	_check(game2.request_lock_formula(preferred_kind) == "", "locking the preferred formula works at shop level 3")
	var formula_before: Dictionary = game2.state["market"]["formulas"][preferred_kind].duplicate(true)
	game2.refresh_market(mid2 + 3 * 86400)
	var formula_after: Dictionary = game2.state["market"]["formulas"][preferred_kind]
	_check(formula_after["type"] == formula_before["type"] and formula_after["attribute"] == formula_before["attribute"], "locked formula keeps its type and attribute")
	if formula_before.get("type", "") == "dual":
		_check(formula_after.get("sub_attribute", "") == formula_before.get("sub_attribute", ""), "locked dual formula keeps its sub attribute")


func _test_quotes_and_rounding() -> void:
	var game := _fresh_game()
	# 手工固定当日公式，验证报价的每一项构成
	game.state["market"]["formulas"]["cabbage"] = {"kind": "cabbage", "type": "single", "attribute": "water", "coefficient": 0.10}
	var guest_cabbage := 1
	for guest_id in MarketDefs.GUESTS:
		if MarketDefs.GUESTS[guest_id]["preferred_kind"] == "cabbage":
			guest_cabbage = guest_id
			break
	var batch := {
		"id": 1, "plot_id": 1, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 270, "attributes": {"water": 2, "fiber": 0, "color": 0},
		"sale_multiplier_bonus": 0.2,
	}
	# ① 客人公式 × 偏好 1.2 + 金克拉 0.2：(1 + 2×0.10) × 1.2 + 0.2 = 1.64
	var priced := game.quote(batch, 5, guest_cabbage)
	_check(abs(float(priced["multiplier"]) - 1.64) < 0.0001, "multiplier is (1+attr×coef)×1.2 + golden 0.2 = 1.64")
	_check(priced["coins"] == int(floor(270.0 * 5 * 1.64 / 100.0)), "guest coins floor the summed total: 270×5×1.64 → 22")
	_check(priced["coins"] == 22, "sample ① computes 22 coins by hand")
	# 非偏好客人无 1.2 倍
	var guest_carrot := 4
	for guest_id in MarketDefs.GUESTS:
		if MarketDefs.GUESTS[guest_id]["preferred_kind"] == "carrot":
			guest_carrot = guest_id
			break
	var priced_plain := game.quote(batch, 5, guest_carrot)
	_check(abs(float(priced_plain["multiplier"]) - (1.2 + 0.2)) < 0.0001, "non-preferred guest gets formula ×1.0 + golden")
	# ② 整笔除以 100 向下取整：27 分 × 5 × 1.2 = 162 计价额 → 1 金币（不是 2）
	game.state["crop_batches"].append({
		"id": 77, "plot_id": 2, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 27, "attributes": {"water": 0, "fiber": 0, "color": 0}, "sale_multiplier_bonus": 0.0,
	})
	var default_price := game.batch_sale_price(game.state["crop_batches"][0])
	_check(default_price == 1, "default sale floors 27×5×1.2=162 → 1 coin, not 2")
	# ③ 商店折扣四舍五入：2 级商店买 3 粒标价 10 → 28.5 → 29
	game.state["shop_level"] = 2
	_check(MarketDefs.discounted_total(30, 2) == 29, "discount rounds 28.5 up to 29")
	game.state["coins"] = 100
	_check(game.buy_seeds(3, "cabbage") == "" and game.state["coins"] == 71, "buying three seeds at shop 2 costs 29")


func _test_split_sale() -> void:
	var game := _fresh_game()
	game.state["market"]["formulas"]["cabbage"] = {"kind": "cabbage", "type": "single", "attribute": "water", "coefficient": 0.08}
	var guest_id := 1
	for candidate in MarketDefs.GUESTS:
		if MarketDefs.GUESTS[candidate]["preferred_kind"] == "cabbage":
			guest_id = candidate
			break
	game.state["crop_batches"].append({
		"id": 501, "plot_id": 1, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 250, "attributes": {"water": 1, "fiber": 0, "color": 0}, "sale_multiplier_bonus": 0.0,
	})
	game.state["coins"] = 0
	var first := game.sell_batch_to(501, 2, guest_id, 1759000100)
	_check(first["ok"] and int(game.state["crop_batches"][0]["count"]) == 3, "selling 2 leaves 3 in the batch")
	var second := game.sell_batch_to(501, 3, guest_id, 1759000200)
	_check(second["ok"] and game.state["crop_batches"].is_empty(), "selling the remaining 3 clears the batch")
	_check(game.state["coins"] == first["coins"] + second["coins"], "coins equal the sum of the two settlements")
	var expected := int(floor(250.0 * 2 * 1.08 * 1.2 / 100.0)) + int(floor(250.0 * 3 * 1.08 * 1.2 / 100.0))
	_check(game.state["coins"] == expected, "split coins match hand computation (%d)" % expected)
	_check(not game.sell_batch_to(501, 1, guest_id, 1759000300)["ok"], "selling from a gone batch fails")
	# 默认出售始终可选
	game.state["crop_batches"].append({
		"id": 502, "plot_id": 2, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 200, "attributes": {"water": 0, "fiber": 0, "color": 0}, "sale_multiplier_bonus": 0.0,
	})
	_check(game.sell_batch(502)["ok"] and game.state["crop_batches"].is_empty(), "default sale always works")
	# 数量边界
	game.state["crop_batches"].append({
		"id": 503, "plot_id": 3, "kind": "cabbage", "count": 5, "base_score": 200,
		"per_crop_score": 200, "attributes": {"water": 0, "fiber": 0, "color": 0}, "sale_multiplier_bonus": 0.0,
	})
	_check(not game.sell_batch_to(503, 0, guest_id, 1759000400)["ok"], "zero count is rejected")
	_check(not game.sell_batch_to(503, 6, guest_id, 1759000400)["ok"], "over-count is rejected")
	# 存读档一致
	_check(SaveStore.save_state(game.state, TEST_SAVE), "split sale save works")
	var reloaded := FarmGame.new()
	_check(reloaded.load_state(SaveStore.load_state(TEST_SAVE)), "split sale reload works")
	_check(reloaded.state["crop_batches"].size() == 1 and int(reloaded.state["crop_batches"][0]["count"]) == 5, "reload restores the remaining batch")


func _test_discount_and_bulk() -> void:
	var game := _fresh_game()
	game.state["farming_exp"] = 120
	game.state["coins"] = 1000
	game.state["shop_level"] = 2
	_check(game.buy_fertilizer("basic", 5) == "", "bulk fertilizer purchase works")
	_check(game.state["coins"] == 1000 - MarketDefs.discounted_total(50, 2), "five packs cost the discounted total (48 at shop 2: round(47.5))")
	_check(int(game.state["fertilizers"]["basic"]) == 50, "bulk purchase adds fifty uses")
	_check(game.buy_fertilizer("basic", 0) != "", "zero quantity is rejected")
	var game4 := _fresh_game()
	game4.state["farming_exp"] = 120
	game4.state["coins"] = 1000
	game4.state["shop_level"] = 4
	_check(game4.buy_fertilizer("basic", 1) == "" and game4.state["coins"] == 1000 - 9, "shop 4 discount rounds 10×0.85=8.5 to 9 (away from zero)")
	_check(not game.state["ledger"].is_empty(), "ledger records purchases")


func _test_plot_expansion() -> void:
	var game := _fresh_game()
	_check(game.owned_plot_ids().size() == 6, "a new game owns six plots")
	_check(game.get_plot(7).is_empty(), "plot 7 is not interactable before purchase")
	game.state["coins"] = 1400
	_check(game.buy_plot() == "" and game.owned_plot_ids().size() == 7, "plot 7 costs 1400")
	_check(game.state["coins"] == 0, "buying plot 7 empties the wallet")
	_check(game.buy_plot() != "", "plot 8 needs 1600 more coins")
	game.state["coins"] = 1600 + 15000 + 17000
	_check(game.buy_plot() == "" and game.buy_plot() == "" and game.buy_plot() == "", "plots 8/9/10 purchase sequentially")
	_check(game.owned_plot_ids().size() == 10 and game.buy_plot() != "", "ten plots is the cap")
	_check(game.plant_seed(10, int(game.state["seeds"][0]["id"]), 1759000500) == "", "plot 10 can be planted")
	var result := game.harvest(10, 1759001700)
	_check(result["ok"], "plot 10 can be harvested")
	_check(game.is_ready(9, 1759001700) == false, "other plots stay untouched")


func _test_can2() -> void:
	var game := _fresh_game()
	game.state["coins"] = MarketDefs.CAN2_COST
	_check(game.buy_can2() == "" and int(game.state["can_level"]) == 2, "can upgrade to level 2 works")
	_check(game.buy_can2() != "", "cannot buy can 2 twice")
	for plot_id in [1, 2, 3]:
		game.plant(plot_id, 1759000600)
	var watered := game.water(1, 1759000700)
	_check(watered["ok"] and watered["watered"].size() == 3, "can 2 waters three plots at once (got %d)" % watered.get("watered", []).size())
	for plot_id in [1, 2, 3]:
		_check(game.get_plot(plot_id)["watered_segments"] == [{"segment": 0, "can_level": 2}], "plot %d records the can-2 watering" % plot_id)
	var result := game.harvest(1, 1759001800)
	_check(result["ok"] and result["batch"]["score_breakdown"]["water_bonus"] == 40, "can 2 gives +20%% (40 points on base 200)")
	# 混合：水壶 1 级浇过的时段在升级后保持 +10%
	var game2 := _fresh_game()
	game2.plant(1, 1759000600)
	game2.water(1, 1759000700)
	_check(game2.get_plot(1)["watered_segments"] == [{"segment": 0, "can_level": 1}], "can 1 watering records level 1")
	game2.state["coins"] = MarketDefs.CAN2_COST
	game2.buy_can2()
	var mixed := game2.harvest(1, 1759001800)
	_check(mixed["ok"] and mixed["batch"]["score_breakdown"]["water_bonus"] == 20, "a segment watered with can 1 keeps its +10%% even after upgrading")


func _test_v3_to_v4_migration() -> void:
	var v3 := {
		"version": 3,
		"next_id": 50,
		"coins": 777,
		"farming_exp": 120,
		"plant_exp": {"cabbage": 120},
		"shop_level": 2,
		"can_level": 1,
		"warehouse_level": 1,
		"fertilizers": {"basic": 0, "mutation": 0, "preserve": 0, "golden": 0},
		"breeder": {"owned": false, "level": 1, "template_seed_id": 0, "pending": 0, "progress": {}, "last_settled": 0},
		"pending": {"crops": [], "seeds": []},
		"plots": [],
		"seeds": [{"id": 40, "kind": "cabbage", "traits": []}],
		"crop_batches": [],
		"created_at": 1,
	}
	for index in range(6):
		v3["plots"].append({
			"id": index + 1, "seed_id": 0, "planted_at": 0, "ready_at": 0, "roll_seed": 0,
			"kind": "", "snapshot": {}, "watered_segments": [0] if index == 0 else [], "fertilizer": {},
			"preroll": {}, "events": [], "parent_traits": [],
		})
	var game := FarmGame.new()
	_check(game.load_state(v3), "version 3 save migrates to version 4")
	_check(game.state["version"] == 4, "migrated save reports version 4")
	_check(game.state["plots"].size() == 10 and game.owned_plot_ids().size() == 6, "six-plot save stays at six owned plots of ten slots")
	_check(game.get_plot(7).is_empty() and game.get_plot(6).is_empty() == false, "unowned new plots are locked, old plots stay usable")
	_check(game.get_plot(1)["watered_segments"] == [{"segment": 0, "can_level": 1}], "int watered segments convert to can-1 records")
	_check(game.state["market"]["day_index"] == -1, "market starts unset and refreshes on demand")
	_check(game.state["market"]["guest_ids"].is_empty(), "no guests before the first refresh")
	game.refresh_market(1759000000)
	_check(game.state["market"]["guest_ids"].size() == 3, "first refresh draws three guests")
	_check(game.state["ledger"].is_empty(), "migration starts with an empty ledger")
	_check(game.state["coins"] == 777, "migration keeps coins")


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = TEST_SAVE + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

class_name ServerDB
extends RefCounted
## M1 服务端存储封装（计划 §4.1）：SQLite WAL+FULL（沿 M0 结论），
## schema v2 = 账号/邀请/token/收据。所有写走 tx()（BEGIN IMMEDIATE），
## 事务函数返回非 OK 时整体回滚，保证"先保存，再回复成功"（规划 §4.2）。

const SCHEMA_VERSION := 3

const SCHEMA := [
	"CREATE TABLE IF NOT EXISTS meta(" +
		"key TEXT PRIMARY KEY, value TEXT NOT NULL)",
	"CREATE TABLE IF NOT EXISTS invites(" +
		"code TEXT PRIMARY KEY, note TEXT NOT NULL DEFAULT '', " +
		"created_at TEXT NOT NULL, used_at TEXT DEFAULT NULL, account_id INTEGER DEFAULT NULL)",
	"CREATE TABLE IF NOT EXISTS accounts(" +
		"id INTEGER PRIMARY KEY AUTOINCREMENT, nick TEXT NOT NULL, " +
		"created_at TEXT NOT NULL, disabled INTEGER NOT NULL DEFAULT 0, " +
		"farm_state TEXT NOT NULL, farm_seq INTEGER NOT NULL DEFAULT 0)",
	"CREATE TABLE IF NOT EXISTS tokens(" +
		"token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL, " +
		"created_at TEXT NOT NULL, revoked_at TEXT DEFAULT NULL)",
	"CREATE TABLE IF NOT EXISTS receipts(" +
		"account_id INTEGER NOT NULL, req_id TEXT NOT NULL, op TEXT NOT NULL, " +
		"args_digest TEXT NOT NULL DEFAULT '', outcome TEXT NOT NULL DEFAULT '', " +
		"result_json TEXT NOT NULL DEFAULT '{}', farm_seq INTEGER NOT NULL DEFAULT 0, " +
		"created_at TEXT NOT NULL, PRIMARY KEY(account_id, req_id))",
]

## v3（M3）：房间/局/结算。结算由服务器事务内直接应用，state 留档对账（S04）。
const SCHEMA_V3 := [
	"CREATE TABLE IF NOT EXISTS rooms(" +
		"id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, " +
		"state TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
	"CREATE TABLE IF NOT EXISTS runs(" +
		"run_id TEXT PRIMARY KEY, room_id INTEGER, owner_account_id INTEGER NOT NULL DEFAULT 0, " +
		"state TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)",
	"CREATE TABLE IF NOT EXISTS settlements(" +
		"settlement_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, account_id INTEGER NOT NULL, " +
		"state TEXT NOT NULL, created_at TEXT NOT NULL)",
]

var db: SQLite
var db_path := ""


func open(path: String) -> bool:
	db_path = path
	if not ClassDB.class_exists("SQLite"):
		push_error("godot-sqlite 扩展未加载（ClassDB 无 SQLite）")
		return false
	db = SQLite.new()
	db.path = path
	if not db.open_db():
		push_error("SQLite 打开失败: %s" % db.error_message)
		return false
	db.query("PRAGMA journal_mode=WAL;")
	db.query("PRAGMA synchronous=FULL;")
	for stmt in SCHEMA + SCHEMA_V3:
		if not db.query(stmt):
			push_error("SQLite 建表失败: %s" % stmt)
			return false
	if not _check_or_init_meta():
		return false
	return true


func _check_or_init_meta() -> bool:
	if not db.query("SELECT value FROM meta WHERE key = 'schema_version'"):
		push_error("meta 读取失败")
		return false
	if db.query_result.is_empty():
		var created := _now_string()
		return db.query_with_bindings(
			"INSERT INTO meta(key, value) VALUES('schema_version', ?)", [str(SCHEMA_VERSION)]
		) and db.query_with_bindings("INSERT INTO meta(key, value) VALUES('created_at', ?)", [created])
	var stored := int(db.query_result[0]["value"])
	if stored > SCHEMA_VERSION:
		push_error("数据库 schema 版本不符：库内 %d，本程序 %d（先备份再迁移）" % [stored, SCHEMA_VERSION])
		return false
	if stored < SCHEMA_VERSION:
		## 只做加表迁移（v2→v3：rooms/runs/settlements）；v1→v2 需人工备份重建。
		for stmt in SCHEMA_V3:
			if not db.query(stmt):
				push_error("SQLite 迁移建表失败: %s" % stmt)
				return false
		if not db.query_with_bindings(
			"UPDATE meta SET value = ? WHERE key = 'schema_version'", [str(SCHEMA_VERSION)]
		):
			return false
	return true


func close() -> void:
	if db != null:
		db.close_db()
		db = null


## 事务助手：fn 内做读改写并返回 true/false；false 或中途查询失败由调用方显式
## 返回 false 触发回滚。返回 [ok, fn 的返回值]。
func tx(fn: Callable) -> Array:
	if not db.query("BEGIN IMMEDIATE"):
		return [false, null]
	var ok: bool = fn.call()
	if not ok:
		db.query("ROLLBACK")
		return [false, null]
	if not db.query("COMMIT"):
		db.query("ROLLBACK")
		return [false, false]
	return [true, true]


func query_one(sql: String, binds: Array = []) -> Dictionary:
	if binds.is_empty():
		if not db.query(sql):
			return {}
	else:
		if not db.query_with_bindings(sql, binds):
			return {}
	if db.query_result.is_empty():
		return {}
	var row: Dictionary = db.query_result[0]
	return row


func query_all(sql: String, binds: Array = []) -> Array:
	if binds.is_empty():
		if not db.query(sql):
			return []
	else:
		if not db.query_with_bindings(sql, binds):
			return []
	return db.query_result.duplicate()


func exec(sql: String, binds: Array = []) -> bool:
	if binds.is_empty():
		return db.query(sql)
	return db.query_with_bindings(sql, binds)


func _now_string() -> String:
	return Time.get_datetime_string_from_system(true)

# 2.7 进度保存与异常恢复：代码执行计划 v0.1

日期：2026-10-01。状态：**已完成（2026-10-01，交付报告见 [archive/Godot_阶段2.7_交付报告.md](../archive/Godot_阶段2.7_交付报告.md)）**。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

> 实施记录（2026-10-01）：心跳/掉线暂停/同身份重连/主机重启接回/未决结算幂等补发全部落地；单人恢复引用 d24。等待倒计时 UI 与快照节流移交 2.8。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.7 详细设计](../design/Godot_阶段2.7_进度保存与异常恢复_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜上游代码计划：[2.1](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)｜[2.4](Godot_阶段2.4_单人洞窟与撤离闭环_代码执行计划_v0.1.md)｜[2.6](Godot_阶段2.6_双人合作与战利品分配_代码执行计划_v0.1.md)

本文把 2.7 详细设计拆成可执行的 Godot 代码任务，并严格遵守 [2.1 代码执行计划](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)附录 A 的全阶段工程约定与模块地图：规则层结果字典统一 `{ok: bool, reason: String, …}`、ID 体系（`run-…`／`act-<peer>-<seq>`／`settle-…`，2.1-W1 已定且跨阶段不改）、存档三段式 tmp→bak→替换、测试命名 `tests/d27_*.gd`、模块地图 2.7 列（`expedition_store.gd` 扩幂等清单/恢复路径、`session_host.gd`/`session_client.gd` 扩重连凭据/暂停恢复/未决结算、`expedition_game.gd` 扩暂停恢复语义、`combat_game.gd` 扩动作去重入口）。设计内容（状态表、故障场景、恢复行为、提示文案）以详细设计为准，本文不重述、不复制设计数值，只引用 `D2.7-XX` 功能号。总计划 §13 已明确：结算幂等与出发占用事务从 2.4 开始实施，本阶段任务是"扩全故障覆盖"，不是从零补做。

## 1. 输入与前置

- 上游交付物（到文件级，均以上游代码计划的 §2 表为准）：
  - 2.1：`scripts/domain/expedition_baseline.gd`（`PROTO_RULES_VERSION`、ID 格式常量）、`scripts/services/expedition_store.gd` 骨架与 `run_<run_id>.json`／`settlement_<settlement_id>.json` 路径、`scripts/domain/inventory_game.gd`（归属唯一／占用）、`scripts/domain/farm_game.gd` v6 迁移与 `expedition` 块（`player_id`、`active_run_ref`、`applied_settlements`）。
  - 2.2：`scripts/domain/combat_game.gd`——战斗状态（回合、手牌、敌人意图、状态）可整体序列化为字典；这是"暂停保留具体回合"的前提。
  - 2.3：`scripts/domain/deck_builder.gd` 与背包布局序列化（恢复后牌组不重建、按快照还原）。
  - 2.4：`scripts/domain/expedition_game.gd`（出发占用、撤离/死亡结算事务、`applied_settlements` 幂等已生效）、`expedition_store.gd` 的局快照/结算读写（含格式版本字段，本文按 `fmt:1` 引用）。
  - 2.6：`scripts/services/session_host.gd`／`session_client.gd`（房间、主机裁定、动作序列、快照广播）、`expedition_game.gd` 双人扩展（分享、公共区、共同撤离）。
  - 既有代码：`scripts/services/save_store.gd`（三段式写法的参照实现）、`scripts/domain/farm_game.gd` 的 `load_state`（版本链拒绝与迁移行为，79~190 行区间）、`tests/stage1_smoke.gd`（`extends SceneTree`＋`_initialize()`＋`_check()` 测试模式）。
- 设计功能范围（逐个覆盖）：D2.7-01 保存反馈与恢复入口、D2.7-02 玩家可理解的状态、D2.7-03 单人关闭与恢复、D2.7-04 客户端断线与重连、D2.7-05 主机关闭与全队恢复、D2.7-06 出发携带与结算一致性、D2.7-07 存档损坏与旧档升级、D2.7-08 故障场景表、D2.7-09 提示文案与可操作性。
- 明确不做的事（本阶段是第二大阶段收尾前的加固阶段，不新增玩法）：
  - 不做云同步、自动主机迁移、新成员替补、掉线托管 AI（设计 §1、总计划 §9.4）；主机长期不可达只保留未决状态与如实说明，不宣称解决。
  - 不做未知版本通用转换器（D2.7-07 末段），不承诺抵抗恶意改本地档（总计划 §9.2）。
  - 不重复实现 2.1-W4 的 v5→v6 个人档迁移；D2.7-07 中"当前农场档内容版本为 v5"的表述按 2.1 迁移链执行，本阶段只验证"旧档升级不强迫重开、恢复路径不破坏迁移结果"。若 2.4～2.6 交付中个人档版本继续升级，沿用其迁移函数，2.7 新增字段一律 `get(field, default)` 容错读取、不强制 bump 版本。
  - 不新增任何玩法规则或数值调整；快照间隔、去重窗口等工程初值在本文声明，试玩后按总计划 §14 流程记录变更。
  - 不做断电级（掉电瞬间缓存丢失）保证：`FileAccess.flush()` 是否等价 fsync 在 Windows 上待验证，首版故障承诺到"进程强退"一级。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/services/expedition_store.gd` | 修改 | 恢复路径加载（主档/备份/损坏分类）、动作日志追加与重放、动作去重表、未决结算清单存取、恢复日志 | +220 行 |
| `scripts/services/session_host.gd` | 修改 | 重连凭据签发与校验、掉线暂停与 120 秒等待、保存暂停并结束会话、个人放弃与全队放弃、未决结算重发 | +240 行 |
| `scripts/services/session_client.gd` | 修改 | 凭据持久化、重连流程与权威快照应用、恢复摘要、未决局视图（主机不可达）、结算确认回执 | +180 行 |
| `scripts/domain/expedition_game.gd` | 修改 | 暂停/恢复语义（保留回合、手牌、意图、布局、奖励）、单人挂起与恢复、放弃事务、恢复后不变量自检 | +140 行 |
| `scripts/domain/combat_game.gd` | 修改 | 动作去重入口：`apply_action` 携带 `action_id`，结果附 `result_digest` 供主机缓存 | +40 行 |
| `scripts/domain/farm_game.gd` | 修改 | 加载失败诊断函数（供"记录异常"详情页）；探险块新字段容错读取 | +50 行 |
| `scripts/domain/expedition_baseline.gd` | 修改 | 新增工程常量：`RECONNECT_WAIT_SECONDS=120`、`DEDUP_WINDOW=256`、`SNAPSHOT_EVERY_ACTIONS=8` | +10 行 |
| `scripts/ui/recovery_panel.gd` | 新增 | 恢复摘要、双方确认继续、记录异常诊断（可复制）、原主机不在线说明 | ~240 行 |
| `scripts/ui/save_status_layer.gd` | 新增 | "正在确认／保存未完成"常驻状态层与重试按钮（非模态，不遮操作） | ~130 行 |
| `scripts/ui/expedition_hub_panel.gd` | 修改 | 补全 D2.7-02 八态状态表、继续探险/完成结算入口、占用清单与"为什么不能出售" | +130 行 |
| `scripts/ui/battle_screen.gd`、`scripts/ui/expedition_map_panel.gd` | 修改 | 掉线暂停遮罩、等待倒计时、等待期只读锁定（可看手牌/物品/日志，不可出牌/领货/切节点）、恢复摘要展示 | +100 行 |
| `scripts/ui/farm_hud.gd` | 修改 | 挂接 `save_status_layer` 与 `recovery_panel`（沿用现有 modal 体系） | +30 行 |
| `scripts/world/farm_world.gd` | 修改 | 组合根接线：确认时点保存流程、写盘失败保留内存态与重试、恢复入口进入流程 | +80 行 |
| `tests/d27_*.gd`、`tests/capture_d27_recovery.gd` 共 8 份 | 新增 | 见 §5 | 共 ~800 行 |
| `docs/Godot_阶段2.7_恢复操作说明_v0.1.md` | 新增 | 单人及双人恢复操作说明（总计划 §10-2.7 交付项） | ~80 行 |

## 3. 数据与存档

所有新档写入一律三段式（tmp→bak→替换，写法与 `save_store.gd` 一致）；测试用自定义路径注入（`user://d27_*.json`），禁止触碰真实 `user://farm_save_v1.json` 与真实局档。

### 3.1 局档：全量快照＋动作日志（快照版本号）

- 全量快照 `user://expeditions/run_<run_id>.json`：2.4 已建立（`fmt`、`run_id`、`rules_version`、地图种子与已裁定结果、当前节点、战斗快照、占用账本、`updated_at`）。2.7 追加字段均"缺失取默认"，不升 `fmt`；`fmt` 大于当前支持值时按"未来版本"拒绝（§3.6）。`rules_version` 沿用 2.1 的 `PROTO_RULES_VERSION`。
- 动作日志 `user://expeditions/run_<run_id>.log.jsonl`（2.7 新增）：主机每接受一个动作追加一行，写后 `flush()`＋`close()`。这是 D2.7-01"玩家看见操作成功时该结果应已有可恢复记录"的落点：出牌、拾取、分享、节点选择等确认时点＝日志行落盘时点；全量快照每 `SNAPSHOT_EVERY_ACTIONS=8` 个动作或阶段切换时重写（工程初值，见待澄清 c）。
- 每行结构：`{seq, action_id, peer_id, kind, params_digest, at}`。日志不存动作完整明文参数（参数由客户端重发或测试夹具提供），重放时按 `action_id` 幂等跳过已应用序号。
- 恢复＝读快照＋重放日志尾部（`replay_run`）。域层动作在单函数内原子完成（2.2/2.6 约定），日志行只在动作完成后追加，因此重放边界天然是"整张有效牌已完成或完全未发生"的边界（D2.7-03）。

### 3.2 动作去重表（主机权威，随快照持久化）

```text
run 快照内新增：
dedup: {
  per_peer: {
    "<peer_id>": {
      last_seq: int,                      # 该玩家最大已接受序号（act-<peer>-<seq> 的 seq）
      results: { "<seq>": {digest: String, ok: bool, at: int} }   # 只保留最近 DEDUP_WINDOW=256 条
    }
  }
}
```

- 判定：`seq > last_seq` 为新动作；`seq <= last_seq` 且在 `results` 窗口内为重复，直接回缓存结果（不再次扣费/领取）；低于窗口为过期，回 `{ok:false, reason:"动作已过期，请刷新状态"}`。窗口大小为工程初值（待澄清 d）。
- `combat_game.apply_action` 的结果字典附 `action_id` 与 `result_digest`（结果字典的稳定摘要），主机以此填充缓存；同一动作重传至多一次费用（D2.7-08 出牌行、总计划 §9.2）。

### 3.3 重连凭据与主机侧花名册（总计划 §9.2/§9.4）

- 客户端本地凭据 `user://expeditions/credential_<run_id>.json`（三段式写入，2.7 新增）：

```text
{
  run_id: String, session_id: String,     # 会话 ID 沿用 2.6 房间会话标识（见待澄清 f）
  player_id: String,                      # 2.1 个人档终身稳定 ID，不是昵称
  rules_version: String, secret: String,  # secret：主机签发的 32 位十六进制随机串，仅下发一次
  issued_at: int, last_seen_seq: int      # last_seen_seq：客户端最后确认的事件序号
}
```

- 主机侧花名册（`run_<run_id>.json` 的 `roster`，2.6 建立、2.7 扩字段）：

```text
roster: [ {
  player_id: String, display_name: String,
  secret_hash: String,                    # sha256(secret + run_id)，主机不留明文
  status: "active"|"dropped"|"left_settled"|"abandoned",
  occupied_instance_ids: [int],           # 该玩家带入占用清单（主机侧账本）
  settlement_id: String,                  # 已结算离开者非空
  reconnect_expires_at: int               # 掉线等待截止（begin_drop_wait 填写）
} ]
```

- 重连校验（`authorize_reconnect`）：`run_id` 存在且未结算结束、`player_id` 在花名册且 `status` 为 `active/dropped`、`secret_hash` 匹配、`rules_version` 一致，四项全过才发完整权威快照；昵称相同但 `player_id`/`secret` 不符一律拒绝（D2.7-04"不能只输入同名昵称冒充"）。恢复要求同版本规则与原参与者匹配（或已结算离开记录），新 `player_id` 不得顶替（D2.7-05）。

### 3.4 未确认结算清单（主机侧）与个人档登记

- `user://expeditions/pending_settlement_<settlement_id>.json`（2.7 新增）：

```text
{
  settlement_id: String, run_id: String, rules_version: String,
  decided_at: int, result_version: int,      # 同一结算重发内容不变，恒为 1；变更须换新 ID
  payload_digest: String,                    # 结算载荷摘要，重发核对防半途改写
  participants: [ { player_id, applied: bool, acked_at: int, retry_count: int } ]
}
```

- 生命周期：结算裁定即写入 → 每人应用成功并回执后置 `applied` → 全员 `applied` 后删除该文件（结算本体 `settlement_<settlement_id>.json` 保留）。客户端写盘失败时主机保留此文件供重试（§9.4 第 8 行）；确认消息丢失时重发，客户端凭个人档 `applied_settlements`（2.4 已有）识别已应用、只回确认不再加物品（D2.7-06）。
- 个人档 `expedition` 块新增（`farm_save_v1.json`，容错读取、不 bump 版本）：

```text
expedition.active_run_info: {              # active_run_ref 旁的显示/恢复摘要，D2.7-01 恢复入口数据源
  run_id, role: "solo"|"host"|"client", rules_version, joined_at: int,
  last_confirmed: { floor, node, phase, hp, at },   # “最后已确认状态”
  pending_settlement_id: String            # 非空＝等待结算的局显示“完成结算”，禁止误进新局
}
```

### 3.5 备份/临时文件恢复路径与恢复日志

- 主记录损坏 → 读 `.bak`：`load_run_with_recovery` / 结算档同形；恢复时提示备份的修改时间（`FileAccess.get_modified_time()`，Windows 行为待验证）与"可能未包含的最新操作"（D2.7-07）。
- `.tmp` 残留：启动时 `sweep_tmp()` 清扫；仅当对应主档可完整解析时删除 `.tmp`，否则保留原文件并记诊断。
- 主档与备份均不可用：保留原文件不动、返回 `corrupt`，UI 进入"记录异常"态，不静默新建、不悄悄清占用（D2.7-02 末行、D2.7-07）。
- 旧备份防线：从 `.bak` 恢复个人档时，若备份的 `active_run_info.run_id` 在 `user://expeditions/` 存在已裁定结算、而备份 `applied_settlements` 未含该 ID，判"记录异常"并给出诊断，不用旧带入清单覆盖已入档结算（D2.7-07 红线）。
- 恢复日志 `user://expeditions/recovery_log.jsonl`（2.7 新增，追加型）：每行 `{at, kind, path, status, detail}`，记录每次备份恢复、tmp 清扫、损坏判定，供详情页展示与交付诊断。

## 4. 工作包拆解

W1→W9 为建议实施顺序；W4 依赖 W1/W3，W5 依赖 W3/W4，W7 依赖 W1～W6，其余可小范围并行。

### W1 局档恢复路径与动作日志（D2.7-01、D2.7-03、D2.7-07）

- 文件：`expedition_store.gd`、`expedition_baseline.gd`（常量）。
- 要点：加载分类五态（`ok/backup_used/corrupt/future_version/missing`）；快照＋日志重放；启动清扫 `.tmp`；恢复日志。签名草案：

```gdscript
# expedition_store.gd 追加（在 2.4 的 run/settlement 读写之上；全部 static，路径可注入）
static func load_run_with_recovery(run_id: String) -> Dictionary
        # -> {ok, state, status: "ok"|"backup_used"|"corrupt"|"future_version"|"missing", detail, used_backup_at}
static func append_action_log(run_id: String, entry: Dictionary) -> bool      # 追加一行，写后 flush+close
static func replay_run(run_id: String) -> Dictionary                          # 快照+日志重放 -> {ok, state, replayed}
static func load_pending_settlement(settlement_id: String) -> Dictionary
static func save_pending_settlement(record: Dictionary) -> bool
static func drop_pending_settlement(settlement_id: String, reason: String) -> bool   # 全员已确认后清理
static func list_runs() -> Array[Dictionary]          # 继续探险列表：模式/层数/节点/最后已确认摘要
static func sweep_tmp() -> int                        # 启动清扫残留下 .tmp
static func append_recovery_log(entry: Dictionary) -> void
```

- 数字归一化：JSON 重载会把整数读成浮点，重放比较前须归一化——复制 `farm_game._normalize_numbers` 为本文件私有函数（不动 `farm_game` 公共面，交付报告记技术债）。
- 验证：`tests/d27_backup_restore_smoke.gd`——主档写坏 JSON 后回退 `.bak`；双损坏返回 `corrupt` 且原文件保留；`fmt+1` 拒绝且 reason 可读；`.tmp` 清扫与恢复日志行数。

### W2 保存反馈与个人写盘失败处理（D2.7-01、D2.7-09）

- 文件：`save_status_layer.gd`（新增）、`farm_world.gd`、`farm_hud.gd`。
- 要点：确认时点保存（出发、结算、农场重要变更）失败时保留内存态、显示"保存未完成"并给重试，不显示"安全保存成功"；重试沿用同一数据与同一结算 ID；"退出并保留记录"仅关界面不丢内存态。签名草案：

```gdscript
# save_status_layer.gd（挂 farm_hud 常驻层，非模态）
func show_confirming(text: String) -> void                       # “正在确认拾取，请稍候。”
func show_unsaved(text: String, on_retry: Callable) -> void      # 重试保存；文案引用 D2.7-09
func clear() -> void

# farm_world.gd 追挂（组合根）
func save_personal_confirmed(reason: String) -> void    # SaveStore 失败 -> 内存态保留 + 状态层提示
func retry_personal_save() -> void
```

- 验证：`tests/d27_pending_settlement_smoke.gd` 的写盘失败段——用"不存在的目录路径"注入打开失败（`FileAccess.open` 返回 null，可靠）；另用 `fail_next_writes` 计数桩模拟"tmp 已写、替换失败"分支。Windows 目录只读属性不阻止建文件，禁止当作故障注入手段（在测试文件头注明）。

### W3 恢复入口与八态状态表（D2.7-01、D2.7-02）

- 文件：`expedition_hub_panel.gd`、`recovery_panel.gd`（新增）。
- 要点：补全设计 §3 八行状态表（未出发/出发确认中/探险中/暂停等待队友/原主机不在线/结算等待保存/已结束/记录异常）与允许操作；"继续探险"列出模式、原队友、层数、节点、生命、暂停原因、最后已确认状态；等待结算的局显示"完成结算"且不给新局入口；占用清单与"为什么不能出售"；记录异常页可复制诊断（路径、版本、status、恢复日志尾行），不输出全部库存。签名草案：

```gdscript
# expedition_hub_panel.gd 扩展
func bind_state_provider(provider: Callable) -> void   # 状态字典由 FarmGame/SessionClient 供给，UI 不自算
func open_resume_list() -> void                        # 数据源 ExpeditionStore.list_runs()
func open_occupied_list() -> void                      # 占用清单 + 出售阻止原因

# recovery_panel.gd（新增）
func show_resume_summary(summary: Dictionary, on_confirm: Callable) -> void  # “已恢复到第 3 回合…”+双方确认
func show_record_error(diag: Dictionary) -> void      # 记录异常：诊断复制 + 尝试备份恢复
func show_host_unreachable(view: Dictionary) -> void  # 原主机不在线：凭据/占用/如实说明限制
```

- 验证：`tests/capture_d27_recovery.gd` 截图八态中的可静态构造态（未出发、暂停等待队友、结算等待保存、记录异常、原主机不在线）进 `screenshots/`。

### W4 会话凭据与重连（D2.7-04，总计划 §9.4 第 2/3 行）

- 文件：`session_host.gd`、`session_client.gd`。
- 要点：凭据签发/持久化/校验按 §3.3；重连以权威快照恢复（快照＋摘要，不重播历史动画）；等待期只读锁定。签名草案：

```gdscript
# session_host.gd 追加
func issue_credential(player_id: String, now: int) -> Dictionary   # -> {ok, credential}
func authorize_reconnect(credential: Dictionary, now: int) -> Dictionary
        # -> {ok, reason, snapshot, resume_seq, pause, summary}
func begin_drop_wait(peer_id: int, player_id: String, now: int) -> Dictionary   # 暂停+120 秒计时+广播
func tick_drop_wait(now: int) -> Dictionary      # -> {expired, remaining, dropped}；时间由调用方注入

# session_client.gd 追加
func persist_credential(credential: Dictionary) -> bool    # credential_<run_id>.json，三段式
func load_credential(run_id: String) -> Dictionary
func request_reconnect(credential: Dictionary) -> void     # 提交凭据，等待权威快照
func apply_resume(snapshot: Dictionary, summary: Dictionary) -> Dictionary   # 摘要给 UI，只重播必要提示
```

- 验证：`tests/d27_credential_smoke.gd`——正确凭据通过；错 `secret`、他人 `player_id`、同名昵称、`rules_version` 不符各被拒且 reason 可读；凭据文件三段式损坏后可从 `.bak` 恢复。

### W5 暂停恢复语义与主机不可达未决（D2.7-02/03/05，总计划 §9.4 第 1/4/5 行）

- 文件：`expedition_game.gd`、`session_host.gd`、`session_client.gd`。
- 要点：暂停冻结回合/手牌/敌人意图/布局/奖励与已完成选择，恢复不是从节点入口重来；单人正常关闭＝保存挂起，恢复经 `replay_run`，不重生成地图/敌人/候选；主机正常"结束会话"保存并提示队友；主机崩溃客户端进未决态；等待超时执行"保存暂停并结束本次连接"，不判死亡/撤离/发物；个人放弃、全队放弃、结束会话三者结果不同（§9.4 第 6/7 行）。签名草案：

```gdscript
# expedition_game.gd 追加（域层，纯函数、时间注入）
func enter_pause(reason: String, now: int) -> Dictionary
func build_resume_context() -> Dictionary       # 回合、最近动作、节点、各人状态摘要
func resume_from_pause(context: Dictionary) -> Dictionary    # 校验不变量后解锁
func save_and_suspend(now: int) -> Dictionary                # 单人返回农场/正常关闭
func resume_solo(run_id: String, now: int) -> Dictionary     # 经 replay_run 恢复
func abandon(player_id: String, now: int) -> Dictionary      # 先列损失清单，确认后按失败结算（幂等）
func verify_restore_invariants() -> Array[String]            # 归属唯一/候选已领/占用一致自检

# session_host.gd 追加
func save_paused_and_close(reason: String, now: int) -> Dictionary   # 超时或正常结束会话
func personal_abandon(player_id: String, now: int) -> Dictionary     # 结算本人，为剩余者维持会话
func team_abandon_vote(player_id: String, now: int) -> Dictionary    # 收齐双方确认才执行

# session_client.gd 追加
func pending_run_view() -> Dictionary   # 原主机不在线：状态/占用清单/凭据摘要/允许操作（回农场处理其他资产）
```

- 主机不可达红线：客户端只能查看凭据与占用、经营未占用资产；不提供"擅自返还全部占用同时保留局内收益"的路径；`recovery_panel.show_host_unreachable` 文案如实陈述本地好友主机方案的限制（D2.7-05、设计 §11）。
- 验证：`tests/d27_pause_resume_smoke.gd`——暂停/恢复后回合数、手牌集合、敌人意图、容器布局、宝箱候选与已领标记逐项相等；恢复期间农场卖出作物后恢复局，农场金币保留且局状态不变（D2.7-08 末行）；反复点放弃只结算一次。

### W6 未决结算重发与动作去重接线（D2.7-06/08，总计划 §9.4 第 8 行）

- 文件：`combat_game.gd`、`session_host.gd`、`session_client.gd`、`farm_game.gd`（诊断函数）。
- 要点：结算确认协议按 §3.4（保留→重试→回执→清理）；动作入口按 §3.2 去重；分享归属单边成立（原主人转出/接收者持有，接收者失败按其保护状态损失，D2.7-06 末段）。签名草案：

```gdscript
# combat_game.gd 追加（结果字典附 action_id 与 result_digest）
func apply_action(action: Dictionary) -> Dictionary

# session_host.gd 追加
func resend_pending_settlement(player_id: String) -> void    # 确认丢失场景的重发
func dedup_check(dedup: Dictionary, peer_id: String, seq: int) -> Dictionary   # new/duplicate/stale
func dedup_register(dedup: Dictionary, peer_id: String, seq: int, digest: String) -> void

# session_client.gd / farm_game.gd
func ack_settlement(settlement_id: String) -> void           # 已应用则只回确认（幂等）
func describe_load_failure(saved: Dictionary) -> Dictionary   # 个人档加载失败诊断（版本/字段/建议）
```

- 验证：`tests/d27_pending_settlement_smoke.gd`——同一结算重发两次只应用一次；确认消息丢失（消息桩丢弃一次）后重发识别已应用再回确认；写盘失败→重试成功→清单清理；旧 `.bak` 个人档含未结算占用时不复活已结算物品（§3.5 红线）。

### W7 故障矩阵测试（D2.7-08，总计划 §9.4 八行表、§10-2.7 验收）

- 文件：`tests/d27_recovery_matrix.gd`（表驱动，夹具与用例数据分离）。
- 故障注入手段（全部具体可执行）：
  - 进程强退 `crash_quit`：两段 boot——第一次运行构造局、写快照/日志、写标记文件 `user://d27_boot_marker.json` 后直接 `quit(0)`，不执行任何清理与保存钩子；第二次运行读标记走恢复断言。运行两次同命令：`godot --headless --path . --script res://tests/d27_recovery_matrix.gd`。前提：工程不在 `_exit_tree`／关闭通知里挂"补保存"钩子（保存只发生在确认时点），交付时验证。
  - 网络断开 `net_close`：同进程 host＋client 双 ENet peer（127.0.0.1，沿用 d21_net_probe 方式），客户端 `peer.close()`，主机等 `peer_disconnected` 信号（延迟待验证，测试加超时兜底）。
  - 确认消息丢失 `msg_drop_once`：主机消息处理入口包一层测试桩，按消息类型丢弃恰好一次。
  - 写盘失败 `disk_fail`：不存在目录路径注入（open 必失败）＋`fail_next_writes` 计数桩（覆盖 tmp 写成功但替换失败分支）。
  - 主档损坏 `corrupt_main`／双损坏 `both_dead`：直接向主档/两档写坏 JSON。
- 总计划 §9.4 八行逐行落成用例：

| §9.4 行 | 用例 | 注入 |
| --- | --- | --- |
| 1 单人正常退出 | R1 挂起后恢复同一地图与奖励 | crash_quit 两段 boot |
| 2 客户端掉线 | R2 暂停推进、120 秒等待显示 | net_close |
| 3 客户端重连 | R3 凭据通过发全量快照；错凭据/同名昵称拒绝 | net_close＋重连 |
| 4 等待超时 | R4 保存暂停并结束会话，不判撤离/死亡/发物 | net_close＋时钟注入到期 |
| 5 主机退出/崩溃 | R5 客户端保持占用与未决态，原主机重启恢复 | 主机侧 crash_quit |
| 6 玩家主动放弃 | R6 本人按失败结算，剩余者继续，敌人意图不回退 | 流程用例 |
| 7 主机个人放弃/全队放弃 | R7 个人放弃维持会话、全队放弃需双确认、结束会话仅暂停 | 流程用例 |
| 8 结算时一端写盘失败 | R8 保留结果与未确认记录，重试同一结算不重发物品 | disk_fail＋msg_drop_once |

- 设计 §9（D2.7-08）十二行落成 M1~M12：房间准备一人退出、出发确认一端失败（按正式开始记录恢复或整体撤销，不猜测）、出牌确认丢失（去重回缓存）、公共拾取同点后断线（唯一主人，公共区不重生成）、分享提议接收前掉线（提议取消物品留原主人）、分享确认移交后丢失（归属已定不双拿）、宝箱中程序关闭（原候选与已领状态恢复不重抽）、撤离确认后掉线（保留选择等待恢复）、客户端写盘失败、主机未收到确认（重发仅回确认）、仓库满关闭结算界面（待领取区可完成本局）、暂停期卖作物（恢复不回滚）。
- 裁剪规则（写进测试文件头注释）：注入点×故障全组合过大，每注入点至少覆盖 `net_close` 与 `crash_quit`，出发扣物/撤离/死亡结算/个人写盘四类注入点另加 `disk_fail` 与 `msg_drop_once`。

### W8 回放一致性（总计划 §9.2"回放同一组有效动作应得到相同游戏状态"）

- 文件：`tests/d27_replay_smoke.gd`。
- 要点：固定种子与固定动作序列（单人一局＋双人同回合交错的序列各一）驱动到终态；再以 `replay_run` 从中途快照＋日志重放重建终态；两份终态经同一数字归一化后深度相等。随机数推进状态随快照保存（2.4 已有），重放不重抽。
- 验证：断言 `state_a == state_b`（归一化后）；并断言重复重放同一日志两次结果仍相等（幂等跳过生效）。

### W9 回归、操作说明与交付

- 全量回归：`stage1~6` 全部 smoke（个人档版本断言以上游交付为准）＋`world_picking_smoke`＋2.2~2.6 全部 `d2N_*` 测试＋本阶段 8 份新测试。
- 实机验收（真实窗口，非规则测试替代）：单人"关闭→继续探险→原位置恢复"；双人"拔网线式断开（对局中关掉客户端窗口）→120 秒等待→重开客户端凭据恢复→双方确认继续"；主机强退→原主机重开恢复；满仓撤离；死亡后再出发（对应总计划 §10-2.7 验收句）。
- 交付文档：`docs/Godot_阶段2.7_恢复操作说明_v0.1.md`（单人及双人恢复操作说明，含"原主机不可达时怎么办"如实陈述）；`docs/archive/Godot_阶段2.7_交付报告.md`（含故障矩阵执行结果、快照间隔/去重窗口实际采用值、待验证项清单）；更新总计划 §10-2.7 状态与 `docs/README.md`、根 `README.md`。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d27_credential_smoke.gd` | 凭据签发/持久化/校验、昵称冒充与版本不符拒绝 | 联机-身份错误 |
| `tests/d27_pause_resume_smoke.gd` | 暂停保留回合/手牌/意图/布局/奖励、恢复摘要、放弃幂等、暂停期农场交易不回滚 | 存档-活动局恢复 |
| `tests/d27_pending_settlement_smoke.gd` | 结算重发幂等、确认丢失、写盘失败重试、旧备份不复活已结算 | 存档-重复结算、库存-带入返还 |
| `tests/d27_backup_restore_smoke.gd` | 主档损坏回备份、双损坏保留原文件、未来版本拒绝、tmp 清扫、恢复日志 | 存档-主备损坏/旧版本拒绝 |
| `tests/d27_recovery_matrix.gd` | §9.4 八行 R1~R8＋D2.7-08 十二行 M1~M12；在出牌、拾取、分享、出发扣物、撤离、死亡结算、个人写盘七个注入点的前/后分别断线或强退 | 联机-掉线重连、主机退出、离线收结算 |
| `tests/d27_replay_smoke.gd` | 固定动作序列重放终态相等、重复重放幂等 | 联机-重复/过期动作（回放口径） |
| `tests/d27_reconnect_probe.gd` | 双 peer 端到端：close() 断开、重连、超时保存暂停 | 联机-连接/掉线 |
| `tests/capture_d27_recovery.gd` | 恢复入口、八态状态表、保存未完成、恢复摘要截图 | 实机记录 |

- 运行命令沿用根 README 形式（`--headless --path . --script res://tests/…`）；`d27_recovery_matrix.gd` 需连续运行两次（两段 boot 模拟强退），CI/验收脚本按两次执行。
- 通过口径（设计 §11）：同一操作最多影响资产一次；已确认奖励可恢复；无法判定时保留未决不造新结果；旧农场不被局恢复覆盖。

## 6. 风险与回退

- 技术风险：
  - Windows 文件替换失败（杀毒/同步盘锁文件）导致 rename 失败：三段式已留 `.bak` 兜底，`save_status_layer` 提供重试；实机验收在开启常用杀软的环境跑一次（待验证）。
  - `FileAccess.flush()` 在 Windows 是否落盘到磁盘扇区待验证：首版承诺只到进程强退级，交付报告如实标注，不断电场景不宣称已解决。
  - ENet `close()` 后对端 `peer_disconnected` 的到达延迟待验证：测试与实现均加超时兜底，不依赖即时性。
  - 快照与日志体积：dedup 表与日志行数随局长增长，`SNAPSHOT_EVERY_ACTIONS=8` 重写全量控制上限；2.9 全量回归时测 20~35 分钟局的档大小。
  - `farm_hud.gd` 已庞大：两个新 UI 一律独立文件，只挂接不内联（附录 A1-3）。
- 回退：W1/W6 是存档路径与协议扩展，单独成提交；回退 W1 后 2.4 的既有幂等与占用事务不受影响（2.7 字段全部容错读取）。W5 的域层暂停语义回退不影响 W2/W3 的 UI 反馈。
- 红线（不可越）：不能把无法恢复的情况宣称已解决——主机长期不可达、主备双损坏、未来版本局档，只保留记录、诊断与如实文案；交付报告"已知限制"必须列这三项（总计划 §10-2.7 验收原文）。
- 待设计澄清：
  - a) 120 秒等待的时钟源（挂钟注入已定，但暂停期间主机是否节流写盘未定）。
  - b) 掉线期间客户端"未确认点击取消或保持待确认"（D2.7-04 允许两种），默认取值未定；本计划先按"保持待确认、重连后明确结果"实现。
  - c) 快照间隔 `SNAPSHOT_EVERY_ACTIONS=8` 为工程初值，设计只要求"确认即有可恢复记录"，全量快照频率需设计确认。
  - d) 去重窗口 `DEDUP_WINDOW=256` 超窗重传的提示文案与是否提供"强制刷新状态"入口。
  - e) 客户端在合作局未决（主机不可达）期间能否用未占用物品开新单人局：D2.6-03 只禁"局中再开一局"，未决态未明说；本计划先禁止（`active_run_info` 非空即阻止新局），待设计确认。
  - f) `session_id` 是否在 2.6 已持久化：若未持久化，凭据以 `run_id` 为主键、`session_id` 仅作显示冗余，需与 2.6 交付对齐。
  - g) 敌人意图重选记录（D2.6-05"立即更新意图并记录"）若 2.6 快照未含该字段，恢复后意图展示需 2.7 补齐——跨阶段字段依赖，W5 开工前核对 2.6 交付。

## 7. 交付物清单

- 代码：§2 表的 2 个新 UI 脚本、1 份操作说明文档与 11 处修改（`expedition_store/session_host/session_client/expedition_game/combat_game/farm_game/expedition_baseline/farm_world/farm_hud/expedition_hub_panel/battle_screen＋expedition_map_panel`）。
- 测试：§5 的 8 份脚本。
- 文档：交付报告（archive，含故障矩阵执行记录与已知限制三红线项）、恢复操作说明、总计划 §10-2.7 状态更新、`docs/README.md` 与根 `README.md` 更新。
- 数据示例：`recovery_log.jsonl` 与 `pending_settlement_*.json` 的字段结构即本计划 §3 的声明，随交付报告附真实样例。

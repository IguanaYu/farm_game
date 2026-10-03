# 合并路线 R1 / M3：洞窟与资产闭环 代码执行计划 v0.1

编写日期：2026-10-03。状态：**代码与本地验证全部完成**（d45 78/78、d46 28/28；部署上生产待 R5/M4 一并或用户指示）。

依据：[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) R1 行；[【主要】好友联网试玩版开发规划 v0.1](../【主要】Godot_好友联网试玩版_开发规划_v0.1.md) §6 M3 行、§3.3/§3.4、W05/W06/W07 工作包。编号引用 C01～C10、S01～S04、T04～T08。

## 1. 目标与非目标

**M3 出口**（主规划 §6 原文）：

> 单人完整出发回家；两台客户端用房间码打完一局，逐件对账；至少两个房间同时运行不串局。

覆盖 C01～C10、S01～S04，工作包 W05（房间与洞窟）、W06（资产衔接与恢复的局内部分）、W07（房间/卡牌 UI 最小改造）。

**非目标（本计划不做）：**

- S05～S08 完整异常矩阵、O 组运维（守护/备份/维护）——R5/M4。M3 保证子集：重连自动回房间拿局快照（S05 核心）；服务器强杀重启后局仍在 DB、重登续玩（S07 核心）；"已返回成功的操作重启后仍在"沿 M1 收据事实。
- 农场互访（R7）、场景改造（R2～R4）：客户端沿用现有面板，不做视觉投入。
- 单机/局域网 ENet 与中继路径**原样保留**（SessionHost/SessionClient/RelayTransport 不动，回归必须零变化）。
- 不改洞窟规则数值；规则层只加"服务器可运行"所需注入点。

## 2. 总体架构

```text
Windows 客户端（联机模式）                       腾讯云 server_main（现有进程）
┌ farm_world ────────────────┐                 ┌ auth_service（账户/会话，M1）──────┐
│  online_farm_bridge        │    WSS+JSON     │ farm_service（农场 39 命令，M2）    │
│   ├ farm 命令（M2 不变）    │ ──────────────→ │ room_service（新增，M3）           │
│   └ room/run 命令 + 推送 ──│←── push.* ───── │   房间生命周期/成员/出发事务         │
│  farm_hud                  │                 │   动作裁定（ExpeditionGame 复用）    │
│   ├ room_panel（在线分支）  │                 │   结算事务（双方 farm+run+收据同事务）│
│   ├ expedition_hub（开放） │                 │ server_db schema v3                │
│   └ map/battle/loot sink ──│                 │   + rooms / runs / settlements 表   │
└ 单机/局域网模式完全不变 ────┘                 └ ExpeditionStore.backend 注入 SQLite ┘
```

关键决策（实施时冻结）：

1. **服务器是唯一裁定者（C04）**：线上房间成员=已认证账户，`peer 1=房主=战斗成员`三合一的旧假设只在单机路径保留；房间创建者只是有出发发起权限的成员，等待中离开→创建者移交给最早成员。
2. **run 字典格式不变**：客户端 UI（expedition_map_panel/battle_screen/expedition_loot_panel）继续消费同一 run 快照与动作意图；服务器裁定入口与 `session_host._execute_action` 同一动作集。信息范围（C09）沿用现状：未进入节点无 resolved 条目，不提前泄露。
3. **持久化注入而非改写**：`ExpeditionStore` 增加 static `backend: Callable` 注入点——服务器把 save_run/save_settlement 路由到"事务暂存区"（同一 SQLite 事务内落 runs/settlements 表），客户端默认文件路径零变化。`expedition_game.gd` 从 `depart/depart_coop` 中抽出纯构造函数 `compose_run`（不改行为，回归护栏）。
4. **结算即跨账户事务（S03）**：`vote_extract/leave_node(gate_clear)/finish_battle(死亡)/abandon_member` 触发结算时，双方 farm 候选副本 + 结算记录 + run 终态 + 收据**一次事务提交**。线上模式无"客机自行应用"——服务器直接应用双方（`ExpeditionGame` 实例加 `apply_guest_too` 标志，仅服务器构造时置 true；单机 coop 路径仍走 guest_handoff）。
5. **出发事务（S01）**：创建者发起 → 服务器单事务：双方候选 `loadout_check` + 牌库非空 + 双方 `is_run_occupied()==false` → 双方候选 `set_run_occupied(run_id)` → 建 runs 记录 → 更新双方 farm_state + rooms 状态。任一步失败整体回滚，两人都不开局、资产分文不动。单人（C05）走同一入口（成员=1，无投票语义）。
6. **在线状态（C03）**：成员在线=该账户有已认证活动会话。任一成员离线 → `run.action` 拒绝并广播暂停等待（不判死不判撤离）；重连（hello）自动回房拿局快照。
7. **动作去重与状态序号（S02/T04）**：`run.action` 走 M1 已有 receipts 收据（同 req_id 重放返回原结果）；run 记录带 `version` 单调递增，推送快照携带 version，客户端丢弃旧版本。
8. **协议 v3**（PROTO_VERSION 2→3；RULES 不变）：新增特性组 `expedition`、房间/局命令、`t="push"` 主动推送（push.room/push.run/push.settlement）、welcome 扩展（在房/在局时带 room+run 即重连恢复）。旧客户端连新服务器按 version_mismatch 拒绝——预期行为。

## 3. 协议扩展（v3）

### 3.1 新命令（feature `expedition`）

| op | args | 语义 | 主要错误（req_err code=op_failed, msg 细分） |
| --- | --- | --- | --- |
| `room.create` | `{}` | 建房得 6 位房码（C01） | `已有活动局`（自己 is_run_occupied） |
| `room.join` | `{code}` | 按房码加入（C01） | `房间不存在`/`房码无效`、`房间已满（双人）`、`本局已开始，不能中途加入`、`已在其他房间`、`已有活动局` |
| `room.leave` | `{}` | 离房；创建者离开→移交（C04） | — |
| `room.ready` | `{ready}` | 准备/取消（C03；修改战备撤回准备由客户端在 M2 配装命令成功后主动发 room.ready false） | — |
| `room.begin_depart` | `{}` | 创建者发起双人出发（C03/S01） | `不是房间创建者`、`还有成员未准备`、`客机尚未加入`、双方校验失败原因 |
| `run.depart_solo` | `{}` | 单人出发（C05/S01 单账户事务） | 同 depart 校验语义 |
| `run.action` | `{kind, args}` | 局内动作（动作集=单机全部+双人投票/分享，见 §5.3） | 规则层原因透传；`有成员掉线：本局暂停推进` |

### 3.2 主动推送（服务器→客户端，`t:"push"`）

| push | 载荷 | 时机 |
| --- | --- | --- |
| `push.room` | `{room}`（成员/准备/在线/phase/run_id 视图） | 任一成员加入/离开/准备/移交/开局 |
| `push.run` | `{run, version}` | 出发成功、任一 `run.action` 改变局态后，广播给在局全体 |
| `push.settlement` | `{settlement}` | 本人结算生成时（报告用；农场资产已由服务器事务应用，快照经 req_ok/farm_seq 体现） |

welcome 扩展：账户在等待房间 → 附 `room`；在活动局 → 附 `room` + `run` + `version`（重连恢复，S05 核心）。`kicked`/错误码表不变。

## 4. 服务端设计

### 4.1 `server_db.gd` schema v3（迁移：检测 <3 建表）

```sql
rooms(id INTEGER PK AUTOINCREMENT, code TEXT UNIQUE NOT NULL, state TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
  -- state: {creator_account_id:int, phase:"waiting"|"running", run_id:"",
  --         members:[{account_id:int, nick:String, ready:bool}]}
runs(run_id TEXT PRIMARY KEY, room_id INTEGER, state TEXT NOT NULL,
     version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)
settlements(settlement_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, account_id INTEGER NOT NULL,
            state TEXT NOT NULL, created_at TEXT NOT NULL)
  -- 服务器结算即应用（applied 隐含）；state 留档供对账与重查（S04）
```

账户侧沿用 farm_state 内既有约定：`expedition.occupied_by_run` / `active_run_ref` / `applied_settlements` / `next_instance_id`。收据沿用 receipts 表。

### 4.2 `room_service.gd`（新增，W05/W06）

- **房间缓存**：内存 `rooms: Dictionary[code → _Room]`；`_Room{row_id, state, run: ExpeditionGame|null, version}`。加载：启动时从 DB 恢复 phase=running 的房间与其 run（S07）。写穿：每次变更即落库（与 farm_service 同纪律）。
- **命令入口**（由 server_main 装配）：`handle(account_id, nick, peer_id, op, args, req_id) -> Dictionary(req_ok/req_err)`。
- **出发事务**：§2 决策 5 的单事务实现——`store.tx(...)` 内对每个成员账户 `SELECT farm_state` → `FarmGame.load_state` 候选 → 校验/占用 → `compose_run` 构造 run → `INSERT runs` + `UPDATE accounts×N` + `INSERT receipt` + `UPDATE rooms` → COMMIT → 内存换入。
- **动作裁定**：`run.action` → 收据查重 → 候选=当前 run 深拷贝 → `ExpeditionGame` 实例（`apply_guest_too=true`，`.game` 绑定 p1 候选 FarmGame）→ 执行动作（与 session_host._execute_action 同分发）→ 若产生结算：p2 结算单对 p2 候选 farm 应用（`ExpeditionGame.apply_settlement`）→ 同事务落 runs(version+1) + 双方 accounts + settlement 记录 + receipt → 广播 push.run + 本人 push.settlement + 双方 farm 快照（各自 req_ok 携带）。
- **成员在线**：`auth_service` 提供 `account_has_session(account_id)`；动作前全员校验（C03 暂停语义）。
- **推送路由**：`_reply` 定向 + 按 room 成员广播（复用 server_main 的 peer 发送与延迟断开纪律）。

### 4.3 `expedition_game.gd` / `expedition_store.gd` 最小注入（离线行为零变化）

1. `ExpeditionStore` 增加 `static var backend: Callable`；`save_run/save_settlement`（及新的 `delete_run` 若需要）在 backend 有效时路由。服务器 backend 写入"暂存 Dictionary"，由 room_service 在事务内搬进 SQL；回滚即丢弃。
2. `expedition_game.gd`：抽 `static func compose_run(farm, guest_profile, run_id, now, coop) -> Dictionary`（depart/depart_coop 改为调用它，行为不变）；`save()` 在 backend 有效时走 backend。
3. `apply_guest_too` 实例标志：`_settle_one_member(is_host=false)` 在该标志下也执行 `apply_settlement`（目标是服务器注入的 p2 候选 farm——通过实例字段 `guest_farm`）。
4. 单机回归护栏：以上注入点默认全部关闭，d24/d26/d27/d32 等既有测试必须零变化通过。

## 5. 客户端设计（W07 最小 UI）

### 5.1 `online_client.gd` / `online_farm_bridge.gd`

- `online_client`：处理 `t:"push"` → 转发信号 `push_received(kind, payload)`；welcome 中的 room/run 转发。请求 API 不变。
- `online_farm_bridge` 新增局命令面：`room_create()/room_join(code)/room_leave()/room_ready(v)/begin_depart()/depart_solo()` 与 `run_action(kind, args) -> Dictionary`（await req 终态，返回 result；超时/离线返回 {} 并提示）。新增信号：`room_updated(room)`、`run_snapshot(run, version)`、`settlement_arrived(settlement)`。

### 5.2 `farm_hud.gd` 在线房间分支

- 现有"联机房间将在洞窟联网（M3）后开放"封条撤除。在线模式房间面板（沿用 room_panel 布局骨架，数据源切 bridge）：显示房码/成员/准备/创建者；创建/加入（房码输入）/准备/离开/发起出发。
- 洞窟入口（expedition_hub）在线开放：单人出发 → `run.depart_solo`；"组队出发"→打开在线房间面板。战备（M2 配装命令）与房间准备解耦：配装面板在线可用（已是 M2 能力）。
- 在局时 HUD 显示"局进行中（房间 XXXX）"；断线重连后自动回局界面（bridge run_snapshot 驱动现有 map_panel 重建）。

### 5.3 局内动作接线

- `expedition_map_panel.host_action_sink` / `battle_screen.action_sink` / `expedition_loot_panel.action_sink`：在线模式注入协程 sink `func(kind,args): return await online.run_action(kind,args)`。
- **调用点全面 `await` 化**：sink 返回 Variant；同步 sink（单机）await 立即返回，行为不变；漏 await 会在结果为 GDFunctionState 时 UI 静默失败——以断言+回归兜底（风险表）。
- 动作集对齐 session_host._execute_action（vote_move/start_battle/play_card/end_turn/finish_battle/claim_reward/claim_public/pick_drop/loot_manage/take_rest/choose_event/leave_node/vote_extract/share_offer/share_accept/share_cancel/signal/abandon_member）+ 单人直通（move_to/extract/abandon）。

## 6. 核销清单（C01～C10、S01～S04 → 测试映射）

| 编号 | 内容 | 处理 | 验证 | 状态 |
| --- | --- | --- | --- | --- |
| C01 | 创建/房码加入/离开 | §3.1 room.*；错误码全覆盖 | d45 段1 | ✅ |
| C02 | 多房间隔离 | runs/rooms 按行隔离；裁定只读本房 run | d45 段5（双房并行不串局） | ✅ |
| C03 | 成员/准备/出发 | room.ready + begin_depart 服务器重查开局 | d45 段2 | ✅ |
| C04 | 创建者与服务器分离 | 创建者仅发起权限；离开移交 | d45 段1（移交断言） | ✅ |
| C05 | 单人线上探险 | run.depart_solo 同一资产入口 | d45 段4 | ✅ |
| C06 | 双端独立操作 | run.action 双方各自提交，服务器排序裁定 | d45 段3 | ✅ |
| C07 | 选路/事件/休整/搜刮/分配 | 动作集全量 + 满包拒绝不吞奖励 | d45 段3 | ✅ |
| C08 | 分享/撤离/死亡/放弃 | vote_extract/abandon_member 语义沿用 | d45 段3 | ✅ |
| C09 | 快照与信息范围 | push.run 快照 version 化；未入节点无 resolved | d45 段3（快照断言） | ✅ |
| C10 | 快捷信号 | signal 动作走同通道 | d45 段3（1 条信号断言） | ✅ |
| S01 | 带入检查与占用 | 出发跨账户单事务 | d45 段2（失败注入：B 未准备/占用中） | ✅ |
| S02 | 去重与过期保护 | receipts 收据 + run.version | d45 段6（重放同号同参/同号异参） | ✅ |
| S03 | 消耗/获得/转移/结算 | 结算跨账户事务+逐件对账 | d45 段3（带入/获得/损失/保险箱四清单核对） | ✅ |
| S04 | 未送达结果查询 | 重连即 welcome 带 run+重放收据回原结果 | d45 段2（强杀重启后动作重放） | ✅ |
| 附带 | `inv.discard`/`inv.claim_reward` 服务端命令 | M2 遗留：局内入口即 run.action 的 loot_manage/claim_reward（无需独立 farm 命令） | d45 段3 | ✅ |

T 编号映射：T04（段6）、T05（段4）、T06（段3 双客户端全链路·自动化近似）、T07（并发动作串行化·子集）、T08（段5）。真双机公网人工验收留 R6/M5（不冒充自动化）。

## 7. 测试计划

| 编号 | 脚本 | 覆盖 |
| --- | --- | --- |
| d45 | `tests/d45_online_room_run_smoke.gd`（自编排：进程内邀请码+子进程服务器，沿 d42 模式） | §6 全表：段1 房间错误码与移交；段2 出发事务+强杀重启恢复+重连回局；段3 双人全链路逐件对账（出牌→胜利→搜刮→休整/事件→撤离→双方带入/获得/损失/保险箱四清单核对）；段4 单人全链路；段5 双房并行；段6 重放去重+版本防护+资产隔离（A 动作不影响 B 农场） |
| 回归 | `tests/run_regression.sh` | 全量离线路径零变化（SessionHost/ENet/中继/单机洞窟不动） |

## 8. 实施顺序

| 步 | 内容 | 提交点 |
| --- | --- | --- |
| M3-a | 协议 v3 常量 + schema v3 + ExpeditionStore backend 注入 + compose_run 抽取 + apply_guest_too（纯重构） | 全量回归绿（零行为变化） |
| M3-b | room_service：房间生命周期 + depart_solo + 单人动作裁定（无结算路径） | d45 段1/4 绿 |
| M3-c | 双人出发事务 + 结算事务 + 推送 + welcome 重连 | d45 段2/3/5/6 绿 |
| M3-d | 客户端：bridge 局命令面 + HUD 房间分支 + hub 开放 + sink await 化 | d45 全绿 + 全量回归绿 |
| 部署 | 上 `/opt/farm-m1`（PROTO 3，旧客户端被拒属预期） | 与 R5/M4 打包一并或用户指示时（本地已验证不阻塞） |

## 9. 风险与权衡

| 风险 | 对策 |
| --- | --- |
| sink 协程化漏 await → UI 静默失败 | 调用点逐一手改+类型断言（result is Dictionary）；d33/d32/d40 回归兜底 |
| farm_hud（约 2000 行）房间 UI 与 SessionHost 耦合 | 在线走独立分支面板，不碰单机/中继路径；离线回归零 diff |
| run 快照体积超 64KB 上限 | d45 记录基线（M0 实测农场档 KB 级，run 含 resolved+battle 预期 <40KB）；超限先裁 resolved 历史明细再考虑增量 |
| 跨账户事务死锁/嵌套 tx | 全部写路径经 server_db.tx（BEGIN IMMEDIATE 串行）；room_service 内禁止嵌套调用 store.tx |
| 服务器重启后房间恢复语义 | 启动时恢复 running 房间与 run；成员离线状态按"无会话"处理，动作暂停等待（与 C03 一致） |
| 单人动作与双人动作分发出错（move_to vs vote_move） | run.action 统一按 run.coop 分发，单人直通；d45 段4 覆盖 |
| 玩家在等待房间直接关客户端 | peer 断开→成员置离线但不移出（重连可回）；房间空置由创建者移交/后续清理（M4 补全） |

## 10. 维护

- 完成后更新本表状态列与[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) §0 进度；实施偏差记录在本文件末尾（沿 M1/M2 计划体例）。


## 11. 实施记录

### 2026-10-03：M3 全部落地（本地验证）

- **M3-a**（7cbfad7）：PROTO v3 + `FEATURE_EXPEDITION`、schema v3（rooms/runs/settlements，v2→v3 加表迁移）、`ExpeditionStore.backend` 注入、`depart_check/compose_run` 抽取、`apply_guest_too/guest_farm` 服务器结算注入。离线洞窟 9 项测试零变化。
- **M3-b/c**（7c3f21f）：`room_service.gd`（C01～C04 房间生命周期、S01 跨账户出发事务、C06～C10 动作裁定+推送、S02～S04 收据去重与结算同事务、S07 启动恢复）；`server_main` 装配/welcome 扩展/断线通知；d45 78/78。
- **M3-d**（本提交）：`online_client` push 信号；`online_farm_bridge` 局命令面（room_*/depart_solo/run_action）+ 房间/局镜像（换局重置版本基线）+ 三信号；`OnlineRoomPanel`/`OnlineRunPanel`（镜像驱动、意图全走服务器，战斗 pending 由回执与新快照双路解除）；farm_hud 在线房间/出发/继续分支 + farm_world welcome 恢复直回局面板；d46 28/28。

**与计划的偏差（实测定型）：**

1. **房主个人放弃 = 终局**：规则层 `_settle_one_member` 的 is_host 分支恒置 outcome（离线路径依赖客机自行处理，服务器无法依赖）。服务器侧为未结算队友自动补一份放弃结算（`_member_unsettled` 防重），杜绝占用悬空；d45 段5 断言该语义。
2. **map/battle/loot 的 sink 未走 await 化路线**：改为 OnlineRunPanel 自带 battle_screen/loot_panel 实例 + fire-and-forget sink（返回 String 走 pending 模式），避免改动单机/中继路径的 20+ 处调用点——离线回归零 diff 风险更低。计划 §5.3 的"调用点全面 await 化"作废，以本偏差记录为准。
3. **客户端镜像版本门控跨局串号**：`_apply_run` 按 run_id 变化重置版本基线（d46 发现：旧局 v3 会挡住新局 v1）。
4. run 持久化不走 ExpeditionStore.backend 暂存（初稿设计），run 行由 room_service 在事务内显式 INSERT/UPDATE（版本统一管理）；backend 只接结算单。

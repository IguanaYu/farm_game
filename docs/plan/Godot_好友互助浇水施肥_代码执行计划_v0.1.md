# 好友互助·浇水施肥 代码执行计划 v0.1（R8 轮）

编写日期：2026-10-12。状态：**已完成**（d59 37/37；d52 复验 20/20；全量回归见文末实施记录）。

依据：[多人种田偷菜玩法循环 v0.1](../design/Godot_多人种田偷菜_玩法循环_v0.1.md) §4 好友帮助（用户选定的规则块）；
[R7 拜访系统执行计划](Godot_合并路线_R7_拜访系统_代码执行计划_v0.1.md)（开放参观是本轮的入口底座）。
用户拍板：**偷菜留下一轮**、**首版不做主人实时推送**（重连/快照可见即可）。

## 1. 设计定稿（本轮参数）

| 项 | 规则 | 落点 |
| --- | --- | --- |
| 好友帮助加成 | 每位好友对同一块地同一轮一次 `基准分 +5%`，多人可叠加 | `plot["helpers"]`（收获时清空）；`PlantDefs.HELPER_BONUS_PCT_PER_FRIEND` |
| 帮助者收益 | 每次有效帮助 `+5` 通用种地经验（不加植物经验/金币） | `PlantDefs.HELPER_EXP_PER_ACTION`；写帮助者自己的档 |
| 水壶取最高档 | 已浇时段：帮助者档位更高→**原位升级** can_level；否则跳过。保持每时段≤1条记录（计分按条求和，不能追加） | `water_help()` |
| 2 级水壶扩散 | 用**帮助者自己**的 can_level，在主人地块上扩散 3 块 | `water_help()` |
| 帮施肥 | 扣**帮助者**库存；主人地块肥料效果/门槛与自家一致（2h 持续、未到期不可覆盖）；`plot.fertilizer` 增记 helper/helper_nick | `fertilize_help()` + `spend_fertilizer_for_help()` |
| 帮浇水记录 | 经历留帮助者昵称（type="help"）；`watered_segments` 条目带 helper/helper_nick 并原样流入收获批次 | `_append_round_event` / harvest |
| 授权/限额 | 无需授权（玩法稿 §4 原口径）；**不设每日限额**（浇水受每时段一次封顶、施肥自耗、加成每人每轮一次） | — |

存档兼容：`helpers`、watered_segments 的 helper 键、fertilizer 的 helper 键均为**纯增量**，`.get(..., 默认)` 读取，
不 bump SAVE_VERSION（沿三栏改版"纯增量不动存档版本"先例）。

## 2. 协议（PROTO 5）

- `PROTO_VERSION 4→5`（新命令族升级先例）；新特性 `FEATURE_VISIT_HELP := "visit_help"` 进默认特性表。
- 新命令（路由进 VisitService，前缀 `visit.`）：
  - `visit.water {owner_id, plot_id}`
  - `visit.fertilize {owner_id, plot_id, kind}`
- 错误：`visit_closed`（关访）/`account_missing`（owner=自己/不存在/禁用）/`plot_missing`/规则失败 op_failed。
- 应答：result 带生效明细与更新后的主人地块数组（`plots`）；`snapshot` = **帮助者自己的农场快照**（客户端桥接自动回灌，刷新肥料数/经验）。

## 3. 服务端（唯一新架构点：跨账户写事务）

照 `room_service._build_depart/_arbitrate_action` 双账户先例，`visit_service.gd` 新增：

1. 收据记在**帮助者**名下（`(account_id, req_id)` 主键 + args_digest，同 `run.action` 口径）；重放只回放结果不重复执行。
2. 单个 `store.tx`：SELECT 双方现值 → 各建候选 FarmGame → 帮助者侧先扣库存（施肥）→ 主人侧 `water_help/fertilize_help`（时钟用 `farm_service.now()`，与 farm.* 一致含 time-shift）→ 帮助者 `grant_help_exp` → 双行 `UPDATE accounts`（farm_seq 各 +1）→ INSERT 收据。规则失败=空事务提交回 op_failed。
3. **提交后 `farm_service.evict(helper_id)` 与 `evict(owner_id)`**——主人在线时其写穿缓存副本已过期，必须失效重载（d59 缓存红线断言）。server_main 给 VisitService 注入 `farm_service`。
4. 红线口径修订：访客**可以**浇水/施肥；仍**不可**收获/消费/买卖主人资产（visit_service 头注释同步改）。

## 4. 客户端

- bridge：`visit_water/visit_fertilize` 封装（应答自带帮助者快照，request 内部回灌）。
- farm_world：`_on_visit_crop_input` 升级为分发器——**生长中**地块开 `visit_care` 弹窗，空地/未开垦/**成熟**仍只读（保住 d52 的"地块仅绑定只读查看"断言：绑定 callable 不变）。互助生效后 `_finish_visit_help`：用 result.plots 修补 `visiting.farm` → `_refresh_visit_yard()`（**原地重建地块热点**，不动路由——router 对"当前地点 unregister"有断言）→ `hud.refresh`（自家计数）→ 弹窗换新数据。
- farm_hud：新弹窗 `visit_care`（compact 布局）：主人作物状态+浇水时段 chips（读主人快照）、帮浇水按钮、施肥按钮按**访客自己的** `game.state["fertilizers"]` 计数渲染；信号 `visit_water_requested/visit_fertilize_requested`。`_breakdown_card` 加"好友帮助 ×N"行。

## 5. 测试（d59）

`tests/d59_visit_help_smoke.gd`（d52 模板：种子档+子进程服务器+WsClient+headless 场景，5 段 4 次服务器重启）：

1. 协议：时段生效/扩散升级（预浇 can1 被原位升级且不追加重复条目）/帮助者经验入应答快照/幂等 duplicate/同级再浇无效果。
2. 施肥：扣帮助者库存、**主人库存零触碰**（红线）、未到期不可覆盖。
3. 缓存红线：主人先发命令焐热写穿缓存（失败命令也走 load_runtime）→ 好友帮助 → 主人下一条**成功**命令（farm.plant）的应答快照必须看到帮助结果——直接验证 evict 链路。注意：失败命令应答不带快照，核验要用成功命令。
4. 门槛与隔离：owner=自己/999→account_missing、坏地块→plot_missing、成熟作物→浇水无效。
5. 客户端：进院子→生长中地块开弹窗（直接调 `_on_visit_crop_input` 传合成点击事件；需先手工填 `online.visiting`，因为真实链路里它由地址簿的 `visit.snapshot` 填）→ 施肥按钮显示访客自己库存 → 点浇水走通真实 bridge 链路（轮询 visiting.farm 生效）。
   客户端段结束后 `world.queue_free()`——防桥接自动重连对后续段的新会话造成踢号干扰（D-01 教训）。
6. 结算：`--dev --dev-time-shift 1300` 跨成熟 → 主人收获 → breakdown 含 helper_count/helper_bonus（+5%×200=10）与 can2 浇水 +20%、经历含好友昵称、收获重置清空 helpers。
7. 开关：`--visits-closed`→visit_closed；`--features`（含 visit 缺 visit_help）→ 地址簿正常但帮助命令 feature_disabled。

坑速查（本轮新增）：
- 种子档里连续 `plant_seed` 不能复用同一 seed_id（播种即从仓库移除），每次取 `state["seeds"][0]`。
- 路由器对"当前地点 unregister"断言**Leave a location before unregistering**——原地刷新只能重建子节点，不能拆地点。
- `Button.pressed.emit()` 可在 headless 里驱动完整信号链（弹窗按钮→世界层→bridge→服务器→快照回灌）。
- 断言失败（assert）不中断 GDScript 脚本执行，但 `SCRIPT ERROR` 会被回归判失败，必须清零。

## 6. 不做项（已声明）

偷菜（下一轮独立做：10%/30% 上限、偷菜记录、主人查看界面）、主人实时推送（push 通道已具备，按需加）、
每日限额、好友关系表（试玩池全员邻里）、给好友空地预施肥（空地保持只读）、卖菜授权（玩法稿"当天授权来卖菜"独立功能）。

## 7. 上线备注

生产需重部署服务器（PROTO 5；旧客户端按 version_mismatch 既定路径拒绝）；M5 真人双机公网验收顺延到本功能完成后一起做。

## 8. 实施记录

### 2026-10-12：R8 全部落地

- 域层：`water_help/fertilize_help/grant_help_exp/spend_fertilizer_for_help` + `_segment_entry/_record_helper/_help_result_plots`；`_score_breakdown` 增 helper_bonus（收获合计行）；收获重置与 `_empty_plot` 增 `helpers`；`_breakdown_card` 加好友行。
- 协议/服务端：PROTO 5 + FEATURE_VISIT_HELP；`visit.water/visit.fertilize` 双账户事务（收据在帮助者、双行 UPDATE、提交后双 evict）；server_main 注入 `visits.farm_service` 并把 visit_help 加进默认特性表。
- 客户端：bridge 两封装；`visit_care` 弹窗（时段 chips/帮浇水/访客自家肥料按钮）；`_on_visit_crop_input` 分发器（生长中→照料，其余只读）；`_add_visit_plot` 抽取 + `_refresh_visit_yard` 原地重建（旧节点先改名再释放防同名冲突）；enter_visit/hint 文案改互助口径。
- d59（37 项）全绿；d52 复验 20/20（分发器设计保住其断言）；全量回归 69/69（68→69）。

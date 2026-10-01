# Godot_阶段2.1_交付报告

交付日期：2026-10-01。子阶段：**2.1 规则基线与工程基础**（第二大阶段第一子阶段）。状态：已完成，验收通过。

依据：[2.1 代码执行计划](../plan/Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)、[2.1 详细设计](../design/Godot_阶段2.1_规则基线与工程基础_详细设计_v0.1.md)、[整体开发计划 §10-2.1](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)。

## 1. 交付物清单

**新增代码（7 个文件）：**

| 文件 | 责任 | 行数 |
| --- | --- | --- |
| `scripts/domain/expedition_baseline.gd` | 规则基线常量、格子几何（占格/旋转/重叠/越界判定） | ~110 |
| `scripts/domain/item_defs.gd` | 物品定义表：基础套装 3 件＋演示物品 3 件 | ~90 |
| `scripts/domain/card_defs.gd` | 12 个牌效果模板（2.2 设计 §5 全表，本阶段只注册定义） | ~95 |
| `scripts/domain/inventory_game.gd` | 物品实例、归属唯一、基础装备发放/补领、占用、牌组预览、准备检查 | ~250 |
| `scripts/services/expedition_store.gd` | 局档/结算档存取边界、四类 ID 生成（局/动作/结算/玩家） | ~100 |
| `scripts/ui/expedition_hub_panel.gd` | 洞窟入口概览面板（D2.1-01"无活动局/未开放"两态） | ~150 |
| `scripts/ui/loadout_panel.gd` | 战备首页 v0：三容器、详情、牌组预览、检查、演示物品 | ~430 |

**修改代码（3 个文件）：**`farm_game.gd`（SAVE_VERSION 5→6、v5→v6 迁移、`expedition` 块校验）、`farm_world.gd`（洞窟入口/战备箱/制作台三个可点击占位，位于东南侧草坪；保存信号接线）、`farm_hud.gd`（两个面板挂接＋`expedition_save_requested` 信号）。

**测试（7 份）：**`d21_defs_smoke`（42 项断言）、`d21_inventory_smoke`（47 项）、`d21_migration_smoke`（16 项）、`d21_net_probe`（5 项）、`capture_d21_hub`、`capture_d21_loadout`（产出 5 张截图进 `screenshots/`）。旧回归 stage1~6＋world_picking 全部保持通过（版本断言按计划更新为 6，行为口径不变）。

## 2. 规则基线表实际采用值

与 2.1 设计 §2 完全一致，无修改：生命 40/40、能量 3、抽 5 手牌上限 10、胸挂 3×4／背包 4×4／保险箱 1×2、容器牌第 1/2/3 回合加入、普通物品占 N 格给 N 张牌、保险箱白名单（小型材料与种子可放，`safe_allowed` 字段）、基础套装=旧短刀(1×2, 切击×2)＋木盾(2×2, 架盾×2/掩护/稳住)＋行囊工具(1×2, 调整呼吸/观察)＝8 格 8 牌。规则版本锚点 `PROTO_RULES_VERSION = "d2-baseline-v0.1"` 已入 `expedition_baseline.gd`。

## 3. 存档迁移记录（总计划 §9.5）

- `FarmGame.SAVE_VERSION` 5→6；`_migrate_v5_to_v6` 只追加默认 `expedition` 块，农场字段零改动。
- `expedition` 块结构：`player_id`（"p-" 前缀稳定标识）、`next_instance_id`（从 1000 递增）、`inventory`（warehouse/loadout 三容器/occupied_by_run）、`loadouts`（配装预设位，本阶段恒空）、`active_run_ref`、`applied_settlements`（2.4 起用）。
- 迁移测试覆盖：金币、词条种子（真实词条 ID `water_guarantee`/`color_guarantee`）、十块地、育种机进度、市场锁定逐项保留；v7 拒绝；损坏 `expedition` 块拒绝（不静默重建）。
- 旧测试断言更新：stage1/2/3/4/5/6 中 `version == 5` 共 8 处改为 6（其中 2 处在计划外发现：stage2:80、stage4:277）。

## 4. 初步网络技术试验记录（W8）

- 单进程内 `ENetMultiplayerPeer` host(31921)＋client 经 `127.0.0.1` 连接：**3 秒内建立、消息双向往返（ping/pong）、主动断开检测均通过**（`tests/d21_net_probe.gd`，5 项断言）。
- 结论：Godot 4.6 ENet 在本机 Windows 下可用于 2.6 的主机权威原型；**互联网好友可达性（NAT/端口/防火墙）仍未验证**，按总计划 §14 在 2.6 开始前确定实际连接方式，不把"本机能连"当作"互联网可玩"。

## 5. 演示物品与正式物品的边界（D2.1-03）

- 演示物品定义带 `demo: true` 且 `def_id` 一律 `demo_` 前缀；实例层 `demo` 标志由 `add_instance(..., demo=true)` 显式传入。
- 演示实例只在内存：战备面板"载入演示物品"注入；**关闭面板时由组合根统一 `strip_demo_instances()` 后再保存**，测试断言剔除后无残留且真实物品不受影响。
- 实施中修复了一个真实缺陷：初版 `inject_demo_items` 误把 `"demo"` 传给 `source` 参数而未置 `demo` 标志，导致演示物不会被剔除——由 `d21_inventory_smoke` 的"读回后牌组预览一致"断言暴露并修复，测试同步加了"残留检查"覆盖。

## 6. 验收对照（总计划 §10-2.1）

| 验收项 | 结果 | 证据 |
| --- | --- | --- |
| 真实 v5 旧档加载后原有资产一致 | 通过 | `d21_migration_smoke` 16 项 |
| 新增系统可以打开退出 | 通过 | `capture_d21_hub/loadout` 5 张截图；关闭回农场视角 |
| 同一物品不能同时属于两个位置 | 通过 | `owner_of` 断言（移动后归属切换、无重复） |
| 原农场八项回归保持通过 | 通过 | stage1~6＋world_picking 全 PASS |
| 互联网连接可行性开始验证 | 部分完成 | 本机 ENet 试验通过；互联网侧待 2.6 前 |

设计 §10 通过条件自查：旧档资产未重置 ✓；基础装备能补领且不可套利（不可出售/分享，每种一件，含活动局占用中的也计入拥有）✓；三个容器、物品牌、失败保护可在战备界面查看并解释 ✓（截图中"首回合牌 8 张（基础装备不计可售价值）"）。

## 7. 实施偏差与工程约定补录

1. **截图脚本需带窗口运行**：headless 模式下 viewport 无渲染纹理（`get_image()` 返回 null）且 `RenderingServer.frame_post_draw` 永不触发。`capture_*` 脚本一律窗口运行，此约定补入 2.1 计划。
2. **迁移测试的词条 ID**：计划未指定造档用词条；实施采用 `BreedingDefs.EFFECTS` 真实 ID。
3. **W6 的保存时机**：战备面板不在每次操作后保存，而是关闭时统一"剔除演示→按 dirty 保存"，避免演示预览期间反复写盘；崩溃丢失风险可接受（2.4 起改事务制）。
4. **视觉核验教训**：截图文字转录出现误读（把"首回合 8 张"读进挪盾后的图）；以数值断言＋像素差分（11353 px 差异）为权威依据。

## 8. 遗留与移交

- 计划 §6 的风险项均未发生（存档升级单独成提交可回退；演示物泄漏已由测试覆盖；占位模型未遮挡原拾取区）。
- 2.1 计划登记的"待设计澄清"无新增；后续阶段的澄清项见各自计划 §6。
- 交棒给 2.2：`card_defs.gd` 的 12 个模板已含 2.2 设计 §5 全部数值；`InventoryGame.deck_preview()` 为牌组构建入口；战斗状态需按 2.2 计划做成可序列化字典。

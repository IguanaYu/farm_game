# 配装预设 UI：方案与执行计划 v0.1

编写日期：2026-10-02。状态：**已实施，待实机验收**（实施记录见 §8）。

导航：本功能为第二大阶段交付遗留项（README 未验证项"配装预设 UI"），不新立设计文档，规则口径复用 2.1/2.3 设计（D2.1-02/05/06、D2.3-02/03）。

## 1. 目标与非目标

**目标**：在战备箱（LoadoutPanel）保存、命名、应用、删除多套战备配装方案。一套预设记录三个容器（胸挂/背包/保险箱）内全部真实物品的容器、格位与旋转；应用时先清空三容器再逐件精确复原，让玩家下洞前一键换装。

**非目标**：不做跨存档共享、不做与好友交换预设、不做预设内物品自动购买/制作（缺料只报告）、不做预设截图缩略图。预设不进入农场主存档结构（见 §3）。

## 2. 现状与接入点

| 现有基础 | 位置 | 复用方式 |
| --- | --- | --- |
| 精确放置／自动找位／原位旋转／清空配置 | `scripts/domain/inventory_game.gd`（place_at :152、move_to_loadout :110、move_to_warehouse :134、rotate_instance :180、clear_loadout :269） | 应用预设直接组合这些命令式 API |
| 占用保护（活动局拒绝改动） | `inventory_game.gd` is_run_occupied :336 | 应用预设复用同一拒绝口径 |
| 演示实例不入档 | `inventory_game.gd` demo 标记 + strip_demo_instances :439 | 快照预设时跳过 demo 实例 |
| 原子写文件模式 | `scripts/services/save_store.gd`（tmp→bak→rename，失败回滚） | PresetStore 照抄同一模式 |
| 面板结构与 dirty 保存链 | `scripts/ui/loadout_panel.gd`（open/_flash/dirty）；`farm_hud.gd` _on_loadout_close :1685 | 预设行加在面板内；应用成功置 dirty，走既有关闭保存 |
| 无头 UI 测试模式 | `tests/d32_coop_play_ui_smoke.gd` root.add_child(panel) + panel.open(game) | d39 沿用 |

## 3. 预设数据模型与文件

- 领域纯逻辑放 `scripts/domain/loadout_presets.gd`（class_name LoadoutPresets，全静态）：不读时钟、不碰文件、不碰 UI。
- 文件存取放 `scripts/services/preset_store.gd`（class_name PresetStore，全静态）：`user://loadout_presets_v1.json`，tmp→bak→rename 原子写，主文件损坏回落 .bak。
- 文件结构（fmt=1）：

```json
{
  "fmt": 1,
  "presets": [
    {"name": "下洞标配", "created_at": 1759000000, "items": [
      {"instance_id": 1001, "def_id": "xxx", "container": "chest", "cell": [0, 0], "rotated": false}
    ]}
  ]
}
```

- **不进农场主档的原因**：主档结构版本 v7 动一次要同步 6 个旧 stage 测试断言，且预设属于"便捷记录"而非资产——分离文件零迁移成本。代价：新游戏重开后旧预设引用的实例编号失效，应用时按"缺失"逐件报告（不整单失败）。线上版落地时预设应并入服务器个人档（规划 W03 命令清单），此文件届时退役。
- 数量上限 12 套、名称最长 12 字符（防误粘贴长文本撑爆 UI）。

## 4. 领域逻辑

- `capture(inventory)`：按 chest→pack→safe 顺序快照容器内全部非 demo 实例，记 instance_id/def_id/container/cell/rotated。def_id 只用于缺失时的名字显示，不参与定位。
- `apply(inventory, preset)`：
  1. `is_run_occupied()` → 整单拒绝（与所有库存命令同口径）；
  2. `clear_loadout()` 先把三容器全部放回仓库（含演示物品，只是回仓库不丢弃）；
  3. 逐条 `place_at` 精确复原；放不下（容器扩容前史/布局冲突）降级 `move_to_loadout` 自动找位，计"自动换位"；
  4. 实例不存在（已被消耗/出售/新档失效）或只剩演示 → 计"缺失"；存在但目标容器放不下且自动找位也失败（如保险箱白名单变化）→ 留在仓库计"放不下"。
  - 返回 `{ok, reason, applied, relocated, missing[], blocked[]}`；部分失败不回滚整单（物品都在仓库，状态一致）。
- `report(result, name)`：拼一句可读反馈（"已应用「X」：5 件就位，1 件自动换位，缺失：旧木剑×1。"）。

## 5. 面板 UI（loadout_panel.gd）

- 在容器区与底部操作行之间加一行：`配装预设` 标签 ＋ 预设下拉框（OptionButton，显示"名称（N 件）"）＋ 名称输入框（LineEdit，留空自动"预设 N"）＋ `存为预设`（同名覆盖）＋ `应用预设` ＋ `删除`。
- 打开面板时 PresetStore.load_presets() 载入；存/删立即写预设文件（不等关闭）；应用成功置 `dirty = true`，农场档仍走既有关闭保存链。
- 公开 `preset_names() / save_preset(raw_name) / apply_selected() / delete_selected()` 供无头测试直接调用。

## 6. 测试计划

- 新增 `tests/d39_loadout_preset_smoke.gd`（SceneTree＋退出码口径，PASS 标记 `D39_LOADOUT_PRESET_PASS`）：
  - 领域：快照排除演示实例、字段与实际布局一致；清空→应用后容器/格位/旋转逐件复原；缺失单件降级报告；占用中整单拒绝；
  - 存取：保存→读取往返一致（int/float 归一化口径）；主文件写坏后回落 .bak；
  - UI：面板实例化→存为预设→列表出现→清空容器→应用所选→布局复原→删除→列表清空；
  - 隔离：测试前后备份/恢复 `user://loadout_presets_v1.json(.bak/.tmp)`。
- 全量回归 `tests/run_regression.ps1` 全过（含既有 44 项），证据拷贝 `docs/testing/loadout_preset_d39/`。

## 7. 风险与回退

- 预设引用实例编号：任何导致编号失效的场景（新档、卖件、消耗）都只降级为"缺失"报告，不会破坏库存——放置全部走 InventoryGame 现成合法性检查。
- 与自动整理/拖放并存：预设只在"应用"瞬间改布局，与其他操作无并发路径（单机单面板）。
- 回退：删除两个新文件＋还原 loadout_panel.gd 即可完整回退；无存档结构改动。

## 8. 实施记录（2026-10-02）

- 新增 `scripts/domain/loadout_presets.gd`、`scripts/services/preset_store.gd`；修改 `scripts/ui/loadout_panel.gd`（预设行＋公开方法 `preset_names/save_preset/apply_selected/delete_selected`）；新增 `tests/d39_loadout_preset_smoke.gd`。
- 实施偏差：①`apply()` 不在单条预设上校验 fmt——版本口径由 PresetStore 在文件层把关，领域层只要求 items 为数组（原 §4 的 fmt 校验下移）；②`_read_dictionary` 用 `JSON.new().parse()` 而非 `JSON.parse_string()`——损坏文件回落 .bak 是设计内路径，不能往日志打 ERROR 行（回归收集器按未预期 ERROR 计数）。
- d39 单测 26 项断言全过（退出码 0）；全量回归 45 项全过、`REGRESSION_ALL_PASS`（bash 版收集器；从 git bash 调 powershell 版会因 GBK/UTF-8 编码误读脚本报解析错，用 `bash tests/run_regression.sh` 即可）。
- 证据：`docs/testing/loadout_preset_d39/`（regression_output.txt、d39_loadout_preset_smoke.txt、results.json、verification_meta.json）。
- 实机验收待用户：预设行视觉布局（1180 宽面板内一行五控件）、拖放与预设并用、真档上保存/应用。

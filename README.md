# 小小农场（单人首版）

点击式种田游戏：在立体农场里直接点击地块与建筑操作，作物按现实时间生长（关游戏也继续）。完整循环：**选种 → 播种与照料 → 成熟收获 → 育种或复制 → 比价出售 → 购买、扩地与升级 → 下一轮**。

## 启动

- 玩家：直接运行 `build/小小农场.exe`（Windows 导出包），或用 Godot 4.6.1 打开本目录按 F5。
- 开发者（PowerShell）：

```powershell
$godot = 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe'
& $godot --headless --editor --path 'E:\gpt\godot\farm' --quit   # 先导入
& $godot --path 'E:\gpt\godot\farm'                              # 运行
```

## 玩法速览

- **地块**：空地点击→选种播种（能看到词条与品质）；生长中点击→照料（分时段浇水、施肥）；成熟点击→收获（面板逐项解释分数构成）。金色浮动标记=可收获。
- **照料**：浇水免费，每个有效时段只记一次（白菜 1 段，2 小时植物 2 段）；肥料每次覆盖 2 小时、可跨多轮，未到期不能换。水壶 2 级一次浇 3 块地、每时段 +20%。
- **育种**：收获的 2~3 粒新种子各自独立判定词条（继承→升档→新词条）；在仓库种子区比较、回收（5 金币/粒）、设为育种机模板。育种机定期复制模板（离线也计时，满了暂停）。
- **集市**：每天北京时间零点刷新三位客人与两种植物的收购公式；可锁客人（商店 2 级）、锁公式类型（商店 3 级）。卖菜可拆批比价，或默认 1.2 倍兜底。金克拉批次倍率 +0.2。
- **升级**：商店（折扣 5%/级）、仓库扩容、水壶 2 级、育种机、扩地到十块。具体价格在游戏内商店查看。
- 新档有五步引导，可跳过。

## 已知限制

1. 单人本地存档（`user://farm_save_v1.json`，内容版本 v5），无云存档；设备时钟可被修改，会影响离线成熟、每日客人与育种机结算。
2. 胡萝卜为暂名（正式名未定）；六位客人为造型草案。
3. 调试按键 F9（全部立即成熟）只在开发构建可用，导出包无效。

## 验证（开发者）

```powershell
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage1_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/world_picking_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage2_rules_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage3_breeding_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage3_warehouse_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage4_market_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage5_ux_smoke.gd'
& $godot --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage6_regression_smoke.gd'
```

规则数值集中在 `scripts/domain/plant_defs.gd`（种植）、`breeding_defs.gd`（育种/仓库/育种机）、`market_defs.gd`（客人/经济）。素材原件在 `art/lowpoly/`（`.gdignore` 隔离），运行时副本与盘点见 `assets/stage1_manifest.json`。各阶段交付文档在 `docs/`。

# 小小农场 · Godot 阶段 2

点击式种田游戏：在立体农场场景中直接点击六块土地操作；作物按现实时间生长（离线也生长）。阶段 2 在阶段 1 的白菜闭环上加入了第二种 2 小时植物、经验等级、浇水、四种肥料、每轮计分与经历，以及一键收获。规则总览见 [`docs/Godot_单人首版_分阶段开发与验收_交接版.md`](docs/Godot_单人首版_分阶段开发与验收_交接版.md)。

## 启动

用 Godot 4.6.1 打开本目录的 `project.godot`，按 F6/F5 运行主场景；或在 PowerShell 中运行：

```powershell
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --path 'E:\gpt\godot\farm'
```

## 操作

- **空地**：点击打开选种面板，选择要播种的种子（白菜 20 分钟；解锁后可种 2 小时植物）。
- **生长中的地块**：点击打开照料面板，可按有效时段浇水（免费，每时段只记一次），或施用肥料（每次覆盖 2 小时，未到期不能更换）。
- **成熟的地块**：点击收获，弹出收获面板展示分数构成（基准、等级、波动、浇水、肥料、遭遇）与这一轮的经历；右下角"一键收获"可一次收完全部成熟地块。
- **商店**（右下角或点击商店建筑）：买两种种子、四种肥料，以及花 1,500 金币把商店升到 2 级（第二种种子需要种地 2 级 + 商店 2 级解锁）。
- **仓库**（右下角或点击仓库建筑）：查看每批作物的每作物分数并按默认 1.2 倍出售。
- 顶部计数显示金币、种子、作物与种地等级经验。开发调试构建可按 F9 让当前作物立即成熟，不会改动系统时钟。

存档保存在 Godot 的 `user://farm_save_v1.json`（内容版本 v2，阶段 1 旧档自动迁移），关闭游戏后按现实时间继续生长。

## 验证

```powershell
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --editor --path 'E:\gpt\godot\farm' --quit
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage1_smoke.gd'
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/world_picking_smoke.gd'
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage2_rules_smoke.gd'
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage2_worked_example.gd'
```

`art/lowpoly/` 是可编辑素材库，由 `.gdignore` 阻止 Godot 扫描源文件；游戏只导入 `assets/stage1_manifest.json` 中列出的运行时模型与面板图片（阶段 2 新增胡萝卜地块模型与肥料、水壶面板图标）。

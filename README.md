# 小小农场 · Godot 阶段 1

这是点击式种田游戏的第一个可玩版本：在立体农场场景中直接点击六块土地，种植 20 分钟白菜；作物离线生长，每地收获五个作物与 2～3 粒新种子。商店、仓库、默认出售和本地存档已接入。后续规则见 [`docs/Godot_单人首版_开发计划_v0.1.md`](docs/Godot_单人首版_开发计划_v0.1.md)。

## 启动

用 Godot 4.6.1 打开本目录的 `project.godot`，按 F6/F5 运行主场景；或在 PowerShell 中运行：

```powershell
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --path 'E:\gpt\godot\farm'
```

点击农场场景中的空地播种，20 分钟后点击成熟地块收获；点击商店和仓库建筑，或使用画面右下角的入口购买种子、出售作物。开发调试构建可按 F9 让当前作物立即成熟，不会改动系统时钟。存档保存在 Godot 的 `user://farm_save_v1.json`，关闭游戏后按现实时间继续成熟。

## 验证

```powershell
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --editor --path 'E:\gpt\godot\farm' --quit
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/stage1_smoke.gd'
& 'E:\其他\chorme_download\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe' --headless --path 'E:\gpt\godot\farm' --script 'res://tests/world_picking_smoke.gd'
```

`art/lowpoly/` 是可编辑素材库，由 `.gdignore` 阻止 Godot 扫描 Blender 源文件；游戏只导入 `assets/stage1_manifest.json` 中列出的运行时模型与面板图片。

# 游戏运行时图片

`models/` 中的 GLB 和 `sprites/` 中的面板图片分别复制自 `art/lowpoly/farm_asset_pack/glb/` 与 `art/lowpoly/farm_asset_pack/sprites/`。原素材包保留 Blender、GLB 与 PNG 全量源文件；Godot 通过 `.gdignore` 不扫描原素材库。阶段 1 的地块、设施和装饰使用立体模型，图片只作面板图标。

素材盘点完成后，按同名资产 ID 检查尺寸、原点、点击范围、透明度和方向，需要替换时以原素材包为源更新这里的运行时副本。

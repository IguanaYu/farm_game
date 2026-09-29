# farm 低多边形美术资源包

这是按照 `farm/docs` 中单人首版范围制作的第一套可编辑美术资源。模型采用低多边形卡通风格；每个资产都有独立的 GLB 模型和 512×512 透明 PNG 图片。

## 内容

| 类别 | 数量 | 内容 |
| --- | ---: | --- |
| 地块状态 | 10 | 空地、浇水、施肥、播种，以及白菜和胡萝卜的幼苗／生长／成熟阶段 |
| 作物与种子 | 4 | 白菜、胡萝卜和各自的种子袋 |
| 道具 | 7 | 四种肥料、浇水壶、收获箱、金币 |
| 设施 | 3 | 购买商店、仓库、育种机 |
| 客人 | 6 | 六位不同造型的客人概念模型 |
| 装饰 | 3 | 树、围栏、花 |

合计 **33 个独立资产**。完整清单及文件名见 `manifest.json`。

## 文件

- `farm_asset_library.blend`：Blender 可编辑资源库，按资产 ID 分 Collection。所有资产在场景里排成展示板。
- `glb/<资产 ID>.glb`：独立 3D 模型，导出时均位于自身原点附近；地块约 2.3 Blender 单位宽。
- `sprites/<资产 ID>.png`：独立透明图片，适合在 Godot 的二维点击界面试摆。
- `farm_asset_catalog.png`：整套总览。
- `plots_and_crops.png`、`items_and_buildings.png`、`guests_and_decorations.png`：分类预览。

## 在 farm 中试用

当前 `farm` 目录还没有 `project.godot`。建立 Godot 工程后，可以把需要的 PNG 放进 `res://art/farm/` 并作为 `TextureRect` 或 `Sprite2D` 的纹理使用。需要 3D 视角时可导入对应 GLB。点击区域、作物状态、金币和客人报价仍须由游戏逻辑驱动；这些文件只提供美术表现。

## 暂定内容

- 玩法文档尚未命名两小时作物，资源包暂用**胡萝卜**展示。确认后可替换模型与文件名映射。
- 六位客人的正式身份、名字和形象尚未确定，`guest_01` 至 `guest_06` 是造型草案。
- 同一地块的五棵植物对应文档中的每块地每轮产出五个作物，但地块画面并不负责计数和随机结算。
- 玩具、小家园、好友偷菜和联网内容属于文档的后续版本，未纳入本包。

## 重新生成

制作脚本在 `source/`。先运行 `build_farm_asset_pack.py`，再运行 `render_farm_sprites.py`；分类预览分别用 `render_farm_sheets.py -- plots_and_crops`、`-- items_and_buildings` 和 `-- guests_and_decorations` 生成。脚本按所在目录写回这个资源包，移动目录后无需改路径。制作和渲染使用 Blender 5.2.2 LTS。

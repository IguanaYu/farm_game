# farm 美术导出清单与后续约定

这里的“参考图”指从 Blender 资源渲染出的预览图，不是建模时使用的外部参考照片。当前共 **6 张总览／场景预览图**；另有 **33 张单件透明 PNG** 可直接试用于二维界面。

## 总览与场景预览（6 张）

| 文件 | 用途 |
| --- | --- |
| `farm_asset_pack/farm_asset_catalog.png` | 33 个独立资产的整套总览 |
| `farm_asset_pack/plots_and_crops.png` | 地块状态与两种作物的分类预览 |
| `farm_asset_pack/items_and_buildings.png` | 种子、肥料、工具、金币及设施的分类预览 |
| `farm_asset_pack/guests_and_decorations.png` | 六位客人与环境装饰的分类预览 |
| `showcase/farm_lowpoly_preview.png` | 六块地农场展示场景的斜俯视图 |
| `showcase/farm_lowpoly_top.png` | 同一展示场景的正俯视图，用于核对布局 |

## 单件透明图（33 张）

以下图片均在 `farm_asset_pack/sprites/`。同名模型在 `farm_asset_pack/glb/`，只需把 `.png` 改成 `.glb`。

| 类别 | 图片文件名 |
| --- | --- |
| 地块（10） | `plot_empty.png`、`plot_wet.png`、`plot_fertilized.png`、`plot_seeded.png`、`plot_cabbage_sprout.png`、`plot_cabbage_growing.png`、`plot_cabbage_mature.png`、`plot_carrot_sprout.png`、`plot_carrot_growing.png`、`plot_carrot_mature.png` |
| 作物与种子（4） | `crop_cabbage.png`、`crop_carrot.png`、`seed_cabbage.png`、`seed_carrot.png` |
| 肥料（4） | `fertilizer_basic.png`、`fertilizer_mutation.png`、`fertilizer_preserve.png`、`fertilizer_golden.png` |
| 其他道具（3） | `tool_watering_can.png`、`item_harvest_crate.png`、`item_coin.png` |
| 设施（3） | `facility_shop.png`、`facility_warehouse.png`、`facility_breeder.png` |
| 客人（6） | `guest_01.png`、`guest_02.png`、`guest_03.png`、`guest_04.png`、`guest_05.png`、`guest_06.png` |
| 装饰（3） | `deco_tree.png`、`deco_fence.png`、`deco_flower.png` |

## 以后新增或修改资产时沿用

1. **一个资产一个稳定 ID。**采用小写英文与下划线，例如 `crop_...`、`plot_...`、`facility_...`。同一资产的 `.glb` 和 `.png` 使用同名 ID；改造型时尽量不改 ID，以免游戏资源引用失效。
2. **每个资产交付四样内容：**可编辑 Blender 源文件、独立 `.glb`、透明背景 `.png`、在分类预览图中的展示。资源清单写入 `manifest.json`。
3. **二维图片规格：**当前使用 512×512 PNG、RGBA 透明背景、统一斜俯视镜头。新增图片沿用这个角度与规格；较大设施仍居中并留有边距。
4. **3D 模型规格：**静态低多边形卡通风格；模型在自身原点附近，接地中心为原点，当前按约 1 Blender 单位≈1 米制作。预览底座、标签、相机、灯光不进入独立 GLB。
5. **预览图规格：**每次更新整套时重导整套总览和受影响的分类图；更新农场布局时同时导斜俯视图和正俯视图。总览用于快速浏览，透明 PNG 用于实际界面试摆。
6. **交付前核对：**文件数量与 `manifest.json` 一致；GLB 能打开；PNG 角落透明；预览图中的模型未被裁切；场景与源文件可在 Blender 中打开。

当前胡萝卜是未命名两小时作物的临时造型，六位客人的身份形象也是草案。确定正式设计时可替换画面，并保留稳定文件 ID 或同步更新 `manifest.json` 和游戏引用。

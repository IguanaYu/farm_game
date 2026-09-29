"""Render transparent 2D sprites and readable category sheets from the asset library."""

import bpy
import json
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(ROOT,'manifest.json'),encoding='utf8') as fh:
    items=json.load(fh)['assets']

bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'farm_asset_library.blend'))
scene=bpy.context.scene
camera=scene.camera
display=bpy.data.collections['CATALOG pedestals and labels']
assets=[bpy.data.collections[item['id']] for item in items]
sprites=os.path.join(ROOT,'sprites')
os.makedirs(sprites,exist_ok=True)

scene.render.resolution_x=512
scene.render.resolution_y=512
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=True
scene.cycles.samples=16
display.hide_render=True

scale_by_category={'plot':3.75,'crop':2.65,'item':2.45,
                   'building':4.55,'guest':2.85,'decoration':3.0}

for slot,item in enumerate(items):
    for c in assets:
        c.hide_render=(c.name!=item['id'])
    x=(slot%6)*3.35-8.375
    y=-(slot//6)*3.42+8.55
    target=Vector((x,y,.63 if item['category'] not in ('building','decoration') else 1.0))
    camera.location=target+Vector((3.8,-4.9,5.3))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=scale_by_category[item['category']]
    scene.render.filepath=os.path.join(sprites,item['id']+'.png')
    bpy.ops.render.render(write_still=True)
    print('SPRITE',item['id'],flush=True)

for c in assets: c.hide_render=False
display.hide_render=False
print('DONE',len(items),flush=True)

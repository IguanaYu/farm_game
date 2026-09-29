"""Fast rerender of the three category overviews from the saved .blend library."""
import bpy
import json
import os
import sys
from mathutils import Vector

root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(root,'farm_asset_library.blend'))
scene=bpy.context.scene
cam=scene.camera
scene.render.resolution_x=2400
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.cycles.samples=16
scene.render.image_settings.file_format='PNG'
cam.data.ortho_scale=23.5
options={'plots_and_crops':(6.84,range(0,12)),
         'items_and_buildings':(0,range(12,24)),
         'guests_and_decorations':(-6.84,range(24,33))}
name=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'plots_and_crops'
y,slots=options[name]
with open(os.path.join(root,'manifest.json'),encoding='utf8') as fh:
    ids=[item['id'] for item in json.load(fh)['assets']]
selected={ids[i] for i in slots}
for aid in ids:
    bpy.data.collections[aid].hide_render=aid not in selected
for obj in bpy.data.collections['CATALOG pedestals and labels'].objects:
    if obj.name!='catalog ground':
        obj.hide_render=not any(obj.name.startswith(aid+' ') for aid in selected)
target=Vector((0,y,.5))
cam.location=target+Vector((0,-8,22))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=os.path.join(root,name+'.png')
bpy.ops.render.render(write_still=True)
print('SHEET',name,flush=True)

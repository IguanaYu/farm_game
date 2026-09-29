"""Editable low-poly asset library for the farm game's single-player scope.

Run inside Blender 5.2+: blender --background --python build_farm_asset_pack.py
All assets are exported at their own origin before being arranged in the catalog.
"""

import bpy
import json
import math
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT = os.path.join(ROOT, 'glb')
os.makedirs(EXPORT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0


def material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = .82
    return m


M = {key: material(key, rgb) for key, rgb in {
    'grass':(.37,.64,.30), 'grass_light':(.52,.75,.38),
    'grass_dark':(.25,.49,.27), 'soil':(.42,.25,.16),
    'soil_ridge':(.57,.35,.22), 'wet_soil':(.27,.19,.17),
    'wood':(.67,.40,.22), 'wood_light':(.84,.58,.32),
    'wood_dark':(.42,.25,.16), 'leaf':(.28,.60,.31),
    'leaf_light':(.58,.79,.37), 'leaf_dark':(.18,.43,.26),
    'carrot':(.94,.39,.11), 'carrot_light':(1.0,.58,.20),
    'water':(.25,.66,.76), 'water_light':(.50,.83,.87),
    'red':(.90,.35,.29), 'orange':(.98,.59,.25),
    'yellow':(.97,.76,.26), 'gold':(.90,.62,.13),
    'cream':(.95,.84,.64), 'stone':(.53,.63,.63),
    'purple':(.56,.39,.72), 'pink':(.94,.65,.67),
    'teal':(.30,.68,.58), 'blue':(.31,.53,.76),
    'skin_1':(.91,.70,.51), 'skin_2':(.69,.43,.29),
    'skin_3':(.98,.81,.64), 'black':(.16,.18,.20),
    'white':(.94,.92,.82), 'backdrop':(.70,.80,.75),
}.items()}


active = None


def link(obj):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    active.objects.link(obj)
    return obj


def bev(obj, width=.04):
    mod = obj.modifiers.new('rounded edges', 'BEVEL')
    mod.width = width
    mod.segments = 1
    obj.modifiers.new('weighted normals', 'WEIGHTED_NORMAL')


def cube(name, xyz, dims, key, edge=.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz)
    obj = link(bpy.context.object)
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(M[key])
    if edge:
        bev(obj, edge)
    return obj


def cyl(name, xyz, radius, depth, key, vertices=8, top=None):
    if top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                            depth=depth, location=xyz)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
                                        radius2=top, depth=depth, location=xyz)
    obj = link(bpy.context.object)
    obj.name = name
    obj.data.materials.append(M[key])
    return obj


def ico(name, xyz, radius, key, scale=(1,1,1), detail=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail,radius=radius,location=xyz)
    obj = link(bpy.context.object)
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(M[key])
    return obj


def beam(name, start, end, width, key):
    a,b = Vector(start),Vector(end)
    obj = cube(name,(a+b)/2,(width,width,(b-a).length),key,.015)
    obj.rotation_euler = (b-a).to_track_quat('Z','Y').to_euler()
    return obj


def torus(name, xyz, major, minor, key, rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=12,minor_segments=5,
                                    location=xyz,rotation=rotation,
                                    major_radius=major,minor_radius=minor)
    obj = link(bpy.context.object)
    obj.name=name
    obj.data.materials.append(M[key])
    return obj


def cabbage(x=0,y=0,z=0,size=1):
    ico('pale cabbage heart',(x,y,z+.30*size),.24*size,'leaf_light',(1,1,.85),2)
    for i in range(5):
        a=math.tau*i/5
        obj=ico('faceted outer leaf',(x+math.cos(a)*.19*size,
                                      y+math.sin(a)*.19*size,z+.20*size),
                .20*size,'leaf' if i%2 else 'grass_dark',(1,.64,.42))
        obj.rotation_euler[2]=a


def carrot(x=0,y=0,z=0,size=1):
    cyl('orange carrot root',(x,y,z+.19*size),.07*size,.36*size,
        'carrot',7,.18*size)
    for i in range(3):
        a=math.tau*i/3
        beam('three pointed greens',(x,y,z+.37*size),
             (x+math.cos(a)*.19*size,y+math.sin(a)*.19*size,z+.64*size),
             .055*size,'leaf_dark')


def seedling(x=0,y=0,z=0,size=1):
    beam('new stem',(x,y,z),(x,y,z+.24*size),.045*size,'leaf_dark')
    for side in (-1,1):
        ico('first leaf',(x+side*.11*size,y,z+.22*size),.11*size,
            'leaf',(1,.60,.30))


def plot_base(wet=False):
    cube('square soil bed',(0,0,.14),(2.18,2.18,.28),
         'wet_soil' if wet else 'soil',.07)
    for x in (-.58,0,.58):
        cube('raised planting row',(x,0,.30),(.46,1.74,.08),
             'wet_soil' if wet else 'soil_ridge',.035)
    for x in (-1.10,1.10):
        cube('long timber edge',(x,0,.32),(.13,2.32,.20),'wood_light',.03)
    for y in (-1.10,1.10):
        cube('short timber edge',(0,y,.32),(2.30,.13,.20),'wood_light',.03)


POSITIONS=[(-.58,-.49),(0,-.49),(.58,-.49),(-.29,.47),(.29,.47)]


def plot(stage, plant='cabbage'):
    plot_base(stage=='wet')
    if stage=='fertilized':
        for x,y in POSITIONS:
            ico('fertilizer granules',(x,y,.36),.045,'gold')
    if stage in ('empty','wet','fertilized'):
        return
    for x,y in POSITIONS:
        if stage=='seed':
            ico('seed in row',(x,y,.35),.065,'cream',(1,.70,.65))
        elif stage=='sprout':
            seedling(x,y,.34,.65)
        elif stage=='growing':
            if plant=='cabbage': cabbage(x,y,.31,.53)
            else: carrot(x,y,.31,.57)
        elif stage=='mature':
            if plant=='cabbage': cabbage(x,y,.29,.84)
            else: carrot(x,y,.30,.86)


def seed_bag(kind):
    key='leaf' if kind=='cabbage' else 'orange'
    cube('folded cloth seed bag',(0,0,.38),(.56,.28,.68),'cream',.07)
    cube('bag folded top',(0,0,.72),(.49,.31,.14),'wood_light',.025)
    cube('colored seed label',(0,-.151,.42),(.37,.025,.28),key,.015)
    if kind=='cabbage': ico('cabbage on label',(0,-.17,.42),.10,'leaf_light')
    else: cyl('carrot on label',(0,-.17,.43),.055,.17,'carrot',7,.025)


def fertilizer(kind):
    colors={'basic':'leaf','mutation':'purple','preserve':'teal','golden':'gold'}
    c=colors[kind]
    cube('fertilizer pouch',(0,0,.42),(.59,.31,.70),c,.08)
    cube('folded pouch rim',(0,0,.76),(.57,.34,.10),'cream',.02)
    ico('bright emblem',(0,-.171,.46),.16,'cream',(1,.28,1))
    if kind=='mutation':
        for a in (0,math.tau/3,2*math.tau/3):
            ico('spark',(math.cos(a)*.12,-.20,.46+math.sin(a)*.12),.045,'yellow')
    elif kind=='preserve':
        ico('protected seed',(0,-.23,.46),.075,'leaf')
    elif kind=='golden':
        ico('gold pellet',(0,-.23,.46),.078,'gold')
    else:
        seedling(0,-.20,.37,.43)


def watering_can():
    cyl('can body',(0,0,.36),.33,.58,'water',10,.38)
    cyl('open cream rim',(0,0,.66),.36,.07,'cream',10)
    beam('angled spout',(.31,0,.43),(.79,0,.69),.11,'water')
    cyl('shower rose',(.83,0,.72),.15,.05,'water',8)
    for i in range(6):
        a0=math.pi*.14+i*math.pi*.75/6
        a1=math.pi*.14+(i+1)*math.pi*.75/6
        p0=(-.25+math.cos(a0)*.45,0,.49+math.sin(a0)*.47)
        p1=(-.25+math.cos(a1)*.45,0,.49+math.sin(a1)*.47)
        beam('rounded can handle',p0,p1,.075,'water')


def harvest_crate():
    cube('wood harvest crate',(0,0,.35),(1.00,.72,.56),'wood',.05)
    cube('dark inside',(0,0,.635),(.85,.57,.03),'wood_dark',.01)
    for x,y in [(-.23,-.13),(.2,-.11),(0,.15)]:
        cabbage(x,y,.60,.60)


def coin():
    cyl('coin', (0,0,.09),.39,.16,'gold',12)
    cyl('raised coin face',(0,0,.18),.29,.03,'yellow',12)
    ico('coin seed emblem',(0,0,.21),.14,'gold',(1,.7,.22))


def tree():
    cyl('faceted trunk',(0,0,.70),.15,1.25,'wood_dark',7,.22)
    ico('left foliage',(-.24,0,1.43),.56,'grass_dark')
    ico('right foliage',(.27,.05,1.58),.59,'leaf')
    ico('top foliage',(0,0,1.99),.63,'grass_light')


def fence():
    for x in (-.95,0,.95):
        cube('fence post',(x,0,.50),(.13,.13,1.0),'wood_light',.015)
    for z in (.42,.74):
        cube('horizontal rail',(0,0,z),(2.07,.08,.11),'wood',.015)


def flower():
    beam('stem',(0,0,0),(0,0,.55),.055,'leaf_dark')
    for i in range(5):
        a=i*math.tau/5
        ico('five simple petals',(.14*math.cos(a),.14*math.sin(a),.57),.12,
            'pink' if i%2 else 'cream',(1,1,.45))
    ico('yellow center',(0,0,.59),.09,'yellow')


def shop():
    cube('little storefront',(0,0,.77),(2.0,1.45,1.55),'cream',.09)
    cube('door',(-.41,-.76,.52),(.53,.08,.99),'wood_dark',.025)
    cube('display window',(.45,-.77,1.00),(.73,.07,.63),'water_light',.025)
    cube('roof slab',(0,0,1.60),(2.34,1.76,.18),'red',.06)
    for x in (-.72,-.24,.24,.72):
        cube('striped awning',(x,-.92,1.31),(.48,.56,.17),
             'red' if x in (-.72,.24) else 'cream',.02)
    cube('counter',(0,-1.05,.67),(1.82,.38,.26),'wood_light',.04)
    for x in (-.53,.48):
        ico('produce on counter',(x,-1.09,.83),.18,'leaf_light' if x<0 else 'carrot')


def warehouse():
    cube('storage building',(0,0,.82),(2.06,1.62,1.64),'wood_light',.07)
    cube('front double doors',(0,-.85,.66),(1.15,.10,1.23),'wood_dark',.035)
    cube('left door stripe',(-.25,-.92,.66),(.06,.04,1.1),'wood',.01)
    cube('right door stripe',(.25,-.92,.66),(.06,.04,1.1),'wood',.01)
    cube('roof',(0,0,1.71),(2.35,1.90,.23),'blue',.06)
    for x in (-.65,.65):
        cube('crate stack',(x,-1.01,.32),(.47,.43,.52),'wood',.025)


def breeder():
    cube('breeder base',(0,0,.22),(1.52,1.02,.44),'wood_dark',.06)
    for x in (-.53,.53):
        cyl('support pillar',(x,0,.93),.075,1.12,'wood_light',8)
    cyl('glass chamber',(0,0,.98),.39,.91,'water_light',10)
    cyl('chamber upper ring',(0,0,1.46),.42,.10,'gold',10)
    cyl('chamber lower ring',(0,0,.51),.42,.10,'gold',10)
    ico('glowing duplicate seed',(0,0,1.02),.22,'leaf_light',(1,.62,.72))
    for x in (-.28,.28):
        ico('control lamp',(x,-.48,.31),.07,'yellow' if x<0 else 'teal')


def guest(index):
    # Six friendly visual concepts; identities and names remain open in the design doc.
    shirts=['red','blue','purple','teal','orange','grass_dark']
    skins=['skin_1','skin_2','skin_3','skin_1','skin_3','skin_2']
    cube('short overalls',(0,0,.56),(.64,.39,.69),shirts[index],.14)
    cyl('round neck',(0,0,.98),.12,.19,skins[index],9)
    ico('head',(0,0,1.27),.35,skins[index],(1,.85,1.0),2)
    for x in (-.12,.12):
        ico('eyes',(x,-.302,1.30),.035,'black',(1,.44,1))
    for s in (-1,1):
        beam('arm',(s*.25,0,.79),(s*.44,0,.47),.16,shirts[index])
        ico('hand',(s*.44,0,.43),.10,skins[index])
        cube('boot',(s*.17,-.03,.12),(.24,.37,.24),'wood_dark',.04)
    if index==0:
        cyl('farmer straw hat',(0,0,1.63),.49,.08,'cream',12)
        cyl('farmer hat crown',(0,0,1.76),.28,.22,'cream',12)
        cube('hat ribbon',(0,-.29,1.68),(.36,.03,.06),'red',.01)
    elif index==1:
        cube('merchant cap',(0,0,1.60),(.62,.48,.18),'blue',.07)
        cube('cap visor',(0,-.35,1.54),(.52,.27,.07),'blue',.02)
    elif index==2:
        cyl('tall chef cap',(0,0,1.76),.27,.38,'white',9)
        cyl('chef cap brim',(0,0,1.57),.34,.07,'white',10)
    elif index==3:
        ico('gardener hair',(0,.04,1.55),.32,'wood_dark',(1,1,.52))
        ico('hair bun',(.25,.15,1.58),.15,'wood_dark')
    elif index==4:
        cyl('traveller hat brim',(0,0,1.59),.45,.07,'wood_dark',10)
        cyl('traveller hat crown',(0,0,1.73),.26,.22,'wood_dark',10)
    else:
        ico('curly hair',(0,0,1.55),.33,'black',(1,.92,.50))
        for x in (-.23,.02,.21):
            ico('small curls',(x,-.15,1.65),.13,'black')


catalog=[]
display=None


def register(asset_id, label, category, make, slot):
    global active
    active=bpy.data.collections.new(asset_id)
    bpy.context.scene.collection.children.link(active)
    make()
    objects=list(active.objects)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    target=os.path.join(EXPORT,asset_id+'.glb')
    bpy.ops.export_scene.gltf(filepath=target,export_format='GLB',use_selection=True)
    dx=(slot%6)*3.35-8.375
    dy=-(slot//6)*3.42+8.55
    for obj in objects:
        obj.location.x += dx
        obj.location.y += dy
    active=display
    cube(asset_id+' plinth',(dx,dy,-.22),(2.90,2.84,.37),'grass',.13)
    # Label is present only in the catalog scene, never inside individual GLB files.
    curve=bpy.data.curves.new(asset_id+' label','FONT')
    curve.body=label
    curve.size=.34
    curve.align_x='CENTER'
    text=bpy.data.objects.new(asset_id+' label',curve)
    display.objects.link(text)
    text.location=(dx,dy-1.26,.02)
    text.data.materials.append(M['wood_dark'])
    catalog.append({'id':asset_id,'label':label,'category':category,
                    'file':'glb/'+asset_id+'.glb'})


display=bpy.data.collections.new('CATALOG pedestals and labels')
bpy.context.scene.collection.children.link(display)

ASSETS=[
 ('plot_empty','EMPTY PLOT','plot',lambda:plot('empty')),
 ('plot_wet','WATERED PLOT','plot',lambda:plot('wet')),
 ('plot_fertilized','FERTILIZED PLOT','plot',lambda:plot('fertilized')),
 ('plot_seeded','SOWN PLOT','plot',lambda:plot('seed')),
 ('plot_cabbage_sprout','CABBAGE SPROUT','plot',lambda:plot('sprout')),
 ('plot_cabbage_growing','CABBAGE GROWING','plot',lambda:plot('growing','cabbage')),
 ('plot_cabbage_mature','CABBAGE RIPE','plot',lambda:plot('mature','cabbage')),
 ('plot_carrot_sprout','CARROT SPROUT','plot',lambda:plot('sprout')),
 ('plot_carrot_growing','CARROT GROWING','plot',lambda:plot('growing','carrot')),
 ('plot_carrot_mature','CARROT RIPE','plot',lambda:plot('mature','carrot')),
 ('crop_cabbage','CABBAGE','crop',lambda:cabbage(size=1.8)),
 ('crop_carrot','CARROT','crop',lambda:carrot(size=1.7)),
 ('seed_cabbage','CABBAGE SEED','item',lambda:seed_bag('cabbage')),
 ('seed_carrot','CARROT SEED','item',lambda:seed_bag('carrot')),
 ('fertilizer_basic','BASIC FEED','item',lambda:fertilizer('basic')),
 ('fertilizer_mutation','MUTATION FEED','item',lambda:fertilizer('mutation')),
 ('fertilizer_preserve','PRESERVE FEED','item',lambda:fertilizer('preserve')),
 ('fertilizer_golden','GOLDEN FEED','item',lambda:fertilizer('golden')),
 ('tool_watering_can','WATERING CAN','item',watering_can),
 ('item_harvest_crate','HARVEST CRATE','item',harvest_crate),
 ('item_coin','GOLD COIN','item',coin),
 ('facility_shop','SEED SHOP','building',shop),
 ('facility_warehouse','WAREHOUSE','building',warehouse),
 ('facility_breeder','SEED BREEDER','building',breeder),
 ('guest_01','GUEST 01','guest',lambda:guest(0)),
 ('guest_02','GUEST 02','guest',lambda:guest(1)),
 ('guest_03','GUEST 03','guest',lambda:guest(2)),
 ('guest_04','GUEST 04','guest',lambda:guest(3)),
 ('guest_05','GUEST 05','guest',lambda:guest(4)),
 ('guest_06','GUEST 06','guest',lambda:guest(5)),
 ('deco_tree','TREE','decoration',tree),
 ('deco_fence','FENCE','decoration',fence),
 ('deco_flower','FLOWER','decoration',flower),
]

for slot,(asset_id,label,category,make) in enumerate(ASSETS):
    register(asset_id,label,category,make,slot)
    print('EXPORTED',asset_id,flush=True)

# A fifth-row empty slot helps the large buildings retain some breathing room.
active=display
cube('catalog ground',(0,0,-.51),(20.7,21.0,.18),'backdrop',.10)

scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.render.resolution_x=2500
scene.render.resolution_y=2600
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.view_settings.exposure=-.35
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.76,.85,.82,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65

lights=bpy.data.collections.new('LIGHTS AND CAMERA')
scene.collection.children.link(lights)

def area(name,where,power,size):
    d=bpy.data.lights.new(name,'AREA')
    o=bpy.data.objects.new(name,d)
    lights.objects.link(o)
    o.location=where
    o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()
    d.energy=power
    d.shape='DISK'
    d.size=size

area('big softbox',(-11,-15,24),3200,14)
area('rim softbox',(13,9,19),1500,12)
cam_data=bpy.data.cameras.new('catalog camera')
cam=bpy.data.objects.new('catalog camera',cam_data)
lights.objects.link(cam)
cam.location=(16,-21,30)
cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'
cam_data.ortho_scale=29.5
scene.camera=cam

scene.render.filepath=os.path.join(ROOT,'farm_asset_catalog.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'farm_asset_library.blend'))
bpy.ops.render.render(write_still=True)

with open(os.path.join(ROOT,'manifest.json'),'w',encoding='utf8') as fh:
    json.dump({'project':'farm','asset_count':len(catalog),
               'notes':['Carrot is a visual placeholder for the unnamed 2-hour crop.',
                        'Six guest appearances are provisional concepts.',
                        'All GLB models use a ground-level origin and meter-scale Blender units.'],
               'assets':catalog},fh,ensure_ascii=False,indent=2)

print('DONE',len(catalog),flush=True)

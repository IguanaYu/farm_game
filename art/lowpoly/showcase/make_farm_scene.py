"""Build a small editable low-poly farm diorama for the farm game concept."""

import bpy
import math
import os
from mathutils import Vector


OUT = os.path.dirname(os.path.abspath(__file__))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != 'Collection':
        bpy.data.collections.remove(collection)


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def move_to(obj, group):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    group.objects.link(obj)
    return obj


GROUND = collection('01 Ground and paths')
PLOTS = collection('02 Six interactive plots')
CROPS = collection('03 Crops by growth stage')
PROPS = collection('04 Farm props')
FENCE = collection('05 Fence and trees')
LIGHTS = collection('06 Camera and lights')


def mat(name, color, roughness=0.84):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = roughness
    return m


grass = mat('warm meadow green', (0.41, 0.67, 0.33))
grass_top = mat('soft fresh grass', (0.52, 0.76, 0.38))
grass_dark = mat('grass accent', (0.29, 0.55, 0.29))
soil = mat('rich cocoa soil', (0.46, 0.28, 0.18))
soil_light = mat('soft tilled ridges', (0.57, 0.37, 0.23))
path_mat = mat('sandy footpath', (0.89, 0.76, 0.54))
wood = mat('honey wood', (0.72, 0.46, 0.25))
wood_light = mat('light cut wood', (0.88, 0.64, 0.35))
wood_dark = mat('dark wood ends', (0.47, 0.28, 0.17))
leaf = mat('cabbage outer leaves', (0.31, 0.65, 0.35))
leaf_light = mat('cabbage inner leaves', (0.60, 0.82, 0.43))
leaf_deep = mat('deep garden leaves', (0.20, 0.49, 0.31))
carrot = mat('carrot orange', (0.95, 0.47, 0.19))
yellow = mat('sunny yellow', (0.99, 0.76, 0.30))
blue = mat('watering can blue', (0.28, 0.65, 0.76))
cream = mat('warm cream', (0.96, 0.87, 0.69))
red = mat('market coral', (0.90, 0.38, 0.30))
stone = mat('blue-grey stone', (0.55, 0.67, 0.64))
trunk = mat('tree bark', (0.54, 0.35, 0.23))


def bevel(obj, amount=0.07, segments=1):
    mod = obj.modifiers.new('soft bevel', 'BEVEL')
    mod.width = amount
    mod.segments = segments
    obj.modifiers.new('weighted normals', 'WEIGHTED_NORMAL')


def cube(name, loc, scale, material, group, bevel_size=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = move_to(bpy.context.object, group)
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel_size:
        bevel(obj, bevel_size)
    return obj


def ico(name, loc, radius, material, group, subdivisions=1, scale=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=loc)
    obj = move_to(bpy.context.object, group)
    obj.name = name
    if scale:
        obj.scale = scale
    obj.data.materials.append(material)
    return obj


def cylinder(name, loc, radius, depth, material, group, vertices=8, radius2=None):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius2,
                                        depth=depth, location=loc)
    obj = move_to(bpy.context.object, group)
    obj.name = name
    obj.data.materials.append(material)
    return obj


def beam(name, start, end, width, material, group):
    mid = (Vector(start) + Vector(end)) / 2
    obj = cube(name, mid, (width, width, (Vector(end)-Vector(start)).length), material, group, 0.025)
    obj.rotation_euler = (Vector(end)-Vector(start)).to_track_quat('Z', 'Y').to_euler()
    return obj


# The low beveled base reads as a toy-like, self-contained game world.
cube('floating earth base', (0, 0, -0.35), (13.8, 10.6, 0.8), soil, GROUND, 0.36)
cube('meadow surface', (0, 0, 0.09), (13.3, 10.1, 0.25), grass_top, GROUND, 0.32)
cube('center footpath', (0, -0.03, 0.24), (9.8, 1.02, 0.045), path_mat, GROUND, 0.12)
cube('entry path', (0, -3.15, 0.24), (1.07, 4.8, 0.045), path_mat, GROUND, 0.12)


def cabbage(cx, cy, size=1):
    z = 0.57
    ico('cabbage head', (cx, cy, z + 0.17*size), 0.27*size, leaf_light, CROPS, 2,
        (1.0, 1.0, 0.83))
    for j in range(5):
        a = j * math.tau / 5 + 0.25
        dx, dy = math.cos(a), math.sin(a)
        obj = ico('broad cabbage leaf', (cx + dx*0.21*size, cy + dy*0.21*size, z+0.10*size),
                  0.23*size, leaf if j % 2 else grass_dark, CROPS, 1,
                  (1.06, 0.65, 0.38))
        obj.rotation_euler[2] = a


def carrot_crop(cx, cy, growth=1):
    z = 0.51
    cylinder('orange carrot above soil', (cx, cy, z+0.12*growth),
             0.105*growth, 0.25*growth, carrot, CROPS, 7, 0.16*growth)
    for j in range(3):
        a = j * math.tau/3
        beam('carrot foliage', (cx,cy,z+0.26*growth),
             (cx+math.cos(a)*0.20*growth,cy+math.sin(a)*0.20*growth,z+0.48*growth),
             0.063*growth, leaf_deep, CROPS)


def sprout(cx, cy, growth=1):
    z = 0.51
    beam('seedling stem', (cx,cy,z), (cx,cy,z+0.28*growth), 0.06, leaf_deep, CROPS)
    for side in (-1,1):
        obj = ico('seedling leaf', (cx+side*0.12*growth,cy,z+0.25*growth),
                  0.14*growth, leaf, CROPS, 1, (1,0.63,0.28))
        obj.rotation_euler[1] = side*0.28


plot_centers = [(-3.7, 2.0), (0, 2.0), (3.7, 2.0),
                (-3.7, -1.98), (0, -1.98), (3.7, -1.98)]
states = ['mature cabbages', 'young greens', 'new seedlings',
          'mature carrots', 'sprouting carrots', 'prepared soil']
for idx, ((px,py), state) in enumerate(zip(plot_centers,states), 1):
    cube(f'Plot {idx:02d} | {state} | soil', (px,py,0.34), (3.1,2.62,0.22), soil, PLOTS, 0.12)
    for offset in (-0.80,0,0.80):
        cube(f'Plot {idx:02d} | planting row', (px+offset,py,0.47),
             (0.62,2.12,0.075), soil_light, PLOTS, 0.07)
    # Four separate boards make each plot legible from the game camera.
    for sx in (-1,1):
        cube(f'Plot {idx:02d} | long frame', (px+sx*1.56,py,0.48),
             (0.15,2.87,0.18), wood_light, PLOTS, 0.045)
    for sy in (-1,1):
        cube(f'Plot {idx:02d} | short frame', (px,py+sy*1.37,0.48),
             (3.23,0.15,0.18), wood_light, PLOTS, 0.045)
    if idx == 6:
        continue
    for c in range(3):
        for r in range(2):
            cx = px + (c-1)*0.81
            cy = py + (r-0.5)*0.97
            if idx == 1:
                cabbage(cx,cy,0.95 + 0.06*((c+r)%2))
            elif idx == 2:
                cabbage(cx,cy,0.53)
            elif idx == 3:
                sprout(cx,cy,0.72)
            elif idx == 4:
                carrot_crop(cx,cy,1.0)
            elif idx == 5:
                carrot_crop(cx,cy,0.52)


# Simple wooden gate, side fences, seed crates and a tiny market stall.
for x in (-6.20,6.20):
    for y in (-4.20,-2.8,-1.4,0,1.4,2.8,4.2):
        cube('fence post', (x,y,0.57), (0.16,0.16,0.78), wood_light, FENCE, 0.025)
    for z in (0.46,0.78):
        cube('side fence rail', (x,0,z), (0.09,8.65,0.105), wood, FENCE, 0.02)
for y in (-4.2,4.2):
    for x in (-6.2,-4.6,-3,-1.4,1.4,3,4.6,6.2):
        cube('fence post', (x,y,0.57), (0.16,0.16,0.78), wood_light, FENCE, 0.025)
    for z in (0.46,0.78):
        for a,b in [(-6.2,-0.67),(0.67,6.2)] if y < 0 else [(-6.2,6.2)]:
            cube('back fence rail' if y>0 else 'front fence rail',
                 ((a+b)/2,y,z), (b-a,0.09,0.105), wood, FENCE, 0.02)


# Entry stones and a short sign beside the gate.
for j, (x,y) in enumerate([(0,-4.58),(0,-3.93),(0,-3.25)]):
    obj = ico('entry stepping stone', (x,y,0.27),0.30,stone,PROPS,1,(1.45,0.85,0.25))
cube('farm sign post',(1.18,-4.22,0.94),(0.15,0.15,1.45),wood_dark,PROPS,0.03)
cube('farm sign board',(1.18,-4.20,1.55),(1.20,0.13,0.52),wood_light,PROPS,0.08)
for dx in (-0.29,0,0.29):
    ico('three seed emblems',(1.18+dx,-4.286,1.56),0.085,
        yellow if dx==0 else leaf,PROPS,1,(0.85,0.31,1.0))


def tree(x,y,s=1):
    cylinder('tree trunk',(x,y,0.84*s),0.19*s,1.20*s,trunk,FENCE,7,0.25*s)
    for dx,dy,dz,r,material in [(-0.24,0,1.61,0.54,grass_dark),
                                (0.27,0.12,1.79,0.56,leaf),
                                (0,0,2.14,0.59,grass_top)]:
        ico('chunky low-poly tree canopy',(x+dx*s,y+dy*s,dz*s),r*s,material,FENCE,1)


tree(-5.73,3.77,0.96)
tree(5.66,3.74,1.02)
tree(-5.72,-3.76,0.76)


# Crates mark the future seed / harvest flow without making a fake game UI.
for x,y,z in [(5.42,-3.50,0.57),(5.04,-3.74,0.94)]:
    cube('stacked harvest crate',(x,y,z),(0.92,0.77,0.50),wood,PROPS,0.04)
    cube('crate inner lip',(x,y,z+0.23),(0.75,0.60,0.05),wood_dark,PROPS,0.02)
for x,y in [(5.31,-3.46),(5.54,-3.43),(5.43,-3.70)]:
    ico('harvest cabbage',(x,y,1.20),0.22,leaf_light,PROPS,1)

# Watering can: chunky geometric body, spout, and circular handle.
cylinder('watering can body',(-5.32,-3.35,0.59),0.27,0.50,blue,PROPS,10,0.33)
cylinder('watering can rim',(-5.32,-3.35,0.85),0.30,0.07,cream,PROPS,10)
beam('watering can spout',(-5.05,-3.35,0.69),(-4.65,-3.35,0.96),0.10,blue,PROPS)
cylinder('watering can rose',(-4.62,-3.35,0.99),0.15,0.055,blue,PROPS,8)
for i in range(6):
    a0 = math.pi*0.16+i*math.pi*0.73/6
    a1 = math.pi*0.16+(i+1)*math.pi*0.73/6
    center = Vector((-5.62,-3.35,0.70))
    p0 = center+Vector((0.34*math.cos(a0),0,0.38*math.sin(a0)))
    p1 = center+Vector((0.34*math.cos(a1),0,0.38*math.sin(a1)))
    beam('watering can handle',p0,p1,0.075,blue,PROPS)

# Bright little wildflowers keep the larger grass areas intentional.
for k,(x,y) in enumerate([(-5.45,1.57),(-5.38,0.55),(-5.4,-1.12),
                           (5.35,1.18),(5.55,-0.72),(4.97,-4.07),
                           (-2.08,-4.10),(2.12,-4.06),(-4.88,4.08)]):
    beam('wildflower stem',(x,y,0.21),(x,y,0.51),0.035,leaf_deep,PROPS)
    ico('wildflower bloom',(x,y,0.54),0.095,yellow if k%2 else cream,PROPS,1)


scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.color = (0.70,0.78,0.74)
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.73,0.83,0.80,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.7
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = -0.35
bpy.context.preferences.filepaths.save_version = 0

cube('matte backdrop',(0,0,-1.16),(200,200,0.15),mat('pale mint backdrop',(0.77,0.86,0.80)),GROUND,0)

def area(name, loc, power, size):
    data = bpy.data.lights.new(name,'AREA')
    obj = bpy.data.objects.new(name,data)
    LIGHTS.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
    data.energy = power
    data.shape = 'DISK'
    data.size = size
    return obj


area('large soft key',(-5,-7,13),2300,9)
area('soft rim',(7,5,11),1200,8)

data = bpy.data.cameras.new('Farm diorama camera')
camera = bpy.data.objects.new('Farm diorama camera',data)
LIGHTS.objects.link(camera)
camera.location = (14,-17,15)
camera.rotation_euler = (Vector((0,0,0.5))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 17.6
scene.camera = camera

# Save a clean native Blender scene and two views for quick review.
bpy.ops.wm.save_as_mainfile(filepath=OUT+r'\farm_lowpoly_scene.blend')
scene.render.filepath = OUT+r'\farm_lowpoly_preview.png'
bpy.ops.render.render(write_still=True)

camera.location = (0,-0.1,20)
camera.rotation_euler = (Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale = 15.5
scene.render.filepath = OUT+r'\farm_lowpoly_top.png'
bpy.ops.render.render(write_still=True)

# Restore the main camera in the delivered .blend file.
camera.location = (14,-17,15)
camera.rotation_euler = (Vector((0,0,0.5))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale = 17.6
scene.render.filepath = OUT+r'\farm_lowpoly_preview.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+r'\farm_lowpoly_scene.blend')

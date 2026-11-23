"""Render the shipped venue mesh with Blender. blender -b -P render_venue.py -- output.png"""
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

assets=Path(__file__).resolve().parents[1]/'Shuttle'/'Assets.xcassets'
target=Path(sys.argv[sys.argv.index('--')+1])
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=48
scene.cycles.use_denoising=False
scene.cycles.max_bounces=3
scene.cycles.diffuse_bounces=2
scene.cycles.glossy_bounces=1
scene.world=bpy.data.worlds.new('House ambient')
scene.world.use_nodes=True
bg=scene.world.node_tree.nodes['Background']
bg.inputs['Color'].default_value=(.13,.21,.31,1)
bg.inputs['Strength'].default_value=.34

def lin(v):
    x=v/255
    return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4

with open(assets/'StadiumMesh.dataset/Arena.bin','rb') as f:
    assert f.read(4)==b'BDA1'
    for g in range(struct.unpack('<I',f.read(4))[0]):
        r,gr,b,e,rough,metal,tex,_,nv,ni=struct.unpack('<8BII',f.read(16))
        v=np.frombuffer(f.read(nv*32),dtype='<f4').reshape((-1,8))
        indices=np.frombuffer(f.read(ni*4),dtype='<u4').reshape((-1,3))
        mesh=bpy.data.meshes.new(f'Batch {g}')
        mesh.from_pydata(np.column_stack((v[:,0],-v[:,2],v[:,1])).tolist(),[],indices.tolist())
        mesh.update()
        uv=mesh.uv_layers.new(name='UV')
        uv.data.foreach_set('uv',v[indices.flatten(),6:8].copy().flatten())
        o=bpy.data.objects.new(mesh.name,mesh); scene.collection.objects.link(o)
        mat=bpy.data.materials.new(mesh.name); mat.use_nodes=True
        shader=mat.node_tree.nodes['Principled BSDF']
        shader.inputs['Roughness'].default_value=rough/255
        shader.inputs['Metallic'].default_value=metal/255
        col=(lin(r),lin(gr),lin(b),1)
        shader.inputs['Base Color'].default_value=col
        shader.inputs['Emission Color'].default_value=col
        shader.inputs['Emission Strength'].default_value=e/255
        if tex:
            shader.inputs['Specular IOR Level'].default_value=.12
            node=mat.node_tree.nodes.new('ShaderNodeTexImage')
            path=assets/('CourtSurface.imageset' if tex==1 else 'CourtRibbon.imageset')/'map.jpg'
            node.image=bpy.data.images.load(str(path))
            mat.node_tree.links.new(node.outputs[0],shader.inputs['Base Color'])
            if e: mat.node_tree.links.new(node.outputs[0],shader.inputs['Emission Color'])
        mesh.materials.append(mat)

def direction(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

def softbox(pos,target,power,size,color):
    data=bpy.data.lights.new('House light','AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
    obj=bpy.data.objects.new(data.name,data); scene.collection.objects.link(obj); obj.location=pos; direction(obj,target)

for x in [-5,5]:
    for y in [-6,3,11]:
        softbox((x,y,8.3),(0,y-.4,0),760,3.8,(.87,.98,1) if x>0 else (1,.93,.83))
softbox((0,12,6.8),(0,14,5),480,4,(.38,.73,.90))

c=bpy.data.cameras.new('Match camera'); camera=bpy.data.objects.new(c.name,c)
scene.collection.objects.link(camera); scene.camera=camera
camera.location=(0,-11.95,5.55)
direction(camera,(0,.58,.32))
c.sensor_fit='VERTICAL'
c.angle=math.radians(55)
scene.render.resolution_x=1440
scene.render.resolution_y=810
scene.render.resolution_percentage=int(sys.argv[sys.argv.index('--')+2]) if len(sys.argv)>sys.argv.index('--')+2 else 100
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.view_settings.exposure=-.20
scene.render.filepath=str(target)
bpy.ops.render.render(write_still=True)

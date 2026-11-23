"""Build the arena's indexed SceneKit mesh and artwork. Requires Pillow and numpy."""
import json
import math
import random
import struct
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'Shuttle' / 'Assets.xcassets'
RNG = random.Random(1753)
def lettering_font():
    candidates = [
        '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-BoldOblique.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf',
        'DejaVuSansCondensed-BoldOblique.ttf',
        'Arial Bold Italic.ttf',
    ]
    for path in candidates:
        try:
            ImageFont.truetype(path, 16)
            return path
        except OSError:
            continue
    raise RuntimeError('Install DejaVu Sans Condensed Bold Oblique or Arial Bold Italic to regenerate the lettering.')


FONT = lettering_font()
INFO = {'version': 1, 'author': 'xcode'}


def image_asset(name, im):
    directory = ROOT / (name + '.imageset')
    directory.mkdir(exist_ok=True)
    im.convert('RGB').save(directory / 'map.jpg', quality=94, subsampling=0)
    (directory / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': 'map.jpg'}], 'info': INFO}))


def text(draw, pos, value, size, color, font=FONT, anchor='mm'):
    draw.text(pos, value, font=ImageFont.truetype(font, size), fill=color, anchor=anchor, stroke_width=0)


def wordmark(draw, cx, cy, s, col):
    # A fan of three feather vanes, also used on the courtside LED boards.
    for i in range(3):
        x = cx + (i - 1) * 9 * s
        draw.polygon([(x-4*s,cy-9*s),(x+2*s,cy-13*s),(x+6*s,cy-11*s),(cx+3*s+(i-1)*3*s,cy+7*s),(cx+(i-1)*3*s,cy+8*s)], fill=col)
    draw.polygon([(cx-3*s,cy+9*s),(cx+7*s,cy+8*s),(cx+6*s,cy+13*s),(cx,cy+15*s)], fill=col)


def floor_art():
    unit = 102
    W, H = 12 * unit, 20 * unit
    im = Image.new('RGB', (W,H), (26,70,83))
    d = ImageDraw.Draw(im)
    def p(x,z): return (round((x+6)*unit),round((z+10)*unit))
    def rect(x1,z1,x2,z2,col): d.rectangle([p(x1,z1),p(x2,z2)],fill=col)
    def line(x1,z1,x2,z2,width,col): d.line([p(x1,z1),p(x2,z2)],fill=col,width=max(1,round(width*unit)))
    # Four stitched vinyl rolls; the bevel surrounding the taped playing surface.
    rect(-4.43,-8.73,4.43,8.73,(21,58,69))
    rect(-4.38,-8.68,4.38,8.68,(48,110,117))
    rect(-4.36,-8.66,4.36,8.66,(28,101,107))
    rect(-3.05,-6.70,3.05,6.70,(33,133,130))
    rect(-2.59,-6.70,2.59,6.70,(36,143,136))
    for x in [-2.24,0,2.24]:
        line(x,-8.64,x,8.64,0.009,(40,121,121))
    chalk=(224,244,228)
    # Each outer line lies inside the boundary. Widths follow the 40mm specification.
    for x in (-3.03,3.03,-2.57,2.57): line(x,-6.7,x,6.7,.04,chalk)
    for z in (-6.68,6.68,-5.94,5.94,-1.98,1.98): line(-3.05,z,3.05,z,.04,chalk)
    for z,base in ((1.98,6.70),(-1.98,-6.70)): line(0,z,0,base,.04,chalk)
    # Discreet screen-printed venue inscriptions beyond the lines.
    for z,label in ((7.66,'COURT   01'),(-7.66,'COURT   01')):
        layer=Image.new('RGBA',(440,94))
        ld=ImageDraw.Draw(layer)
        wordmark(ld,72,45,1.6,(123,195,182))
        text(ld,(247,47),label,38,(123,195,182))
        if z>0: layer=layer.rotate(180)
        cx,cy=p(0,z)
        im.paste(layer,(cx-layer.width//2,cy-layer.height//2),layer)
    for sign in [-1,1]:
        for x in [3.70,3.79,3.88]:
            line(sign*x, -7.27, sign*(x+.13),-7.53,.028,(232,129,90))
        for z in np.arange(-8.50,8.60,.20):
            end = .10 if abs((z+8.5)%1.0)<.01 else .045
            line(sign*4.55,z,sign*(4.55+end),z,.012,(92,137,139))
    arr=np.array(im,dtype=np.float32)
    y,x=np.indices(arr.shape[:2])
    # Grain and fine embossed weave; broad gradients are baked into the resin.
    noise=np.random.default_rng(43).normal(0,.9,(H,W))+((x%4==0)&(y%3==0))*.9
    pool = 1.01-.12*((x-W/2)/(W/2))**2-.055*((y-H/2)/(H/2))**2
    arr=arr*pool[:,:,None]+noise[:,:,None]
    image_asset('CourtSurface',Image.fromarray(np.uint8(np.clip(arr,0,255))))


def banner_art():
    im=Image.new('RGB',(2048,192),(12,32,46)); d=ImageDraw.Draw(im)
    for i in range(0,2048,10):
        d.line([(i,0),(i-65,192)],fill=(15,40,53),width=2)
    d.rectangle((0,0,2048,5),fill=(82,197,183))
    d.rectangle((0,182,2048,190),fill=(43,85,92))
    wordmark(d,118,92,3.7,(123,231,203))
    text(d,(545,94),'FEATHERBLADE',80,(218,239,225))
    for i in range(3):
        x=940+i*25
        d.polygon([(x,58),(x+16,58),(x-20,131),(x-36,131)],fill=(253,122,85))
    text(d,(1433,95),'BADMINTON CLUB',72,(125,215,200))
    for i in range(8):
        d.rectangle((1852+i*14,50,1857+i*14,142),fill=(81,147,148))
    image_asset('CourtRibbon',im)


# Material id, color, emissive level, roughness, metallic, texture id.
palette = {
    'base':('152431',0,.85,.04,0), 'rise':('233947',0,.92,.04,0),
    'rim':('567281',0,.56,.25,0), 'ink':('0e202f',0,.68,.18,0),
    'floor':('ffffff',0,.80,0,1), 'board':('ffffff',.23,.80,0,2),
    'led':('74e7d3',.75,.36,.1,0), 'orange':('f27b57',.38,.60,.08,0),
    'ivory':('e1ead8',.12,.66,0,0), 'mesh':('394849',.02,.65,.08,0),
    'lamp':('f5eedb',1,.36,0,0), 'ocean':('14586a',0,.65,.04,0),
    'marine':('294a5d',0,.66,.04,0), 'turq':('347983',0,.61,.04,0),
    'chair':('a66150',0,.66,.04,0), 'c1':('324957',0,.82,0,0),
    'c2':('405770',0,.82,0,0), 'c3':('426971',0,.82,0,0),
    'c4':('765b5d',0,.82,0,0), 'head':('9a7d6c',0,.86,0,0),
    'hair':('27313a',0,.84,0,0)
}
class Group:
    def __init__(self): self.vertices=[]; self.indices=[]; self.lookup={}
    def face(self, points, uvs):
        a,b,c=map(np.array,points[:3])
        n=np.cross(b-a,c-a)
        if np.linalg.norm(n)<.0000001: return
        normal=tuple(n/np.linalg.norm(n))
        for i in range(1,len(points)-1):
            for j in (0,i,i+1):
                key=tuple(round(float(v),5) for v in (*points[j],*normal,*uvs[j]))
                if key not in self.lookup:
                    self.lookup[key]=len(self.vertices); self.vertices.append(key)
                self.indices.append(self.lookup[key])
groups=defaultdict(Group)


def face(m,*v,uv=None):
    groups[m].face(v,uv or [(0,0)]*len(v))


def box(m,x,y,z,w,h,d):
    x0,x1=x-w/2,x+w/2; y0,y1=y-h/2,y+h/2; z0,z1=z-d/2,z+d/2
    A=(x0,y0,z0); B=(x1,y0,z0); C=(x1,y1,z0); D=(x0,y1,z0)
    E=(x0,y0,z1); F=(x1,y0,z1); G=(x1,y1,z1); H=(x0,y1,z1)
    for quad in [(A,D,C,B),(E,F,G,H),(A,E,H,D),(B,C,G,F),(D,H,G,C),(A,B,F,E)]:
        face(m,*quad)


def rod(m,a,b,r,segments=6,r2=None):
    a,b=np.array(a),np.array(b); axis=b-a; axis=axis/np.linalg.norm(axis)
    ref=np.array([0.,1.,0.]) if abs(axis[1])<.90 else np.array([1.,0.,0.])
    ex=np.cross(ref,axis); ex=ex/np.linalg.norm(ex); ez=np.cross(axis,ex)
    ring=[math.cos(i*math.tau/segments)*ex+math.sin(i*math.tau/segments)*ez for i in range(segments)]
    P=[a+r*e for e in ring]; Q=[b+(r if r2 is None else r2)*e for e in ring]
    face(m,*P[::-1]); face(m,*Q)
    for i in range(segments):
        j=(i+1)%segments; face(m,P[i],P[j],Q[j],Q[i])


def arena():
    box('base',0,-.20,0,30,.36,34)
    face('floor',(-6,0,10),(6,0,10),(6,0,-10),(-6,0,-10),uv=[(0,0),(1,0),(1,1),(0,1)])
    for side in [-1,1]:
        box('ink',side*5.73,.04,0,.13,.08,19.85)
        for z in [-7.3,-2.6,2.6,7.3]:
            box('base',side*5.78,.36,z,.18,.66,4.36)
            x=side*5.68
            q=[(x,.11,z-2.15),(x,.11,z+2.15),(x,.61,z+2.15),(x,.61,z-2.15)]
            if side<0: q=q[::-1]
            face('board',*q,uv=[(0,0),(1,0),(1,1),(0,1)] if side>0 else [(1,1),(0,1),(0,0),(1,0)])
            box('rim',side*5.78,.7,z,.19,.038,4.39)
        for z in [-9.58,9.58]:
            x=side*3.23
            box('ink',x,.45,z,5.72,.88,.23)
            front=z+(.13 if z<0 else -.13)
            face('board',(x-2.82,.10,front),(x+2.82,.10,front),(x+2.82,.81,front),(x-2.82,.81,front),uv=[(0,0),(1,0),(1,1),(0,1)])
    # Net hangs 26mm lower in the middle. The contrasting top tape is also the collision-plane cue.
    def height(x): return 1.524+.026*(x/3.05)**2
    for side in [-1,1]:
        x=side*3.055
        box('ink',x,.055,0,.35,.11,.41)
        rod('rim',(x,.08,0),(x,1.59,0),.035,10)
        for lo,hi,m in [(.12,.27,'orange'),(1.43,1.54,'ivory')]:
            rod(m,(x,lo,0),(x,hi,0),.038,10)
        box('ink',x,.96,.057,.105,.18,.07)
    for i in range(87):
        x=-3.05+i*6.1/86
        # Thin flat yarn reduces visual interference with the shuttlecock.
        box('mesh',x,height(x)-.38,0,.0065,.76,.005)
    for i in range(12):
        height_offset=i*.067
        for k in range(8):
            x=-3.05+k*6.10/8; xx=x+6.10/8
            y=height(x)-height_offset; yy=height(xx)-height_offset
            face('mesh',(x,y-.003,0),(xx,yy-.003,0),(xx,yy+.003,0),(x,y+.003,0))
    for k in range(14):
        x=-3.05+k*6.10/14; xx=x+6.10/14
        y=height(x); yy=height(xx)
        face('ivory',(x,y-.040,.005),(xx,yy-.040,.005),(xx,yy,.005),(x,y,.005))
    for side in [-1,1]:
        # Sawtooth seating banks, including three contrasting access aisles.
        for row in range(5):
            h=.44*(row+1); x=side*(6.52+row*.83)
            box('rise',x,h/2-.02,0,.86,h,22.6)
            box('rim',x-side*.398,h-.03,0,.035,.035,22.57)
            for j in range(-15,16):
                if j in [-9,0,9]: continue
                z=j*.69; seat_m=RNG.choices(['marine','ocean','turq','chair'],[41,38,17,4])[0]
                chair(x,h,z,side,0,seat_m)
        for row in range(4):
            x=side*(10.94+row*.86); h=2.94+row*.46
            box('rise',x,h/2-.02,0,.88,h,23.25)
            for j in range(-15,16):
                if j in [-9,0,9]:continue
                chair(x,h,j*.69,side,0,RNG.choice(['marine','ocean','ink']))
        for z in [-6.21,0,6.21]:
            for i in range(10):
                x=side*(6.24+i*.415); h=.22*(i+1)
                box('rim',x,h/2,z,.42,h,.48)
                box('orange',x-side*.198,h+.004,z,.029,.012,.47)
            for row in [0,2,4]:
                x=side*(6.52+row*.83)
                rod('rim',(x,.44*(row+1),z+.31),(x,.44*(row+1)+.86,z+.31),.023)
            rod('rim',(side*6.52,1.30,z+.31),(side*9.84,3.06,z+.31),.028)
        box('base',side*14.,4.8,0,.50,9.6,32)
        # Beamwork with warm linear lights and exposed trusses.
        for z in [-12,-7,-2,3,8,13]:
            rod('rim',(side*13.6,3.2,z),(side*12.85,8.5,z),.105,4)
            rod('ink',(side*12.85,8.5,z),(0,10.72,z),.17,4)
            rod('rim',(side*12.8,7.9,z),(0,10.03,z),.068,4)
            for t in range(6):
                x0=side*(12.85-t*2.1); x1=x0-side*2.1
                rod('marine',(x0,8.42+t*.36,z),(x1,8.08+t*.36,z),.035,4)
            rod('lamp',(side*8.7,8.80,z),(side*3.0,9.78,z),.035)
        box('led',side*13.65,5.32,0,.035,.048,27)
    # Court officials' chair: four tapered legs, cross bracing and a side ladder.
    ux,uz=-4.12,.13
    for side in [-1,1]:
        for end in [-1,1]:
            rod('rim',(ux+side*.37,.015,uz+end*.41),(ux+side*.24,1.82,uz+end*.25),.031)
        rod('rim',(ux+side*.34,.20,uz-.37),(ux+side*.24,1.48,uz+.275),.022)
        rod('rim',(ux+side*.30,1.63,uz-.28),(ux+side*.30,1.96,uz-.28),.023)
        rod('rim',(ux+side*.30,1.96,uz-.28),(ux+side*.30,1.96,uz+.24),.027)
    for i in range(5):
        t=i/5; y=.23+i*.255; z=uz+.41-t*.16
        rod('rim',(ux-.37+t*.13,y,z),(ux+.37-t*.13,y,z),.026)
    box('ink',ux,1.62,uz,.72,.09,.72)
    box('orange',ux,1.72,uz,.49,.09,.44)
    box('orange',ux-.20,1.92,uz,.075,.40,.44)
    # A sideline bench and the players' equipment bags.
    for z in [-4.8,4.8]:
        x=4.93
        for zz in [z-.72,z+.72]:
            box('ink',x,.17,zz,.40,.34,.08)
        for i in [-1,0,1]:
            box('marine',x+i*.15,.37,z,.136,.058,1.90)
        box('ivory',x,.408,z+.52,.41,.019,.32)
        box('ivory',x-.21,.305,z+.52,.025,.21,.32)
        rod('ink',(x-.56,.132,z-.34),(x-.56,.132,z+.29),.125,8)
        for dz in [-.20,.14]:
            rod('orange',(x-.56,.131,z+dz),(x-.56,.131,z+dz+.041),.128,8)
        for dz in [.32,.49]:
            rod('turq',(x,.41,z-.91+dz),(x,.64,z-.91+dz),.033,8)
            rod('ivory',(x,.64,z-.91+dz),(x,.68,z-.91+dz),.019,8)
    # End grandstand.
    for row in range(5):
        z=-10.37-row*.83; h=.48*(row+1)
        box('rise',0,h/2-.02,z,12.25,h,.86)
        box('rim',0,h-.025,z+.403,12.2,.038,.035)
        for j in range(-8,9):
            if j in [-4,4]: continue
            chair(j*.68,h,z,0,-1,RNG.choice(['ocean','marine','turq']))
    box('ink',0,4.5,-14.9,28,9,.4)
    for x in np.arange(-13,13,.53):
        box('base',x,4.1,-14.62,.14,7.6,.20)
    box('led',0,3.61,-14.46,26,.038,.08)
    # A backlit crest in a brushed-anodised recess above the end grandstand.
    box('base',0,5.24,-14.34,7.98,2.14,.22)
    box('ink',0,5.24,-14.20,7.83,1.99,.13)
    face('board',(-3.81,4.42,-14.11),(3.81,4.42,-14.11),(3.81,6.06,-14.11),(-3.81,6.06,-14.11),uv=[(0,0),(1,0),(1,1),(0,1)])
    for x in [-6.40,6.40,-10.65,10.65]:
        for i in range(3):
            rod('orange',(x+i*.20-.14,4.77,-14.43),(x+i*.20+.15,5.45,-14.43),.055,4)


def chair(x,h,z,sx,sz,m):
    # Small molded seats, angled backrest and dark inset. 's' points toward rear.
    def P(u,y,d): return (x-u*sz+d*sx,h+y,z+u*sx+d*sz)
    def loft(material,rings,steps=8):
        rings=[[P(rx*math.cos(k*math.tau/steps),y,offset+rz*math.sin(k*math.tau/steps))
                for k in range(steps)] for y,rx,rz,offset in rings]
        face(material,*rings[-1]); face(material,*rings[0][::-1])
        for bot,top in zip(rings,rings[1:]):
            for i in range(steps):
                j=(i+1)%steps
                face(material,bot[i],bot[j],top[j],top[i])
    # Tapered molded bucket. Faceted corners catch the floodlight along the rim.
    loft(m,[(.091,.19,.14,0),(.14,.244,.22,-.015),(.154,.225,.19,-.013)])
    face(m,P(-.22,.15,.14),P(.22,.15,.14),P(.193,.42,.205),P(.16,.44,.205),P(-.16,.44,.205),P(-.193,.42,.205))
    if RNG.random()>.47: return
    col=RNG.choice(['c1','c1','c2','c3','c4'])
    ht=RNG.uniform(.34,.46)
    loft(col,[(.16,.12,.09,-.015),(.16+ht*.52,.145,.107,-.03),(.16+ht*.89,.171,.095,-.032),(.16+ht,.095,.078,-.04)],7)
    chin=.158+ht
    loft('head',[(chin,.052,.065,-.061),(chin+.08,.080,.087,-.055),(chin+.16,.078,.075,-.052)],7)
    loft('hair',[(chin+.105,.085,.084,-.050),(chin+.17,.080,.073,-.046),(chin+.195,.038,.032,-.05)],7)
    for side in [-1,1]:
        rod(col,P(side*.147,chin-.065,-.035),P(side*.15,chin-.14,-.115),.042,5,.034)
        rod('head',P(side*.15,chin-.14,-.115),P(side*.1,.31,-.18),.032,5,.027)
        rod('ink',P(side*.081,.16,-.06),P(side*.085,.155,-.247),.067,6,.051)
        rod('ink',P(side*.085,.155,-.247),P(side*.09,-.012,-.27),.046,6,.029)


def write():
    directory=ROOT/'StadiumMesh.dataset'
    directory.mkdir(exist_ok=True)
    with open(directory/'Arena.bin','wb') as f:
        f.write(b'BDA1'+struct.pack('<I',len(groups)))
        for key,g in groups.items():
            rgb,e,r,m,tex=palette[key]; R,G,B=bytes.fromhex(rgb)
            f.write(struct.pack('<8BII',R,G,B,round(e*255),round(r*255),round(m*255),tex,0,len(g.vertices),len(g.indices)))
            f.write(np.array(g.vertices,dtype='<f4').tobytes())
            f.write(np.array(g.indices,dtype='<u4').tobytes())
    (directory/'Contents.json').write_text(json.dumps({'data':[{'idiom':'universal','filename':'Arena.bin'}],'info':INFO}))


if __name__=='__main__':
    floor_art(); banner_art(); arena(); write()

import re, json
s=open('buildFile',encoding='latin-1').read()
def fix(n):
    try: return n.encode('latin-1').decode('utf-8')
    except: return n
W,H=2640.0,2040.0
# Zone paths
zones={}
for n,p in re.findall(r'Zone[^>]*name="([^"]*)"[^>]*path="([^"]*)"', s):
    zones[fix(n)]=p
# SetupStack x,y (markers) — name + x + y
stacks={}
for m in re.finditer(r'SetupStack[^>]*name="([^"]*)"[^>]*?x="(-?\d+)"[^>]*?y="(-?\d+)"', s):
    stacks[fix(m.group(1))]=(int(m.group(2)),int(m.group(3)))

def poly(name):
    pts=[]
    for pair in zones[name].split(';'):
        x,y=pair.split(',')
        pts.append([round(int(x)/W,4), round(int(y)/H,4)])
    # rimuovi duplicati consecutivi
    out=[]
    for pt in pts:
        if not out or out[-1]!=pt: out.append(pt)
    return out
def centroid(pts):
    return [round(sum(p[0] for p in pts)/len(pts),4), round(sum(p[1] for p in pts)/len(pts),4)]
def circle(name):
    pts=poly(name)
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2
    r=min(max(xs)-min(xs), max(ys)-min(ys))/2
    return [round(cx,4),round(cy,4),round(r,4)]
def mk(name):  # normalized marker pos
    if name in stacks:
        x,y=stacks[name]; return [round(x/W,4),round(y/H,4)]
    return None

prov={'Pinar del Río':'pinar_del_rio','La Habana':'la_habana','Matanzas':'matanzas',
 'Las Villas':'las_villas','Camagüey':'camaguey_province','Oriente':'oriente','Sierra Maestra':'sierra_maestra'}
city={'Havana':'havana','Camagüey City':'camaguey_city','Santiago de Cuba':'santiago_de_cuba'}
ec={'Economic Center 1':'ec_pinar_habana','Economic Center 2':'ec_lasvillas_camaguey','Economic Center 3':'ec_oriente_sierra'}

regions={}
for vname,rid in {**prov,**city,**ec}.items():
    if vname not in zones:
        print('MISSING zone', vname); continue
    e={}
    pts=poly(vname)
    if vname in prov:
        e['polygon']=pts; e['anchor']=centroid(pts)
    else:
        c=circle(vname); e['circle']=c; e['anchor']=[c[0],c[1]]
    cb=mk(vname+' Control')
    if cb: e['cbox']=cb
    sb=mk(vname+' Sup/Opp')
    if sb: e['sbox']=sb
    regions[rid]=e

out={'_note':'Dati estratti dal modulo Vassal (board 2640x2040). polygon=province; circle=[cx,cy,r] citta/EC; cbox/sbox=posizioni esatte marcatori Controllo/Supporto; anchor=centro.','regions':regions}
json.dump(out, open('/home/user/Cuba-Libre-GMT/godot/games/cuba_libre/data/regions.json','w'), ensure_ascii=False, indent=2)
print('Scritte', len(regions), 'regioni:', list(regions))
for rid,e in regions.items():
    print(rid, 'circle' if 'circle' in e else 'poly%d'%len(e['polygon']), 'cbox' in e, 'sbox' in e)

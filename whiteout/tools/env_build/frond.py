import random, math
from PIL import Image, ImageDraw, ImageFilter
random.seed(7)
CELL=1024   # supersampled cell
N=2
img=Image.new('RGBA',(CELL*N,CELL*N),(0,0,0,0))
d=ImageDraw.Draw(img)
def col(base,var):
    return tuple(max(0,min(255,int(b+random.uniform(-var,var)))) for b in base)
def frond(ox,oy,kind):
    S=CELL
    # stem from bottom centre to near top, slight curve
    pts=[]
    sway=random.uniform(-30,30)
    for i in range(41):
        t=i/40
        pts.append((ox+S*0.5+sway*math.sin(t*3.1)*(t), oy+S-30-(S-90)*t))
    d.line(pts,fill=(70,48,34,255),width=9)
    nb=34 if kind==0 else 28
    for k in range(nb):
        t=0.06+0.9*k/nb
        i=int(t*40); px,py=pts[min(i,39)]
        for side in (-1,1):
            # branchlet length: tapered towards tip, longest ~ 35%
            Lmax=S*0.46*(1.0 if kind!=2 else 0.8)
            L=Lmax*(1-t)**0.7*min(1,(t+0.04)/0.14)**0.6*random.uniform(0.88,1.08)
            L=max(L,S*0.05)
            ang=math.radians(random.uniform(52,70))      # from stem, towards tip
            dx=math.sin(ang)*side; dy=-math.cos(ang)
            ex=px+dx*L; ey=py+dy*L
            # slight droop curve
            mx=(px+ex)/2+0; my=(py+ey)/2+L*0.08
            bl=[(px,py),(mx,my),(ex,ey)]
            d.line(bl,fill=(66,46,32,255),width=5)
            # needles along branchlet
            nn=max(5,int(L/9))
            for j in range(nn):
                u=(j+random.random()*0.5)/nn
                # quadratic bezier point
                bx=(1-u)**2*px+2*(1-u)*u*mx+u*u*ex
                by=(1-u)**2*py+2*(1-u)*u*my+u*u*ey
                nl=random.uniform(24,38)*(1-0.55*u)
                for s2 in (-1,1):
                    a2=math.atan2(dy,dx)+s2*math.radians(random.uniform(48,72))
                    # mix forward bias
                    tx=bx+math.cos(a2)*nl; ty=by+math.sin(a2)*nl
                    c=col((34,66,42),18) if random.random()<0.8 else col((52,92,58),16)
                    d.line([(bx,by),(tx,ty)],fill=c+(255,),width=4)
    # leader tip needles
    px,py=pts[-1]
    for j in range(14):
        a=math.radians(-90+random.uniform(-40,40))
        d.line([(px,py),(px+math.cos(a)*30,py+math.sin(a)*30)],fill=col((38,70,46),14)+(255,),width=4)
for r in range(N):
    for c in range(N):
        frond(c*CELL,r*CELL,(r*N+c)%3)
out=img.resize((CELL,CELL),Image.LANCZOS)   # 512 per cell
out.save('tex/frond_atlas.png')
a=out.split()[3].filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(7))
a.save('tex/frond_clump.png')
bg=Image.new('RGB',out.size,(180,190,210)); bg.paste(out,mask=out.split()[3]); bg.save('frond_prev.png')
print('ok')

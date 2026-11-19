// ==== landmark models ====
const MODELS={}; // id -> {x,y,h}
const GLOW=[]; // extra night lights [x, height, y] (the stadium's masts)
const NOLOTS=[]; // polygons (grid metres) where cityGen places no lots: fenced grounds modelled on their own
const TREES=[]; // round trees a landmark plants where the real ones stand [x, y, scale, seed] (the Parque Río Claro's eucalyptus)
function rotRect(cx,cy,w,d,a=0){const c=Math.cos(a),s=Math.sin(a);return [[-w/2,-d/2],[w/2,-d/2],[w/2,d/2],[-w/2,d/2]].map(([x,y])=>[cx+x*c-y*s,cy+x*s+y*c]);}
function ngon(cx,cy,r,n,a0=0){const o=[];for(let i=0;i<n;i++){const a=a0+i/n*Math.PI*2;o.push([cx+Math.cos(a)*r,cy+Math.sin(a)*r]);}return o;}
function pyramid(B,q,y,h,col){let cx=0,cy=0;q.forEach(p=>{cx+=p[0];cy+=p[1];});cx/=q.length;cy/=q.length;B._c=[cx,-cy];for(let i=0;i<q.length;i++){const a=q[i],b=q[(i+1)%q.length];B.face([[a[0],y,-a[1]],[b[0],y,-b[1]],[cx,y+h,-cy]],null,i%2?shade(col,.9):col);}B._c=null;}
// a landmark's local frame (docs/METODOLOGIA.md §9.2): origin (X, Y) in grid metres, v along angle A (radians from
// +x), u to the right of v. G: (u,v) -> grid metres; V: (u,v,height) -> scene point; N3: a (u,v) direction as a scene
// normal (ny: its vertical part, normalised with it); R: an axis-aligned (u,v) rectangle in grid metres
function localFrame(X,Y,A){const sa=Math.sin(A),ca=Math.cos(A),G=(u,v)=>[X+u*sa+v*ca,Y-u*ca+v*sa],Gs=q=>q.map(p=>G(p[0],p[1]));
  return {G,Gs,V:(u,v,h)=>{const g=G(u,v);return [g[0],h,-g[1]];},
    N3:(nu,nv,ny=0)=>{const L=Math.hypot(nu,nv,ny)||1;return [(nu*sa+nv*ca)/L,ny/L,(nu*ca-nv*sa)/L];},
    R:(u0,v0,u1,v1)=>Gs([[u0,v0],[u1,v0],[u1,v1],[u0,v1]])};}
// façade vocabulary for a landmark drawn on S in frame F (localFrame) with palette K (docs/ESTETICA.md §7). K needs
// tile/tile2 (roof bays), white (copings), glass/glass2 (stained glass) and brick, or gable, for the gable ends
function facade(S,F,K){const {V,N3,R}=F;
  const box=(u0,v0,u1,v1,h0,h1,wall,top,lid=true)=>S.prism(R(u0,v0,u1,v1),h0,h1,wall,top,lid);
  // a wall from (u,v) a to b with outward direction `out`; details are drawn `o` metres in front of it, s runs
  // along the wall from a (so on a wall parallel to u, s is u itself). The wall keeps a, b and out, and w.at(o2) is
  // the same wall with its details o2 in front (a second layer over the first: a sill, a mullion)
  const WL=(a,b,out,o=.06)=>{const L=Math.hypot(b[0]-a[0],b[1]-a[1]),du=(b[0]-a[0])/L,dv=(b[1]-a[1])/L;
    return {L,a,b,out,at:o2=>WL(a,b,out,o2),q:(s,h)=>V(a[0]+du*s+out[0]*o,a[1]+dv*s+out[1]*o,h),n:N3(out[0],out[1])};};
  // the unit normal of the edge a→b in (u,v) on its [dv, -du] side (sg=-1: the other side): the outward direction of
  // the edges of a ring that runs clockwise in (u,v) (sg=1) or counter-clockwise (sg=-1)
  const outOf=(a,b,sg=1)=>{const du=b[0]-a[0],dv=b[1]-a[1],L=Math.hypot(du,dv);return [sg*dv/L,-sg*du/L];};
  const WV=(v,sg,o)=>WL([0,v],[1,v],[0,sg],o),WU=(u,sg,o)=>WL([u,0],[u,1],[sg,0],o);
  const rect=(w,s0,s1,h0,h1,col)=>S.face([w.q(s0,h0),w.q(s1,h0),w.q(s1,h1),w.q(s0,h1)],w.n,col);
  // the walls of a (u,v) ring (outOf(a,b) outward) from h0 to h1, their top 0.5 m a coping band in cop (null: none);
  // col a colour or a function of the edge's index. Edges under 1 cm are skipped
  const walls=(ring,h0,h1,col,cop=K.white)=>{for(let i=0;i<ring.length;i++){const a=ring[i],b=ring[(i+1)%ring.length],L=Math.hypot(b[0]-a[0],b[1]-a[1]);
      if(L<.01)continue;const w=WL(a,b,outOf(a,b),0),c=typeof col==='function'?col(i):col,top=cop?h1-.5:h1;
      S.face([w.q(0,h0),w.q(L,h0),w.q(L,top),w.q(0,top)],w.n,c);if(cop)S.face([w.q(0,h1-.5),w.q(L,h1-.5),w.q(L,h1),w.q(0,h1)],w.n,cop);}};
  // pixel arch: a rectangle under two narrower steps
  const arch=(w,sc,wd,h0,h1,col)=>{const r=wd*.45;rect(w,sc-wd/2,sc+wd/2,h0,h1-r,col);rect(w,sc-wd*.36,sc+wd*.36,h1-r,h1-r*.4,col);rect(w,sc-wd*.18,sc+wd*.18,h1-r*.4,h1,col);};
  // stained glass: leaded bands in two tones
  const glass=(w,sc,wd,h0,h1)=>{const r=wd*.45;for(let h=h0,k=0;h<h1-r-.01;h+=1.5,k++)rect(w,sc-wd/2,sc+wd/2,h,Math.min(h+1.5,h1-r),k%2?K.glass2:K.glass);
    rect(w,sc-wd*.36,sc+wd*.36,h1-r,h1-r*.4,K.glass);rect(w,sc-wd*.18,sc+wd*.18,h1-r*.4,h1,K.glass);};
  // gable roof over s0..s1 (along its ridge) and t0..t1, eaves at h, ridge rh higher; ax 'v': the ridge runs along
  // v. Tiles in bays of two tones; gable ends with a white coping; eaves overhang by half a metre
  const roof=(ax,s0,s1,t0,t1,h,rh,bay,ends=[1,1])=>{const P=(s,t,y)=>ax==='v'?V(t,s,y):V(s,t,y),D=(ds,dt,y)=>ax==='v'?N3(dt,ds,y):N3(ds,dt,y);
    const tm=(t0+t1)/2,hw=(t1-t0)/2,o=.5,dr=o*rh/hw;
    for(let s=s0,k=0;s<s1-1e-6;s+=bay,k++){const e=Math.min(s+bay,s1),c=k%2?K.tile2:K.tile;
      S.face([P(s,t0-o,h-dr),P(e,t0-o,h-dr),P(e,tm,h+rh),P(s,tm,h+rh)],D(0,-rh,hw),c);
      S.face([P(s,t1+o,h-dr),P(e,t1+o,h-dr),P(e,tm,h+rh),P(s,tm,h+rh)],D(0,rh,hw),c);}
    [s0,s1].forEach((s,i)=>{if(!ends[i])return;const sg=i?1:-1,n=D(sg,0,0),f=s+sg*.08;
      S.face([P(s,t0,h),P(s,t1,h),P(s,tm,h+rh)],n,K.gable||K.brick);
      S.face([P(f,t0-o,h-dr-.45),P(f,tm,h+rh-.45),P(f,tm,h+rh+.05),P(f,t0-o,h-dr+.05)],n,K.white);
      S.face([P(f,t1+o,h-dr-.45),P(f,tm,h+rh-.45),P(f,tm,h+rh+.05),P(f,t1+o,h-dr+.05)],n,K.white);});};
  // hipped roof over an axis-aligned (u,v) rectangle: eaves o out and `drop` under h, the ridge rh over h along the
  // longer side (ax 'u' or 'v' forces it), its ends kept at the middle when clamp (a square gets a point, not a cross).
  // Tones: the slopes facing +u and -v in t1, the others in t2 (sun-lit and shaded, the Liceo, the Colegio De La
  // Salle); with ends, the two long slopes in t1 and the hips in t2 (the Ex Cárcel). GB.hipRoof (50-city.js) is the
  // city's: one tone and any convex quad
  const hipped=(u0,v0,u1,v1,h,rh,t1,t2,{o=.4,drop=0,ax,clamp=true,ends=false}={})=>{u0-=o;v0-=o;u1+=o;v1+=o;
    const he=h-drop,hr=h+rh,alU=ax?ax==='u':u1-u0>=v1-v0,hw=(alU?v1-v0:u1-u0)/2,f=(q,c)=>S.face(q,null,c);
    if(alU){const vm=(v0+v1)/2,a=clamp?Math.min(u0+hw,(u0+u1)/2):u0+hw,b=clamp?Math.max(u1-hw,(u0+u1)/2):u1-hw;
      f([V(u0,v0,he),V(u1,v0,he),V(b,vm,hr),V(a,vm,hr)],t1);f([V(u1,v1,he),V(u0,v1,he),V(a,vm,hr),V(b,vm,hr)],ends?t1:t2);
      f([V(u0,v1,he),V(u0,v0,he),V(a,vm,hr)],t2);f([V(u1,v0,he),V(u1,v1,he),V(b,vm,hr)],ends?t2:t1);}
    else{const um=(u0+u1)/2,a=clamp?Math.min(v0+hw,(v0+v1)/2):v0+hw,b=clamp?Math.max(v1-hw,(v0+v1)/2):v1-hw;
      f([V(u0,v1,he),V(u0,v0,he),V(um,a,hr),V(um,b,hr)],ends?t1:t2);f([V(u1,v0,he),V(u1,v1,he),V(um,b,hr),V(um,a,hr)],t1);
      f([V(u0,v0,he),V(u1,v0,he),V(um,a,hr)],ends?t2:t1);f([V(u1,v1,he),V(u0,v1,he),V(um,b,hr)],t2);}};
  return {box,WL,WV,WU,rect,arch,glass,roof,outOf,walls,hipped};}
// A road or rail deck on piers, for any bridge (the Río Claro ones, puentes-rio-claro): pts the deck's polyline in grid
// metres, hw half its width, hAt(p) its height along the span (never under the terrain plus 0.3 m), o its parts:
// walk (half the roadway: asphalt, sidewalks and parapets) or deck (a plain top colour) with balus (balustrade in two
// tones), beamD/beamCol the beam under the deck, pier the piers' spacing, lamps, ends (false: no end walls, for a deck that
// runs on into a road on the ground: the Ruta 5's, ruta5Base). K: asph, walk, par, red, metal, lamp,
// old, old2. Marks its footprint in occ and removes the TREES under it. Call it from buildModels (before the city).
function deckBridge(S,K,pts,hw,hAt,o){const sm=[];
    for(let i=0;i<pts.length-1;i++){const a=pts[i],b=pts[i+1],L=Math.hypot(b[0]-a[0],b[1]-a[1]),n=Math.max(1,Math.ceil(L/2.5));
      for(let k=i?1:0;k<=n;k++)sm.push({x:a[0]+(b[0]-a[0])*k/n,y:a[1]+(b[1]-a[1])*k/n,dx:(b[0]-a[0])/L,dy:(b[1]-a[1])/L});}
    let D=0;sm.forEach((p,i)=>{if(i)D+=Math.hypot(p.x-sm[i-1].x,p.y-sm[i-1].y);p.d=D;p.h=Math.max(hAt(p),E(p.x,p.y)+.3);p.nx=-p.dy;p.ny=p.dx;});
    const P=(p,off,dh)=>[p.x+p.nx*off,p.h+dh,-(p.y+p.ny*off)],N=(p,s)=>[p.nx*s,0,-p.ny*s];S.dy=0;
    for(let i=0;i<sm.length-1;i++){const a=sm[i],b=sm[i+1],top=(o0,o1,dh,col)=>S.face([P(a,o0,dh),P(b,o0,dh),P(b,o1,dh),P(a,o1,dh)],[0,1,0],col);
      const side=(off,s,d0,d1,col)=>S.face([P(a,off,d0),P(b,off,d0),P(b,off,d1),P(a,off,d1)],N(a,s),col);
      if(o.walk){top(-o.walk,o.walk,0,K.asph);for(const s of [1,-1]){top(s*o.walk,s*(hw-.25),.15,K.walk);side(s*o.walk,-s,0,.15,K.walk);}}
      else top(-hw+.25,hw-.25,0,o.deck);
      for(const s of [1,-1]){const rail=o.balus?(i%2?K.old2:K.old):K.par;
        side(s*hw,s,-o.beamD,o.walk?.15:0,o.beamCol);side(s*hw,s,o.walk?.15:0,o.walk?1.05:.9,rail);       // beam and the parapet's outer face
        side(s*(hw-.25),-s,o.walk?.15:0,o.walk?1.05:.9,rail);top(s*(hw-.25),s*hw,o.walk?1.05:.9,o.walk?K.par:K.old);}}
    if(o.ends!==false)for(const [p,sg] of [[sm[0],-1],[sm[sm.length-1],1]])S.face([P(p,-hw,-o.beamD),P(p,hw,-o.beamD),P(p,hw,1),P(p,-hw,1)],[p.dx*sg,0,-p.dy*sg],o.beamCol);
    let nextPier=o.pier/2,nextLamp=10,ls=1,nextRed=0;
    for(const p of sm){const g=E(p.x,p.y),a=Math.atan2(p.dy,p.dx);occMark(rotRect(p.x,p.y,3,2*hw+4,a));
      if(p.d>=nextPier){nextPier+=o.pier;if(p.h-g>2.5){
        if(o.walk){for(const s of [1,-1])S.prism(ngon(p.x+p.nx*s*4,p.y+p.ny*s*4,.75,6),g-.5,p.h-o.beamD-.8,o.beamCol,o.beamCol);
          S.prism(rotRect(p.x,p.y,1.4,2*hw-1,a),p.h-o.beamD-.8,p.h-o.beamD,o.beamCol,o.beamCol);}
        else S.prism(rotRect(p.x,p.y,1.2,2*hw-1.5,a),g-.5,p.h-o.beamD,o.beamCol,o.beamCol);}}
      if(o.walk&&p.d>=nextRed){nextRed+=4;for(const s of [1,-1])S.prism(rotRect(p.x+p.nx*s*(hw-.12),p.y+p.ny*s*(hw-.12),.35,.35,a),1.05+p.h,1.35+p.h,K.red,K.red);}
      if(o.lamps&&p.d>=nextLamp){nextLamp+=35;ls=-ls;const ox=p.x+p.nx*ls*(hw-.6),oy=p.y+p.ny*ls*(hw-.6);
        S.prism(rotRect(ox,oy,.3,.3,a),p.h+1.05,p.h+8,K.metal,K.metal);S.prism(rotRect(ox-p.nx*ls*1,oy-p.ny*ls*1,.25,2.2,a),p.h+7.8,p.h+8.05,K.metal,K.metal);
        const hx=ox-p.nx*ls*2,hy=oy-p.ny*ls*2;S.prism(rotRect(hx,hy,.6,.8,a),p.h+7.55,p.h+7.85,K.metal,K.lamp);GLOW.push(hx,p.h+7.4,hy);}}
    // no tree of the park's wood under or through the deck
    for(let i=TREES.length-1;i>=0;i--){const t=TREES[i];if(sm.some(p=>Math.hypot(t[0]-p.x,t[1]-p.y)<hw+5))TREES.splice(i,1);}}
// The landmarks' clock: build.py puts __HT('<id>') after each landmark in buildModels, which records its ms in
// HITOS_T (__stats.t.hitos). With window.__HITOS_HASH set before the page loads (tools/hitos.py) it also records in
// HITOS_H a fingerprint of what the landmark emitted and changed, per part: the new vertices and indices of S and B,
// the occupancy raster, the terrain (EH) and the shared lists the landmarks write. A refactor of a landmark has to
// leave every fingerprint as it was; the first one that changes names the landmark. Hashing takes seconds and is not
// counted in HITOS_T.
const HITOS_T={},HITOS_H=window.__HITOS_HASH?{}:null;window.__hitos={t:HITOS_T,h:HITOS_H};
function hitoClock(B,S){let t=performance.now();const last={S:[S.nv,S.ni],B:[B.nv,B.ni]};
  const fnv=(h,u)=>{for(let i=0;i<u.length;i++)h=Math.imul(h^u[i],16777619);return h>>>0;};
  const bytes=a=>new Uint8Array(a.buffer,a.byteOffset,a.byteLength),hx=h=>h.toString(16).padStart(8,'0');
  const txt=x=>{const s=JSON.stringify(x,(k,v)=>typeof v==='function'?undefined:v instanceof RegExp?String(v):v)??'';let h=0x811c9dc5;for(let i=0;i<s.length;i++)h=Math.imul(h^s.charCodeAt(i),16777619);return hx(h>>>0);};
  const gb=(G,k)=>{const [v0,i0]=last[k];let h=0x811c9dc5;h=fnv(h,bytes(G.P.subarray(v0*3,G.nv*3)));h=fnv(h,bytes(G.N.subarray(v0*3,G.nv*3)));
    h=fnv(h,bytes(G.C.subarray(v0*3,G.nv*3)));h=fnv(h,bytes(G.I.subarray(i0,G.ni).map(i=>i-v0)));last[k]=[G.nv,G.ni];return hx(h)+'/'+(G.nv-v0);};
  const grid=g=>{let h=0x811c9dc5;g.c.forEach((c,i)=>{if(c){h=fnv(h,new Uint8Array(new Uint32Array([i]).buffer));h=fnv(h,c);}});return hx(h);};
  return id=>{const n=performance.now();HITOS_T[id]=Math.round((n-t)*10)/10;
    if(HITOS_H)HITOS_H[id]={S:gb(S,'S'),B:gb(B,'B'),dy:[S.dy,B.dy],occ:grid(occ),EH:hx(fnv(0x811c9dc5,bytes(EH))),
      models:txt(MODELS),pads:txt(PADS),glow:txt(GLOW),nolots:txt(NOLOTS),trees:txt(TREES),clear:txt([CLEAR,CLEAR_T,LAMP_SKIP]),
      rail:txt(RAIL_BR),streets:txt(streets.map(s=>[s.c,s.name,s.bridge,s.paint,s.lanes])),usos:txt(USOS.map(u=>u.keep))};
    t=performance.now();};}
// The landmarks' base palette, docs/ESTETICA.md §4 in code: a landmark's palette starts from it, K={...KH, <its own
// colours>}, and a colour of its own under a name of KH replaces that tone (where the photos say otherwise). Also the
// colours of the shared objects (palmS, flagS)
const KH=Object.freeze({brick:hex('#A04B34'),brick2:hex('#8F4330'),white:hex('#ECE7DC'),white2:hex('#D3CDC0'),plinth:hex('#C9C3B6'),
  rim:hex('#EEE8DA'),tile:hex('#A35C42'),tile2:hex('#8E4F3A'),flat:hex('#8F8A82'),membrane:hex('#F0EFE9'),membrane2:hex('#D8D6CE'),
  glass:hex('#3B4653'),glass2:hex('#2C3540'),office:hex('#4D5D66'),door:hex('#5A4636'),opening:hex('#2E2C2B'),copper:hex('#3F5C4E'),
  iron:hex('#3A3A3A'),mast:hex('#707070'),grass:hex('#5F9840'),grass2:hex('#72AC4D'),step:hex('#D9D3C5'),step2:hex('#C6BFAF'),
  palmTrunk:hex('#6E5B48'),palmCrown:hex('#4E7A3C'),palmFrond:hex('#5F8C45'),palmFrond2:hex('#4E7A3A'),
  pole:hex('#D9D9D6'),flagRed:hex('#C8322B'),flagBlue:hex('#2B4C8C'),flagWhite:hex('#F2F0EA')});
// polygon tools for the landmarks (with ringArea, toCCW and convexHull of 15-utils.js, insetRing and clipHalf of
// 52-edificios.js): pairs() turns a flat list [x0,y0,x1,y1,…] (how the long outlines are written) into points
const pairs=a=>{const o=[];for(let i=0;i<a.length;i+=2)o.push([a[i],a[i+1]]);return o;};
// A walled ground's own furniture (the Cementerio, the Regimiento, the colleges, the gym, the casino), in (u,v) of its
// frame. keepOut(m0): the boxes its random graves and trees keep off, {all, bl, has, hits}: bl(u0,v0,u1,v1,m=m0) adds one
// grown by m, has(u,v) says if a point is strictly inside one, hits(u0,v0,u1,v1) if a rectangle overlaps one; indexed in
// cells of 16 m (the Cementerio asks ~30 000 times)
function keepOut(m0=2){const cells=new Map(),C=16,key=(i,j)=>i*65536+j,all=[];
  return {all,bl:(u0,v0,u1,v1,m=m0)=>{const o=[u0-m,v0-m,u1+m,v1+m];all.push(o);
      for(let i=Math.floor(o[0]/C);i<=Math.floor(o[2]/C);i++)for(let j=Math.floor(o[1]/C);j<=Math.floor(o[3]/C);j++){const k=key(i,j);let c=cells.get(k);if(!c)cells.set(k,c=[]);c.push(o);}},
    has:(u,v)=>{const c=cells.get(key(Math.floor(u/C),Math.floor(v/C)));return !!c&&c.some(o=>u>o[0]&&u<o[2]&&v>o[1]&&v<o[3]);},
    hits:(u0,v0,u1,v1)=>{for(let i=Math.floor(u0/C);i<=Math.floor(u1/C);i++)for(let j=Math.floor(v0/C);j<=Math.floor(v1/C);j++){
      const c=cells.get(key(i,j));if(c&&c.some(o=>u0<o[2]&&u1>o[0]&&v0<o[3]&&v1>o[1]))return true;}return false;}};}
// treeAt(F, ok, rr): plant(u, v, s), a round tree of scale s (TREES) at (u,v) of frame F where ok(u,v) and the point
// is in the commune; its seed is rr(), drawn only for a tree that is planted
function treeAt(F,ok,rr){return (u,v,s)=>{const p=F.G(u,v);if(ok(u,v)&&inTerrain(p[0],p[1]))TREES.push([p[0],p[1],s,rr()]);};}
// scatterTrees(rr, poly, n, s0, ok, plant): a grove of up to n trees of scale s0..s0+0.5 at random points of poly
// (its box, then pip) where ok(x,y), at most 40 n tries
function scatterTrees(rr,poly,n,s0,ok,plant){let k=0,bb=[1e9,1e9,-1e9,-1e9];for(const p of poly)bb=[Math.min(bb[0],p[0]),Math.min(bb[1],p[1]),Math.max(bb[2],p[0]),Math.max(bb[3],p[1])];
  for(let g=0;g<n*40&&k<n;g++){const x=bb[0]+rr()*(bb[2]-bb[0]),y=bb[1]+rr()*(bb[3]-bb[1]);if(pip([x,y],poly)&&ok(x,y)){plant(x,y,s0+rr()*.5);k++;}}}
// ownTracks(ring): the map's tracks (class 7, the cicloconecta graph) with half their points or more inside the ring
// of grid metres become the landmark's own (s.bridge: the map does not draw them), for a ground that draws its paths
function ownTracks(ring){for(const s of streets)if(s.c===7){let k=0;for(const p of s.pts)if(inRing(p[0],p[1],ring))k++;if(k*2>=s.pts.length)s.bridge=true;}}
// occFill(ring, margin): marks the ring's cells in occ (1, like occMark), leaving margin m free along the map's streets
// (usosPlan's rule: the sidewalks, street trees and parked cars stay). A landmark that covers a land use with it makes
// usosPlan skip that use (trap «Un hito sobre un uso de suelo lo saca entero»)
function occFill(ring,m){let y0=1e9,y1=-1e9;for(const p of ring){y0=Math.min(y0,p[1]);y1=Math.max(y1,p[1]);}
  for(let gy=Math.max(0,Math.floor((y0-YMIN)/OC));gy<=Math.min(ocH-1,Math.floor((y1-YMIN)/OC));gy++){const cy=YMIN+(gy+.5)*OC,xs=pipRow(ring,cy,[]);
    for(let i=0;i+1<xs.length;i+=2)for(let gx=Math.max(0,Math.ceil((xs[i]-XMIN)/OC-.5));gx<=Math.min(ocW-1,Math.floor((xs[i+1]-XMIN)/OC-.5));gx++){
      if(occ.get(gx,gy)===1)continue;if(!nearStreet(XMIN+(gx+.5)*OC,cy,m))occ.set(gx,gy,1);}}}
// Flat layers on the terrain where a landmark has no pad (trap «Capas planas sin explanada»): the layer is
// filled in a GB of its own, cut along the terrain's edges and laid on it (drape()), and its triangles copied to S with
// the normal [0,1,0] (EN() is still zero in buildModels), at S.dy 0 (S.dy is put back after).
function drapeInto(S,G){const d=drape(G),sv=S.dy;S.dy=0;
  for(let t=0;t<d.ni;t+=3){const k=d.I[t]*3;S.face([0,1,2].map(j=>{const m=d.I[t+j]*3;return [d.P[m],d.P[m+1],d.P[m+2]];}),[0,1,0],[d.C[k],d.C[k+1],d.C[k+2]]);}
  S.dy=sv;}
// groundLayer(S, cap, F): such a layer, {G, lay, rc, pl, done}: G the GB (cap: its first size, ribbon(G, …) draws in
// it), lay(q, o, col) a ring of grid metres at o over the ground (one of fewer than three points is skipped), with F
// (localFrame) rc(u0, v0, u1, v1, o, col) a (u,v) rectangle and pl(pts, o, col) a (u,v) ring; done() lays it on S.
// Heights: trap «Capas planas sin explanada»
function groundLayer(S,cap,F){const G=new GB(cap),lay=(q,o,c)=>{if(q.length>2)G.flat(q,o,c);};
  return {G,lay,rc:F&&((u0,v0,u1,v1,o,c)=>lay(F.R(u0,v0,u1,v1),o,c)),pl:F&&((pts,o,c)=>lay(F.Gs(pts),o,c)),done:()=>drapeInto(S,G)};}
// onFinalTerrain(fn): runs fn on the final terrain from inside buildModels, where E() is the terrain without pads
// (trap «E() dentro de buildModels…»): the pads registered so far are applied to EH (applyPads) while fn
// runs and EH is put back after, also if fn throws. It sees only the pads of the landmarks before it in ORDER
function onFinalTerrain(fn){const keep=EH.slice();applyPads();try{return fn();}finally{EH.set(keep);}}
// buildModels(B, S): the landmarks, src/js/hitos/<id>.js pasted at /*HITOS*/ in the order of hitos/ORDER (build.py).
// Every landmark draws on S (no window shader: each one draws its own windows); B, the mesh with procedural windows,
// is there for a landmark that wants them, and none does today. A landmark is a block {…} of its own: what it declares
// stays in it, and what the landmarks share is declared here, in this header, never in a landmark (tools/check.py fails
// when a landmark uses a name another one declares). The shared state they write, which the landmarks after them read
// (so their order matters; hitos/ORDER says where):
//   MODELS[id]: each landmark's point and height; MODELS['plaza-de-armas'].pad is the pad height the buildings round
//     the plaza take (memorial, Catedral, GORE, Municipalidad, Servicios Públicos, Torre Talca), so that their pads,
//     which share terrain nodes, stay level (trap «Explanadas vecinas»);
//   PADS (padAt), which onFinalTerrain() applies: it sees only the pads registered before it;
//   TREES: deckBridge() removes those under its deck (puentes-rio-claro, after parque-rio-claro);
//   streets[i].bridge: a street a landmark draws itself (bridges; the tracks inside a ground, ownTracks()), which the
//     map skips and calles-plaza leaves alone;
//   occ, NOLOTS, GLOW, CLEAR, CLEAR_T, LAMP_SKIP, RAIL_BR, USOS[i].keep: read after buildModels.
function buildModels(B,S){ // S: models drawn without the window shader
  const __HT=hitoClock(B,S); // build.py calls it after each landmark
  const C=hex;
  // a Canary palm (ringed trunk, dark crown, eight arched fronds in two greens) and a Chilean flag on a pole, both on S
  // at S.dy, in grid metres (the Plaza de Armas, the GORE, the Municipalidad, the Parque Río Claro, the casino)
  const palmS=(x,y,h,r0=0)=>{const tr=KH.palmTrunk,cr=KH.palmCrown,fr=[KH.palmFrond,KH.palmFrond2];occMark(rotRect(x,y,3,3));
    for(let z=0.3,k=0;z<h-.6;z+=1.2,k++)S.prism(ngon(x,y,k%2?.45:.5,6),z,Math.min(z+1.2,h-.6),k%2?shade(tr,.9):tr,tr);
    S.prism(ngon(x,y,.8,6),h-.6,h+.3,cr,cr);
    for(let i=0;i<8;i++){const t=r0+i*Math.PI/4,c=Math.cos(t),s=Math.sin(t),P=(d,w,z)=>[x+c*d-s*w,z,-(y+s*d+c*w)];
      S.face([P(.3,-.3,h+.2),P(.3,.3,h+.2),P(2.2,.7,h+.6),P(2.2,-.7,h+.6)],null,fr[i%2]);
      S.face([P(2.2,-.7,h+.6),P(2.2,.7,h+.6),P(4,.25,h-1),P(4,-.25,h-1)],null,fr[i%2]);}};
  const flagS=(x,y,h0,ph)=>{const pole=KH.pole,f=(x0,x1,z0,z1,c)=>{const t=h0+ph-.2;
      for(const sg of [1,-1])S.face([[x+x0,t-z1,-y],[x+x1,t-z1,-y],[x+x1,t-z0,-y],[x+x0,t-z0,-y]],[0,0,sg],c);};
    S.prism(rotRect(x,y,.22,.22),h0,h0+ph,pole,pole);f(.1,2.2,.75,1.5,KH.flagRed);f(.1,.85,0,.75,KH.flagBlue);f(.85,2.2,0,.75,KH.flagWhite);};
  // wallPath(pts, closed, h, w, wall, cap, gaps): a wall of thickness w along the grid points pts, on the left of its
  // direction, h high with a cap 0.3 m wider and 0.3 m taller, in pieces of ≤8 m on their lowest corner; gaps [x, y, r]
  // leave an opening r each side of the point. wallRing(ring, …) closes a ring with its wall on the inside (the
  // Cementerio, the Regimiento, the colleges, the casino)
  const wallPath=(pts,closed,h,w,wall,cap,gaps=[],sg=1)=>{
    for(let i=0;i<pts.length-(closed?0:1);i++){const a=pts[i],b=pts[(i+1)%pts.length],L=Math.hypot(b[0]-a[0],b[1]-a[1]);if(L<.5)continue;
      const tx=(b[0]-a[0])/L,ty=(b[1]-a[1])/L,nx=-ty*sg,ny=tx*sg,cuts=[];
      for(const [gx,gy,gr] of gaps){const tg=(gx-a[0])*tx+(gy-a[1])*ty,d=Math.abs((gx-a[0])*nx+(gy-a[1])*ny);if(d<gr+w&&tg>-gr&&tg<L+gr)cuts.push([tg-gr,tg+gr]);}
      cuts.sort((p,q)=>p[0]-q[0]);
      const P=(s,o)=>[a[0]+tx*s+nx*o,a[1]+ty*s+ny*o],run=(s,e)=>{if(e-s<.4)return;const n=Math.ceil((e-s)/8);
        for(let k=0;k<n;k++){const s0=s+(e-s)*k/n,s1=s+(e-s)*(k+1)/n,q=[P(s0,0),P(s1,0),P(s1,w),P(s0,w)];S.dy=groundMin(q);
          S.prism(q,.3,h,wall,wall,false);S.prism([P(s0,-.15),P(s1,-.15),P(s1,w+.15),P(s0,w+.15)],h,h+.3,cap,cap);}};
      let t=0;for(const [c0,c1] of cuts){if(c0>t)run(t,c0);t=Math.max(t,c1);}if(t<L)run(t,L);}
    S.dy=0;};
  const wallRing=(ring,h,w,wall,cap,gaps)=>wallPath(ring,true,h,w,wall,cap,gaps,ringArea(ring)>0?1:-1);
  /*HITOS*/
  // ==== fin de los hitos ====
  B.dy=0;S.dy=0;
}


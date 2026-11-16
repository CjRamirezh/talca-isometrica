// ==== overlay: pins + labels ====
const overlay=$('#overlay');
const pinEls=new Map();
POIS.forEach(p=>{const b=document.createElement('button');b.className='pin';b.style.setProperty('--cc',`var(--c-${p.c})`);b.setAttribute('aria-label',p.n);
  b.innerHTML=`<span class="coin">${icon(p.c)}</span><span class="lbl">${esc(p.n)}</span>`;b.addEventListener('click',e=>{e.stopPropagation();select(p.id,true);});overlay.appendChild(b);pinEls.set(p.id,b);});
// street labels
const SL=[];
(function(){const want=new Map();
  streets.forEach(s=>{if(!s.name)return;const nm=s.name.replace(/^(Calle|Avenida) (\d+ )/,'$2').replace("Avenida Alameda Bernardo O'Higgins","Alameda");
    const grid=/^\d+ (Norte|Sur|Oriente|Poniente)$/.test(nm);if(!grid&&s.c>3&&nm!=='Alameda')return;
    if(!want.has(nm))want.set(nm,[]);want.get(nm).push(s);});
  want.forEach((list,nm)=>{let acc=0;const every=nm==='Alameda'?900:650;
    list.forEach(s=>{for(let i=0;i<s.pts.length-1;i++){const a=s.pts[i],b=s.pts[i+1];const L=Math.hypot(b[0]-a[0],b[1]-a[1]);if(L<30){acc+=L;continue;}
      if(acc<=0||acc>every){const m=[(a[0]+b[0])/2,(a[1]+b[1])/2];if(Math.abs(m[0])<3200&&Math.abs(m[1])<3400){SL.push({t:nm,x:m[0],y:m[1],dx:b[0]-a[0],dy:b[1]-a[1],w:false});acc=1;}}else acc+=L;}});});
  // the countryside's main roads: the named routes and caminos of OSM (trunk to tertiary), sparsely, on stretches of
  // 60 m or more away from the urban area; shown from farther out than the city's streets (r)
  const RURAL={'Avenida San Miguel':'Ruta 115-CH a San Clemente'}; // its name in OSM all the way out; the ref and the destination are OSM's
  const rural=new Map();streets.forEach(s=>{if(!s.name||s.c>3||!(/^(Ruta|Camino) /.test(s.name)||RURAL[s.name]))return;const t=RURAL[s.name]||s.name;
    if(!rural.has(t))rural.set(t,[]);rural.get(t).push(s);});
  rural.forEach((list,t)=>{let acc=0;list.forEach(s=>{for(let i=0;i<s.pts.length-1;i++){const a=s.pts[i],b=s.pts[i+1],L=Math.hypot(b[0]-a[0],b[1]-a[1]),m=[(a[0]+b[0])/2,(a[1]+b[1])/2];
    if(L<60||urbanAt(...m)||!inTerrain(...m)||(acc>0&&acc<3000)){acc+=L;continue;}SL.push({t,x:m[0],y:m[1],dx:b[0]-a[0],dy:b[1]-a[1],w:false,r:true});acc=1;}});});
  // the rivers: each label on the segment of the OSM axis nearest to its point (grid metres)
  [['Río Claro','claro',-1593,872],['Río Claro','claro',-2916,-1198],['Río Claro','claro',2932,7645],['Río Lircay','lircay',3198,4293],['Río Lircay','lircay',8677,2158],
   ['Estero Piduco','piduco',680,-1264],['Estero Piduco','piduco',2966,-2243],['Estero Piduco','piduco',6654,-3266],
   ['Estero Pangue','panguilemo',9300,8420],['Estero Panguilemo','panguilemo',6300,8640],['Canal Pencahue','pencahue',7600,4780],['Canal Pencahue','pencahue',-1400,2700]].forEach(([t,k,x,y])=>{const pts=dec(DATA.water[k]);
    let i=0,bd=1e18;for(let j=0;j<pts.length-1;j++){const d=segDist2(x,y,pts[j][0],pts[j][1],pts[j+1][0],pts[j+1][1]);if(d<bd){bd=d;i=j;}}const a=pts[i],b=pts[i+1];SL.push({t,x:(a[0]+b[0])/2,y:(a[1]+b[1])/2,dx:b[0]-a[0],dy:b[1]-a[1],w:true});});
  SL.forEach(l=>{const e=document.createElement('div');e.className='street'+(l.w?' water':l.r?' rural':'');e.textContent=l.t;overlay.appendChild(e);l.el=e;});
})();
let showStreets=true;
const vtmp=new T.Vector3();
function proj(x,y,h){vtmp.set(x,h,-y).project(cam);return [(vtmp.x+1)/2*VW,(1-vtmp.y)/2*VH];}
function visibleP(p){if(enabled.has(p.c))return true;for(const c of p.cs)if(enabled.has(c))return true;return false;}
// layout(), after every frame drawn: the pins (the selected one first, then by priority: the order is made again only
// when the selection changes) and the street labels, each hidden where it would overlap one placed before it; the
// compass and the scale bar. The DOM is written only where something changed (LAY: what each element was given
// last), since a frame drawn while the map moves would otherwise write ~300 elements for nothing
const LAY=new WeakMap(),laySt=el=>{let s=LAY.get(el);if(!s)LAY.set(el,s={});return s;};
const layHide=(el,v)=>{const s=laySt(el);if(s.h!==v){s.h=v;el.hidden=v;}};
const layMove=(el,t)=>{const s=laySt(el);if(s.t!==t){s.t=t;el.style.transform=t;}};
const layClass=(el,c,on)=>{const s=laySt(el),k='c'+c;if(s[k]!==on){s[k]=on;el.classList.toggle(c,on);}};
const PIN_MINZ=[0,0.9,1.9,3.2],PIN_LBLZ=[0.5,1.6,3.0,6],SCALES=[10,20,50,100,200,500,1000,2000,5000];
const compassSvg=$('#compass svg'),scaleBar=$('#sc-i'),scaleTxt=$('#sc-t');
let layList=null,laySel;
function layout(){
  const rects=[];const hit=(r)=>{for(const q of rects)if(r[0]<q[2]&&r[2]>q[0]&&r[1]<q[3]&&r[3]>q[1])return true;return false;};
  const z=view.zoom;
  if(!layList||laySel!==selId){layList=POIS.slice().sort((a,b)=>(b.id===selId)-(a.id===selId)||a.p-b.p);laySel=selId;}
  for(const p of layList){const el=pinEls.get(p.id),sel=p.id===selId;
    if(!(visibleP(p)||sel)||(z<PIN_MINZ[p.p]&&!sel)){layHide(el,true);continue;}
    const m=MODELS[p.id],s=proj(m?m.x:p.x,m?m.y:p.y,m?m.h:E(p.x,p.y)+6);
    if(s[0]<-40||s[1]<-40||s[0]>VW+40||s[1]>VH+60){layHide(el,true);continue;}
    const small=p.p>=3&&!sel;layClass(el,'small',small);
    const cs=small?20:26,stem=small?10:14;
    const x=s[0]-cs/2,y=s[1]-cs-stem;
    const coinR=[x,y,x+cs,y+cs];
    if(!sel&&hit(coinR)&&p.p>=1){layHide(el,true);continue;}
    layHide(el,false);layMove(el,`translate(${x.toFixed(1)}px,${y.toFixed(1)}px)`);rects.push(coinR);
    const lw=Math.min(290,p.n.length*6.9+16);const lr=[x+cs+4,y+2,x+cs+4+lw,y+cs-2];
    const wantL=sel||z>=PIN_LBLZ[p.p];
    if(wantL&&(sel||!hit(lr))){layClass(el,'nolbl',false);rects.push(lr);}else layClass(el,'nolbl',true);
    layClass(el,'sel',sel);
  }
  const sz=z>=2.6&&showStreets;
  for(const l of SL){if(l.r?(z<0.45||!showStreets):(!sz&&!l.w)||(l.w&&z<0.5)){layHide(l.el,true);continue;}
    if(l.h==null)l.h=E(l.x,l.y)+0.3;const s=proj(l.x,l.y,l.h);if(s[0]<0||s[1]<0||s[0]>VW||s[1]>VH){layHide(l.el,true);continue;}
    const s2=proj(l.x+l.dx,l.y+l.dy,l.h);let ang=Math.atan2(s2[1]-s[1],s2[0]-s[0]);if(ang>Math.PI/2)ang-=Math.PI;if(ang<-Math.PI/2)ang+=Math.PI;
    const w=l.t.length*(l.w?7:l.r?6.2:6.6),hgt=14;const c=Math.abs(Math.cos(ang)),sn=Math.abs(Math.sin(ang));const bw=w*c+hgt*sn,bh=w*sn+hgt*c;
    const r=[s[0]-bw/2,s[1]-bh/2,s[0]+bw/2,s[1]+bh/2];if(hit(r)){layHide(l.el,true);continue;}rects.push(r);
    layHide(l.el,false);layMove(l.el,`translate(${(s[0]-w/2).toFixed(1)}px,${(s[1]-7).toFixed(1)}px) rotate(${ang.toFixed(3)}rad)`);}
  // compass
  const n0=proj(view.tx,view.ty,0),n1=proj(view.tx,view.ty+100,0);const ca=Math.atan2(n1[0]-n0[0],-(n1[1]-n0[1]));layMove(compassSvg,`rotate(${ca}rad)`);
  // scale bar
  const mpp=wpp();const target=90*mpp;const nice=SCALES.find(v=>v>=target)||5000,barW=(nice/mpp).toFixed(0)+'px',bt=nice>=1000?`${nice/1000} km`:`${nice} m`,st=laySt(scaleBar);
  if(st.w!==barW){st.w=barW;scaleBar.style.width=barW;}if(st.x!==bt){st.x=bt;scaleTxt.textContent=bt;}
}


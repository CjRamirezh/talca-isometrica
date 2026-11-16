/* =============== utils =============== */
function rng(seed){let a=seed>>>0;return()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
// T.ShapeUtils.triangulateShape on [x,y] rings: index triples into the ring followed by its holes, or null when it
// throws (a degenerate ring). Every polygon dropped that way is counted in TRI_FAIL (__stats.triFail), so that it is
// not lost in silence: tools/screenshot.py --strict (make smoke) fails when it is not 0
let TRI_FAIL=0;
function triangulate(ring,holes){const V=a=>a.map(p=>new T.Vector2(p[0],p[1]));
  try{return T.ShapeUtils.triangulateShape(V(ring),holes?holes.map(V):[]);}catch(e){TRI_FAIL++;return null;}}
const pick=(r,arr)=>arr[Math.floor(r()*arr.length)];
// wpick(r, arr, w): the index of an element of arr drawn by weight (w(e): its weight; without w, arr holds the weights);
// one r() call. The roof families (fam), the barrios' recipes, the cars' colours
const wpick=(r,arr,w)=>{let t=0;for(const e of arr)t+=w?w(e):e;let x=r()*t;for(let k=0;k<arr.length;k++){x-=w?w(arr[k]):arr[k];if(x<0)return k;}return arr.length-1;};
const hex=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
const shade=(c,f)=>[Math.min(255,c[0]*f),Math.min(255,c[1]*f),Math.min(255,c[2]*f)];
function pipXY(x,y,r){let ins=false;for(let i=0,j=r.length-1;i<r.length;j=i++){const xi=r[i][0],yi=r[i][1],xj=r[j][0],yj=r[j][1];if(((yi>y)!==(yj>y))&&(x<(xj-xi)*(y-yi)/(yj-yi)+xi))ins=!ins;}return ins;}
const pip=(pt,r)=>pipXY(pt[0],pt[1],r);
// inRing(x, y, r): pipXY with the ring's box first, kept in RING_BB (for rings that do not change: the rivers, NOLOTS).
// A point more than 1 m outside the box is outside for pipXY too: no edge straddles its y, or every one it could cross
// lies to its right, an even number of them. The margin covers the rounding of the crossing's x.
const RING_BB=new WeakMap(),ringBox=r=>{let b=RING_BB.get(r);if(!b){b=[1e9,1e9,-1e9,-1e9];for(const p of r){b[0]=Math.min(b[0],p[0]);b[1]=Math.min(b[1],p[1]);b[2]=Math.max(b[2],p[0]);b[3]=Math.max(b[3],p[1]);}RING_BB.set(r,b);}return b;};
const inRing=(x,y,r)=>{const b=ringBox(r);return x>b[0]-1&&y>b[1]-1&&x<b[2]+1&&y<b[3]+1&&pipXY(x,y,r);};
// pipRow(r, y, xs): into xs, sorted, the x where the edges of ring r cross the line at y, computed exactly as pipXY()
// does; (x, y) is inside r, as pipXY() says, when an odd number of them is greater than x. For a row of points
// (a raster, the relief's nodes) instead of a pip per point: same answers, one pass over the ring per row
function pipRow(r,y,xs){xs.length=0;for(let i=0,j=r.length-1;i<r.length;j=i++){const xi=r[i][0],yi=r[i][1],xj=r[j][0],yj=r[j][1];if((yi>y)!==(yj>y))xs.push((xj-xi)*(y-yi)/(yj-yi)+xi);}
  return sortRow(xs);}
const sortRow=xs=>{for(let i=1;i<xs.length;i++){const v=xs[i];let k=i-1;while(k>=0&&xs[k]>v){xs[k+1]=xs[k];k--;}xs[k+1]=v;}return xs;}; // insertion sort: a row crosses a ring a few times
// rowCross(rings, y, xs): pipRow over several rings (even-odd: a polygon and its holes). With first, each edge's
// crossing is computed from its first vertex (r[i] to r[i+1]) instead of pipRow's second: the commune's limit (CM) and
// the rivers' areas were filled that way, and the two can differ in the last bit
function rowCross(rings,y,xs,first){xs.length=0;
  for(const r of rings)for(let i=0,j=r.length-1;i<r.length;j=i++){const P=first?r[j]:r[i],Q=first?r[i]:r[j];
    if((r[i][1]>y)!==(r[j][1]>y))xs.push((Q[0]-P[0])*(y-P[1])/(Q[1]-P[1])+P[0]);}
  return sortRow(xs);}
// rowCells(xs, x0, c, n, f): a scanline fill's row: f(g) for every cell g (0..n-1, of size c from x0) whose centre lies
// between a pair of crossings xs (rowCross: inside them, the edges included)
function rowCells(xs,x0,c,n,f){for(let m=0;m+1<xs.length;m+=2)for(let g=Math.max(0,Math.ceil((xs[m]-x0)/c-.5));g<=Math.min(n-1,Math.floor((xs[m+1]-x0)/c-.5));g++)f(g);}
// clipKeep(q, d): the part of polygon q where d(p) >= 0, for a d linear in p (a half-plane; Sutherland–Hodgman's step)
function clipKeep(q,d){const o=[];
  for(let k=0;k<q.length;k++){const p=q[k],r=q[(k+1)%q.length],dp=d(p),dr=d(r);if(dp>=0)o.push(p);
    if((dp>=0)!==(dr>=0)){const u=dp/(dp-dr);o.push([p[0]+(r[0]-p[0])*u,p[1]+(r[1]-p[1])*u]);}}
  return o;}
// splitAt(q, fq, k, A, B): polygon q cut by the line where a linear function, fq at q's points, is k: its part at or
// below k into A, at or above into B (a point on the line goes to both)
function splitAt(q,fq,k,A,B){for(let i=0;i<q.length;i++){const i1=i+1<q.length?i+1:0,p=q[i],r=q[i1],fp=fq[i],fr=fq[i1];
    if(fp<=k)A.push(p);if(fp>=k)B.push(p);
    if((fp<k&&fr>k)||(fp>k&&fr<k)){const t=(k-fp)/(fr-fp),m=[p[0]+(r[0]-p[0])*t,p[1]+(r[1]-p[1])*t];A.push(m);B.push(m);}}}
// ringArea(r): the signed area of ring r (counter-clockwise > 0); toCCW(q): q counter-clockwise (a reversed copy if not)
const ringArea=r=>{let A=0;for(let i=0;i<r.length;i++){const p=r[i],q=r[(i+1)%r.length];A+=p[0]*q[1]-q[0]*p[1];}return A/2;};
const toCCW=q=>ringArea(q)<0?q.slice().reverse():q;
// convexHull(r): the convex hull of r's points, counter-clockwise (Andrew's monotone chain; collinear points left out)
function convexHull(r){const P=r.slice().sort((a,b)=>a[0]-b[0]||a[1]-b[1]),lo=[],hi=[];
  for(const p of P){while(lo.length>1&&cross3(lo[lo.length-2],lo[lo.length-1],p)<=0)lo.pop();lo.push(p);}
  for(let i=P.length-1;i>=0;i--){const p=P[i];while(hi.length>1&&cross3(hi[hi.length-2],hi[hi.length-1],p)<=0)hi.pop();hi.push(p);}
  return lo.slice(0,-1).concat(hi.slice(0,-1));}
const cross3=(o,a,b)=>(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0]); // > 0: o, a, b turn left
// PolyPath(pts): a polyline by distance: d[i] the length of segment i, S[i] the distance to point i (summed in order),
// L the whole; seg(u) the segment that holds distance u (the first that ends at or past it; past the end, the last)
class PolyPath{constructor(pts){const n=pts.length;this.p=pts;this.d=new Float64Array(Math.max(0,n-1));this.S=new Float64Array(n);
    for(let i=0;i+1<n;i++){this.d[i]=Math.hypot(pts[i+1][0]-pts[i][0],pts[i+1][1]-pts[i][1]);this.S[i+1]=this.S[i]+this.d[i];}this.L=n?this.S[n-1]:0;}
  seg(u){let lo=0,hi=this.p.length-2;while(lo<hi){const m=(lo+hi)>>1;if(this.S[m+1]<u)lo=m+1;else hi=m;}return lo;}}
// bbox(q): [x0, y0, x1, y1] of points q (ringBox keeps it for rings that do not change)
const bbox=q=>{let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;for(const p of q){if(p[0]<x0)x0=p[0];if(p[0]>x1)x1=p[0];if(p[1]<y0)y0=p[1];if(p[1]>y1)y1=p[1];}return [x0,y0,x1,y1];};
function segDist2(px,py,ax,ay,bx,by){const dx=bx-ax,dy=by-ay;const L=dx*dx+dy*dy;let t=L?((px-ax)*dx+(py-ay)*dy)/L:0;t=t<0?0:t>1?1:t;const x=ax+t*dx-px,y=ay+t*dy-py;return x*x+y*y;}


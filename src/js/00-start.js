(async function(){
"use strict";
const T_SCRIPT=performance.now(); // when the script starts running (after the download and three.js): __stats.load
const $=s=>document.querySelector(s);
const loadMsg=t=>{$('#load-msg').textContent=t};
const fail=t=>{$('#loading').classList.remove('over');$('#err').hidden=false;$('#err').textContent=t;};
// an uncaught error while the map is generated (in boot() or a slice of rest(): window's error and unhandledrejection)
// stops the generation for good, and the loading message used to stay on screen forever. Before the first frame (the
// loading screen still covers the map) it says so there; after it, the map drawn so far stays and #more says the rest
// is missing. Once the generation is over (window.__stats) errors are left to the console
const genFail=()=>{if(window.__stats)return;const l=$('#loading'),m=$('#more');
  if(l.style.opacity==='0'&&m){m.hidden=false;m.textContent='No se pudo levantar el resto de la comuna. Recargue la página.';}
  else fail('No se pudo levantar la maqueta. Recargue la página.');};
window.addEventListener('error',genFail);window.addEventListener('unhandledrejection',genFail);
if(!window.THREE)return fail('No se pudo cargar la librería 3D (three.js). Revise su conexión y recargue la página.');
// the data that src/page.html asked for (window.__data): DATA is data/geometry.json (with the land uses, build.py) and
// the other files of data/ in it; PD the places and tours (data/pois.json)
let L;try{L=await window.__data;}catch(e){console.error(e);
  return fail(location.protocol==='file:'?'La maqueta no se puede abrir como archivo: sírvala con make serve.':'No se pudieron cargar los datos del mapa. Revise su conexión y recargue la página.');}
const DATA=Object.assign(L.geo,{elev:L.elev,r5:L.r5,ed:L.ed,golf:L.golf,cob:L.cob}),PD=L.pois;
const T=THREE;


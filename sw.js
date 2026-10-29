/* Varv – offlineläge: sidan och ikonerna sparas så att appen fungerar utan nät. */
const CACHE="varv-v1";
const FILES=["./","index.html","manifest.webmanifest","icons/icon.svg","icons/icon-192.png","icons/icon-512.png","icons/apple-touch-icon.png","icons/favicon-32.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(n=>n!==CACHE).map(n=>caches.delete(n)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{
  const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
  // nätet först för sidan så att uppdateringar syns direkt, cache när nätet saknas
  e.respondWith(fetch(r).then(res=>{const copy=res.clone();caches.open(CACHE).then(c=>c.put(r,copy));return res}).catch(()=>caches.match(r).then(m=>m||caches.match("index.html"))));
});

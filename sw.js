// Per la Maglia — service worker: the game works offline after the first visit.
const CACHE = "perlamaglia-v43";
const NEW = "https://perlamaglia.com/";
const CORE = ["./", "./index.html", "./trasloco.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png",
  "./fonts/bigshouldersdisplay.woff", "./fonts/barlowcondensed-Medium.woff", "./fonts/barlowcondensed-SemiBold.woff", "./fonts/barlowcondensed-Bold.woff",
  "./fonts/barlow-Regular.woff", "./fonts/barlow-Medium.woff", "./fonts/barlow-SemiBold.woff"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // the page itself: try the network first so updates arrive, fall back to the cache offline
  if (req.mode === "navigate") {
    // only the game page is stored as the offline copy; privacy and terms pages are cached under their own name
    const root = new URL(self.registration.scope).pathname, isGame = url.pathname === root || url.pathname === root + "index.html";
    // the game has moved to its own address: when this old one answers with a redirect,
    // open the moving page instead, so the player's name, team and points come along
    e.respondWith(fetch(req.url, { cache: "no-store", redirect: "manual", credentials: "same-origin" }).then(r => {
      if (r.type === "opaqueredirect") return isGame ? caches.match("./trasloco.html").then(t => t || Response.redirect(NEW, 302)) : Response.redirect(NEW + url.pathname.replace(new URL(self.registration.scope).pathname, ""), 302);
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(isGame ? "./index.html" : req, copy)); return r; })
      .catch(() => isGame ? caches.match("./index.html") : caches.match(req)));
    return;
  }
  // own files: cache first, refresh in the background
  if (url.origin === location.origin) {
    e.respondWith(caches.match(req).then(hit => {
      const net = fetch(req).then(r => { if (r.ok || r.type === "opaque") { const copy = r.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return r; }).catch(() => hit);
      return hit || net;
    }));
  }
});

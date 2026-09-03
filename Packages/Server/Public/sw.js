const CACHE_NAME = 'homebudget-v2';
const ASSETS = [
  '/',
  '/manifest.json',
  '/icon.svg',
  '/styles.css',
  '/app/index.js',
  '/vendor/browser_wasi_shim.js',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  // Report downloads and anything that changes data always go straight to the network.
  if (e.request.method !== 'GET' || e.request.url.includes('/api/reports/')) {
    e.respondWith(fetch(e.request));
    return;
  }

  // Network first, falling back to whatever was cached on a previous successful load.
  e.respondWith(
    fetch(e.request)
      .then((response) => {
        if (response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(e.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(e.request))
  );
});

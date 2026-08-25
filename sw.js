/* ================================================================
   ENAMED Engine — Service Worker
   Estratégia: NETWORK-FIRST para o app (index.html e navegação).
   Isso garante que toda atualização publicada chegue automaticamente
   ao usuário, sem precisar limpar cache. O cache serve só de
   reserva para quando estiver offline.
   ================================================================ */

const VERSION = 'enamed-v' + '2026-08-25-01';  // troque a data a cada deploy grande
const CACHE = VERSION;

// Arquivos que valem manter em cache como reserva offline.
const ASSETS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
];

// INSTALL: baixa a reserva e assume o controle imediatamente.
self.addEventListener('install', (e) => {
  self.skipWaiting(); // não espera abas antigas fecharem
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS).catch(() => {}))
  );
});

// ACTIVATE: apaga caches de versões antigas e assume as abas abertas.
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// FETCH:
// - Navegação / HTML  -> NETWORK-FIRST (sempre tenta a versão nova online;
//   só usa cache se estiver offline). É isso que faz a atualização ser automática.
// - Outros arquivos   -> cache com atualização em segundo plano (stale-while-revalidate).
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  const isHTML =
    req.mode === 'navigate' ||
    req.destination === 'document' ||
    url.pathname.endsWith('/') ||
    url.pathname.endsWith('index.html');

  if (isHTML) {
    // NETWORK-FIRST: pega sempre o app mais novo quando há internet.
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put('./index.html', copy)).catch(() => {});
          return res;
        })
        .catch(() =>
          caches.match('./index.html').then((r) => r || caches.match('./'))
        )
    );
    return;
  }

  // Demais recursos: responde do cache e atualiza por trás.
  e.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});

// Permite que a página mande o SW ativar na hora (usado no aviso de update).
self.addEventListener('message', (e) => {
  if (e.data === 'skipWaiting') self.skipWaiting();
});

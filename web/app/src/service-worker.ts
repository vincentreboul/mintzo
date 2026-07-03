/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />

/**
 * Service worker Mintzo — PWA installable.
 * Precache : build (JS/CSS versionnés) + static (captures, fontes, icônes).
 * Réseau d'abord pour tout le reste (pages, API) — le cache ne sert que
 * de repli hors connexion. L'API de transcription (autre origine) n'est
 * JAMAIS mise en cache.
 */

const sw = self as unknown as ServiceWorkerGlobalScope;

import { build, files, version } from '$service-worker';

const CACHE = `mintzo-${version}`;
const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
	event.waitUntil(
		caches
			.open(CACHE)
			.then((cache) => cache.addAll(ASSETS))
			.then(() => sw.skipWaiting())
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
			.then(() => sw.clients.claim())
	);
});

sw.addEventListener('fetch', (event) => {
	const { request } = event;
	if (request.method !== 'GET') return;

	const url = new URL(request.url);

	/* autre origine (API de transcription incluse) : réseau pur, zéro cache */
	if (url.origin !== sw.location.origin) return;

	/* assets versionnés : cache d'abord — immuables par construction */
	if (ASSETS.includes(url.pathname)) {
		event.respondWith(
			caches.open(CACHE).then(async (cache) => {
				const hit = await cache.match(url.pathname);
				return hit ?? fetch(request);
			})
		);
		return;
	}

	/* pages : réseau d'abord, repli cache hors connexion */
	event.respondWith(
		(async () => {
			const cache = await caches.open(CACHE);
			try {
				const res = await fetch(request);
				if (res.ok) cache.put(request, res.clone());
				return res;
			} catch {
				const hit = await cache.match(request);
				if (hit) return hit;
				/* navigation hors connexion sans cache : l'outil est le foyer */
				if (request.mode === 'navigate') {
					const home = await cache.match('/tresna');
					if (home) return home;
				}
				throw new Error('offline');
			}
		})()
	);
});

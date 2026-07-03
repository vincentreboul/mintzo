import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// Site 100 % statique (Cloudflare Pages) — toutes les routes sont prérendues,
			// 404.html sert de fallback SPA pour les chemins inconnus.
			adapter: adapter({ fallback: '404.html' })
		})
	],

	// Démo à distance : `vite preview` derrière un tunnel (host dynamique).
	// Sans effet sur le build statique déployé.
	preview: { allowedHosts: true }
});

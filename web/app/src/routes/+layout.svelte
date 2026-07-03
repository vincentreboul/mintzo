<script lang="ts">
	import '../app.css';
	import { initLocale, t } from '$lib/i18n/index.svelte';
	import Header from '$lib/components/Header.svelte';
	import Footer from '$lib/components/Footer.svelte';

	let { children } = $props();

	// Détection de langue au premier chargement (client uniquement).
	$effect(() => {
		initLocale();
	});
</script>

<a class="skip" href="#eduki">{t('common.skip')}</a>
<Header />
<main id="eduki">
	{@render children()}
</main>
<Footer />

<style>
	main {
		flex: 1 0 auto;
	}

	.skip {
		position: absolute;
		left: -100vw;
		top: 0.75rem;
		z-index: 10;
		background: var(--surface);
		color: var(--ink);
		border: 1px solid var(--hairline);
		border-radius: 0.5rem;
		padding: 0.625rem 1rem;
		font-size: 0.875rem;
		text-decoration: none;
	}

	.skip:focus-visible {
		left: 0.75rem;
	}

	:global(body) {
		display: flex;
		flex-direction: column;
	}
</style>

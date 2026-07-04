<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
</script>

<svelte:head>
	<title>{t('privacy.metaTitle')}</title>
	<meta name="description" content={t('privacy.metaDescription')} />
</svelte:head>

<div class="shell page">
	<header class="page-head">
		<h1 class="display title">{t('privacy.title')}</h1>
		<p class="lead">{t('privacy.lead')}</p>
	</header>

	<section>
		<h2 class="display sub">{t('privacy.macHead')}</h2>
		<p>{t('privacy.macP1')}</p>
	</section>

	<section>
		<h2 class="display sub">{t('privacy.cookiesHead')}</h2>
		<p>{t('privacy.cookiesP1')}</p>
	</section>

	<p class="updated tnum">{t('privacy.updated')}</p>
</div>

<style>
	.page {
		max-width: 46rem;
		padding-block: clamp(3rem, 7vw, 5rem) clamp(2rem, 5vw, 3rem);
	}

	.page-head::before {
		content: '';
		display: block;
		width: 2.5rem;
		height: 3px;
		border-radius: 2px;
		background: var(--gorri);
		margin-bottom: 1.5rem;
	}

	.title {
		font-size: clamp(2rem, 5vw, 2.75rem);
	}

	.lead {
		margin-top: 0.875rem;
		font-family: var(--font-read);
		font-optical-sizing: auto;
		font-size: 1.125rem;
		color: var(--ink-2);
	}

	section {
		margin-top: clamp(2.25rem, 5vw, 3rem);
		padding-top: 1.75rem;
		border-top: 1px solid var(--hairline);
	}

	.sub {
		font-size: 1.375rem;
	}

	section p {
		margin-top: 0.875rem;
		font-size: 0.9375rem;
		line-height: 1.7;
		color: var(--ink-2);
		max-width: 62ch;
	}

	.updated {
		margin-top: 3rem;
		font-size: 0.75rem;
		color: var(--ink-3);
	}
</style>

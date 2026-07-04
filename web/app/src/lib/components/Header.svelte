<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import { MAC_DOWNLOAD_URL } from '$lib/links';
	import Logo from './Logo.svelte';
	import LangSwitch from './LangSwitch.svelte';
</script>

<header>
	<div class="shell bar">
		<a href="/" class="home" aria-label="Mintzo — hasiera">
			<Logo compact />
		</a>
		<nav class="right" aria-label="Nabigazioa">
			<LangSwitch />
			<a class="btn btn-primary cta" href={MAC_DOWNLOAD_URL} rel="noopener"
				>{t('common.navDownload')}</a
			>
		</nav>
	</div>
</header>

<style>
	header {
		position: sticky;
		top: 0;
		z-index: 40;
		background: color-mix(in srgb, var(--paper) 84%, transparent);
		-webkit-backdrop-filter: blur(14px);
		backdrop-filter: blur(14px);
		border-bottom: 1px solid var(--hairline);
	}

	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-block: 0.75rem;
	}

	.home {
		text-decoration: none;
		border-radius: 0.375rem;
	}

	.right {
		display: flex;
		align-items: center;
		gap: 1rem;
	}

	.cta {
		min-height: 2.25rem;
		padding: 0.375rem 1.125rem;
		font-size: 0.875rem;
	}
</style>

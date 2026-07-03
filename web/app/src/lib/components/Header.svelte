<script lang="ts">
	import { page } from '$app/state';
	import { t } from '$lib/i18n/index.svelte';
	import Logo from './Logo.svelte';
	import LangSwitch from './LangSwitch.svelte';
</script>

<header>
	<div class="shell bar">
		<a href="/" class="home" aria-label="Mintzo — hasiera">
			<Logo compact />
		</a>
		<nav class="right" aria-label="Nabigazioa">
			{#if page.url.pathname !== '/tresna'}
				<a class="navlink" href="/tresna">{t('common.navTool')}</a>
			{/if}
			<LangSwitch />
		</nav>
	</div>
</header>

<style>
	header {
		border-bottom: 1px solid var(--hairline);
	}

	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-block: 1.125rem;
	}

	.home {
		text-decoration: none;
	}

	.right {
		display: flex;
		align-items: center;
		gap: 1.25rem;
	}

	.navlink {
		font-size: 0.875rem;
		font-weight: 500;
		text-decoration: none;
		color: var(--ink-2);
		transition: color var(--motion-micro);
	}

	.navlink:hover {
		color: var(--gorri);
	}
</style>

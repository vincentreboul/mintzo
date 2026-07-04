<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import { GITHUB_URL } from '$lib/links';
	import Logo from './Logo.svelte';
	import LangSwitch from './LangSwitch.svelte';
</script>

<footer>
	<div class="shell bar">
		<div class="brand">
			<Logo compact />
			<p class="colophon">{t('common.footerLicense')}</p>
		</div>
		<nav class="links" aria-label="Oina">
			<a href="/pribatutasuna">{t('common.footerPrivacy')}</a>
			<a href="/lancement">{t('common.footerAnnouncement')}</a>
			<!-- TODO-URL -->
			<a href={GITHUB_URL} rel="noopener">{t('common.footerGithub')}</a>
		</nav>
		<LangSwitch />
	</div>
</footer>

<style>
	footer {
		border-top: 1px solid var(--hairline);
		margin-top: clamp(3rem, 8vw, 5rem);
		background: var(--surface-2);
	}

	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1.5rem;
		flex-wrap: wrap;
		padding-block: 2.25rem;
	}

	.brand {
		display: grid;
		gap: 0.5rem;
	}

	.colophon {
		font-size: 0.8125rem;
		color: var(--ink-3);
	}

	.links {
		display: flex;
		gap: 1.75rem;
		flex-wrap: wrap;
	}

	.links a {
		font-size: 0.875rem;
		color: var(--ink-2);
		text-decoration: none;
		transition: color var(--motion-micro);
	}

	.links a:hover {
		color: var(--gorri);
	}

	/* cibles tactiles ≥ 44 px sans changer la densité au pointeur fin */
	@media (pointer: coarse) {
		.links a {
			display: inline-flex;
			align-items: center;
			min-height: 2.75rem;
		}
	}

	@media (max-width: 40rem) {
		.bar {
			flex-direction: column;
			align-items: flex-start;
			gap: 1.25rem;
		}
	}
</style>

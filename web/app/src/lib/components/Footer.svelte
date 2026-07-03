<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import { GITHUB_URL } from '$lib/links';
	import LangSwitch from './LangSwitch.svelte';
</script>

<footer>
	<div class="shell bar">
		<p class="colophon">Mintzo · {t('common.footerLicense')}</p>
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
	}

	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1.5rem;
		flex-wrap: wrap;
		padding-block: 1.75rem;
	}

	.colophon {
		font-size: 0.8125rem;
		color: var(--ink-3);
	}

	.links {
		display: flex;
		gap: 1.5rem;
		flex-wrap: wrap;
	}

	.links a {
		font-size: 0.8125rem;
		color: var(--ink-2);
		text-decoration: none;
		transition: color var(--motion-micro);
	}

	.links a:hover {
		color: var(--gorri);
	}

	@media (max-width: 40rem) {
		.bar {
			flex-direction: column;
			align-items: flex-start;
			gap: 1rem;
		}
	}
</style>

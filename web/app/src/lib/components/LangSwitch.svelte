<script lang="ts">
	import { getLocale, setLocale, locales, t } from '$lib/i18n/index.svelte';
</script>

<nav class="langs" aria-label={t('common.langLabel')}>
	{#each locales as l (l)}
		<button
			class="lang"
			class:active={getLocale() === l}
			aria-current={getLocale() === l ? 'true' : undefined}
			onclick={() => setLocale(l)}
		>
			{l}
		</button>
	{/each}
</nav>

<style>
	.langs {
		display: inline-flex;
		align-items: center;
		gap: 0.125rem;
	}

	.lang {
		font-size: 0.6875rem;
		font-weight: 600;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--ink-3);
		padding: 0.375rem 0.4375rem;
		border-radius: 0.25rem;
		transition: color var(--motion-micro);
	}

	.lang:hover {
		color: var(--ink);
	}

	.lang.active {
		color: var(--gorri);
		background: var(--gorri-8);
	}

	.lang + .lang {
		position: relative;
	}

	/* cible tactile ≥ 44 px sans changer la densité au pointeur fin */
	@media (pointer: coarse) {
		.lang {
			min-width: 2.75rem;
			min-height: 2.75rem;
			display: inline-flex;
			align-items: center;
			justify-content: center;
		}
	}
</style>

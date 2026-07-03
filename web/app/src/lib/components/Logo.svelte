<script lang="ts">
	let { compact = false }: { compact?: boolean } = $props();
</script>

<!-- BRAND-MARK: remplacé par assets/brand/lauburu.svg à livraison.
     Le span.mark ci-dessous est l'emplacement réservé du lauburu typographique
     (4 virgules en rotation) en cours de création — pour l'instant, wordmark seul. -->
<span class="logo" class:compact>
	<span class="mark" aria-hidden="true"></span>
	<span class="word">Mintzo</span>
</span>

<style>
	.logo {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		font-family: var(--font-display);
		font-optical-sizing: auto;
		font-weight: 640;
		font-size: 1.3125rem;
		letter-spacing: -0.01em;
		color: var(--ink);
		line-height: 1;
	}

	.compact {
		font-size: 1.1875rem;
	}

	.mark:empty {
		display: none;
	}
</style>

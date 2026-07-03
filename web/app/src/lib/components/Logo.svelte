<script lang="ts">
	let { compact = false }: { compact?: boolean } = $props();
</script>

<!-- Marque : lauburu typographique (4 virgules en rotation) — static/brand/lauburu.svg,
     inliné ici en <img> masqué aux lecteurs d'écran, teinté par currentColor via mask. -->
<span class="logo" class:compact>
	<span class="mark" aria-hidden="true"></span>
	<span class="word">Mintzo</span>
</span>

<style>
	.logo {
		display: inline-flex;
		align-items: center;
		gap: 0.55rem;
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

	.mark {
		width: 1.5em;
		height: 1.5em;
		background-color: var(--gorri);
		mask: url('/brand/lauburu.svg') no-repeat center / contain;
		-webkit-mask: url('/brand/lauburu.svg') no-repeat center / contain;
	}
</style>

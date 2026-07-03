<script lang="ts">
	/**
	 * Le motif produit : la parole (barres gorri, waveform du HUD) devient
	 * ligne de texte (trait encre). Statique et calme — arnasa, pas de vibration.
	 * 26 barres, comme la waveform de l'app (§4.2).
	 */
	const heights = [
		6, 10, 16, 8, 13, 19, 11, 6, 15, 9, 17, 12, 7, 14, 18, 10, 5, 12, 8, 14, 7, 10, 6, 8, 5, 4
	];
</script>

<svg class="seismo" viewBox="0 0 440 32" fill="none" aria-hidden="true">
	{#each heights as h, i (i)}
		<rect x={i * 4.5} y={16 - h / 2} width="2" height={h} rx="1" class="bar" />
	{/each}
	<rect x="121" y="15.25" width="319" height="1.5" rx="0.75" class="line" />
</svg>

<style>
	.seismo {
		display: block;
		width: min(27.5rem, 100%);
		height: auto;
	}

	.bar {
		fill: var(--gorri-bizi);
		opacity: 0.9;
	}

	.line {
		fill: var(--ink);
		opacity: 0.85;
	}
</style>

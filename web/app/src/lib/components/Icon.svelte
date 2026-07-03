<script lang="ts">
	/** Icônes SVG inline, trait arrondi — registre SF Symbols, jamais d'emoji. */
	let {
		name,
		size = 16
	}: {
		name: 'copy' | 'check' | 'drop' | 'trash' | 'warning' | 'mic' | 'stop';
		size?: number;
	} = $props();
</script>

<svg
	width={size}
	height={size}
	viewBox="0 0 24 24"
	fill="none"
	stroke="currentColor"
	stroke-width="1.6"
	stroke-linecap="round"
	stroke-linejoin="round"
	aria-hidden="true"
>
	{#if name === 'copy'}
		<rect x="9" y="9" width="11" height="11" rx="2.5" />
		<path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5" />
	{:else if name === 'check'}
		<path d="M4.5 12.5l5 5L19.5 6.5" />
	{:else if name === 'drop'}
		<path d="M12 3.5v10.5" />
		<path d="M7.5 9.5L12 14l4.5-4.5" />
		<path d="M5 20.5h14" />
	{:else if name === 'trash'}
		<path d="M4 6.5h16" />
		<path d="M9.5 6.5V5A1.5 1.5 0 0 1 11 3.5h2A1.5 1.5 0 0 1 14.5 5v1.5" />
		<path d="M6.5 6.5l.9 12A2 2 0 0 0 9.4 20.5h5.2a2 2 0 0 0 2-1.9l.9-12.1" />
	{:else if name === 'mic'}
		<rect x="9" y="3" width="6" height="11" rx="3" />
		<path d="M5.5 11.5a6.5 6.5 0 0 0 13 0" />
		<path d="M12 18v2.5" />
	{:else if name === 'stop'}
		<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor" stroke="none" />
	{:else if name === 'warning'}
		<path
			d="M10.6 4.3L3.2 17.1a1.6 1.6 0 0 0 1.4 2.4h14.8a1.6 1.6 0 0 0 1.4-2.4L13.4 4.3a1.6 1.6 0 0 0-2.8 0z"
		/>
		<path d="M12 9.5v4" />
		<circle cx="12" cy="16.4" r="0.7" fill="currentColor" stroke="none" />
	{/if}
</svg>

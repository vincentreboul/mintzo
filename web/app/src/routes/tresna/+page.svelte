<script lang="ts">
	import { t, getLocale } from '$lib/i18n/index.svelte';
	import { transcribe, ApiError, MAX_FILE_BYTES } from '$lib/api';
	import {
		addEntry,
		clearEntries,
		deleteEntry,
		listEntries,
		type HistoryEntry
	} from '$lib/history';
	import { fmtClock, fmtDay, fmtDuration, fmtSeconds, dayGroup } from '$lib/format';
	import {
		startRecording,
		recordingSupported,
		RecorderError,
		type RecorderHandle
	} from '$lib/recorder';
	import Icon from '$lib/components/Icon.svelte';

	type Phase = 'idle' | 'uploading' | 'transcribing' | 'correcting' | 'done' | 'error';

	const AUDIO_EXT = /\.(opus|oga|ogg|m4a|mp3|wav|aac|flac|webm|amr|wma|mp4|3gp|caf|aiff?)$/i;

	let phase = $state<Phase>('idle');
	let language = $state<'eu' | 'fr'>('eu');
	let correct = $state(true);
	let progress = $state(0);
	let fileName = $state('');
	let result = $state<HistoryEntry | null>(null);
	let showRaw = $state(false);
	let errorKey = $state('errGeneric');
	let dragDepth = $state(0);
	let copiedMain = $state(false);

	let entries = $state<HistoryEntry[]>([]);
	let expandedId = $state<string | null>(null);
	let expandedRaw = $state(false);
	let copiedId = $state<string | null>(null);
	let confirmClear = $state(false);

	let fileInput: HTMLInputElement;
	let abortCurrent: (() => void) | null = null;
	let correctTimer: ReturnType<typeof setTimeout> | null = null;
	let copyTimer: ReturnType<typeof setTimeout> | null = null;

	/* réveil du serveur (GPU serverless) : au-delà du délai attendu,
	   on le dit honnêtement au lieu de laisser la barre muette */
	let wakeHint = $state(false);
	let wakeTimer: ReturnType<typeof setTimeout> | null = null;

	/* ---------- dictée au micro ---------- */
	const REC_MAX_S = 900; // 15 min — protège la batterie et l'upload
	const REC_BARS = 30;

	let mode = $state<'mic' | 'upload'>('mic');
	let micSupported = $state(true);
	let recording = $state(false);
	let recSeconds = $state(0);
	let recLevels = $state<number[]>(Array.from({ length: REC_BARS }, () => 0));
	let micErrorKey = $state<string | null>(null);

	let rec: RecorderHandle | null = null;
	let recTimer: ReturnType<typeof setInterval> | null = null;
	let recStartTs = 0;

	$effect(() => {
		micSupported = recordingSupported();
		if (!micSupported) mode = 'upload';
	});

	/* micro coupé proprement si on quitte la page en enregistrant */
	$effect(() => {
		return () => discardMic();
	});

	async function startMic() {
		if (busy || recording) return;
		micErrorKey = null;
		try {
			const handle = await startRecording((lvl) => {
				recLevels = [...recLevels.slice(1), lvl];
			});
			rec = handle;
			recording = true;
			recSeconds = 0;
			recStartTs = Date.now();
			recLevels = Array.from({ length: REC_BARS }, () => 0);
			recTimer = setInterval(() => {
				recSeconds = Math.floor((Date.now() - recStartTs) / 1000);
				if (recSeconds >= REC_MAX_S) void stopMic();
			}, 250);
		} catch (e) {
			micErrorKey =
				e instanceof RecorderError
					? e.kind === 'denied'
						? 'errMicDenied'
						: e.kind === 'unsupported'
							? 'errMicUnsupported'
							: 'errMicFailed'
					: 'errMicFailed';
		}
	}

	function stopRecTicker() {
		if (recTimer) clearInterval(recTimer);
		recTimer = null;
	}

	async function stopMic() {
		if (!rec) return;
		const handle = rec;
		rec = null;
		stopRecTicker();
		recording = false;
		try {
			const file = await handle.stop();
			await processFile(file);
		} catch {
			micErrorKey = 'errMicFailed';
		}
	}

	function discardMic() {
		if (!rec) return;
		rec.discard();
		rec = null;
		stopRecTicker();
		recording = false;
	}

	const busy = $derived(
		phase === 'uploading' || phase === 'transcribing' || phase === 'correcting'
	);

	const phaseLabel = $derived(
		phase === 'uploading'
			? t('tool.phaseUploading')
			: phase === 'transcribing'
				? t('tool.phaseTranscribing')
				: phase === 'correcting'
					? t('tool.phaseCorrecting')
					: ''
	);

	const groups = $derived.by(() => {
		const map = new Map<string, HistoryEntry[]>();
		for (const e of entries) {
			const g = dayGroup(e.createdAt);
			if (!map.has(g)) map.set(g, []);
			map.get(g)!.push(e);
		}
		return [...map.entries()].map(([key, items]) => ({
			key,
			label:
				key === 'today'
					? t('tool.today')
					: key === 'yesterday'
						? t('tool.yesterday')
						: fmtDay(key, getLocale()),
			items
		}));
	});

	$effect(() => {
		listEntries()
			.then((list) => (entries = list))
			.catch(() => {
				/* IndexedDB indisponible : l'outil marche sans historique */
			});
	});

	/** Durée de l'audio (métadonnées), pour séquencer la phase « Zuzentzen… ». */
	function probeDuration(file: File): Promise<number | null> {
		return new Promise((resolve) => {
			let settled = false;
			const url = URL.createObjectURL(file);
			const audio = new Audio();
			const done = (v: number | null) => {
				if (settled) return;
				settled = true;
				URL.revokeObjectURL(url);
				resolve(v);
			};
			audio.preload = 'metadata';
			audio.onloadedmetadata = () =>
				done(Number.isFinite(audio.duration) ? audio.duration : null);
			audio.onerror = () => done(null);
			setTimeout(() => done(null), 2500);
			audio.src = url;
		});
	}

	function looksLikeAudio(file: File): boolean {
		if (file.type.startsWith('audio/')) return true;
		if (['video/mp4', 'video/webm', 'application/ogg'].includes(file.type)) return true;
		return AUDIO_EXT.test(file.name);
	}

	async function processFile(file: File) {
		if (busy) return;

		if (file.size > MAX_FILE_BYTES) {
			errorKey = 'errTooBig';
			phase = 'error';
			return;
		}
		if (!looksLikeAudio(file)) {
			errorKey = 'errFormat';
			phase = 'error';
			return;
		}

		result = null;
		showRaw = false;
		fileName = file.name;
		progress = 0;
		phase = 'uploading';

		// estimation de la fenêtre de transcription, pour la phase « Zuzentzen… »
		const wantCorrect = correct;
		const lang = language;
		probeDuration(file).then((dur) => {
			// au-delà du délai attendu pour cette durée d'audio, le serveur
			// est sans doute en train de se réveiller : on l'affiche.
			const wakeMs = Math.max(10_000, dur ? dur * 450 + 8_000 : 10_000);
			wakeTimer = setTimeout(() => {
				if (phase === 'transcribing' || phase === 'correcting') {
					wakeHint = true;
					if (phase === 'correcting') phase = 'transcribing';
				}
			}, wakeMs);
			if (!wantCorrect) return;
			const estMs = dur ? Math.min(90_000, Math.max(4_000, dur * 450)) : 12_000;
			correctTimer = setTimeout(() => {
				if (phase === 'transcribing' && !wakeHint) phase = 'correcting';
			}, estMs);
		});

		const t0 = performance.now();
		const handle = transcribe(file, lang, wantCorrect, (f) => {
			progress = f;
			if (f >= 1 && phase === 'uploading') phase = 'transcribing';
		});
		abortCurrent = handle.abort;

		try {
			const res = await handle.promise;
			const text = (res.text ?? '').trim();
			const rawText = (res.rawText ?? '').trim() || text;
			const entry: HistoryEntry = {
				id: crypto.randomUUID(),
				createdAt: Date.now(),
				filename: file.name,
				language: res.language || lang,
				durationSeconds: res.durationSeconds ?? 0,
				text,
				rawText,
				corrected: wantCorrect,
				processedMs: Math.round(performance.now() - t0)
			};
			result = entry;
			phase = 'done';
			entries = [entry, ...entries];
			addEntry(entry).catch(() => {
				/* pas d'historique possible : le résultat reste affiché */
			});
		} catch (e) {
			if (e instanceof ApiError && e.kind === 'aborted') {
				phase = 'idle';
			} else {
				errorKey =
					e instanceof ApiError
						? e.kind === 'too-big'
							? 'errTooBig'
							: e.kind === 'format'
								? 'errFormat'
								: e.kind === 'timeout'
									? 'errTimeout'
									: 'errServer'
						: 'errGeneric';
				phase = 'error';
			}
		} finally {
			if (correctTimer) clearTimeout(correctTimer);
			correctTimer = null;
			if (wakeTimer) clearTimeout(wakeTimer);
			wakeTimer = null;
			wakeHint = false;
			abortCurrent = null;
		}
	}

	function cancel() {
		abortCurrent?.();
	}

	function openPicker() {
		fileInput.click();
	}

	function onPick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (file) processFile(file);
	}

	function hasFiles(e: DragEvent): boolean {
		return [...(e.dataTransfer?.types ?? [])].includes('Files');
	}

	function onDragEnter(e: DragEvent) {
		if (!hasFiles(e) || busy) return;
		e.preventDefault();
		dragDepth += 1;
	}

	function onDragOver(e: DragEvent) {
		if (!hasFiles(e)) return;
		e.preventDefault();
	}

	function onDragLeave(e: DragEvent) {
		if (!hasFiles(e) || busy) return;
		dragDepth = Math.max(0, dragDepth - 1);
	}

	function onDrop(e: DragEvent) {
		if (!hasFiles(e)) return;
		e.preventDefault();
		dragDepth = 0;
		if (busy) return;
		const file = e.dataTransfer?.files?.[0];
		if (file) processFile(file);
	}

	async function copyText(text: string, target: 'main' | string) {
		try {
			await navigator.clipboard.writeText(text);
		} catch {
			return;
		}
		if (copyTimer) clearTimeout(copyTimer);
		if (target === 'main') {
			copiedMain = true;
			copyTimer = setTimeout(() => (copiedMain = false), 800);
		} else {
			copiedId = target;
			copyTimer = setTimeout(() => (copiedId = null), 800);
		}
	}

	function toggleExpand(id: string) {
		expandedRaw = false;
		expandedId = expandedId === id ? null : id;
	}

	async function removeEntry(id: string) {
		await deleteEntry(id).catch(() => undefined);
		entries = entries.filter((e) => e.id !== id);
		if (expandedId === id) expandedId = null;
		if (result?.id === id) result = null;
	}

	async function clearAll() {
		await clearEntries().catch(() => undefined);
		entries = [];
		expandedId = null;
		confirmClear = false;
	}

	function reset() {
		result = null;
		showRaw = false;
		phase = 'idle';
	}
</script>

<svelte:head>
	<title>{t('tool.metaTitle')}</title>
	<meta name="description" content={t('tool.metaDescription')} />
</svelte:head>

<svelte:window
	ondragenter={onDragEnter}
	ondragover={onDragOver}
	ondragleave={onDragLeave}
	ondrop={onDrop}
/>

<input
	bind:this={fileInput}
	type="file"
	accept="audio/*,video/mp4,video/webm,.opus,.oga,.ogg,.m4a,.mp3,.wav,.aac,.flac,.webm,.amr,.wma,.3gp,.caf,.aif,.aiff"
	class="visually-hidden"
	tabindex="-1"
	aria-hidden="true"
	onchange={onPick}
/>

{#if dragDepth > 0}
	<div class="drop-overlay" aria-hidden="true">
		<div class="drop-frame">
			<Icon name="drop" size={30} />
			<p>{t('tool.overlay')}</p>
		</div>
	</div>
{/if}

<div class="shell tool-shell">
	<section class="stage" aria-label={t('tool.metaTitle')}>
		{#if phase === 'idle'}
			<div class="invite">
				{#if micSupported}
					<div
						class="modes"
						role="radiogroup"
						aria-label="{t('tool.modeMic')} / {t('tool.modeUpload')}"
					>
						<label class="mode" class:active={mode === 'mic'}>
							<input type="radio" name="mode" value="mic" bind:group={mode} disabled={recording} />
							<Icon name="mic" size={16} />
							<span>{t('tool.modeMic')}</span>
						</label>
						<label class="mode" class:active={mode === 'upload'}>
							<input
								type="radio"
								name="mode"
								value="upload"
								bind:group={mode}
								disabled={recording}
							/>
							<Icon name="drop" size={16} />
							<span>{t('tool.modeUpload')}</span>
						</label>
					</div>
				{/if}

				{#if micSupported && mode === 'mic'}
					<div class="micbox" aria-live="polite">
						{#if recording}
							<div class="capsule" role="status" aria-label={t('tool.micRecording')}>
								<span class="cap-lang">{language}</span>
								<span class="cap-wave" aria-hidden="true">
									{#each recLevels as l, i (i)}
										<span class="cap-bar" style:height="{Math.max(9, Math.round(l * 100))}%"
										></span>
									{/each}
								</span>
								<span class="cap-time tnum">{fmtDuration(recSeconds)}</span>
							</div>
							<button type="button" class="recbtn stop" onclick={stopMic}>
								<Icon name="stop" size={28} />
								<span class="visually-hidden">{t('tool.micStop')}</span>
							</button>
							<p class="mic-title">{t('tool.micStop')}</p>
							<button type="button" class="btn-text" onclick={discardMic}>
								{t('tool.micDiscard')}
							</button>
						{:else}
							<button type="button" class="recbtn" onclick={startMic}>
								<Icon name="mic" size={34} />
								<span class="visually-hidden">{t('tool.micStartAria')}</span>
							</button>
							<p class="mic-title">{t('tool.micTitle')}</p>
							<p class="mic-hint">{t('tool.micHint')} {t('tool.micLimit')}</p>
							{#if micErrorKey}
								<p class="mic-error" role="alert">{t(`tool.${micErrorKey}`)}</p>
							{/if}
						{/if}
					</div>
				{:else}
					<button
						type="button"
						class="dropzone"
						onclick={openPicker}
						aria-label={t('tool.dropAria')}
					>
						<span class="drop-icon"><Icon name="drop" size={26} /></span>
						<span class="invite-title">{t('tool.emptyTitle')}</span>
						<span class="invite-sub">{t('tool.emptySub')}</span>
						<span class="invite-hint tnum">{t('tool.emptyHint')}</span>
					</button>
					{#if !micSupported && micErrorKey}
						<p class="mic-error" role="alert">{t(`tool.${micErrorKey}`)}</p>
					{/if}
				{/if}
				<div class="controls" class:dim={recording}>
					<div class="control">
						<span class="kicker control-label" id="lang-label">{t('tool.langLabel')}</span>
						<div class="segmented" role="radiogroup" aria-labelledby="lang-label">
							<label class="seg" class:active={language === 'eu'}>
								<input type="radio" name="lang" value="eu" bind:group={language} />
								<span>eu</span>
							</label>
							<label class="seg" class:active={language === 'fr'}>
								<input type="radio" name="lang" value="fr" bind:group={language} />
								<span>fr</span>
							</label>
						</div>
					</div>
					<label class="control switch-wrap">
						<span class="kicker control-label">{t('tool.correction')}</span>
						<input type="checkbox" role="switch" bind:checked={correct} class="switch-input" />
						<span class="switch-track" aria-hidden="true"><span class="switch-knob"></span></span>
					</label>
				</div>
			</div>
		{:else if busy}
			<div class="working">
				<p class="working-file">{fileName}</p>
				<p class="phase" role="status">{phaseLabel}</p>
				<div
					class="bar-rail"
					role="progressbar"
					aria-valuemin="0"
					aria-valuemax="100"
					aria-valuenow={phase === 'uploading' ? Math.round(progress * 100) : undefined}
					aria-label={phaseLabel}
				>
					<div
						class="bar-fill"
						class:indeterminate={phase !== 'uploading'}
						style:width={phase === 'uploading' ? `${Math.max(2, progress * 100)}%` : '100%'}
					></div>
				</div>
				{#if wakeHint}
					<p class="wake-note" role="status">{t('tool.wakeHint')}</p>
				{/if}
				<button type="button" class="btn-text cancel" onclick={cancel}>{t('tool.cancel')}</button>
			</div>
		{:else if phase === 'error'}
			<div class="errorbox" role="alert">
				<span class="err-icon"><Icon name="warning" size={22} /></span>
				<p class="err-msg">{t(`tool.${errorKey}`)}</p>
				<button type="button" class="btn btn-quiet" onclick={reset}>{t('tool.retry')}</button>
			</div>
		{:else if result}
			<article class="result">
				<header class="result-bar">
					{#if result.corrected && result.rawText !== result.text}
						<div class="segmented small" role="radiogroup" aria-label="jatorrizkoa / zuzendua">
							<label class="seg" class:active={!showRaw}>
								<input type="radio" name="version" value={false} bind:group={showRaw} />
								<span>{t('tool.corrected')}</span>
							</label>
							<label class="seg" class:active={showRaw}>
								<input type="radio" name="version" value={true} bind:group={showRaw} />
								<span>{t('tool.original')}</span>
							</label>
						</div>
					{:else}
						<span></span>
					{/if}
					<button
						type="button"
						class="iconbtn"
						class:ok={copiedMain}
						onclick={() => copyText(showRaw ? result!.rawText : result!.text, 'main')}
						aria-label={copiedMain ? t('tool.copied') : t('tool.copy')}
					>
						{#if copiedMain}<Icon name="check" size={17} />{:else}<Icon
								name="copy"
								size={17}
							/>{/if}
					</button>
				</header>
				<p class="read result-text" lang={result.language}>
					{showRaw ? result.rawText : result.text}
				</p>
				<footer class="result-meta">
					<span class="tnum">{fmtDuration(result.durationSeconds)}</span>
					<span class="dot" aria-hidden="true">·</span>
					<span class="lang-tag">{result.language}</span>
					<span class="dot" aria-hidden="true">·</span>
					<span class="tnum">{fmtSeconds(result.processedMs)} {t('tool.processedSuffix')}</span>
				</footer>
				<button type="button" class="btn btn-quiet again" onclick={reset}>{t('tool.newFile')}</button>
			</article>
		{/if}
	</section>

	<section class="journal" aria-label={t('tool.historyHead')}>
		<div class="journal-head">
			<h2 class="section-head journal-title"><span class="kicker">{t('tool.historyHead')}</span></h2>
			{#if entries.length > 0}
				{#if confirmClear}
					<div class="confirm" role="alertdialog" aria-label={t('tool.clearConfirm')}>
						<span class="confirm-q">{t('tool.clearConfirm')}</span>
						<button type="button" class="btn-text danger" onclick={clearAll}>{t('tool.clearYes')}</button>
						<button type="button" class="btn-text" onclick={() => (confirmClear = false)}>
							{t('tool.clearNo')}
						</button>
					</div>
				{:else}
					<button type="button" class="btn-text" onclick={() => (confirmClear = true)}>
						{t('tool.clear')}
					</button>
				{/if}
			{/if}
		</div>
		<p class="journal-note">{t('tool.historyNote')}</p>

		{#if entries.length === 0}
			<p class="journal-empty">{t('tool.historyEmpty')}</p>
		{:else}
			{#each groups as group (group.key)}
				<p class="kicker day">{group.label}</p>
				<ul class="cells">
					{#each group.items as e (e.id)}
						<li class="cell" class:open={expandedId === e.id}>
							<div class="cell-row">
								<button
									type="button"
									class="cell-main"
									onclick={() => toggleExpand(e.id)}
									aria-expanded={expandedId === e.id}
								>
									<span class="excerpt read" class:clamp={expandedId !== e.id} lang={e.language}>
										{expandedId === e.id && expandedRaw ? e.rawText : e.text}
									</span>
									<span class="meta">
										<span class="tnum">{fmtClock(e.createdAt)}</span>
										<span class="dot" aria-hidden="true">·</span>
										<span class="tnum">{fmtDuration(e.durationSeconds)}</span>
										<span class="dot" aria-hidden="true">·</span>
										<span class="lang-tag">{e.language}</span>
										<span class="dot" aria-hidden="true">·</span>
										<span class="fname">{e.filename}</span>
									</span>
								</button>
								<span class="cell-actions">
									<button
										type="button"
										class="iconbtn"
										class:ok={copiedId === e.id}
										onclick={() => copyText(expandedRaw && expandedId === e.id ? e.rawText : e.text, e.id)}
										aria-label={copiedId === e.id ? t('tool.copied') : t('tool.copy')}
									>
										{#if copiedId === e.id}<Icon name="check" size={16} />{:else}<Icon
												name="copy"
												size={16}
											/>{/if}
									</button>
									<button
										type="button"
										class="iconbtn"
										onclick={() => removeEntry(e.id)}
										aria-label={t('tool.delete')}
									>
										<Icon name="trash" size={16} />
									</button>
								</span>
							</div>
							{#if expandedId === e.id && e.corrected && e.rawText !== e.text}
								<div class="cell-versions">
									<div class="segmented small" role="radiogroup" aria-label="jatorrizkoa / zuzendua">
										<label class="seg" class:active={!expandedRaw}>
											<input type="radio" name="v-{e.id}" value={false} bind:group={expandedRaw} />
											<span>{t('tool.corrected')}</span>
										</label>
										<label class="seg" class:active={expandedRaw}>
											<input type="radio" name="v-{e.id}" value={true} bind:group={expandedRaw} />
											<span>{t('tool.original')}</span>
										</label>
									</div>
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{/each}
		{/if}
	</section>
</div>

<style>
	.tool-shell {
		max-width: 52rem;
	}

	/* ---------- overlay de drop (§6.3) ---------- */
	.drop-overlay {
		position: fixed;
		inset: 0;
		z-index: 50;
		background: color-mix(in srgb, var(--paper) 88%, transparent);
		backdrop-filter: blur(6px);
		-webkit-backdrop-filter: blur(6px);
		animation: overlay-in 180ms cubic-bezier(0.2, 0.7, 0.3, 1);
	}

	.drop-frame {
		position: absolute;
		inset: 0.75rem;
		border: 1.5px dashed var(--gorri);
		border-radius: 0.875rem;
		display: grid;
		place-content: center;
		justify-items: center;
		gap: 0.875rem;
		color: var(--gorri);
	}

	.drop-frame p {
		font-size: 0.9375rem;
		font-weight: 500;
		color: var(--ink);
	}

	@keyframes overlay-in {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	/* ---------- scène ---------- */
	.stage {
		padding-block: clamp(2.5rem, 6vw, 4.5rem) clamp(2rem, 5vw, 3.5rem);
		min-height: 24rem;
		display: grid;
		align-content: start;
	}

	.invite {
		display: grid;
		gap: 1.75rem;
		justify-items: center;
	}

	.dropzone {
		width: 100%;
		max-width: var(--measure);
		display: grid;
		justify-items: center;
		gap: 0.5rem;
		padding: clamp(2.5rem, 6vw, 3.75rem) 1.5rem;
		border: 1px solid var(--hairline);
		border-radius: 0.875rem;
		background: transparent;
		transition:
			background-color var(--motion-micro),
			border-color var(--motion-micro);
	}

	.dropzone:hover {
		background: var(--surface-hover);
		border-color: var(--gorri-24);
	}

	.drop-icon {
		color: var(--gorri);
		margin-bottom: 0.375rem;
	}

	.invite-title {
		font-family: var(--font-read);
		font-optical-sizing: auto;
		font-size: 1.375rem;
		line-height: 1.36;
		color: var(--ink);
	}

	.invite-sub {
		font-size: 0.8125rem;
		color: var(--ink-2);
	}

	.invite-hint {
		font-size: 0.75rem;
		color: var(--ink-2);
		margin-top: 0.625rem;
	}

	/* ---------- sélecteur de mode ---------- */
	.modes {
		display: inline-flex;
		gap: 0.25rem;
		padding: 0.25rem;
		background: var(--surface-2);
		border: 1px solid var(--hairline);
		border-radius: 999px;
	}

	.mode {
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 0.5rem;
		min-height: 2.5rem;
		padding: 0.375rem 1.25rem;
		border-radius: 999px;
		font-size: 0.875rem;
		font-weight: 560;
		color: var(--ink-2);
		cursor: pointer;
		transition:
			background-color var(--motion-micro),
			color var(--motion-micro),
			box-shadow var(--motion-micro);
	}

	.mode:hover {
		color: var(--ink);
	}

	.mode.active {
		background: var(--surface);
		color: var(--gorri);
		box-shadow: var(--shadow-card);
	}

	.mode input {
		position: absolute;
		inset: 0;
		opacity: 0;
		margin: 0;
		cursor: pointer;
	}

	.mode:has(input:focus-visible) {
		outline: 2px solid var(--gorri);
		outline-offset: 2px;
	}

	.mode:has(input:disabled) {
		cursor: default;
		opacity: 0.6;
	}

	/* ---------- dictée au micro ---------- */
	.micbox {
		width: 100%;
		max-width: var(--measure);
		min-height: 16.5rem;
		display: grid;
		justify-items: center;
		align-content: center;
		gap: 1rem;
		padding: clamp(1.5rem, 4vw, 2.5rem) 1.5rem;
		border: 1px solid var(--hairline);
		border-radius: 1.25rem;
		background: var(--surface);
	}

	.recbtn {
		display: grid;
		place-items: center;
		width: 5.5rem;
		height: 5.5rem;
		border-radius: 50%;
		background: var(--fill-red);
		color: var(--on-red);
		box-shadow: var(--shadow-card);
		transition:
			background-color var(--motion-micro),
			transform var(--motion-micro);
	}

	.recbtn:hover {
		background: var(--fill-red-hover);
	}

	.recbtn:active {
		transform: scale(0.96);
	}

	.recbtn.stop {
		animation: rec-pulse 1800ms ease-out infinite;
	}

	@keyframes rec-pulse {
		0% {
			box-shadow: 0 0 0 0 var(--gorri-24);
		}
		70% {
			box-shadow: 0 0 0 1.125rem transparent;
		}
		100% {
			box-shadow: 0 0 0 0 transparent;
		}
	}

	.mic-title {
		font-family: var(--font-read);
		font-optical-sizing: auto;
		font-size: 1.1875rem;
		color: var(--ink);
	}

	.mic-hint {
		font-size: 0.8125rem;
		color: var(--ink-2);
		max-width: 40ch;
		text-align: center;
		line-height: 1.55;
		margin-top: -0.375rem;
	}

	.mic-error {
		font-size: 0.875rem;
		line-height: 1.55;
		color: var(--error);
		max-width: 44ch;
		text-align: center;
	}

	/* la capsule — l'ADN du HUD de l'app */
	.capsule {
		display: flex;
		align-items: center;
		gap: 0.875rem;
		width: min(21rem, 100%);
		min-height: 3.25rem;
		padding: 0.5rem 1.125rem;
		border-radius: 999px;
		background: color-mix(in srgb, var(--gorri) 6%, var(--surface));
		border: 1px solid var(--gorri-12);
		box-shadow: var(--shadow-float);
	}

	.cap-lang {
		font-size: 0.625rem;
		font-weight: 650;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--gorri);
		background: var(--gorri-12);
		border-radius: 0.25rem;
		padding: 0.125rem 0.375rem;
		flex: none;
	}

	.cap-wave {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1.5px;
		height: 1.875rem;
	}

	.cap-bar {
		flex: 1;
		max-width: 3.5px;
		min-height: 2px;
		border-radius: 2px;
		background: var(--gorri-bizi);
		transition: height 70ms linear;
	}

	.cap-time {
		font-size: 0.8125rem;
		color: var(--ink-2);
		flex: none;
	}

	.controls.dim {
		opacity: 0.45;
		pointer-events: none;
	}

	/* ---------- contrôles ---------- */
	.controls {
		display: flex;
		align-items: center;
		gap: 2.5rem;
		flex-wrap: wrap;
		justify-content: center;
	}

	.control {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.control-label {
		color: var(--ink-3);
	}

	.segmented {
		display: inline-flex;
		border: 1px solid var(--hairline);
		border-radius: 0.5rem;
		padding: 0.125rem;
		gap: 0.125rem;
		background: var(--surface);
	}

	.seg {
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 2.75rem;
		min-height: 1.875rem;
		padding: 0.25rem 0.75rem;
		border-radius: 0.375rem;
		font-size: 0.6875rem;
		font-weight: 600;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--ink-2);
		cursor: pointer;
		transition:
			background-color var(--motion-micro),
			color var(--motion-micro);
	}

	.seg:hover {
		color: var(--ink);
	}

	.seg.active {
		background: var(--gorri-12);
		color: var(--gorri);
	}

	.seg input {
		position: absolute;
		inset: 0;
		opacity: 0;
		margin: 0;
		cursor: pointer;
	}

	.seg:has(input:focus-visible) {
		outline: 2px solid var(--gorri);
		outline-offset: 2px;
	}

	/* interrupteur zuzenketa */
	.switch-wrap {
		cursor: pointer;
	}

	.switch-input {
		position: absolute;
		opacity: 0;
		width: 1px;
		height: 1px;
	}

	.switch-track {
		display: inline-block;
		width: 2.25rem;
		height: 1.3125rem;
		border-radius: 999px;
		background: color-mix(in srgb, var(--ink) 18%, transparent);
		position: relative;
		transition: background-color var(--motion-micro);
		flex: none;
	}

	.switch-knob {
		position: absolute;
		top: 0.1875rem;
		left: 0.1875rem;
		width: 0.9375rem;
		height: 0.9375rem;
		border-radius: 50%;
		background: var(--paper);
		transition: transform var(--motion-micro);
	}

	.switch-input:checked ~ .switch-track {
		background: var(--gorri);
	}

	.switch-input:checked ~ .switch-track .switch-knob {
		transform: translateX(0.9375rem);
	}

	.switch-input:focus-visible ~ .switch-track {
		outline: 2px solid var(--gorri);
		outline-offset: 2px;
	}

	/* ---------- traitement ---------- */
	.working {
		max-width: var(--measure);
		width: 100%;
		margin-inline: auto;
		display: grid;
		gap: 0.75rem;
		padding-top: clamp(2rem, 6vw, 4rem);
	}

	.working-file {
		font-size: 0.875rem;
		font-weight: 500;
		color: var(--ink);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.phase {
		font-size: 0.8125rem;
		font-weight: 500;
		color: var(--ink-2);
	}

	.bar-rail {
		height: 2px;
		background: var(--hairline);
		border-radius: 1px;
		overflow: hidden;
	}

	.bar-fill {
		height: 100%;
		background: var(--gorri);
		border-radius: 1px;
		transition: width 200ms cubic-bezier(0, 0, 0.2, 1);
	}

	/* trait traversé par une onde de luminosité (§4.3 état 2) */
	.bar-fill.indeterminate {
		background: linear-gradient(
			90deg,
			var(--gorri) 0%,
			var(--gorri) 35%,
			var(--gorri-bizi) 50%,
			var(--gorri) 65%,
			var(--gorri) 100%
		);
		background-size: 200% 100%;
		animation: shimmer var(--motion-shimmer) linear infinite;
	}

	@keyframes shimmer {
		from {
			background-position: 200% 0;
		}
		to {
			background-position: 0% 0;
		}
	}

	.cancel {
		justify-self: start;
		margin-top: 0.5rem;
		padding: 0.375rem 0;
	}

	.wake-note {
		font-size: 0.8125rem;
		line-height: 1.55;
		color: var(--ink-2);
		animation: overlay-in 400ms cubic-bezier(0.2, 0.7, 0.3, 1);
	}

	/* ---------- erreur ---------- */
	.errorbox {
		max-width: var(--measure);
		width: 100%;
		margin-inline: auto;
		display: grid;
		justify-items: start;
		gap: 1rem;
		padding-top: clamp(2rem, 6vw, 4rem);
	}

	.err-icon {
		color: var(--error);
	}

	.err-msg {
		font-size: 0.9375rem;
		line-height: 1.6;
		color: var(--ink);
		max-width: 44ch;
	}

	/* ---------- résultat ---------- */
	.result {
		max-width: var(--measure);
		width: 100%;
		margin-inline: auto;
		display: grid;
		gap: 1.25rem;
	}

	.result-bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	.result-text {
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.result-meta,
	.meta {
		display: inline-flex;
		align-items: center;
		gap: 0.4375rem;
		font-size: 0.6875rem;
		color: var(--ink-2);
	}

	.dot {
		color: var(--ink-3);
	}

	.lang-tag {
		font-size: 0.625rem;
		font-weight: 600;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--gorri);
		background: var(--gorri-12);
		border-radius: 0.25rem;
		padding: 0.0625rem 0.375rem;
	}

	.again {
		justify-self: start;
		margin-top: 0.25rem;
	}

	/* ---------- boutons d'icône ---------- */
	.iconbtn {
		display: inline-grid;
		place-items: center;
		width: 2.125rem;
		height: 2.125rem;
		border-radius: 0.5rem;
		color: var(--ink-2);
		transition:
			color var(--motion-micro),
			background-color var(--motion-micro);
	}

	.iconbtn:hover {
		color: var(--ink);
		background: var(--surface-hover);
	}

	.iconbtn.ok {
		color: var(--success);
	}

	/* ---------- journal ---------- */
	.journal {
		padding-block: 1rem clamp(2rem, 5vw, 3rem);
	}

	.journal-head {
		display: flex;
		align-items: center;
		gap: 1.5rem;
	}

	.journal-title {
		flex: 1;
	}

	.journal-note {
		margin-top: 0.75rem;
		font-size: 0.75rem;
		color: var(--ink-2);
	}

	.journal-empty {
		margin-top: 2rem;
		font-size: 0.875rem;
		color: var(--ink-2);
	}

	.confirm {
		display: inline-flex;
		align-items: center;
		gap: 1rem;
	}

	.confirm-q {
		font-size: 0.8125rem;
		color: var(--ink);
	}

	.danger {
		color: var(--error);
	}

	.danger:hover {
		color: var(--error);
	}

	.day {
		color: var(--ink-2);
		margin-top: 2rem;
	}

	.cells {
		list-style: none;
		margin: 0.75rem 0 0;
		padding: 0;
		background: var(--surface);
		border: 1px solid var(--hairline);
		border-radius: 0.625rem;
	}

	.cell + .cell {
		border-top: 1px solid var(--hairline);
	}

	.cell-row {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		padding: 0.875rem 1rem;
	}

	.cell.open .cell-row {
		padding-bottom: 0.5rem;
	}

	.cell-main {
		flex: 1;
		min-width: 0;
		display: grid;
		gap: 0.4375rem;
		text-align: left;
		border-radius: 0.375rem;
	}

	.excerpt {
		font-size: 0.9375rem;
		line-height: 1.47;
		color: var(--ink);
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.excerpt.clamp {
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
		white-space: normal;
	}

	.fname {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		max-width: 14rem;
	}

	.meta {
		flex-wrap: wrap;
	}

	.cell-actions {
		display: inline-flex;
		gap: 0.125rem;
		opacity: 0;
		transition: opacity var(--motion-micro);
	}

	.cell:hover .cell-actions,
	.cell:focus-within .cell-actions,
	.cell.open .cell-actions {
		opacity: 1;
	}

	@media (hover: none) {
		.cell-actions {
			opacity: 1;
		}
	}

	.cell-versions {
		padding: 0 1rem 0.875rem;
	}

	/* ---------- responsive ---------- */
	@media (max-width: 40rem) {
		.controls {
			gap: 1.25rem;
			flex-direction: column;
			align-items: flex-start;
		}

		.invite {
			justify-items: stretch;
		}

		.stage {
			min-height: 0;
		}

		.fname {
			max-width: 8rem;
		}
	}
</style>

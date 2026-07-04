<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import {
		GITHUB_URL,
		MAC_DOWNLOAD_URL,
		MAC_DOWNLOAD_VERSION,
		COMMON_VOICE_URL,
		HITZ_URL,
		XEZPELETA_URL,
		WHISPER_CPP_URL,
		LLAMA_CPP_URL
	} from '$lib/links';

	/* barres décoratives du vocal — dessin fixe, calme */
	const waveBars = [
		5, 9, 14, 8, 12, 17, 10, 6, 13, 16, 9, 5, 11, 15, 8, 12, 6, 10, 14, 7, 5, 8, 4, 6
	];
</script>

<svelte:head>
	<title>{t('home.metaTitle')}</title>
	<meta name="description" content={t('home.metaDescription')} />
</svelte:head>

<!-- ============ Hero : la promesse + le produit ============ -->
<section class="hero">
	<div class="shell hero-copy">
		<p class="kicker hero-kicker rise" style="--d: 0ms">{t('home.heroKicker')}</p>
		<h1 class="display hero-title rise" style="--d: 60ms">{t('home.heroTitle')}</h1>
		<p class="hero-sub rise" style="--d: 120ms">{t('home.heroSub')}</p>
		<div class="ctas rise" style="--d: 180ms">
			<a class="btn btn-primary btn-lg" href="#mac">{t('home.ctaMac')}</a>
			<a class="btn btn-quiet btn-lg" href={GITHUB_URL} rel="noopener">{t('home.ctaGithub')}</a>
		</div>
	</div>
	<div class="shell stage-wrap rise" style="--d: 260ms">
		<div class="stage">
			<div class="product-frame">
				<picture>
					<source srcset="/screenshots/window-eu-dark.png" media="(prefers-color-scheme: dark)" />
					<img
						src="/screenshots/window-eu-light.png"
						alt={t('home.windowAlt')}
						width="1520"
						height="1224"
						fetchpriority="high"
					/>
				</picture>
			</div>
			<img
				class="hud-float"
				src="/screenshots/hud-listening.png"
				alt=""
				aria-hidden="true"
				width="840"
				height="220"
			/>
		</div>
	</div>
</section>

<!-- ============ Diktaketa kurtsorean ============ -->
<section class="feature">
	<div class="shell feature-grid">
		<div class="feature-copy">
			<p class="kicker accent">{t('home.dictKicker')}</p>
			<h2 class="display feature-title">{t('home.dictTitle')}</h2>
			<p class="feature-body">{t('home.dictBody')}</p>
		</div>
		<figure class="panel hud-panel">
			<img
				src="/screenshots/hud-listening.png"
				alt={t('home.hudAlt')}
				width="840"
				height="220"
				loading="lazy"
			/>
			<figcaption class="panel-caption">{t('home.dictCaption')}</figcaption>
		</figure>
	</div>
</section>

<!-- ============ Fitxategiak → testua ============ -->
<section class="feature">
	<div class="shell feature-grid flip">
		<div class="feature-copy">
			<p class="kicker accent">{t('home.voiceKicker')}</p>
			<h2 class="display feature-title">{t('home.voiceTitle')}</h2>
			<p class="feature-body">{t('home.voiceBody')}</p>
		</div>
		<div class="panel chat-panel" aria-hidden="true">
			<div class="chat-in">
				<span class="chat-wave">
					{#each waveBars as h, i (i)}
						<span class="chat-bar" style="height: {h}px"></span>
					{/each}
				</span>
				<span class="chat-dur tnum">0:42</span>
			</div>
			<p class="chat-name">{t('home.voiceDemoName')}</p>
			<div class="chat-link">
				<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
					<path d="M12 4v14" />
					<path d="M6.5 12.5L12 18l5.5-5.5" />
				</svg>
				<span class="kicker">{t('home.voiceDemoLabel')}</span>
			</div>
			<div class="chat-out">
				<p class="read chat-text">{t('home.voiceDemoOut')}</p>
				<p class="chat-meta">
					<span class="tnum">0:42</span>
					<span class="chat-dot">·</span>
					<span class="chat-lang">{t('home.voiceDemoLang')}</span>
				</p>
			</div>
		</div>
	</div>
</section>

<!-- ============ % 100 lokala — bloc rouge ============ -->
<section class="local">
	<span class="local-mark" aria-hidden="true"></span>
	<div class="shell local-inner">
		<p class="kicker local-kicker">{t('home.localKicker')}</p>
		<h2 class="display local-title">{t('home.localTitle')}</h2>
		<p class="local-body">{t('home.localBody')}</p>
		<a class="local-link" href="/pribatutasuna">{t('home.localLink')}</a>
	</div>
</section>

<!-- ============ Nola dabilen ============ -->
<section class="how">
	<div class="shell">
		<h2 class="section-head"><span class="kicker">{t('home.howHead')}</span></h2>
		<div class="steps">
			<div class="step">
				<span class="num tnum" aria-hidden="true">01</span>
				<h3 class="display step-name">{t('home.how1Name')}</h3>
				<p class="step-desc">{t('home.how1Desc')}</p>
			</div>
			<div class="step">
				<span class="num tnum" aria-hidden="true">02</span>
				<h3 class="display step-name">{t('home.how2Name')}</h3>
				<p class="step-desc">{t('home.how2Desc')}</p>
			</div>
			<div class="step">
				<span class="num tnum" aria-hidden="true">03</span>
				<h3 class="display step-name">{t('home.how3Name')}</h3>
				<p class="step-desc">{t('home.how3Desc')}</p>
			</div>
		</div>
	</div>
</section>

<!-- ============ Instalatu ============ -->
<section class="install" id="mac">
	<div class="shell">
		<h2 class="section-head"><span class="kicker">{t('home.installHead')}</span></h2>
		<div class="install-grid">
			<article class="panel install-card">
				<p class="kicker accent">{t('home.installMacKicker')}</p>
				<h3 class="display install-name">{t('home.installMacTitle')}</h3>
				<p class="install-req">{t('home.installMacReq')}</p>
				<a class="btn btn-primary install-dl" href={MAC_DOWNLOAD_URL} rel="noopener">
					<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
						<path d="M12 3.5v11" />
						<path d="M7 10l5 4.5L17 10" />
						<path d="M4.5 19.5h15" />
					</svg>
					{t('home.installMacCta')}
				</a>
				<p class="install-note">
					{t('home.installMacMeta', { version: MAC_DOWNLOAD_VERSION })}
				</p>
				<ol class="install-steps">
					<li>{t('home.installMac1')}</li>
					<li>{t('home.installMac2')}</li>
					<li>{t('home.installMac3')}</li>
				</ol>
				<a class="btn-text install-alt" href={GITHUB_URL} rel="noopener">
					{t('home.installMacAlt')}<span aria-hidden="true"> ↗</span>
				</a>
			</article>
		</div>
	</div>
</section>

<!-- ============ Kredituak ============ -->
<section class="credits">
	<div class="shell">
		<h2 class="section-head"><span class="kicker">{t('home.creditsHead')}</span></h2>
		<p class="credits-intro">{t('home.creditsIntro')}</p>
		<ul class="credit-list">
			<li>
				<a href={HITZ_URL} rel="noopener">{t('home.creditHitzName')}</a>
				<span class="credit-desc">{t('home.creditHitzDesc')}</span>
			</li>
			<li>
				<a href={XEZPELETA_URL} rel="noopener">{t('home.creditXezName')}</a>
				<span class="credit-desc">{t('home.creditXezDesc')}</span>
			</li>
			<li>
				<a href={COMMON_VOICE_URL} rel="noopener">{t('home.creditCvName')}</a>
				<span class="credit-desc">
					{t('home.creditCvDesc')}
					<a class="cv-link" href={COMMON_VOICE_URL} rel="noopener">{t('home.creditCvLink')}</a>
				</span>
			</li>
			<li>
				<span class="credit-pair">
					<a href={WHISPER_CPP_URL} rel="noopener">whisper.cpp</a>
					<span aria-hidden="true"> · </span>
					<a href={LLAMA_CPP_URL} rel="noopener">llama.cpp</a>
				</span>
				<span class="credit-desc">{t('home.creditGgmlDesc')}</span>
			</li>
		</ul>
	</div>
</section>

<style>
	/* ---------- entrée en scène ---------- */
	.rise {
		animation: rise 640ms cubic-bezier(0.2, 0.7, 0.3, 1) both;
		animation-delay: var(--d, 0ms);
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(14px);
		}
		to {
			opacity: 1;
			transform: none;
		}
	}

	/* ---------- hero ---------- */
	.hero {
		padding-block: clamp(3.5rem, 8vw, 6.5rem) 0;
		overflow: hidden;
	}

	.hero-copy {
		display: grid;
		justify-items: center;
		text-align: center;
	}

	.hero-kicker {
		color: var(--gorri);
	}

	.hero-title {
		font-size: clamp(2.875rem, 8.5vw, 5.75rem);
		font-weight: 660;
		max-width: 16ch;
		margin-top: 1.125rem;
	}

	.hero-sub {
		color: var(--ink-2);
		font-size: clamp(1.0625rem, 1.6vw, 1.25rem);
		line-height: 1.55;
		max-width: 44ch;
		margin-top: 1.375rem;
		text-wrap: balance;
	}

	.ctas {
		display: flex;
		gap: 0.875rem;
		flex-wrap: wrap;
		justify-content: center;
		margin-top: 2.25rem;
	}

	/* la scène produit : fenêtre + capsule flottante */
	.stage-wrap {
		max-width: 66rem;
	}

	.stage {
		position: relative;
		margin-top: clamp(3rem, 7vw, 5.5rem);
		padding-bottom: clamp(2.5rem, 5vw, 4rem);
	}

	.hud-float {
		position: absolute;
		left: 50%;
		bottom: 0;
		width: min(26rem, 58%);
		height: auto;
		transform: translate(-50%, 8%);
		animation: hud-breath var(--motion-breath) ease-in-out infinite alternate;
		pointer-events: none;
	}

	@keyframes hud-breath {
		from {
			transform: translate(-50%, 8%);
		}
		to {
			transform: translate(-50%, 3%);
		}
	}

	/* ---------- sections feature ---------- */
	.feature {
		padding-block: clamp(3.5rem, 8vw, 6.5rem);
	}

	.feature + .feature {
		padding-top: 0;
	}

	.feature-grid {
		display: grid;
		grid-template-columns: minmax(0, 5fr) minmax(0, 7fr);
		gap: clamp(2rem, 6vw, 5rem);
		align-items: center;
	}

	.feature-grid.flip {
		grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
	}

	.feature-grid.flip .feature-copy {
		order: 2;
	}

	.accent {
		color: var(--gorri);
	}

	.feature-title {
		font-size: clamp(1.75rem, 3.4vw, 2.5rem);
		margin-top: 0.875rem;
	}

	.feature-body {
		color: var(--ink-2);
		font-size: 1.0625rem;
		line-height: 1.65;
		margin-top: 1rem;
		max-width: 42ch;
	}

	/* panneau pierre commun aux visuels */
	.panel {
		background: var(--surface-2);
		border: 1px solid var(--hairline);
		border-radius: 1.25rem;
		margin: 0;
	}

	.hud-panel {
		display: grid;
		justify-items: center;
		gap: 0.25rem;
		padding: clamp(1.75rem, 4vw, 3rem) clamp(1rem, 3vw, 2.5rem);
	}

	.hud-panel img {
		width: min(33rem, 100%);
		height: auto;
	}

	.panel-caption {
		font-size: 0.8125rem;
		color: var(--ink-3);
		text-align: center;
		max-width: 38ch;
		line-height: 1.55;
	}

	/* ---------- mockup vocal ---------- */
	.chat-panel {
		display: grid;
		justify-items: start;
		padding: clamp(1.75rem, 4vw, 2.75rem);
	}

	.chat-in {
		display: inline-flex;
		align-items: center;
		gap: 0.875rem;
		background: var(--surface);
		border: 1px solid var(--hairline);
		border-radius: 1.125rem 1.125rem 1.125rem 0.25rem;
		padding: 0.875rem 1.125rem;
		box-shadow: var(--shadow-card);
	}

	.chat-wave {
		display: inline-flex;
		align-items: center;
		gap: 2.5px;
	}

	.chat-bar {
		width: 2.5px;
		border-radius: 1.25px;
		background: var(--ink-3);
	}

	.chat-dur {
		font-size: 0.75rem;
		color: var(--ink-2);
	}

	.chat-name {
		margin-top: 0.5rem;
		font-size: 0.6875rem;
		color: var(--ink-3);
	}

	.chat-link {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		color: var(--gorri);
		margin-block: 1.125rem;
	}

	.chat-out {
		justify-self: stretch;
		background: var(--surface);
		border: 1px solid var(--hairline);
		border-radius: 0.875rem;
		padding: 1.125rem 1.25rem;
		box-shadow: var(--shadow-card);
	}

	.chat-text {
		font-size: 0.9688rem;
		line-height: 1.6;
	}

	.chat-meta {
		display: flex;
		align-items: center;
		gap: 0.4375rem;
		margin-top: 0.75rem;
		font-size: 0.6875rem;
		color: var(--ink-2);
	}

	.chat-dot {
		color: var(--ink-3);
	}

	.chat-lang {
		font-size: 0.625rem;
		font-weight: 650;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--gorri);
		background: var(--gorri-12);
		border-radius: 0.25rem;
		padding: 0.0625rem 0.375rem;
	}

	/* ---------- bloc rouge : le moment de marque ---------- */
	.local {
		position: relative;
		background: var(--fill-red);
		color: var(--on-red);
		padding-block: clamp(4.5rem, 10vw, 8rem);
		overflow: hidden;
	}

	.local-mark {
		position: absolute;
		right: -8rem;
		top: 50%;
		width: clamp(24rem, 44vw, 36rem);
		aspect-ratio: 1;
		transform: translateY(-50%) rotate(12deg);
		background: currentColor;
		opacity: 0.1;
		mask: url('/brand/lauburu.svg') no-repeat center / contain;
		-webkit-mask: url('/brand/lauburu.svg') no-repeat center / contain;
		pointer-events: none;
	}

	.local-inner {
		position: relative;
		display: grid;
		justify-items: start;
	}

	.local-kicker {
		color: var(--on-red-soft);
	}

	.local-title {
		font-size: clamp(2rem, 5.5vw, 3.75rem);
		max-width: 18ch;
		margin-top: 1.125rem;
	}

	.local-body {
		color: var(--on-red-soft);
		font-size: 1.0625rem;
		line-height: 1.65;
		max-width: 56ch;
		margin-top: 1.25rem;
	}

	.local-link {
		margin-top: 1.75rem;
		color: var(--on-red);
		font-size: 0.9375rem;
		font-weight: 560;
		text-decoration-color: var(--on-red-soft);
	}

	.local-link:hover {
		text-decoration-color: var(--on-red);
	}

	/* ---------- nola dabilen ---------- */
	.how,
	.install,
	.credits {
		padding-block: clamp(3rem, 7vw, 5rem) 0;
	}

	.steps {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: clamp(1.5rem, 4vw, 3rem);
		margin-top: 2.25rem;
	}

	.step {
		display: grid;
		gap: 0.5rem;
		align-content: start;
	}

	.num {
		font-family: var(--font-display);
		font-optical-sizing: auto;
		font-weight: 560;
		font-size: 1.125rem;
		color: var(--gorri);
	}

	.step-name {
		font-size: 1.375rem;
	}

	.step-desc {
		color: var(--ink-2);
		font-size: 0.9375rem;
		line-height: 1.6;
		max-width: 34ch;
	}

	/* ---------- instalatu ---------- */
	.install-grid {
		display: grid;
		grid-template-columns: minmax(0, 40rem);
		justify-content: center;
		margin-top: 2.25rem;
	}

	.install-card {
		display: grid;
		justify-items: start;
		align-content: start;
		padding: clamp(1.75rem, 4vw, 2.5rem);
	}

	.install-name {
		font-size: clamp(1.375rem, 2.4vw, 1.75rem);
		margin-top: 0.875rem;
		max-width: 20ch;
	}

	.install-req {
		color: var(--ink-2);
		font-size: 0.9375rem;
		line-height: 1.6;
		margin-top: 0.75rem;
		max-width: 44ch;
	}

	.install-dl {
		margin-top: 1.5rem;
	}

	.install-note {
		margin-top: 0.875rem;
		font-size: 0.8125rem;
		color: var(--ink-3);
	}

	.install-steps {
		list-style: none;
		counter-reset: step;
		display: grid;
		gap: 1rem;
		margin: 1.75rem 0 0;
		padding: 1.75rem 0 0;
		border-top: 1px solid var(--hairline);
		justify-self: stretch;
	}

	.install-steps li {
		counter-increment: step;
		position: relative;
		padding-left: 2.375rem;
		font-size: 0.9375rem;
		line-height: 1.6;
		color: var(--ink-2);
		max-width: 44ch;
	}

	.install-steps li::before {
		content: counter(step, decimal-leading-zero);
		position: absolute;
		left: 0;
		top: 0.1em;
		font-family: var(--font-display);
		font-optical-sizing: auto;
		font-weight: 560;
		font-size: 0.9375rem;
		font-variant-numeric: tabular-nums;
		color: var(--gorri);
	}

	.install-alt {
		margin-top: 1.75rem;
	}

	/* ---------- crédits ---------- */
	.credits-intro {
		margin-top: 2rem;
		font-size: 0.9375rem;
		color: var(--ink-2);
		max-width: 52ch;
	}

	.credit-list {
		list-style: none;
		margin: 1.25rem 0 0;
		padding: 0;
	}

	.credit-list li {
		display: grid;
		grid-template-columns: minmax(13rem, 17rem) 1fr;
		gap: 2rem;
		padding-block: 1.125rem;
		font-size: 0.9375rem;
		line-height: 1.6;
	}

	.credit-list li + li {
		border-top: 1px solid var(--hairline);
	}

	.credit-list a {
		font-weight: 500;
	}

	.credit-desc {
		color: var(--ink-2);
	}

	.cv-link {
		color: var(--gorri);
		text-decoration-color: var(--gorri-24);
	}

	/* ---------- responsive ---------- */
	@media (max-width: 56rem) {
		.hero-title {
			font-size: clamp(2.5rem, 11.5vw, 3.5rem);
		}

		.hud-float {
			width: min(20rem, 74%);
		}

		.feature-grid,
		.feature-grid.flip {
			grid-template-columns: 1fr;
			gap: 1.75rem;
		}

		.feature-grid.flip .feature-copy {
			order: 0;
		}

		.steps {
			grid-template-columns: 1fr;
			gap: 1.75rem;
		}

		.install-grid {
			grid-template-columns: 1fr;
		}

		.credit-list li {
			grid-template-columns: 1fr;
			gap: 0.25rem;
		}

		.local-mark {
			right: -10rem;
			opacity: 0.08;
		}
	}
</style>

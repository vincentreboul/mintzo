<script lang="ts">
	import { t } from '$lib/i18n/index.svelte';
	import Seismograph from '$lib/components/Seismograph.svelte';
	import {
		GITHUB_URL,
		COMMON_VOICE_URL,
		HITZ_URL,
		XEZPELETA_URL,
		WHISPER_CPP_URL,
		LLAMA_CPP_URL
	} from '$lib/links';
</script>

<svelte:head>
	<title>{t('home.metaTitle')}</title>
	<meta name="description" content={t('home.metaDescription')} />
</svelte:head>

<div class="shell">
	<!-- ============ Hero ============ -->
	<section class="hero">
		<div class="hero-main">
			<h1 class="wordmark">Mintzo</h1>
			<div class="seismo-row">
				<Seismograph />
			</div>
			<p class="tagline">{t('home.tagline')}</p>
			<p class="sub">{t('home.sub')}</p>
			<div class="ctas">
				<a class="btn btn-primary" href="/tresna">{t('home.ctaTool')}</a>
				<a class="btn btn-quiet" href="#mac">{t('home.ctaMac')}<span aria-hidden="true"> ↓</span></a>
			</div>
		</div>
		<aside class="hero-notes">
			<p class="kicker langs-note">eu · fr</p>
			<p class="note">{t('home.macPrivacy')}</p>
		</aside>
	</section>

	<!-- ============ La promesse en 3 blocs ============ -->
	<section class="promises">
		<article>
			<p class="kicker accent">{t('home.b1Kicker')}</p>
			<h2 class="display block-title">{t('home.b1Title')}</h2>
			<p class="block-body">{t('home.b1Body')}</p>
		</article>
		<article>
			<p class="kicker accent">{t('home.b2Kicker')}</p>
			<h2 class="display block-title">{t('home.b2Title')}</h2>
			<p class="block-body">{t('home.b2Body')}</p>
		</article>
		<article>
			<p class="kicker accent">{t('home.b3Kicker')}</p>
			<h2 class="display block-title">{t('home.b3Title')}</h2>
			<p class="block-body">{t('home.b3Body')}</p>
		</article>
	</section>

	<!-- ============ Nola dabilen ============ -->
	<section class="how">
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
	</section>

	<!-- ============ Mac aplikazioa ============ -->
	<section class="mac" id="mac">
		<h2 class="section-head"><span class="kicker">{t('home.macHead')}</span></h2>
		<div class="mac-body">
			<div class="mac-text">
				<p class="display mac-status">{t('home.macStatus')}</p>
				<p class="mac-req">{t('home.macBody')}</p>
				<blockquote class="mac-privacy read">{t('home.macPrivacy')}</blockquote>
				<!-- TODO-URL -->
				<a class="btn btn-quiet mac-cta" href={GITHUB_URL} rel="noopener">
					{t('home.macGithub')}<span aria-hidden="true"> ↗</span>
				</a>
			</div>
			<div class="build-card">
				<p class="kicker">{t('home.macBuildLabel')}</p>
				<pre><code>brew install xcodegen
scripts/fetch-whisper-xcframework.sh
scripts/fetch-llama-xcframework.sh
xcodegen generate</code></pre>
				<p class="build-hint">{t('home.macBuildHint')}</p>
			</div>
		</div>
	</section>

	<!-- ============ Kredituak ============ -->
	<section class="credits">
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
	</section>
</div>

<style>
	/* ---------- hero ---------- */
	.hero {
		display: grid;
		grid-template-columns: 1fr auto;
		align-items: end;
		gap: 3rem;
		padding-block: clamp(3.5rem, 9vw, 7rem) clamp(3.5rem, 8vw, 6rem);
	}

	.wordmark {
		font-family: var(--font-display);
		font-optical-sizing: auto;
		font-weight: 900;
		font-size: clamp(4.75rem, 13vw, 10.5rem);
		line-height: 0.95;
		letter-spacing: -0.015em;
		margin-left: -0.04em;
		color: var(--ink);
	}

	.seismo-row {
		margin-top: clamp(1.5rem, 3vw, 2.25rem);
	}

	.tagline {
		font-family: var(--font-read);
		font-optical-sizing: auto;
		font-size: clamp(1.25rem, 2.2vw, 1.5rem);
		line-height: 1.45;
		max-width: 30ch;
		margin-top: clamp(1.75rem, 3.5vw, 2.5rem);
	}

	.sub {
		color: var(--ink-2);
		font-size: 1rem;
		line-height: 1.6;
		max-width: 52ch;
		margin-top: 0.875rem;
	}

	.ctas {
		display: flex;
		gap: 0.75rem;
		flex-wrap: wrap;
		margin-top: 2.25rem;
	}

	.hero-notes {
		border-left: 1px solid var(--hairline);
		padding-left: 1.5rem;
		max-width: 13rem;
		padding-bottom: 0.375rem;
	}

	.langs-note {
		color: var(--gorri);
	}

	.note {
		margin-top: 0.875rem;
		font-size: 0.8125rem;
		line-height: 1.55;
		color: var(--ink-3);
	}

	/* ---------- blocs promesse ---------- */
	.promises {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		border-top: 1px solid var(--hairline);
		padding-block: clamp(3rem, 6.5vw, 4.5rem);
	}

	.promises article {
		padding-inline: 2rem;
		border-left: 1px solid var(--hairline);
	}

	.promises article:first-child {
		padding-left: 0;
		border-left: none;
	}

	.promises article:last-child {
		padding-right: 0;
	}

	.accent {
		color: var(--gorri);
	}

	.block-title {
		font-size: 1.5rem;
		margin-top: 0.875rem;
	}

	.block-body {
		color: var(--ink-2);
		font-size: 0.9375rem;
		line-height: 1.65;
		margin-top: 0.75rem;
		max-width: 36ch;
	}

	/* ---------- nola dabilen ---------- */
	.how,
	.mac,
	.credits {
		padding-block: clamp(2.75rem, 6vw, 4.5rem);
	}

	.steps {
		margin-top: 2rem;
	}

	.step {
		display: grid;
		grid-template-columns: 3.5rem 15rem 1fr;
		align-items: baseline;
		gap: 1.5rem;
		padding-block: 1.375rem;
	}

	.step + .step {
		border-top: 1px solid var(--hairline);
	}

	.num {
		font-family: var(--font-display);
		font-optical-sizing: auto;
		font-weight: 560;
		font-size: 1.25rem;
		color: var(--gorri);
	}

	.step-name {
		font-size: 1.4375rem;
	}

	.step-desc {
		color: var(--ink-2);
		font-size: 0.9375rem;
		line-height: 1.6;
	}

	/* ---------- mac ---------- */
	.mac-body {
		display: grid;
		grid-template-columns: 1.1fr 0.9fr;
		gap: clamp(2rem, 5vw, 4rem);
		margin-top: 2rem;
		align-items: start;
	}

	.mac-status {
		font-size: clamp(1.375rem, 2.4vw, 1.75rem);
		max-width: 24ch;
	}

	.mac-req {
		color: var(--ink-2);
		font-size: 0.9375rem;
		line-height: 1.6;
		margin-top: 1rem;
		max-width: 44ch;
	}

	.mac-privacy {
		margin: 1.75rem 0 0;
		padding-left: 1.125rem;
		border-left: 2px solid var(--gorri);
		font-size: 1.0625rem;
		color: var(--ink);
	}

	.mac-cta {
		margin-top: 1.75rem;
	}

	.build-card {
		background: var(--surface);
		border: 1px solid var(--hairline);
		border-radius: 0.75rem;
		padding: 1.5rem;
	}

	.build-card .kicker {
		color: var(--ink-2);
	}

	.build-card pre {
		margin: 1rem 0 0;
		overflow-x: auto;
		font-family: var(--font-mono);
		font-size: 0.8125rem;
		line-height: 1.8;
		color: var(--ink);
	}

	.build-hint {
		margin-top: 1rem;
		font-size: 0.8125rem;
		color: var(--ink-3);
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
		.hero {
			grid-template-columns: 1fr;
			gap: 0;
		}

		.hero-notes {
			display: none;
		}

		.promises {
			grid-template-columns: 1fr;
			padding-block: 1rem 1.5rem;
		}

		.promises article {
			padding: 1.75rem 0;
			border-left: none;
		}

		.promises article + article {
			border-top: 1px solid var(--hairline);
		}

		.step {
			grid-template-columns: 2.75rem 1fr;
			row-gap: 0.375rem;
		}

		.step-desc {
			grid-column: 2;
		}

		.mac-body {
			grid-template-columns: 1fr;
		}

		.credit-list li {
			grid-template-columns: 1fr;
			gap: 0.25rem;
		}
	}
</style>

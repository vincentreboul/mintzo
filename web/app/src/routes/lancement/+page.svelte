<script lang="ts">
	import { GITHUB_URL, COMMON_VOICE_URL } from '$lib/links';
</script>

<svelte:head>
	<title>Mintzo — annonce · iragarpena</title>
	<meta
		name="description"
		content="Mintzo est open source : dictée et transcription pour le basque et le français, 100 % locales sur Mac. Mintzo kode irekian dago."
	/>
</svelte:head>

<!-- Page d'annonce publique : une seule page, français d'abord puis euskara (#eu). -->
<div class="shell page">
	<p class="switch"><a href="#eu">Euskaraz irakurri ↓</a></p>

	<!-- ============ Français ============ -->
	<article lang="fr" id="fr">
		<p class="kicker accent">Annonce — juillet 2026</p>
		<h1 class="display title">Mintzo est open source.</h1>
		<p class="lead">
			Dictée et transcription pour le basque et le français — gratuites, locales, libres.
		</p>

		<p>
			Mintzo est une application de dictée et de transcription pour l’euskara et le français.
			Sur Mac, une touche suffit : on parle, et le texte corrigé se pose au curseur, dans
			n’importe quelle application. Un outil en ligne transcrit aussi les fichiers audio —
			vocaux WhatsApp compris — directement depuis le navigateur.
		</p>

		<h2 class="display sub">Pourquoi</h2>
		<p>
			L’euskara mérite des outils de premier rang — les mêmes que ceux dont disposent l’anglais
			ou le français. La communauté des technologies de la langue basque a déjà fait le plus
			dur : les modèles du centre HiTZ, les voix de Common Voice, des années de travail libre.
			Mintzo transforme ce travail en outil quotidien. Sur Mac, tout se passe en local : l’audio
			ne quitte jamais la machine.
		</p>

		<h2 class="display sub">Ce que fait la première version</h2>
		<ul>
			<li>Dictée système au curseur, en basque et en français.</li>
			<li>Transcription de fichiers audio (.opus, .m4a, .mp3…).</li>
			<li>Correction locale par Latxa : orthographe, ponctuation, majuscules.</li>
			<li>Historique local, avec recherche plein texte.</li>
			<li>Hors ligne, une fois les modèles téléchargés.</li>
		</ul>

		<blockquote class="privacy read">L’audio ne quitte jamais votre Mac.</blockquote>

		<h2 class="display sub">Un projet à construire ensemble</h2>
		<p>
			Testez, ouvrez des issues, proposez des correctifs. Les retours sur les dialectes sont
			particulièrement précieux : plus les voix sont variées, meilleure est la reconnaissance.
			Vous pouvez aussi donner votre voix au corpus
			<a href={COMMON_VOICE_URL} rel="noopener">Common Voice</a> — quelques phrases suffisent.
			La localisation suit les conventions de Librezale et reste ouverte à la relecture de la
			communauté.
		</p>

		<p class="actions">
			<!-- TODO-URL -->
			<a class="btn btn-primary" href={GITHUB_URL} rel="noopener">
				Le code sur GitHub<span aria-hidden="true"> ↗</span>
			</a>
		</p>
		<p class="license">
			Code sous licence MIT. Les modèles téléchargés à l’exécution ont chacun leur propre
			licence.
		</p>
	</article>

	<hr class="hairline sep" />

	<!-- ============ Euskara ============ -->
	<article lang="eu" id="eu">
		<p class="switch back"><a href="#fr">Lire en français ↑</a></p>
		<p class="kicker accent">Iragarpena — 2026ko uztaila</p>
		<h2 class="display title">Mintzo kode irekian dago.</h2>
		<p class="lead">
			Diktaketa eta transkripzioa euskararako eta frantseserako — doan, lokalean, libre.
		</p>

		<p>
			Mintzo euskararako eta frantseserako diktaketa- eta transkripzio-aplikazio bat da.
			Mac-ean, tekla bat aski da: hitz egin, eta testu zuzendua kurtsorean itsasten da, edozein
			aplikaziotan. Lineako tresna batek audio-fitxategiak ere transkribatzen ditu — WhatsAppeko
			ahots-mezuak barne — nabigatzailetik bertatik.
		</p>

		<h3 class="display sub">Zergatik</h3>
		<p>
			Euskarak lehen mailako tresnak merezi ditu — ingelesak eta frantsesak dituztenen
			parekoak. Euskal hizkuntza-teknologien komunitateak egin du zailena: HiTZ zentroaren
			ereduak, Common Voice-ko ahotsak, urteetako lan librea. Mintzok lan hori eguneroko tresna
			bihurtzen du. Mac-ean, dena lokalki gertatzen da: audioa ez da inoiz makinatik ateratzen.
		</p>

		<h3 class="display sub">Zer dakarren lehen bertsioak</h3>
		<ul>
			<li>Diktaketa sistema osoan, kurtsorean, euskaraz eta frantsesez.</li>
			<li>Audio-fitxategien transkripzioa (.opus, .m4a, .mp3…).</li>
			<li>Zuzenketa lokala Latxarekin: ortografia, puntuazioa, maiuskulak.</li>
			<li>Historia lokala, testu osoko bilaketarekin.</li>
			<li>Konexiorik gabe dabil, ereduak behin deskargatuta.</li>
		</ul>

		<blockquote class="privacy read">Audioa ez da inoiz zure Mac-etik ateratzen.</blockquote>

		<h3 class="display sub">Elkarrekin eraikitzeko proiektua</h3>
		<p>
			Probatu, ireki issueak, proposatu hobekuntzak. Euskalkiei buruzko oharrak bereziki
			baliotsuak dira: zenbat eta ahots gehiago, orduan eta ezagutza hobea. Zure ahotsa ere
			eman diezaiokezu <a href={COMMON_VOICE_URL} rel="noopener">Common Voice</a> corpusari —
			esaldi gutxi batzuk aski dira. Lokalizazioak Librezaleren konbentzioei jarraitzen die, eta
			komunitatearen berrikuspenera zabalik dago.
		</p>

		<p class="actions">
			<!-- TODO-URL -->
			<a class="btn btn-primary" href={GITHUB_URL} rel="noopener">
				Kodea GitHub-en<span aria-hidden="true"> ↗</span>
			</a>
		</p>
		<p class="license">
			Kodea MIT lizentziapean. Exekuzioan deskargatzen diren ereduek nork bere lizentzia dute.
		</p>
	</article>
</div>

<style>
	.page {
		max-width: 46rem;
		padding-block: clamp(2.5rem, 6vw, 4rem) clamp(2rem, 5vw, 3rem);
	}

	.switch {
		font-size: 0.8125rem;
	}

	.switch a {
		color: var(--ink-2);
	}

	.switch a:hover {
		color: var(--gorri);
	}

	article {
		margin-top: clamp(2.25rem, 5vw, 3.5rem);
	}

	.back {
		margin-bottom: 2rem;
	}

	.accent {
		color: var(--gorri);
	}

	.accent::before {
		content: '';
		display: block;
		width: 2.5rem;
		height: 3px;
		border-radius: 2px;
		background: var(--gorri);
		margin-bottom: 1.5rem;
	}

	.title {
		font-size: clamp(2.125rem, 5.5vw, 3rem);
		margin-top: 1rem;
	}

	.lead {
		margin-top: 1rem;
		font-family: var(--font-read);
		font-optical-sizing: auto;
		font-size: 1.1875rem;
		line-height: 1.5;
		color: var(--ink-2);
		max-width: 48ch;
	}

	article > p:not(.lead):not(.kicker):not(.switch):not(.actions):not(.license) {
		margin-top: 1.5rem;
		font-size: 0.9688rem;
		line-height: 1.75;
		color: var(--ink-2);
		max-width: 64ch;
	}

	.sub {
		font-size: 1.4375rem;
		margin-top: clamp(2.25rem, 5vw, 3rem);
	}

	ul {
		margin: 1.25rem 0 0;
		padding: 0;
		list-style: none;
	}

	li {
		position: relative;
		padding-left: 1.375rem;
		font-size: 0.9375rem;
		line-height: 1.7;
		color: var(--ink-2);
		margin-top: 0.5rem;
	}

	li::before {
		content: '';
		position: absolute;
		left: 0;
		top: 0.71em;
		width: 0.5rem;
		height: 2px;
		border-radius: 1px;
		background: var(--gorri);
	}

	.privacy {
		margin: 2.25rem 0 0;
		padding-left: 1.125rem;
		border-left: 2px solid var(--gorri);
		font-size: 1.125rem;
		color: var(--ink);
	}

	.actions {
		margin-top: 2.25rem;
	}

	.license {
		margin-top: 1.25rem;
		font-size: 0.8125rem;
		color: var(--ink-3);
		max-width: 56ch;
		line-height: 1.6;
	}

	.sep {
		margin-top: clamp(3rem, 7vw, 4.5rem);
	}

	article a:not(.btn) {
		color: var(--ink);
	}
</style>

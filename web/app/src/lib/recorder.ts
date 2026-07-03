/**
 * Dictée au micro — getUserMedia + MediaRecorder.
 * Conteneur choisi par capacité : audio/webm;codecs=opus (Chrome, Firefox,
 * Edge, Safari 18.4+), repli audio/mp4 (Safari iOS plus ancien).
 * Le niveau LIVE sort d'un AnalyserNode (RMS), pour la capsule waveform.
 */

export type RecorderErrorKind = 'denied' | 'unsupported' | 'failed';

export class RecorderError extends Error {
	kind: RecorderErrorKind;

	constructor(kind: RecorderErrorKind) {
		super(kind);
		this.kind = kind;
	}
}

export interface RecorderHandle {
	/** Extension du fichier produit — le serveur route le décodage dessus. */
	ext: 'webm' | 'mp4';
	/** Arrêt propre : rend le fichier prêt à envoyer. */
	stop(): Promise<File>;
	/** Abandon : jette tout, coupe le micro. */
	discard(): void;
}

function pickMime(): { mime: string; ext: 'webm' | 'mp4' } | null {
	if (typeof MediaRecorder === 'undefined') return null;
	if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
		return { mime: 'audio/webm;codecs=opus', ext: 'webm' };
	}
	if (MediaRecorder.isTypeSupported('audio/mp4')) {
		return { mime: 'audio/mp4', ext: 'mp4' };
	}
	return null;
}

export function recordingSupported(): boolean {
	return (
		typeof navigator !== 'undefined' &&
		!!navigator.mediaDevices?.getUserMedia &&
		pickMime() !== null
	);
}

/**
 * Démarre l'enregistrement. `onLevel` reçoit ~20 fois/s un niveau 0..1
 * (RMS normalisé) pour animer la waveform de la capsule.
 */
export async function startRecording(
	onLevel: (level: number) => void
): Promise<RecorderHandle> {
	const picked = pickMime();
	if (!picked || !navigator.mediaDevices?.getUserMedia) {
		throw new RecorderError('unsupported');
	}

	let stream: MediaStream;
	try {
		stream = await navigator.mediaDevices.getUserMedia({ audio: true });
	} catch (e) {
		const name = e instanceof DOMException ? e.name : '';
		throw new RecorderError(
			name === 'NotAllowedError' || name === 'SecurityError' ? 'denied' : 'failed'
		);
	}

	let recorder: MediaRecorder;
	try {
		recorder = new MediaRecorder(stream, { mimeType: picked.mime });
	} catch {
		stream.getTracks().forEach((t) => t.stop());
		throw new RecorderError('unsupported');
	}

	const chunks: Blob[] = [];
	recorder.addEventListener('dataavailable', (e) => {
		if (e.data.size > 0) chunks.push(e.data);
	});

	/* niveau live — AnalyserNode, RMS sur le domaine temporel */
	const audioCtx = new AudioContext();
	const source = audioCtx.createMediaStreamSource(stream);
	const analyser = audioCtx.createAnalyser();
	analyser.fftSize = 512;
	source.connect(analyser);
	const buf = new Uint8Array(analyser.fftSize);

	let raf = 0;
	let lastEmit = 0;
	const tick = (ts: number) => {
		raf = requestAnimationFrame(tick);
		if (ts - lastEmit < 45) return; // ~20 Hz suffit à la capsule
		lastEmit = ts;
		analyser.getByteTimeDomainData(buf);
		let sum = 0;
		for (let i = 0; i < buf.length; i++) {
			const v = (buf[i] - 128) / 128;
			sum += v * v;
		}
		const rms = Math.sqrt(sum / buf.length);
		/* la voix parlée plafonne vers ~0.35 RMS : normalisation douce */
		onLevel(Math.min(1, rms * 3.2));
	};
	raf = requestAnimationFrame(tick);

	const cleanup = () => {
		cancelAnimationFrame(raf);
		source.disconnect();
		stream.getTracks().forEach((t) => t.stop());
		void audioCtx.close().catch(() => undefined);
	};

	recorder.start(250);

	return {
		ext: picked.ext,
		stop(): Promise<File> {
			return new Promise((resolve, reject) => {
				recorder.addEventListener(
					'stop',
					() => {
						cleanup();
						const blob = new Blob(chunks, { type: picked.mime.split(';')[0] });
						if (blob.size === 0) {
							reject(new RecorderError('failed'));
							return;
						}
						const d = new Date();
						const hh = String(d.getHours()).padStart(2, '0');
						const mm = String(d.getMinutes()).padStart(2, '0');
						resolve(
							new File([blob], `diktaketa-${hh}${mm}.${picked.ext}`, { type: blob.type })
						);
					},
					{ once: true }
				);
				try {
					recorder.stop();
				} catch {
					cleanup();
					reject(new RecorderError('failed'));
				}
			});
		},
		discard(): void {
			try {
				recorder.stop();
			} catch {
				/* déjà arrêté */
			}
			cleanup();
			chunks.length = 0;
		}
	};
}

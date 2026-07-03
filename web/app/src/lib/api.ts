/**
 * Client de l'API de transcription (contrat ADR-002).
 * AUCUN octet ne part ailleurs que VITE_API_URL — pas de tiers, pas de CDN.
 */

export interface TranscribeResult {
	text: string;
	rawText: string;
	language: string;
	durationSeconds: number;
	timings?: Record<string, number>;
}

export type ApiErrorKind = 'too-big' | 'format' | 'server' | 'timeout' | 'aborted';

export class ApiError extends Error {
	kind: ApiErrorKind;

	constructor(kind: ApiErrorKind) {
		super(kind);
		this.kind = kind;
	}
}

export const API_URL: string =
	(import.meta.env.VITE_API_URL as string | undefined) || 'http://localhost:8787';

export const MAX_FILE_BYTES = 50 * 1024 * 1024;
const TIMEOUT_MS = 300_000;

export interface TranscribeHandle {
	promise: Promise<TranscribeResult>;
	abort: () => void;
}

/**
 * POST /v1/transcribe — multipart { file, language eu|fr, correct bool }.
 * XHR plutôt que fetch : c'est le seul moyen d'avoir la progression d'upload.
 */
export function transcribe(
	file: File,
	language: 'eu' | 'fr',
	correct: boolean,
	onProgress?: (fraction: number) => void
): TranscribeHandle {
	const xhr = new XMLHttpRequest();

	const promise = new Promise<TranscribeResult>((resolve, reject) => {
		const form = new FormData();
		form.append('file', file, file.name);
		form.append('language', language);
		form.append('correct', String(correct));

		xhr.open('POST', `${API_URL}/v1/transcribe`);
		xhr.timeout = TIMEOUT_MS;
		xhr.responseType = 'json';

		if (onProgress) {
			xhr.upload.addEventListener('progress', (e) => {
				if (e.lengthComputable) onProgress(e.loaded / e.total);
			});
		}

		xhr.addEventListener('load', () => {
			if (xhr.status >= 200 && xhr.status < 300 && xhr.response) {
				resolve(xhr.response as TranscribeResult);
			} else if (xhr.status === 413) {
				reject(new ApiError('too-big'));
			} else if (xhr.status === 400 || xhr.status === 415 || xhr.status === 422) {
				reject(new ApiError('format'));
			} else {
				reject(new ApiError('server'));
			}
		});
		xhr.addEventListener('error', () => reject(new ApiError('server')));
		xhr.addEventListener('timeout', () => reject(new ApiError('timeout')));
		xhr.addEventListener('abort', () => reject(new ApiError('aborted')));

		xhr.send(form);
	});

	return { promise, abort: () => xhr.abort() };
}

/** GET /v1/health — utilisé par l'auto-QA, pas par l'UI. */
export async function health(): Promise<boolean> {
	try {
		const res = await fetch(`${API_URL}/v1/health`, { signal: AbortSignal.timeout(4000) });
		return res.ok;
	} catch {
		return false;
	}
}

/**
 * Historique local — IndexedDB, navigateur uniquement.
 * Rien ne part jamais vers un serveur ; « Dena ezabatu » vide tout.
 */

export interface HistoryEntry {
	id: string;
	createdAt: number;
	filename: string;
	language: string;
	durationSeconds: number;
	/** Texte affiché (corrigé si la correction était active). */
	text: string;
	/** Transcription brute (identique à text si pas de correction). */
	rawText: string;
	corrected: boolean;
	processedMs: number;
}

const DB_NAME = 'mintzo';
const DB_VERSION = 1;
const STORE = 'transcriptions';

function openDb(): Promise<IDBDatabase> {
	return new Promise((resolve, reject) => {
		const req = indexedDB.open(DB_NAME, DB_VERSION);
		req.onupgradeneeded = () => {
			const db = req.result;
			if (!db.objectStoreNames.contains(STORE)) {
				const store = db.createObjectStore(STORE, { keyPath: 'id' });
				store.createIndex('createdAt', 'createdAt');
			}
		};
		req.onsuccess = () => resolve(req.result);
		req.onerror = () => reject(req.error);
	});
}

function tx<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
	return openDb().then(
		(db) =>
			new Promise<T>((resolve, reject) => {
				const t = db.transaction(STORE, mode);
				const req = run(t.objectStore(STORE));
				req.onsuccess = () => resolve(req.result);
				req.onerror = () => reject(req.error);
				t.oncomplete = () => db.close();
			})
	);
}

export async function addEntry(entry: HistoryEntry): Promise<void> {
	await tx('readwrite', (s) => s.put(entry));
}

export async function listEntries(): Promise<HistoryEntry[]> {
	const all = await tx<HistoryEntry[]>('readonly', (s) => s.getAll());
	return all.sort((a, b) => b.createdAt - a.createdAt);
}

export async function deleteEntry(id: string): Promise<void> {
	await tx('readwrite', (s) => s.delete(id));
}

export async function clearEntries(): Promise<void> {
	await tx('readwrite', (s) => s.clear());
}

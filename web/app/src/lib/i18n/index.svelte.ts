/**
 * i18n maison — dictionnaires JSON eu (défaut) / fr / en.
 * Défaut : euskara (identité du projet). La détection navigateur ne joue
 * qu'au premier chargement ; un choix explicite est persisté.
 */
import eu from './eu.json';
import fr from './fr.json';
import en from './en.json';

export type Locale = 'eu' | 'fr' | 'en';
export const locales: Locale[] = ['eu', 'fr', 'en'];

const dicts: Record<Locale, Record<string, Record<string, string>>> = { eu, fr, en };
const STORAGE_KEY = 'mintzo:locale';

let current = $state<Locale>('eu');

export function getLocale(): Locale {
	return current;
}

/** Changement explicite (switcher) : appliqué + persisté. */
export function setLocale(l: Locale): void {
	current = l;
	if (typeof document !== 'undefined') document.documentElement.lang = l;
	try {
		localStorage.setItem(STORAGE_KEY, l);
	} catch {
		/* stockage indisponible : le choix vaut pour la session */
	}
}

/** Premier chargement : choix persisté, sinon langue du navigateur, sinon eu. */
export function initLocale(): void {
	let l: Locale = 'eu';
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored === 'eu' || stored === 'fr' || stored === 'en') {
			l = stored;
		} else {
			const nav = (navigator.language ?? '').toLowerCase();
			if (nav.startsWith('fr')) l = 'fr';
			else if (nav.startsWith('en')) l = 'en';
		}
	} catch {
		/* défaut eu */
	}
	current = l;
	document.documentElement.lang = l;
}

/** t('tool.copy') — repli sur eu, puis sur la clé elle-même. */
export function t(key: string, params?: Record<string, string | number>): string {
	const [ns, k] = key.split('.');
	let s = dicts[current]?.[ns]?.[k] ?? dicts.eu?.[ns]?.[k] ?? key;
	if (params) {
		for (const [name, value] of Object.entries(params)) {
			s = s.replaceAll(`{${name}}`, String(value));
		}
	}
	return s;
}

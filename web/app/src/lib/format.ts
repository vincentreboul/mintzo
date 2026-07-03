/** Formats — durées m:ss, heures, groupes de jours (§3.4 : pas de « s » ni « min »). */

export function fmtDuration(seconds: number): string {
	const s = Math.max(0, Math.round(seconds));
	const m = Math.floor(s / 60);
	const r = s % 60;
	return `${m}:${String(r).padStart(2, '0')}`;
}

export function fmtClock(ts: number): string {
	const d = new Date(ts);
	return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export function fmtSeconds(ms: number): string {
	const s = ms / 1000;
	return s < 10 ? s.toFixed(1) : String(Math.round(s));
}

export type DayGroup = 'today' | 'yesterday' | string;

/** 'today' | 'yesterday' | 'YYYY-MM-DD' (clé stable, libellé localisé ailleurs). */
export function dayGroup(ts: number, now: number = Date.now()): DayGroup {
	const d = new Date(ts);
	const n = new Date(now);
	const startOf = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
	const diffDays = Math.round((startOf(n) - startOf(d)) / 86_400_000);
	if (diffDays === 0) return 'today';
	if (diffDays === 1) return 'yesterday';
	return d.toISOString().slice(0, 10);
}

/** Libellé d'un groupe ancien : « ekainak 30 » / « 30 juin » selon la locale. */
export function fmtDay(iso: string, locale: string): string {
	const [y, m, d] = iso.split('-').map(Number);
	try {
		return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long' }).format(
			new Date(y, m - 1, d)
		);
	} catch {
		return iso;
	}
}

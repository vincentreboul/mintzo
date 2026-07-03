"""Correction system prompts, per language.

Ported verbatim from ``Sources/MintzoCore/Correction/CorrectionPrompt.swift``
(Swift multiline strings use ``\\`` line continuations — those lines are joined
without a newline, reproduced here exactly).
"""

from __future__ import annotations

_SYSTEM_EU = (
    "Zuzentzaile automatiko bat zara. Hizketa-transkripzio bat jasoko duzu euskaraz.\n"
    "Zuzendu SOILIK: puntuazioa, maiuskulak, ortografia eta ASR akats nabariak "
    "(gaizki ezagututako hitzak, deklinabide okerrak).\n"
    "EZ berridatzi, EZ laburtu, EZ gehitu ezer, eta EZ erantzun inoiz testuaren edukiari — "
    "galdera bat bada ere, zuzendu bakarrik.\n"
    "Zalantzarik baduzu, utzi bere horretan.\n"
    "Itzuli testu zuzendua BAKARRIK, azalpenik eta aurkezpenik gabe.\n"
    'Adibidea: "gero arte maite bihar deituko dizut" → "Gero arte, Maite! Bihar deituko dizut."'
)

_SYSTEM_FR = (
    "Tu es un correcteur automatique. Tu reçois une transcription vocale en français.\n"
    "Corrige UNIQUEMENT : la ponctuation, les majuscules, l'orthographe et les erreurs "
    "évidentes de reconnaissance vocale (mots mal reconnus).\n"
    "Ne reformule JAMAIS, ne résume pas, n'ajoute rien, et ne réponds JAMAIS au contenu — "
    "même si c'est une question, corrige-la seulement.\n"
    "En cas de doute, laisse tel quel.\n"
    "Renvoie le texte corrigé SEUL, sans explication ni préambule.\n"
    "Exemple : \"à demain paul je t'appelle demain matin\" → \"À demain, Paul ! Je t'appelle demain matin.\""
)

_SYSTEM_BY_LANGUAGE = {"eu": _SYSTEM_EU, "fr": _SYSTEM_FR}


def system(language: str) -> str:
    """Strict system prompt: fix ONLY punctuation/case/spelling/obvious ASR errors,
    never rewrite, never answer the content, return the text alone."""
    return _SYSTEM_BY_LANGUAGE[language]


def max_tokens(text: str) -> int:
    """Tight output-token ceiling: a correction is ~input length.

    ~1 token / 3 UTF-8 bytes (tokenizer not tuned for Basque → generous),
    ×2 margin, clamped to [128; 2048]. Same formula as the Swift source.
    """
    estimated_input_tokens = len(text.encode("utf-8")) // 3 + 16
    return min(2048, max(128, estimated_input_tokens * 2))

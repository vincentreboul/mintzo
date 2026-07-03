"""Post-generation guardrails: never trust the corrector LLM output as-is.

Ported verbatim from ``Sources/MintzoCore/Correction/CorrectionGuardrails.swift``
(+ ``FallbackReason`` from ``Corrector.swift``). Pipeline: ``sanitize`` (meta-text
cleanup) then ``evaluate`` (quantitative bounds).

Fidelity notes vs Swift:
- length ratio uses ``len(str)`` (code points) where Swift counts grapheme
  clusters — identical on Basque/French text;
- word normalization drops Unicode punctuation (P*) and symbols (S*), matching
  ``CharacterSet.punctuationCharacters`` / ``.symbols``.
"""

from __future__ import annotations

import enum
import unicodedata

#: Bounds of the output/input length ratio (characters), inclusive.
LENGTH_RATIO_BOUNDS: tuple[float, float] = (0.7, 1.5)

#: Minimal lexical similarity (normalized word Levenshtein, 1 = identical).
MINIMUM_WORD_SIMILARITY: float = 0.6

#: Known meta-text prefixes (the model "presents" its answer instead of
#: returning the bare text) — compared lowercased. Same order as Swift.
_META_PREFIXES: tuple[str, ...] = (
    "voici le texte corrigé :",
    "voici le texte corrigé:",
    "voici la correction :",
    "voici la correction:",
    "texte corrigé :",
    "texte corrigé:",
    "hona hemen testu zuzendua:",
    "hona hemen zuzenketa:",
    "testu zuzendua:",
    "zuzenketa:",
    "zuzendutako testua:",
    "here is the corrected text:",
    "corrected text:",
)

#: Wrapping quote pairs (the model quotes the text instead of returning it bare).
_QUOTE_PAIRS: tuple[tuple[str, str], ...] = (("«", "»"), ("“", "”"), ('"', '"'))


class FallbackReason(str, enum.Enum):
    """Why the corrected output was rejected in favor of the raw text."""

    #: Output/input length ratio out of bounds — the model truncated or padded.
    LENGTH_RATIO = "lengthRatio"
    #: Lexical similarity too low — the model rewrote or answered the content.
    LOW_SIMILARITY = "lowSimilarity"
    #: Empty output (or empty once the meta-text was stripped).
    EMPTY_OUTPUT = "emptyOutput"
    #: The engine raised (model unloaded, network, API…).
    ENGINE_ERROR = "engineError"


def sanitize(raw: str) -> str:
    """Clean the raw LLM output: trim, strip one known meta prefix, strip wrapping quotes."""
    text = raw.strip()

    lowered = text.lower()
    for prefix in _META_PREFIXES:
        if lowered.startswith(prefix):
            text = text[len(prefix):].strip()
            break

    for open_quote, close_quote in _QUOTE_PAIRS:
        if len(text) >= 2 and text.startswith(open_quote) and text.endswith(close_quote):
            text = text[1:-1].strip()
            break
    return text


def evaluate(input_text: str, output_text: str) -> FallbackReason | None:
    """Evaluate a sanitized output against the input.

    Returns ``None`` when the output is acceptable, otherwise the rejection reason.
    """
    input_text = input_text.strip()
    if not output_text:
        return FallbackReason.EMPTY_OUTPUT
    if not input_text:
        return None

    ratio = len(output_text) / len(input_text)
    low, high = LENGTH_RATIO_BOUNDS
    if not (low <= ratio <= high):
        return FallbackReason.LENGTH_RATIO

    if word_similarity(input_text, output_text) < MINIMUM_WORD_SIMILARITY:
        return FallbackReason.LOW_SIMILARITY
    return None


def word_similarity(a: str, b: str) -> float:
    """Lexical similarity in [0; 1]: 1 − (word-level Levenshtein / max word count).

    Words are lowercased and stripped of punctuation/symbols: a legitimate
    correction (punctuation, capitalization) does not count as an edit — only
    word replacements/insertions/deletions do.
    """
    words_a = _normalized_words(a)
    words_b = _normalized_words(b)
    max_count = max(len(words_a), len(words_b))
    if max_count == 0:
        return 1.0
    return 1.0 - _levenshtein(words_a, words_b) / max_count


def _normalized_words(text: str) -> list[str]:
    words = []
    for token in text.lower().split():
        word = "".join(
            ch for ch in token if unicodedata.category(ch)[0] not in ("P", "S")
        )
        if word:
            words.append(word)
    return words


def _levenshtein(a: list[str], b: list[str]) -> int:
    """Classic two-row DP Levenshtein over word sequences."""
    if not a:
        return len(b)
    if not b:
        return len(a)

    previous = list(range(len(b) + 1))
    current = [0] * (len(b) + 1)

    for i in range(1, len(a) + 1):
        current[0] = i
        for j in range(1, len(b) + 1):
            substitution_cost = 0 if a[i - 1] == b[j - 1] else 1
            current[j] = min(
                previous[j] + 1,  # deletion
                current[j - 1] + 1,  # insertion
                previous[j - 1] + substitution_cost,  # substitution
            )
        previous, current = current, previous
    return previous[len(b)]

"""Guardrail tests — same cases as Tests/MintzoCoreTests/CorrectionGuardrailsTests.swift."""

from __future__ import annotations

import pytest

from app.guardrails import FallbackReason, evaluate, sanitize, word_similarity

# -- evaluate: length ratio -----------------------------------------------------


def test_overlong_output_rejected():
    input_text = "kaixo maite bihar goizean elkartuko gara"
    output = input_text + " " + "eta abar luze bat gehitu du modeloak " * 4
    assert evaluate(input_text, output) is FallbackReason.LENGTH_RATIO


def test_truncated_output_rejected():
    input_text = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"
    assert evaluate(input_text, "Kaixo.") is FallbackReason.LENGTH_RATIO


# -- evaluate: identity and legitimate corrections -------------------------------


def test_identical_output_accepted():
    input_text = "bonjour on se retrouve demain matin au bureau"
    assert evaluate(input_text, input_text) is None


def test_punctuation_and_case_correction_accepted():
    input_text = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"
    output = "Kaixo, Maite! Bihar goizean elkartuko gara bulegoan, proiektua ixteko. Ados?"
    # Punctuation + capitalization must NOT count as word edits.
    assert evaluate(input_text, output) is None


def test_rewritten_output_rejected():
    input_text = "bonjour on se retrouve demain matin au bureau pour finir le projet"
    # The model "answered" instead of correcting — almost all words differ.
    output = "Très bien, je note votre rendez-vous et je vous souhaite une bonne journée"
    assert evaluate(input_text, output) is FallbackReason.LOW_SIMILARITY


def test_empty_output_rejected():
    assert evaluate("kaixo", "") is FallbackReason.EMPTY_OUTPUT


# -- sanitize: parasitic meta-text ------------------------------------------------


def test_french_meta_prefix_stripped():
    raw = "Voici le texte corrigé : Bonjour, on se retrouve demain."
    assert sanitize(raw) == "Bonjour, on se retrouve demain."


def test_basque_meta_prefix_stripped():
    raw = "Testu zuzendua: Kaixo, Maite! Bihar elkartuko gara."
    assert sanitize(raw) == "Kaixo, Maite! Bihar elkartuko gara."


def test_wrapping_quotes_stripped():
    assert sanitize("« Kaixo, Maite! »") == "Kaixo, Maite!"
    assert sanitize('"Bonjour, Maite."') == "Bonjour, Maite."


def test_clean_output_untouched():
    clean = "Kaixo, Maite! Bihar goizean elkartuko gara."
    assert sanitize(clean) == clean


def test_whitespace_only_output_sanitizes_to_empty():
    assert sanitize("  \n\t ") == ""


# -- word_similarity ---------------------------------------------------------------


def test_word_similarity_identical_is_one():
    assert word_similarity("kaixo maite", "Kaixo, Maite!") == 1.0


def test_word_similarity_disjoint_is_zero():
    assert word_similarity("aaa bbb ccc", "xxx yyy zzz") == 0.0


def test_word_similarity_single_substitution():
    # Case-only difference is not an edit.
    assert word_similarity("un deux trois quatre", "un deux TROIS quatre") == 1.0
    # 1 word replaced out of 4 -> similarity 0.75.
    assert word_similarity("un deux trois quatre", "un deux cinq quatre") == pytest.approx(
        0.75, abs=0.001
    )

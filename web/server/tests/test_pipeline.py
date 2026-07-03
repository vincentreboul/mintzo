"""Correction pass with a mocked engine + prompt port checks."""

from __future__ import annotations

import pytest

from app import prompts
from app.guardrails import FallbackReason
from app.pipeline import correct_text, make_llama_corrector

# -- correct_text (port of CorrectionService.correct) ---------------------------


def test_accepted_correction():
    result = correct_text(
        "kaixo maite bihar deituko dizut",
        "eu",
        corrector=lambda text, language: "Kaixo, Maite! Bihar deituko dizut.",
    )
    assert result.outcome == "corrected"
    assert result.text == "Kaixo, Maite! Bihar deituko dizut."
    assert result.fallback_reason is None


def test_identical_output_is_unchanged():
    result = correct_text(
        "Kaixo, Maite!", "eu", corrector=lambda text, language: "Kaixo, Maite!"
    )
    assert result.outcome == "unchanged"
    assert result.text == "Kaixo, Maite!"


def test_meta_prefix_sanitized_before_evaluation():
    result = correct_text(
        "bonjour on se retrouve demain",
        "fr",
        corrector=lambda text, language: "Voici le texte corrigé : Bonjour, on se retrouve demain.",
    )
    assert result.outcome == "corrected"
    assert result.text == "Bonjour, on se retrouve demain."


def test_rewritten_output_falls_back_to_raw():
    input_text = "bonjour on se retrouve demain matin au bureau pour finir le projet"
    result = correct_text(
        input_text,
        "fr",
        corrector=lambda text, language: (
            "Très bien, je note votre rendez-vous et je vous souhaite une bonne journée"
        ),
    )
    assert result.outcome == "fallbackRaw"
    assert result.fallback_reason is FallbackReason.LOW_SIMILARITY
    assert result.text == input_text  # raw dictation preserved


def test_engine_exception_falls_back_to_raw():
    def broken(text: str, language: str) -> str:
        raise RuntimeError("boom")

    result = correct_text("kaixo maite", "eu", corrector=broken)
    assert result.outcome == "fallbackRaw"
    assert result.fallback_reason is FallbackReason.ENGINE_ERROR
    assert result.text == "kaixo maite"


def test_empty_input_short_circuits():
    def never_called(text: str, language: str) -> str:  # pragma: no cover
        raise AssertionError("corrector must not run on empty input")

    result = correct_text("   \n ", "eu", corrector=never_called)
    assert result.outcome == "unchanged"
    assert result.text == ""


# -- prompt port -----------------------------------------------------------------


def test_prompts_exist_per_language_and_stay_strict():
    eu = prompts.system("eu")
    fr = prompts.system("fr")
    assert "Zuzentzaile automatiko bat zara" in eu
    assert "Itzuli testu zuzendua BAKARRIK" in eu
    assert "Tu es un correcteur automatique" in fr
    assert "Renvoie le texte corrigé SEUL" in fr
    with pytest.raises(KeyError):
        prompts.system("en")


def test_max_tokens_formula_matches_swift():
    # Swift: min(2048, max(128, (utf8count/3 + 16) * 2))
    assert prompts.max_tokens("") == 128
    assert prompts.max_tokens("a" * 30) == 128  # (10+16)*2 = 52 -> clamped to 128
    assert prompts.max_tokens("a" * 300) == 232  # (100+16)*2
    assert prompts.max_tokens("a" * 9000) == 2048  # clamped high


def test_make_llama_corrector_binds_prompt_and_budget():
    calls: list[tuple[str, str, int]] = []

    def chat(system: str, user: str, max_tokens: int) -> str:
        calls.append((system, user, max_tokens))
        return "Kaixo!"

    corrector = make_llama_corrector(chat)
    assert corrector("kaixo", "eu") == "Kaixo!"
    system, user, max_tokens = calls[0]
    assert system == prompts.system("eu")
    assert user == "kaixo"
    assert max_tokens == prompts.max_tokens("kaixo")

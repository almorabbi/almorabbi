"""Real cache writes through streaming and both offline warmers, without models."""
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest

from app.services import answer_cache as cache
from tests import test_answer_cache_source_revision as revisions
from tests import test_redaction_v2 as redaction

corpus = revisions.corpus
client = redaction.client
pipeline = redaction.pipeline
_change_source, ANSWER = revisions._change_source, revisions.ANSWER
_auth, _Recorder = redaction._auth, redaction._Recorder

ROOT = Path(__file__).resolve().parents[2]
_REAL_STORE = cache.store


def _observe(monkeypatch, corpus, change):
    events, writes = [], []
    original_capture = cache.capture_revision

    def capture():
        revision = original_capture()
        events.append(("capture", revision))
        return revision

    def generate():
        events.append(("generate", None))
        assert events[0][0] == "capture", "provenance must precede retrieval/generation"
        if change:
            _change_source(corpus, "edit")

    def store(*args, **kwargs):
        writes.append((kwargs.get("generation_revision"), _REAL_STORE(*args, **kwargs)))
        return writes[-1][1]

    monkeypatch.setattr(cache, "capture_revision", capture)
    monkeypatch.setattr(cache, "store", store)
    return events, writes, generate


@pytest.mark.parametrize("change", [False, True])
def test_stream_carries_pre_retrieval_revision(corpus, client, pipeline, monkeypatch, change):
    from app.routers import assistant

    events, writes, generate = _observe(monkeypatch, corpus, change)
    original_retrieve = assistant.retrieve_hybrid

    def retrieve(**kwargs):
        generate()
        return original_retrieve(**kwargs)

    def stream(self, prompt, *, options):
        yield {"response": ANSWER, "done": False}
        yield {"response": "", "done": True, "prompt_eval_count": 1, "eval_count": 1}

    monkeypatch.setattr(assistant, "retrieve_hybrid", retrieve)
    monkeypatch.setattr(_Recorder, "stream", stream)
    response = client.post("/api/assistant/stream", headers=_auth(client, "revision-client"),
                           json={"message_text": "طفلي يرفض النوم", "age_group": "4-6",
                                 "severity": "خفيف"})
    assert response.status_code == 200
    assert "event: done" in response.text, response.text
    assert len(writes) == 1, response.text
    assert writes == [(events[0][1], not change)]


def _warmer(path):
    spec = importlib.util.spec_from_file_location("review_warmer_" + path.parts[0], ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# The second copy (backend/ops/scripts/warm_answer_cache.py) was removed 2026-10-29:
# the image copies the repo-root ops/scripts, never backend/ops, so it never ran.


@pytest.mark.parametrize("change", [False, True])
def test_root_offline_carries_revision_and_reports_rejection(corpus, monkeypatch, change):
    import asyncio

    module = _warmer(Path("ops/scripts/warm_answer_cache.py"))
    events, writes, generate = _observe(monkeypatch, corpus, change)
    monkeypatch.setattr(module, "_QUESTIONS", ["question"])
    monkeypatch.setattr(module, "_AGE_GROUPS", ["4-6"])

    async def fake_generate(*a):
        generate()
        return ANSWER, "islamic_parenting", "خفيف"

    async def no_delay(_):
        pass

    monkeypatch.setattr(module, "_generate_answer", fake_generate)
    monkeypatch.setattr(module.asyncio, "sleep", no_delay)
    assert asyncio.run(module._main()) == (1 if change else 0)
    assert writes == [(events[0][1], not change)]

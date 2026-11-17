"""AI rewording of resume bullets for a job, with checks that keep it truthful.

The model may only rephrase what a bullet already says, using the job's wording. Every
rewrite is checked before it is used:
  - no number that the original bullet doesn't have
  - no job keyword that the resume doesn't already show anywhere
  - no new name or tool (a capitalized word) that the resume doesn't mention
Anything that fails is dropped and the original bullet stays.
"""
from __future__ import annotations

import json
import os
import re
import urllib.request

from resume_tailoring import tokens

API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
MAX_JOB_CHARS = 5000
NUMBER = re.compile(r"\d[\d,.]*\d|\d")


def _numbers(text: str) -> set[str]:
    return {number.replace(",", "") for number in NUMBER.findall(text)}


def _proper_words(text: str) -> set[str]:
    """Capitalized words, except a sentence's first word."""
    words = re.findall(r"[A-Za-z][A-Za-z0-9+#.\-]*", text)
    found = set()
    for index, word in enumerate(words):
        word = word.rstrip(".-")
        if index and (word[0].isupper() or any(ch.isupper() for ch in word[1:])):
            found.add(word.lower())
    return found


def _stem(word: str) -> str:
    for suffix in ("ations", "ation", "ings", "ing", "ies", "ers", "ed", "es", "er", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[: -len(suffix)]
    return word


def check_rewrite(original: str, new: str, resume_text: str, job_text: str) -> str:
    """Why a rewrite can't be used, or "" if it's fine."""
    if len(new) < 0.5 * len(original):
        return "it dropped too much of the original"
    extra_numbers = _numbers(new) - _numbers(original)
    if extra_numbers:
        return "it added a number (" + ", ".join(sorted(extra_numbers)) + ")"
    resume_stems = {_stem(word) for word in tokens(resume_text)}
    added = set(tokens(new)) - set(tokens(original))
    unproven = {word for word in added & set(tokens(job_text)) if _stem(word) not in resume_stems}
    if unproven:
        return "it claimed " + ", ".join(sorted(unproven)) + ", which the resume doesn't show"
    resume_lower = resume_text.lower()
    new_names = {word for word in _proper_words(new) - _proper_words(original) if word not in resume_lower}
    if new_names:
        return "it named " + ", ".join(sorted(new_names)) + ", which the resume doesn't mention"
    return ""


SYSTEM_PROMPT = (
    "You edit resume bullet points so they match a job posting's wording, without changing "
    "what they claim. Rules: "
    "1) Keep every fact, number, tool, and result exactly as stated. Never add a tool, skill, "
    "number, metric, title, or responsibility the bullet doesn't already state. "
    "2) Where the bullet already describes something the job asks for, use the job's term for it. "
    "3) Keep the same tense and voice, and start with a strong verb. "
    "4) Each rewrite must be at most max_chars characters. "
    "5) Leave a bullet out if it doesn't relate to the job or already uses the job's words. "
    'Reply with JSON only: {"rewrites": [{"id": "...", "text": "..."}]}'
)


def suggest_rewrites(candidates: list[dict], job_title: str, job_text: str, api_key: str | None = None, timeout: float = 25.0) -> dict[str, str]:
    """Ask the model for rewrites. Returns {id: text}; raises on network or format errors."""
    key = (api_key or os.environ.get("DEEPSEEK_API_KEY", "")).strip()
    if not key or key == "your_deepseek_key_here":
        raise RuntimeError("No AI key is set.")
    user = json.dumps({
        "job_title": str(job_title or "")[:120],
        "job_description": str(job_text or "")[:MAX_JOB_CHARS],
        "bullets": candidates,
    })
    payload = {
        "model": MODEL,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": user}],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}", "User-Agent": "Launchpad/1.0"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode("utf-8"))
    content = json.loads(body["choices"][0]["message"]["content"])
    ids = {candidate["id"] for candidate in candidates}
    found = {}
    for item in content.get("rewrites", []):
        if isinstance(item, dict) and str(item.get("id")) in ids and isinstance(item.get("text"), str):
            found[str(item["id"])] = re.sub(r"\s+", " ", item["text"]).strip()[:400]
    return found


def has_key() -> bool:
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    return bool(key) and key != "your_deepseek_key_here"

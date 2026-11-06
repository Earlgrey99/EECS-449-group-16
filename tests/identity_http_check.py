"""HTTP regression checks for identity and authorization.

`jac test` calls functions in process, which misses bugs in how the server handles
requests, so these run against a live server:

    export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"
    jac run --dev --profile test main.jac
    .jac/venv/bin/python tests/identity_http_check.py

Creates throwaway accounts with random credentials in the configured database.
Point it only at a local test database.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

BASE = os.getenv("DEMO_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
RESUME = "PRIVATE-RESUME-MARKER Python SQL APIs"

# Public functions that must never be reachable over HTTP, even when logged in.
INTERNAL_FUNCTIONS = [
    "list_users", "get_user_by_email", "get_user_by_id", "update_user", "delete_user",
    "create_user", "register_user", "authenticate_user", "hash_password", "verify_password",
    "list_resumes_by_user", "get_resume_by_id", "create_resume", "update_resume", "delete_resume",
    "list_applications_by_user", "get_application_by_id", "create_application",
    "update_application", "delete_application", "get_db_connection", "init_db", "load_env_file",
    "ensure_test_user", "main", "build_parser", "fetch", "fetch_jooble", "fetch_himalayas",
    "table_Sheet", "patch", "resolve_token_identity",
]
PROTECTED = {
    "get_user_profile_data": {"token": "x"},
    "get_user_tailored_jobs": {"token": "x"},
    "get_resume_match_scores": {"jobs": [], "token": "x"},
    "submit_profile_and_generate_query": {"token": "x", "first_name": "X"},
    "sync_user_session": {"token": "x"},
}
failures: list[str] = []


def check(name: str, passed: bool, detail: object = "") -> None:
    print(("PASS  " if passed else "FAIL  ") + name + ("" if passed else f"  -> {detail}"))
    if not passed:
        failures.append(name)


def http(path: str, body: dict, token: str | None = None, method: str = "POST") -> tuple[int, dict, str]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            status, raw = res.status, res.read().decode()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read().decode()
    try:
        return status, json.loads(raw), raw
    except ValueError:
        return status, {}, raw


def result(payload: dict) -> dict:
    return (payload.get("data") or {}).get("result") or {}


def try_register(identity_type: str, value: str) -> str | None:
    status, payload, _ = http("/user/register", {
        "identities": [{"type": identity_type, "value": value}],
        "credential": {"type": "password", "password": secrets.token_urlsafe(24)},
    })
    return (payload.get("data") or {}).get("token") if status < 400 else None


def register(identity_type: str, value: str) -> str:
    token = try_register(identity_type, value)
    if not token:
        raise AssertionError(f"Could not register {identity_type} account")
    return token


def forge(claims: dict, key: str) -> str:
    def enc(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")
    head = enc(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = enc(json.dumps(claims).encode())
    sig = hmac.new(key.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest()
    return f"{head}.{body}.{enc(sig)}"


def main() -> int:
    tag = secrets.token_hex(6)
    alice_email, bob_email = f"alice-{tag}@example.test", f"bob-{tag}@example.test"
    # jacSignup(email, password), the app's real signup, stores the email as a username.
    alice, bob = register("username", alice_email), register("username", bob_email)

    for name in INTERNAL_FUNCTIONS:
        status, _, raw = http(f"/function/{name}", {}, alice)
        check(f"{name} is not an endpoint", status in (404, 405), f"{status} {raw[:120]}")

    for name, body in PROTECTED.items():
        status, _, raw = http(f"/function/{name}", body)
        check(f"{name} rejects anonymous callers", status == 401, f"{status} {raw[:120]}")

    # The web app's normal path: only the token is sent.
    status, payload, raw = http("/function/submit_profile_and_generate_query", {
        "token": alice, "first_name": "Alice", "location": "Remote", "job_titles": "Backend Engineer",
        "salary_min": None, "contract_type": "Full-time",
        "resume_title": "resume.txt", "resume_content": RESUME,
    }, alice)
    check("user can save their profile", result(payload).get("ok") is True, raw[:200])

    _, payload, raw = http("/function/get_user_profile_data", {"token": alice}, alice)
    profile = result(payload)
    check("saved profile loads from the token alone", (profile.get("user") or {}).get("email") == alice_email, raw[:200])
    check("onboarding state survives", profile.get("onboarding_completed") is True, raw[:200])
    check("saved resume loads", RESUME in raw, raw[:200])
    check("password hash is not returned", "password_hash" not in raw, raw[:200])

    _, payload, raw = http("/function/get_resume_match_scores", {
        "token": alice, "jobs": [{"id": "1", "title": "Backend Engineer", "desc": "Python and SQL", "tags": "Python, SQL"}],
    }, alice)
    scores = result(payload)
    check("match scores use the saved resume", scores.get("has_resume") is True and scores.get("scores"), raw[:200])

    _, payload, raw = http("/function/get_user_tailored_jobs", {"token": alice}, alice)
    check("feed is tailored from the token alone", result(payload).get("tailored") is True, raw[:200])

    _, payload, raw = http("/function/sync_user_session", {"token": alice}, alice)
    check("sign-in sync succeeds", result(payload).get("ok") is True and "password_hash" not in raw, raw[:200])

    # Crossing between users.
    _, _, raw = http("/function/get_user_profile_data", {"token": bob}, bob)
    check("another user cannot see the resume", RESUME not in raw and alice_email not in raw, raw[:200])

    _, _, raw = http("/function/get_user_profile_data", {"token": bob, "email": alice_email}, bob)
    check("a supplied email cannot select another user", RESUME not in raw, raw[:200])

    http("/function/submit_profile_and_generate_query", {"token": bob, "email": alice_email, "first_name": "Mallory"}, bob)
    _, payload, raw = http("/function/get_user_profile_data", {"token": alice}, alice)
    check("another user cannot overwrite the profile", (result(payload).get("user") or {}).get("first_name") == "Alice", raw[:200])

    # Forged and look-alike identities.
    claims = {"email": alice_email, "sub": alice_email, "user_id": alice_email, "exp": 4102444800}
    unsigned = forge(claims, "")[:-4] + "AAAA"
    for label, forged in (("unsigned", unsigned), ("wrong-key", forge(claims, secrets.token_hex(32)))):
        status, _, raw = http("/function/get_user_profile_data", {"token": forged}, bob)
        check(f"{label} token in the body is rejected", RESUME not in raw and result(json.loads(raw)).get("ok") is False, f"{status} {raw[:200]}")
        status, _, raw = http("/function/get_user_profile_data", {"token": forged}, forged)
        check(f"{label} bearer token is rejected", status == 401, f"{status} {raw[:200]}")

    for kind in ("email", "username"):
        check(f"{kind} signup cannot reuse a taken address", try_register(kind, alice_email) is None)
    check("signup is not case-sensitive about taken addresses", try_register("email", alice_email.upper()) is None)

    email_kind = f"email-kind-{tag}@example.test"
    email_token = register("email", email_kind)
    _, payload, raw = http("/function/get_user_profile_data", {"token": email_token}, email_token)
    check("an email identity also resolves", (result(payload).get("user") or {}).get("email") == email_kind, raw[:200])

    plain = register("username", f"plain_{tag}")
    _, payload, raw = http("/function/get_user_profile_data", {"token": plain}, plain)
    check("an account with no email gets no profile", result(payload).get("ok") is False, raw[:200])

    spoof = register("username", f"spoof_{tag}")
    http("/user/profile", {"profile": {"sso": {"google": {"email": alice_email}}}}, spoof, method="PUT")
    _, _, raw = http("/function/get_user_profile_data", {"token": spoof}, spoof)
    check("a self-edited SSO profile cannot claim an email", RESUME not in raw and alice_email not in raw, raw[:200])

    print(f"\n{len(failures)} failed" if failures else "\nAll identity checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

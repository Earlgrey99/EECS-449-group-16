"""End-to-end test of the browser extension against a live Launchpad server.

Loads the real extension in Chromium and drives its real popup:

    export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"
    jac run --dev --profile test main.jac
    .jac/venv/bin/python tests/extension_e2e.py

A toolbar click can't be automated, so the test copy of the extension gets access to
the fixture page's origin only, which matches what activeTab grants, and the popup is
told which tab to use.
Creates a throwaway account with random credentials in the configured database.
"""
from __future__ import annotations

import base64
import functools
import http.server
import json
import os
import secrets
import shutil
import sys
import tempfile
import threading
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
BASE = os.getenv("DEMO_BASE_URL", "http://localhost:8000").rstrip("/")
RESUME_BYTES = (ROOT / "tests/data/compatibility/resume_backend.pdf").read_bytes()
failures: list[str] = []


def check(name: str, passed: bool, detail: object = "") -> None:
    print(("PASS  " if passed else "FAIL  ") + name + ("" if passed else f"  -> {detail}"))
    if not passed:
        failures.append(name)


def api(path: str, body: dict, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, json.dumps(body).encode(), headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode())


def create_account() -> tuple[str, str]:
    email = f"ext-{secrets.token_hex(6)}@example.test"
    registered = api("/user/register", {
        "identities": [{"type": "username", "value": email}],
        "credential": {"type": "password", "password": secrets.token_urlsafe(24)},
    })
    token = registered["data"]["token"]
    saved = api("/function/submit_profile_and_generate_query", {
        "token": token, "first_name": "Ada", "last_name": "Tester", "location": "Remote, Seattle, WA",
        "job_titles": "Software Engineer", "salary_min": None, "contract_type": "Full-time",
        "resume_title": "ada_resume.pdf",
        "resume_content": "data:application/pdf;base64," + base64.b64encode(RESUME_BYTES).decode(),
    }, token)
    assert saved["data"]["result"]["ok"], saved
    return email, token


def prepare_extension(directory: Path) -> Path:
    target = directory / "extension"
    shutil.copytree(ROOT / "extension", target)
    manifest = json.loads((target / "manifest.json").read_text())
    manifest["host_permissions"] = ["http://localhost:8000/*", "http://127.0.0.1/*"]
    manifest["background"] = {"service_worker": "test_worker.js"}  # Reveals the extension id.
    (target / "manifest.json").write_text(json.dumps(manifest))
    (target / "test_worker.js").write_text("")
    return target


def serve_fixtures(directory: Path) -> tuple[http.server.HTTPServer, str]:
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(Quiet, directory=str(directory))
    # The fixture embeds itself as localhost, a different origin from 127.0.0.1.
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def results_text(popup) -> str:
    return popup.locator("#results").inner_text()


def main() -> int:
    email, token = create_account()
    with tempfile.TemporaryDirectory() as temp:
        temp_path = Path(temp)
        extension = prepare_extension(temp_path)
        pages = temp_path / "pages"
        pages.mkdir()
        shutil.copy(ROOT / "tests/extension/fixtures/tricky_form.html", pages)
        shutil.copy(ROOT / "tests/extension/fixtures/other_origin_frame.html", pages)
        shutil.copy(ROOT / "examples/application_form.html", pages)
        server, site = serve_fixtures(pages)

        with sync_playwright() as playwright:
            context = playwright.chromium.launch_persistent_context(
                str(temp_path / "profile"),
                channel="chromium",
                headless=True,
                args=[f"--disable-extensions-except={extension}", f"--load-extension={extension}"],
            )
            try:
                worker = context.service_workers[0] if context.service_workers else context.wait_for_event("serviceworker")
                extension_id = worker.url.split("/")[2]
                popup_url = f"chrome-extension://{extension_id}/popup.html"

                # Not signed in yet: connecting should send the user to Launchpad.
                form = context.new_page()
                form.goto(f"{site}/tricky_form.html")
                popup = context.new_page()
                popup.goto(popup_url)
                check("starts disconnected", popup.locator("#connect").is_visible())
                tab_id = popup.evaluate(
                    "url => chrome.tabs.query({url}).then(tabs => tabs[0].id)", f"{site}/tricky_form.html"
                )

                # Connect through a signed-in Launchpad tab.
                launchpad = context.new_page()
                launchpad.goto(f"{BASE}/login", wait_until="domcontentloaded")
                launchpad.evaluate(
                    "token => { localStorage.setItem('dev_logged_out', 'true'); localStorage.setItem('jac_token', token); }",
                    token,
                )
                popup.goto(f"{popup_url}?tab={tab_id}")
                popup.locator("#connect").click()
                popup.locator("#main-view").wait_for(state="visible", timeout=15000)
                account = popup.locator("#account-name").inner_text()
                check("connects using the Launchpad session", email in account and "Ada Tester" in account, account)
                check("shows the saved resume", popup.locator("#resume-title").inner_text() == "ada_resume.pdf")
                stored = popup.evaluate("chrome.storage.local.get(null)")
                check("token is not kept in persistent storage", token not in json.dumps(stored), stored)

                # Details saved in the extension.
                popup.locator("#settings summary").click()
                popup.locator("input[name=phone]").fill("555-0100")
                popup.locator("input[name=location]").fill("Ann Arbor")
                popup.locator("input[name=linkedin]").fill("https://linkedin.com/in/ada")
                popup.locator("input[name=github]").fill("https://github.com/ada")
                popup.locator("input[name=portfolio]").fill("https://ada.example")
                popup.locator("#details-form button[type=submit]").click()
                popup.get_by_text("Saved.", exact=True).wait_for(timeout=5000)

                # Preview must not change the page.
                popup.locator("#preview").click()
                popup.locator("#results h2").first.wait_for(timeout=10000)
                preview = results_text(popup)
                check("preview lists fillable fields", "Ready to fill" in preview and "First Name" in preview, preview)
                check("preview changes nothing", form.locator("#first").input_value() == "")

                # Fill.
                popup.locator("#fill").click()
                popup.get_by_text("Filled. Please review", exact=False).wait_for(timeout=10000)
                report = results_text(popup)
                print("\nPopup report:\n" + report + "\n")

                expected = {
                    "#first": "Ada",
                    "[name='job_application[last_name]']": "Tester",
                    "[name=field_17]": email,
                    "#phone": "555-0100",
                    "#linkedin": "https://linkedin.com/in/ada",
                    "#controlled": "https://github.com/ada",
                    "#city": "ann",
                }
                for selector, value in expected.items():
                    actual = form.locator(selector).input_value()
                    check(f"fills {selector}", actual == value, actual)

                check(
                    "React-style input registers the change",
                    form.locator("#controlled-state").inner_text() == "https://github.com/ada",
                )
                resume = form.evaluate(
                    """() => {
                        const file = document.getElementById('resume').files[0];
                        return file ? file.arrayBuffer().then(buffer => ({
                            name: file.name, type: file.type, size: buffer.byteLength
                        })) : null;
                    }"""
                )
                check(
                    "attaches the resume intact",
                    resume == {"name": "ada_resume.pdf", "type": "application/pdf", "size": len(RESUME_BYTES)},
                    resume,
                )
                check(
                    "keeps an existing answer",
                    form.locator("#existing").input_value() == "https://already-here.example",
                )

                for selector in ["#company", "#emergency", "#reference", "#gender", "#visa", "#salary",
                                 "#why", "#readonly-email", "#password", "#hidden-email", "#invisible-email"]:
                    actual = form.locator(selector).input_value()
                    check(f"leaves {selector} empty", actual == "", actual)
                check(
                    "does not attach a resume as the cover letter",
                    form.evaluate("document.getElementById('cover').files.length") == 0,
                )
                state = form.evaluate("({submitted: window.__submitted, clicked: window.__clicked})")
                check("never clicks or submits", state == {"submitted": False, "clicked": False}, state)

                check("reports fields left for the user", "Please answer these yourself" in report, report)
                for label in ["Gender", "Salary expectations", "Will you require visa sponsorship?"]:
                    check(f"reports sensitive field: {label}", label in report, report)
                check("reports the kept answer", "Already has a value" in report, report)
                check("report contains no values", "555-0100" not in report and email not in report, report)

                other_frame = next(frame for frame in form.frames if "other_origin_frame" in frame.url)
                check(
                    "a page with an inaccessible frame still fills, and the frame stays empty",
                    other_frame.locator("#frame-email").input_value() == "",
                )

                # Filling again must not overwrite the user's edits.
                form.locator("#first").fill("Edited")
                popup.locator("#fill").click()
                popup.get_by_text("Already has a value", exact=False).wait_for(timeout=10000)
                form.wait_for_timeout(500)
                check("does not overwrite user edits", form.locator("#first").input_value() == "Edited")

                # The repo's plain sample form, with the resume turned off.
                sample = context.new_page()
                sample.goto(f"{site}/application_form.html")
                sample_tab = popup.evaluate(
                    "url => chrome.tabs.query({url}).then(tabs => tabs[0].id)", f"{site}/application_form.html"
                )
                popup.goto(f"{popup_url}?tab={sample_tab}")
                popup.locator("#main-view").wait_for(state="visible", timeout=15000)
                popup.locator("#include-resume").uncheck()
                popup.locator("#fill").click()
                popup.get_by_text("Filled. Please review", exact=False).wait_for(timeout=10000)
                check("fills the sample form", sample.locator("#full_name").input_value() == "Ada Tester")
                check("respects the resume checkbox", sample.evaluate("document.getElementById('resume').files.length") == 0)

                # Pages that can't be scripted get a clear message.
                blocked_tab = popup.evaluate(
                    "() => chrome.tabs.create({url: 'chrome://version', active: false}).then(tab => tab.id)"
                )
                popup.goto(f"{popup_url}?tab={blocked_tab}")
                popup.locator("#main-view").wait_for(state="visible", timeout=15000)
                popup.locator("#preview").click()
                popup.locator("#message.error").wait_for(timeout=10000)
                check("explains pages it can't run on", "can't run on this page" in popup.locator("#message").inner_text())

                # Disconnect removes the token.
                popup.locator("#disconnect").click()
                popup.locator("#connect").wait_for(state="visible", timeout=5000)
                session = popup.evaluate("chrome.storage.session.get(null)")
                check("disconnect clears the token", "token" not in session, list(session))
            finally:
                context.close()
                server.shutdown()

    print(f"\n{len(failures)} failed" if failures else "\nAll extension checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

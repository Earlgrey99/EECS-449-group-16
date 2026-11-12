"""End-to-end test of the browser extension against a live Launchpad server.

Loads the real extension in Chromium and drives its real popup:

    export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"
    jac run --dev --profile test main.jac
    .jac/venv/bin/python tests/extension_e2e.py

A toolbar click can't be automated, so the test copy of the extension gets access to
the fixture page's origin only, which matches what activeTab grants, and the popup is
told which tab to use. The test copy also treats the fixture site as a hiring site, so
the on-page panel appears, and opens the panel's shadow root so the test can read it.
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
    contact = api("/function/save_contact_details", {
        "token": token, "phone": "555-0100", "city": "Ann Arbor", "linkedin": "https://linkedin.com/in/ada",
        "github": "https://github.com/ada", "portfolio": "https://ada.example",
    }, token)
    assert contact["data"]["result"]["ok"], contact
    return email, token


def prepare_extension(directory: Path) -> Path:
    target = directory / "extension"
    shutil.copytree(ROOT / "extension", target)
    manifest = json.loads((target / "manifest.json").read_text())
    manifest["host_permissions"] = [f"{BASE}/*", "http://127.0.0.1/*"]
    for script in ("background.js", "popup.js"):
        path = target / script
        path.write_text(path.read_text().replace("http://localhost:8000", BASE))
    manifest["content_scripts"][0]["matches"] = ["http://127.0.0.1/ats_form.html*"]
    (target / "manifest.json").write_text(json.dumps(manifest))
    panel = target / "panel.js"
    panel.write_text(panel.read_text().replace('mode: "closed"', 'mode: "open"'))
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
        shutil.copy(ROOT / "tests/extension/fixtures/ats_form.html", pages)
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

                # Add the job to the tracker from the popup.
                track = popup.locator("#track-form")
                check("offers to add the job to the tracker", track.is_visible())
                check(
                    "guesses the job title from the page",
                    track.locator("input[name=role]").input_value() == "Software Engineer application",
                    track.locator("input[name=role]").input_value(),
                )
                track.locator("input[name=role]").fill("Software Engineer")
                track.locator("input[name=company]").fill("Fixture Co")
                track.locator("button[type=submit]").click()
                popup.get_by_text("Added to your tracker.", exact=True).wait_for(timeout=10000)
                tracked = api("/function/list_tracker_applications", {"token": token}, token)["data"]["result"]["applications"]
                check(
                    "the job reaches the tracker with its link",
                    len(tracked) == 1 and tracked[0]["role"] == "Software Engineer" and tracked[0]["company"] == "Fixture Co"
                    and tracked[0]["job_url"].endswith("/tricky_form.html") and tracked[0]["status"] == "Applied",
                    tracked,
                )

                # Filling again must not overwrite the user's edits.
                form.locator("#first").fill("Edited")
                popup.locator("#fill").click()
                popup.get_by_text("Already has a value", exact=False).wait_for(timeout=10000)
                form.wait_for_timeout(500)
                check("does not overwrite user edits", form.locator("#first").input_value() == "Edited")
                popup.locator("#track-form button[type=submit]").wait_for(timeout=5000)
                popup.locator("#track-form input[name=role]").fill("Software Engineer")
                popup.locator("#track-form input[name=company]").fill("Fixture Co")
                popup.locator("#track-form button[type=submit]").click()
                popup.get_by_text("already in your tracker", exact=False).wait_for(timeout=10000)
                check("does not add the same job twice", True)

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

                # The on-page panel, with saved answers.
                api("/function/save_application_answers", {"token": token, "answers": {
                    "work_authorized": "yes", "needs_sponsorship": "no", "current_company": "Acme",
                    "salary": "120000", "country": "United States",
                }}, token)
                popup.goto(f"chrome-extension://{extension_id}/options.html")
                popup.locator("select[name=gender]").select_option("woman")
                popup.locator("select[name=veteran]").select_option("no")
                popup.locator("select[name=hispanic]").select_option("decline")
                popup.locator("select[name=race]").select_option("white")
                popup.get_by_role("button", name="Save").click()
                popup.get_by_text("Saved.", exact=True).wait_for(timeout=5000)
                check(
                    "demographic answers stay in this browser",
                    popup.evaluate("chrome.storage.local.get('demographics').then(r => r.demographics.gender)") == "woman",
                )

                ats = context.new_page()
                ats.goto(f"{site}/ats_form.html")
                panel = ats.locator("#launchpad-autofill-panel")
                button = panel.get_by_role("button", name="Autofill this application")
                button.wait_for(timeout=10000)
                check("the panel appears on a hiring site", button.is_visible())
                check("nothing is filled before the click", ats.locator("#first").input_value() == "")
                button.click()
                panel.get_by_text("Please review them", exact=False).wait_for(timeout=20000)
                report = panel.locator("section.panel").inner_text()
                print("\nPanel report:\n" + report + "\n")

                for selector, value in {"#first": "Ada", "#last": "Tester", "#email": email, "#company": "Acme", "#salary": "120000"}.items():
                    actual = ats.locator(selector).input_value()
                    check(f"panel fills {selector}", actual == value, actual)
                picked = lambda field: ats.locator(f"#{field}").get_attribute("data-selected")
                check("picks from a searchable dropdown", picked("q-country") == "United States", picked("q-country"))
                check("answers work authorization", picked("q-auth") == "Yes", picked("q-auth"))
                check("maps a saved gender to the site's wording", picked("q-gender") == "Female", picked("q-gender"))
                check("maps a saved veteran answer", picked("q-vet") == "I am not a protected veteran", picked("q-vet"))
                check("picks a city suggestion", picked("q-city") == "Ann Arbor, Michigan, United States", picked("q-city"))
                check("leaves an unknown dropdown alone", picked("q-ambiguous") is None)
                check("never answers a blocked dropdown", picked("q-dob") is None)
                pressed = lambda root: ats.evaluate(
                    "root => [...document.querySelectorAll(root + ' button[aria-pressed=true]')].map(b => b.textContent)", root
                )
                check("presses the right Yes/No button", pressed("#sponsor") == ["No"], pressed("#sponsor"))
                check("leaves an unknown Yes/No question", pressed("#other-yesno") == [])
                check("picks a radio answer", ats.locator("input[name=hispanic][value=d]").is_checked())
                check("skips a hidden survey", ats.evaluate("[...document.getElementsByName('hidden-survey')].every(r => !r.checked)"))
                check("never answers a blocked radio question", ats.evaluate("[...document.getElementsByName('age')].every(r => !r.checked)"))
                check(
                    "picks one race checkbox",
                    ats.locator("#race input[name=White]").is_checked() and not ats.locator("#race input[name=Other]").is_checked(),
                )
                check(
                    "picks a race checkbox when labels are siblings",
                    ats.locator("#eth-2").is_checked() and not ats.locator("#eth-3").is_checked(),
                )
                check("a reused checkbox name doesn't merge two questions", not ats.locator("#eth-4").is_checked() and not ats.locator("#oth-2").is_checked())
                check("finds a location field with an icon-only button", picked("ashby-city") == "Ann Arbor, MI", picked("ashby-city"))
                check("never ticks a consent box", not ats.locator("#consent").is_checked())
                check("never fills a blocked text field", ats.locator("#ssn").input_value() == "")
                check("leaves free-text questions", ats.locator("#why").input_value() == "")
                resume_name = ats.evaluate("document.getElementById('resume').files[0]?.name")
                check("attaches the resume to a hidden Attach input", resume_name == "ada_resume.pdf", resume_name)
                check("the panel lists what it never answers", "Launchpad never answers these" in report and "Social Security Number" in report, report)
                check("the panel contains no values", email not in report and "120000" not in report, report)
                check("nothing is submitted by autofill", ats.evaluate("window.__submitted") is False)
                check("the page cannot read the token", token not in ats.content())

                # Pressing the site's Submit offers tracking.
                ats.locator("#submit").click()
                panel.get_by_text("Submitted? Add it to your tracker.").wait_for(timeout=5000)
                check("guesses the job from the page title", panel.get_by_label("Job title").input_value() == "Staff Engineer" and panel.get_by_label("Company").input_value() == "Fixture Labs")
                panel.get_by_role("button", name="Add to tracker").click()
                panel.get_by_text("Added to your tracker.").wait_for(timeout=10000)
                tracked = api("/function/list_tracker_applications", {"token": token}, token)["data"]["result"]["applications"]
                check("Submit reaches the tracker", any(t["role"] == "Staff Engineer" and t["company"] == "Fixture Labs" for t in tracked), tracked)

                popup.goto(f"{popup_url}?tab={tab_id}")
                popup.locator("#main-view").wait_for(state="visible", timeout=15000)

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

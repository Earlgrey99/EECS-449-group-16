"""Headless browser smoke walkthrough for the Jaccit classroom demonstration.

Requires a running Jac server in the TEST profile and Playwright Chromium.
Use sample data only; this does not submit any external application.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError

BASE = os.getenv("DEMO_BASE_URL", "http://127.0.0.1:8000").rstrip("/")


def main() -> int:
    errors: list[str] = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, args=["--no-sandbox"])
        context = browser.new_context(viewport={"width": 1380, "height": 850})
        page = context.new_page()
        page.on("pageerror", lambda exc: errors.append(str(exc)[:320]))
        try:
            page.goto(f"{BASE}/login", wait_until="domcontentloaded", timeout=45000)
            try:
                page.wait_for_url("**/jobs", timeout=30000)
            except PlaywrightTimeoutError:
                login_button = page.get_by_role("button", name="Continue as Test User")
                if login_button.count():
                    login_button.click()
                    page.wait_for_url("**/jobs", timeout=25000)
                else:
                    raise AssertionError("Test profile did not authenticate or redirect to /jobs")

            page.get_by_text("Based on your preferences").wait_for(timeout=35000)
            role = page.get_by_text("Data Analyst", exact=True).first
            role.wait_for(timeout=35000)
            role.click()

            page.get_by_role("button", name="Apply now (demo)").click()
            page.wait_for_url("**/tools?job=3", timeout=20000)
            page.get_by_role("heading", name="Application tools").wait_for(timeout=20000)

            page.get_by_placeholder("Test Applicant").fill("Demo Candidate")
            page.get_by_placeholder("test@example.com").fill("test@example.com")
            page.get_by_role("button", name="Autofill demo form").click()
            assert page.get_by_label("Candidate name").input_value() == "Demo Candidate"
            assert page.get_by_label("Candidate email").input_value() == "test@example.com"
            assert page.get_by_role("button", name="Submit application (disabled)").is_disabled()
            print("PASS: Job -> tools routing, sample autofill, no auto-submission")

            page.get_by_role("button", name="Generate resume review").click()
            page.locator("pre").wait_for(timeout=30000)
            review = page.locator("pre").inner_text()
            assert "Original resume" in review, "Resume review returned no original resume section"
            print("PASS: Local backend resume review")

            page.goto(f"{BASE}/tracker", wait_until="domcontentloaded", timeout=30000)
            page.get_by_role("heading", name="Application tracker").wait_for(timeout=25000)
            page.get_by_role("button", name="Insights").click()
            print("PASS: Tracker and insights")

            page.goto(f"{BASE}/me", wait_until="domcontentloaded", timeout=30000)
            page.get_by_text("Personal Information").wait_for(timeout=25000)
            print("PASS: Profile/onboarding page")

            if errors:
                print("Browser reported errors:", errors[-3:], file=sys.stderr)
            print("DEMO BROWSER WALKTHROUGH PASSED")
            return 0
        except Exception:
            print(f"Demo browser failed on {page.url}", file=sys.stderr)
            if errors:
                print("Browser errors:", errors[-5:], file=sys.stderr)
            page.screenshot(path="demo-browser-failure.png", full_page=True)
            raise
        finally:
            context.close()
            browser.close()


if __name__ == "__main__":
    raise SystemExit(main())

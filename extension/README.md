# Launchpad Autofill

A Chrome extension that fills job applications from your Launchpad profile. It
fills fields for you to review. **It never submits an application.**

## Try it

1. Start Launchpad:

   ```bash
   export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"
   jac run --dev --profile test main.jac
   ```

2. In Chrome, open `chrome://extensions`, turn on **Developer mode**, click
   **Load unpacked**, and choose this `extension/` folder.
3. Sign in at <http://localhost:8000> and complete your profile.
4. Click the extension icon, then **Connect to Launchpad**.
5. Open a job application, click the icon, and choose **Preview** or **Fill this page**.

The extension also works in other Chromium browsers, such as Edge and Brave.

## How it works

On Greenhouse, Lever, Ashby, Workday, SmartRecruiters, iCIMS, Jobvite, Workable, and
BambooHR application pages, a panel appears in the corner. Click **Autofill this
application**, review the result, and submit it yourself. When you press the site's
Submit button, the panel offers to add the job to your tracker.

For other sites, click the toolbar icon and choose **Preview** or **Fill this page**.

## What it fills

| Field | Source |
|---|---|
| Name, email, phone, city, LinkedIn, GitHub, portfolio | Your Launchpad profile |
| Resume | Newest resume in your Launchpad profile |
| Work authorization, sponsorship, employer, education, country, salary, start date | **Application answers** in your Launchpad profile |
| Gender, race, Hispanic or Latino, veteran, disability, pronouns | **Saved answers** in the extension, stored only in this browser |

It handles text boxes, dropdowns, searchable dropdowns, radio buttons, checkboxes, Yes/No
buttons, and resume uploads.

## What it leaves alone

- **Anything you haven't answered.** Personal questions are filled only from answers you
  chose, and "Leave for me" is the default.
- **Never filled, whatever you save:** passwords, Social Security and government ID
  numbers, bank and card details, date of birth or age, religion, sexual orientation, and
  criminal history.
- **Fields about other people or organizations**, such as "Emergency contact phone".
- **Consent checkboxes and free-text questions**, such as "Why do you want this job?".
- **Anything already filled in**, including your own edits.
- **Anything unclear.** If a saved answer doesn't match exactly one option, it's left for
  you and listed in the panel.

## Permissions and data

- Hiring sites listed above: show the panel on those sites. It reads the page's fields,
  and gets your profile only after you click Autofill.
- `activeTab` and `scripting`: fill other sites only when you click a popup button.
- `storage`: holds your session token until the browser closes, and your saved answers and
  the Launchpad address in this browser.
- Access to `http://localhost:8000`: read your Launchpad session and profile. Another
  Launchpad address must use HTTPS, and Chrome asks you to approve it.

Your session token stays in the extension's background service. Job sites never see it.

The extension never handles your password. Filling a form puts your data on that
employer's page, where the site can read it even before you submit, so only fill
forms on sites you trust.

## Known limits

- **Multi-step forms** such as Workday: click **Fill again** on each step. Workday's custom
  controls haven't been tested.
- **Other sites' custom dropdowns** that don't follow common patterns aren't filled.
- **Filling is tested on fixtures and live forms, without submitting.** Review every field.

## Tests

```bash
node --test tests/extension/autofill.test.js
```

With Launchpad running in the test profile:

```bash
.jac/venv/bin/python -m playwright install chromium
.jac/venv/bin/python tests/extension_e2e.py
```

On macOS 13, set `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=mac14-arm64` for both Playwright
commands, because Playwright has no Chromium build for that version.

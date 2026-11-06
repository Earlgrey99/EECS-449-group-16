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

## What it fills

| Field | Source |
|---|---|
| First name, last name, full name, email | Launchpad account |
| Resume | Newest resume in your Launchpad profile, if the box is checked |
| Phone, city, LinkedIn, GitHub, portfolio | **Details and settings** in the popup, saved only in this browser |

It uses only City for location, because the Launchpad location field holds the
places you want to work.

## What it leaves alone

- **Sensitive questions:** demographics, disability, veteran status, date of birth,
  salary, work authorization, visas, criminal history, and government or financial
  IDs. The popup lists these for you to answer.
- **Fields about other people or organizations**, such as "Company name" or
  "Emergency contact phone".
- **Anything already filled in**, including your own edits.
- **Anything it isn't sure about.** A blank field is better than a wrong answer.

## Permissions and data

- `activeTab` and `scripting`: run on a page only when you click a popup button.
  The extension has no access to the sites you browse otherwise.
- `storage`: holds your session token until the browser closes, and your details
  and settings in this browser.
- Access to `http://localhost:8000`: read your Launchpad session and profile.
  Another Launchpad address must use HTTPS, and Chrome asks you to approve it.

The extension never handles your password. Filling a form puts your data on that
employer's page, where the site can read it even before you submit, so only fill
forms on sites you trust.

## Known limits

- **Embedded forms:** an application in another site's iframe can't be reached. The
  popup links to known hiring systems so you can open the form in its own tab.
- **Multi-step forms** such as Workday: click **Fill this page** again on each step.
- **Custom dropdowns** that aren't real `<select>` elements aren't filled.
- **Real hiring sites** haven't been tested yet, so review every field.

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

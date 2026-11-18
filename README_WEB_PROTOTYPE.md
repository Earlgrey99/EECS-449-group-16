# Launchpad local applicant-tools prototype

This branch is based on the latest main, including multi-provider job fetching,
compatibility scoring, and lazy Turso imports. It includes the earlier CLI tools.

## Run

From the repository root on Mac (Jac 0.37.11):

```bash
git fetch origin
git switch feature/launchpad-web-autofill-tailoring
jac install
jac check main.jac
jac test -d tests -v
python3 -m unittest discover -s tests -p 'test_applicant*.py' -v
jac run --dev main.jac
```

Visit http://localhost:8000, sign in using your test account, and open
**Applicant tools** in the top navigation or use **Apply now** in the sample
job feed. The page routes are `/tools` and `/tracker`.

## Application tracker

Open **Tracker** in the top navigation to view a Notion-style application table
or switch to **Insights** for live status totals, a configurable status pie,
bar, or data-table view, and an application-flow Sankey diagram. Use
**Manage widgets** to add or remove individual statistics and charts. Add
applications, click **Edit** in the tracker toolbar and check one or more
applications to edit their details independently in one session, update
their status, and export the current table as CSV. In the application editor,
customize status names and colors; statuses currently assigned to applications
cannot be removed until those applications are reassigned. You can optionally
attach a resume PDF and cover letter PDF (up to 2 MB each). Applications and
status options are saved to the signed-in user's tracker.
The table keeps descriptions compact in a **Notes** column; double-click a
Notes button to read the full description in a side sheet.
Use the sun/moon control in the top navigation to switch between light and dark
mode; the preference is remembered in the browser.

## Prototype A: autofill

Enter a test name and email (optional phone/LinkedIn), then click
**Autofill demo form**. The right-side sample form is filled in, remains
editable, and cannot submit. Data lives in component memory only and clears
on refresh. This is not an integration with external ATS websites.

The CLI Playwright proof-of-concept is also preserved:

```bash
jac run main.jac -- profile --set name "Test Applicant" --set email "test@example.com"
jac x playwright install chromium
jac run main.jac -- autofill --target "file://$(pwd)/examples/application_form.html" --mapping examples/mapping.json --apply
```

## Prototype B: resume tailoring

On `/tools`, edit the sample resume and job description and click
**Generate resume review**. The page invokes the Jac server function
`services/applicant_demo.jac::review_resume_text`, which calls the same
Python `generate_tailored_markdown` algorithm used by the CLI.
The review shows verified terms, requirements missing from the resume,
existing relevant bullets, and unchanged original text. It is *not* an
LLM-generated final resume.

Only pasted text is supported in the web page. PDF and DOCX support remain
available in the CLI `tailor-resume` command.

## Career Navigator chat

The Career Navigator chat uses Puter.js in the browser with the
`openai/gpt-5.3-codex` model. No server API key is required. Puter may prompt
users to sign in on first use; AI usage follows Puter's user-pays model. Chat
history remains saved to the Launchpad account database.

When neither `TURSO_DATABASE_URL` nor `TURSO_URL` is configured, local
development stores app data in `.jac/data/launchpad.db`. Set the Turso
environment variables to use a shared database instead.

## Boundaries and merge checks

- Local prototype only; do not expose to the public Internet.
- Applicant-tools web inputs are session-only and do not sync with Turso or the
  local CLI profile. Career Navigator chats are saved per account in the app
  database.
- The browser sample form never submits a job application.
- Resume text is processed by the local Jac backend, not stored in the app.
- Run `jac check main.jac`, Jac tests, Python tests, and manually verify routes
  `/`, `/login`, `/jobs`, `/tools` before requesting merge.
- Browser compatibility with external job application forms is not guaranteed.

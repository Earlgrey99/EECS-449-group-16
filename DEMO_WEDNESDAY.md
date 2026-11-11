# Launchpad — Wednesday, November 4, 2026 demo checklist

> **Local classroom prototype** — run only on localhost with sample data.
> The applicant autofill is not a full production workflow.

## 1. Set up the demo Mac (before presenting)

Run in Terminal from the team repo:

```bash
cd ~/Desktop/EECS-449-group-16
git status --short
git switch main
git pull --ff-only origin main
jac --version                    # expected 0.37.11
jac install
export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"
jac run --dev --profile test main.jac
```

The `git switch` / `git pull` commands require a clean working tree.
Use the existing shell or set `TURSO_DATABASE_URL` again when opening a new shell.
The SQLite demo database is outside the Git checkout. Do not commit real resumes,
credentials, or database files.

Check these routes before the talk:

- `http://localhost:8000/` — landing page
- `http://localhost:8000/login` — authentication (test profile auto-login)
- `http://localhost:8000/jobs` — job feed
- `http://localhost:8000/tools` — autofill and resume review
- `http://localhost:8000/tracker` — application tracker
- `http://localhost:8000/me` — profile/onboarding

In test mode, a fresh login should use the development test user automatically.
If you deliberately signed out, the login page may show a test-user sign-in option.
Do not rely on Google OAuth or a working external jobs API for the classroom demo.

## 2. The 5-minute live walkthrough

**0:00–0:30: Landing and jobs.**
Introduce Launchpad as a Jac-based job application workflow. Go to Jobs.
Explain local sample listings are a reliable fallback, while the backend also
supports Jooble, USAJobs, Himalayas and The Muse with optional credentials/network.

**0:30–1:45: Autofill.**
In Jobs, select the local **Data Analyst** role (Cascade Health).
Click **Apply now (demo)**. On the Applicant tools page, enter:
`Test Applicant`, `test@example.com`, `5551234567`.
Click **Autofill demo form**. Show that fields populate and remain editable.
The submit button is intentionally disabled; this does **not** submit a real application.

**1:45–2:45: Resume review.**
On the same page, keep the sample resume or paste:
```text
Data science student
- Built Python data pipelines to process incoming files.
- Created dashboards to summarize analytics.
```
Use the job description prefilled from the selected local Data Analyst role.
Click **Generate resume review**. Explain verified matches (e.g. Python,
dashboards) and requirements that need evidence (e.g. SQL).
The tool does not invent experience or produce a finalized rewritten resume.

**2:45–4:00: Tracker and Insights.**
Click Tracker. Add an example with a company, title and application date.
Change its status, refresh to show it was saved, open Insights, explore the status
chart and response statistics, and export a CSV.

**4:00–5:00: Profile and personalization.**
Open Account → Profile. Show sector, target titles, location, salary, and
resume-upload controls. With the configured SQLite demo database, saving a
profile stores preferences and a cached job-search query. With a DeepSeek key,
the backend can synthesize queries; without one, it uses a deterministic
fallback. Network/API access may affect live search, so show this last.

## 3. What is demo-ready vs. prototype-only

| Capability | State |
| --- | --- |
| Landing, sign-in/test profile, navigation | Implemented; verify visually |
| Job feed + query filters | Implemented; includes local fallback |
| Personalized job query | Backend database flow; API/LLM optional |
| Autofill web page | Local sample form; no external submission |
| Resume tailoring web page | Server-side text matching/review, not full rewrite |
| Application tracker | Saved per user in the database; CSV export |
| Multi-provider external jobs | API-dependent; do not rely on live calls |
| Google OAuth | Integration exists; avoid as a demo dependency |
| End-to-end form submissions | Not implemented |

## 4. Recovery plan

- If login fails, verify the process was started with
  `jac run --dev --profile test main.jac` and
  `TURSO_DATABASE_URL="$HOME/launchpad-demo.db"`.
- If a cached job query gives poor results, clear the two *visible* job-search
  fields (on the presentation-hardening PR) or start with the local demo
  listings before profile onboarding.
- If external APIs stall or return no jobs, stay with local listings.
- If a save action fails, confirm SQLite is configured and available.
- If autofill or review has an issue, show the other feature and the README
  rather than attempting real external job submissions.
- Keep a clean restart option: stop server with Ctrl+C and rerun the above
  command. Avoid deleting the demo DB if you want profile persistence.

## 5. Validation

Run `jac check main.jac` and `jac test -d tests -v` before the presentation.
GitHub CI also compiles the page files, runs applicant Python tests, and smoke
tests routes; HTTP smoke tests **do not** replace a browser click-through.

**Security:** Current public configuration includes committed authentication
defaults, and identity resolution requires security hardening. Use localhost
and fake applicant details only; do not deploy publicly as-is.

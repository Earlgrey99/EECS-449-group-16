# Jaccit local applicant-tools prototype

This branch is based on the latest main, including multi-provider job fetching,
compatibility scoring, and lazy Turso imports. It includes the earlier CLI tools.

## Run

From the repository root on Mac (Jac 0.37.11):

```bash
git fetch origin
git switch feature/jaccit-web-autofill-tailoring
jac install
jac check main.jac
jac test main.jac -v
python3 -m unittest discover -s tests -p 'test_applicant*.py' -v
jac run --dev main.jac
```

Visit http://localhost:8000, sign in using your test account, and open
**Applicant tools** in the top navigation or use **Apply now** in the sample
job feed. The new page route is `/tools`.

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

## Boundaries and merge checks

- Local prototype only; do not expose to the public Internet.
- Web inputs are session-only and do not sync with Turso or the local CLI profile.
- The browser sample form never submits a job application.
- Resume text is processed by the local Jac backend, not stored in the app.
- Run `jac check main.jac`, Jac tests, Python tests, and manually verify routes
  `/`, `/login`, `/jobs`, `/tools` before requesting merge.
- Browser compatibility with external job application forms is not guaranteed.

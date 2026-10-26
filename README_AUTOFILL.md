# Applicant autofill and resume tailoring (Issues #7 and #15)

These features add three commands to the existing Jac CLI while preserving the current site and Turso implementation.

Setup: Install dependencies from jac.toml, then run `python -m playwright install chromium`.
Run Python tests: `python -m unittest discover -s tests -v`.
Check Jac: `jac check main.jac` (requires Jac 0.37.11).

## Profile
`jac run main.jac -- profile --set name "Jane Doe" --set email "jane@example.org"`
`jac run main.jac -- profile --set resume_path /absolute/path/resume.pdf`
`jac run main.jac -- profile --show`

Profile is saved locally under ~/.eecs449/profile.json with mode 0600; don't commit real applicant data.

## Autofill
`jac run main.jac -- autofill --target "https://example.org/apply"` (preview)
`jac run main.jac -- autofill --target "https://example.org/apply" --apply` (fill only)

Custom field mappings: `--mapping examples/mapping.json`.
Never automatically submits. The final action belongs to the user. Common text/select/file fields are supported; dynamically rendered sites and iframe forms may require site-specific adjustments.

## Resume review
`jac run main.jac -- tailor-resume --resume myresume.pdf --job-description job.txt --role "Data Analyst" --output review.md`

Creates review.md and review.review.json with verified terms, gaps, and relevant original bullets. This is an evidence-preserving review draft, not a guaranteed ATS-optimized application.

## Integration notes
This is a CLI-first implementation. Turso profile syncing, authenticated web APIs, frontend UI, and site-specific ATS automation are future integration tasks. Validate Jac compilation with the pinned toolchain before merging.

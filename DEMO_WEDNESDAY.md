# Launchpad demo checklist

> **Local prototype.** Run on localhost with sample data and fake applicant details.
> The extension fills forms but never submits them.

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

`git switch` and `git pull` need a clean working tree. Set `TURSO_DATABASE_URL` again in any
new shell. Keep the database outside the repo, and don't commit resumes, credentials, or
database files. Run `jac install` after every pull, because new packages are added from time
to time.

If a page keeps reloading on its own, stop the server, run `jac clean --cache`, and start it
again.

Load the extension:

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and choose the repo's `extension/` folder. If it's already loaded,
   click its reload button instead.
3. Click the extension icon, then **Connect to Launchpad**.

Check these routes before the talk:

- `http://localhost:8000/`: landing page
- `http://localhost:8000/login`: sign-in (the test profile signs in automatically)
- `http://localhost:8000/jobs`: job feed with match scores
- `http://localhost:8000/me`: profile, contact details, and application answers
- `http://localhost:8000/tools`: autofill profile, resume review, and tailored PDF
- `http://localhost:8000/tracker`: application tracker

Don't rely on Google sign-in or the external job APIs during the demo.

## 2. Prepare the demo profile

On **Account → Profile**:

1. Step 1: name, phone, city, and a LinkedIn URL.
2. Step 2: under **Application answers**, set work authorization, sponsorship, school, and
   current company.
3. Step 3: upload a sample PDF resume, then click **Finish**.

In the extension, click **Saved answers** and choose demographic answers, or
**Prefer not to say**. These stay in the browser and are never sent to Launchpad.

## 3. The 6-minute walkthrough

**0:00–1:00: Jobs.**
Show the feed tailored to the saved profile, with a match score on each job. Open a job,
point out its matched and missing skills, and click **Add to tracker**.

**1:00–2:30: Autofill profile, resume review and tailored PDF.**
Click **Apply now (demo)**. Applicant Tools opens with the job description and the saved
resume already filled in. Under **Your autofill profile**, show exactly what the extension
will fill, and which values were read from the resume. Then click **Generate resume review** and show verified skills and
requirements the resume doesn't support. Under **Tailored resume PDF**, click **Create
tailored PDF**, show the list of what changed, and download it. Point out that it only
reorders: the most relevant bullets move up and matching skills come first, and nothing is
added or reworded.

**2:30–4:30: The extension on a real application.**
Open a public Greenhouse or Lever application, such as a job from
`https://boards.greenhouse.io/figma`. When the Launchpad panel appears, click **Autofill
this application**. Show the filled fields, the dropdowns and Yes/No questions answered from
saved answers, and the panel's report:

- questions it left for you, such as "Why do you want this job?"
- questions it never answers, such as date of birth or Social Security number

**Do not click Submit.** Close the tab when you're done.

**4:30–6:00: Tracker.**
Open Tracker. Show the job added earlier, change its status, refresh to show it saved, open
Insights, and export a CSV.

## 4. What is demo-ready vs. prototype-only

| Capability | State |
| --- | --- |
| Sign-in, profile, onboarding | Implemented; identity comes from the verified session |
| Job feed, filters, match scores | Implemented; local listings are the fallback |
| Resume review and tailored PDF | Implemented; reorders only, never invents content |
| Extension panel | Implemented on Greenhouse, Lever, Ashby, and more; Workday untested |
| Application tracker | Saved per user; Add to tracker from jobs and the extension |
| External job APIs | Network-dependent; Himalayas needs no key |
| Google sign-in | Implemented; avoid as a demo dependency |
| Submitting applications | Never automated, by design |

## 5. Recovery plan

- **Login fails:** check that the server was started with `--profile test` and the
  `TURSO_DATABASE_URL` above.
- **A page keeps reloading:** run `jac clean --cache` and restart the server.
- **External jobs are slow or empty:** stay with the local listings.
- **The extension panel doesn't appear:** reload the extension, then the job page, and check
  that it says it's connected. The toolbar popup's **Fill this page** works on any site.
- **A dropdown isn't filled:** say so, and show the panel listing it for the user. Don't
  improvise answers on a live form.
- **Restarting:** stop the server with Ctrl+C and rerun the command above. Keep the demo
  database if you want the profile to persist.

## 6. Validation

Before presenting, run `jac check main.jac` and `jac test -d tests -v`. CI also runs the
Python tests, the extension tests, identity checks, and a browser walkthrough on every pull
request and push to `main`. Automated tests don't replace one live click-through.

**Security:** endpoints take the user only from the verified session. The Google OAuth client
secret is still in `jac.toml` and git history and must be rotated before any public
deployment. Use localhost and fake applicant details for the demo.

# Class demo: autofill and the resume enhancer

This guide sets up a laptop to show two Launchpad features to the class:

1. **Resume enhancer.** It tailors a resume PDF to a job and keeps the original look.
2. **Application autofill.** The Chrome extension fills a job application from the
   Launchpad profile.

Everything uses **Alex Morgan, a made-up applicant**, and a separate demo database, so
no real resume or personal details appear on screen.

## What's in `demo/`

| File | What it's for |
|---|---|
| `alex_morgan_resume.pdf` | Alex's one-page resume (built from `alex_morgan_resume.tex`) |
| `job_posting.txt` | A Data Engineering Intern posting to paste into the enhancer |
| `seed_demo_profile.jac` | Fills the demo account with Alex's profile and resume |
| `sample_application.html` | An offline practice application form, for the autofill demo |
| `backup/before.png`, `backup/after.png`, `backup/Alex_Morgan_Resume_tailored.pdf` | Screenshots and output to show if the live demo fails |

---

## Part 1: Set up the night before (about 20 minutes)

You need Chrome, Git, and Jac 0.37.11. If you haven't set up Launchpad on this laptop
before, follow Part 1 of [EXTENSION_SETUP.md](EXTENSION_SETUP.md) first.

### 1. Get the latest code

```bash
cd ~/Desktop/EECS-449-group-16 && git switch launch && git pull --ff-only origin launch && jac install
```

### 2. Add the AI key

AI rewording needs the team's DeepSeek key in a `.env` file at the repo root. Ask the
team for the key if you don't have it. The file only needs this line:

```
DEEPSEEK_API_KEY=sk-...
```

`.env` is ignored by git. Never commit it. Don't put `TURSO_*` lines in it for the
demo, or Launchpad will use the shared online database instead of the demo one.

### 3. Fill the demo account with Alex's profile

The demo uses its own database file, so your real profile isn't touched. Run both
lines in the same terminal:

```bash
export TURSO_DATABASE_URL="$HOME/launchpad-class-demo.db"
```

```bash
jac run --no-takeover demo/seed_demo_profile.jac
```

It prints `Alex Morgan is ready in .../launchpad-class-demo.db`. Run it again at any
time to reset Alex: his resume goes back to the original, the tailored copy is cleared
and the tracker is emptied.

### 4. Start Launchpad

In the same terminal (so `TURSO_DATABASE_URL` is still set):

```bash
jac clean --cache --force && jac run --dev --profile test main.jac
```

Wait until it prints `App: http://localhost:8000/`. It must be port 8000, because
that's the only Launchpad address the extension trusts. If it picks another port,
something else is already using 8000: stop it and start again.

### 5. Load and connect the extension

1. Go to `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**,
   and choose the repo's `extension` folder. If it's already loaded, click its reload
   arrow instead.
2. Pin **Launchpad Autofill** to the toolbar (puzzle-piece icon, then the pin).
3. Open <http://localhost:8000/login>. The test account signs in by itself.
4. Click the Launchpad toolbar icon, then **Connect to Launchpad**. It should say
   **Alex Morgan** and show `Alex_Morgan_Resume.pdf`.

If it shows a different name, the extension is still connected to another account:
click **Disconnect**, then **Connect to Launchpad** again.

### 6. Start the practice application form

Open a **second** terminal and leave it running:

```bash
cd ~/Desktop/EECS-449-group-16/demo && python3 -m http.server 8090
```

The form is then at <http://localhost:8090/sample_application.html>.

### 7. Rehearse once, then reset

Run the whole script in Part 3. Then go back to the first terminal, press
<kbd>Ctrl</kbd>+<kbd>C</kbd>, run step 3's seed command again, and start Launchpad
again with step 4. Alex is back to his starting state for the real demo.

---

## Part 2: 10 minutes before class

1. Check that both terminals are still running: Launchpad on 8000 and the form on 8090.
2. Open these tabs, in this order:
   - <http://localhost:8000/tools>
   - <http://localhost:8090/sample_application.html>
   - `demo/backup/before.png` and `after.png`, in Preview, in case you need them.
3. Open `demo/job_posting.txt` in a text editor and select all of it, ready to paste.
4. Click the extension icon and check that it still says **Alex Morgan**.
5. Zoom Chrome to about 125% (<kbd>Cmd</kbd>+<kbd>+</kbd>) so the back row can read it.
6. Turn on Do Not Disturb, and close other apps and tabs.

---

## Part 3: The demo script (about 6 minutes)

### Introduce Alex (30 seconds)

> "This is Alex Morgan, a made-up CS student. Alex has a normal one-page resume and is
> applying for a Data Engineering internship."

On <http://localhost:8000/tools>, scroll through **1. Your autofill profile**.

> "This is everything our extension will fill in on an application: contact details
> and the usual questions, like work authorization and graduation year."

### Feature 1: The resume enhancer (3 minutes)

1. Scroll to **2. Tailor your resume**.
2. In **Job title**, type `Data Engineering Intern`.
3. In **Job description**, paste all of `job_posting.txt`.
4. Tick **Reword bullets with AI**.
5. Click **Tailor my resume**. It takes about 3 seconds.

Walk through the result from top to bottom:

- **Job keywords your resume has:** "Alex already has Python, SQL, PostgreSQL, ETL,
  pandas and Docker."
- **What changed:**
  - "In each job, the bullet that best matches the posting moved to the top. The Python
    ETL bullet used to be fourth; now it's first."
  - "In the skills section, the matching skills come first. Python and SQL lead the
    languages line now."
  - "AI reworded a few bullets in the job's terms. 'ETL job' became 'ETL pipeline.'"
- **Left as it was:** This is the safety check.

  > "Every AI rewording is checked. If it adds a number, a skill, a company or a claim
  > that isn't already on the resume, Launchpad throws it away."

  The AI's wording changes from run to run. Usually one rewording is rejected here,
  often the data quality one, and you can read it out. If this list doesn't appear,
  just explain the check.
- **The new PDF:** Scroll to the preview.

  > "This is the same PDF, edited in place. Same fonts, same layout, still one page. It
  > didn't regenerate the resume from a template."

  If you want a side-by-side, show `backup/before.png` next to it.

Then show the missing keywords:

6. Under **Job keywords your resume doesn't mention**, click **+ spark**.

   > "Launchpad never adds a skill on its own. Alex says they really do know Spark, so we
   > confirm it."

7. Click **Add 1 skill and tailor again**. The list now says **Added Spark to Developer
   Tools**, and Spark appears at the end of that skills line in the PDF.
8. Click **Use this resume for applications**. The banner changes to "tailored for Data
   Engineering Intern."

   > "Now the extension attaches this tailored version instead of the original."

### Feature 2: Autofill an application (2 minutes)

1. Switch to the practice form tab.

   > "This is a typical job application: contact info, education, the yes/no
   > questions, a resume upload, and a few things we should never fill in."

2. Click the Launchpad toolbar icon. The popup shows Alex and the tailored resume.
3. Click **Fill this page**. Clicking the icon gives the extension access to this one
   tab, so no permission prompt appears.
4. Click the page to close the popup, then scroll down the form:
   - Name, email, phone, city, LinkedIn and GitHub are filled.
   - School, degree, major, graduation year, company and title are filled.
   - **Country** and **work authorization** dropdowns are set, and **sponsorship** is
     answered No.
   - The **resume** is attached: `Resume - Data Engineering Intern.pdf`, the one we just
     tailored.
5. Point at what stayed empty:

   > "'Why do you want to work here' is left for Alex to write. Date of birth and Social
   > Security number are never filled, by design. Gender and veteran status are only
   > filled if Alex chooses answers in the extension's private Saved answers, and those
   > never leave the browser."

6. Click the toolbar icon again to show the report: **Filled. Please review (19)**,
   **Please answer these yourself**, and **Launchpad never answers these**.

   > "It never clicks Submit. Alex reviews everything and submits it himself."

The email field shows `testuser@example.com`. That's the built-in test account's
email, which autofill always takes from the account. Mention it if anyone asks.

### Optional: a real job site (1 minute)

If the Wi-Fi is good, open a real Greenhouse application, such as any job on
<https://boards.greenhouse.io/figma>. A Launchpad panel appears on the page by itself.
Click **Autofill this application**, show the filled fields, then **close the tab
without submitting**.

---

## If something goes wrong

| Problem | What to do |
|---|---|
| The AI rewording doesn't appear, or the note says AI was unavailable | Carry on. Reordering still works without AI. Mention that rewording needs the API key and network, and show `backup/after.png`. |
| Tailoring fails or the preview is blank | Show `backup/before.png` and `backup/after.png` side by side, or open `backup/Alex_Morgan_Resume_tailored.pdf`. |
| The extension shows the wrong person, or "sign in first" | Keep a `localhost:8000` tab open, click **Disconnect**, then **Connect to Launchpad**. |
| **Fill this page** does nothing | Reload the form tab, then click the icon and **Fill this page** again. On `chrome://extensions`, reload the extension if needed. |
| The resume isn't attached | Make sure **Include resume** is ticked in the popup. |
| A build error, or a page that keeps reloading | Press <kbd>Ctrl</kbd>+<kbd>C</kbd> and rerun step 4. It clears the cache first. |
| Alex's resume or tracker is messy from rehearsal | Stop Launchpad, rerun the seed command in step 3, start Launchpad again. |
| The form page won't load | The second terminal from step 6 isn't running. Start it again. |

## After the demo

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in both terminals. To go back to your own profile,
run `export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"` before you start Launchpad
again, and reconnect the extension. The demo database is `~/launchpad-class-demo.db`.
You can delete it when you're done.

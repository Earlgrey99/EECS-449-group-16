# Class demo: a tour of every Launchpad feature

This guide sets up a laptop and walks the class through all of Launchpad, from finding
a job to applying for it and tracking it, in about 12 minutes. Everything runs from one
Launchpad server at <http://localhost:8000>, including the practice application form.

It uses **a demo profile for Shashank Sekhar with made-up details**, in a separate demo
database, so no real resume or personal details appear on screen.

## What the demo uses

| File | What it's for |
|---|---|
| `demo/seed_demo_profile.jac` | Fills the demo account with Shashank's profile and resume |
| `demo/shashank_sekhar_resume.pdf` | Shashank's one-page resume (built from `shashank_sekhar_resume.tex`) |
| `demo/job_posting.txt` | The Data Engineering Intern posting, in case you need to paste it |
| `assets/demo-application.html` | The practice application form, served at `localhost:8000/static/demo-application.html` |
| `demo/backup/` | Before and after images and the tailored PDF, to show if the live demo fails |

The job feed includes a made-up **Data Engineering Intern at Bluewater Analytics**
listing. Its **Apply now** button opens the practice form, so you can go from the job to
the application without leaving Launchpad.

---

## Part 1: Set up the night before (about 15 minutes)

You need Chrome, Git, and Jac 0.37.11. If you haven't set up Launchpad on this laptop
before, follow Part 1 of [EXTENSION_SETUP.md](EXTENSION_SETUP.md) first.

### 1. Get the latest code

```bash
cd ~/Desktop/EECS-449-group-16 && git switch launch && git pull --ff-only origin launch && jac install
```

### 2. Add the AI key

AI rewording needs the team's DeepSeek key in a `.env` file at the repo root. Ask the
team for the key if you don't have it. The file needs this line:

```
DEEPSEEK_API_KEY=sk-...
```

`.env` is ignored by git. Never commit it. Don't put `TURSO_*` lines in it for the
demo, or Launchpad will use the shared online database instead of the demo one.

### 3. Fill the demo account and start Launchpad

Run these in one terminal and leave it open. The first line points Launchpad at the
demo database, so your real profile isn't touched:

```bash
export TURSO_DATABASE_URL="$HOME/launchpad-class-demo.db"
```

```bash
jac run --no-takeover demo/seed_demo_profile.jac && jac clean --cache --force && jac run --dev --profile test main.jac
```

It prints `Shashank Sekhar is ready in .../launchpad-class-demo.db`, then starts
Launchpad. Wait until it prints `App: http://localhost:8000/`. It must be port 8000,
because that's the only Launchpad address the extension trusts. If it picks another
port, something else is already using 8000: stop it and start again.

### 4. Load and connect the extension

1. Go to `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**,
   and choose the repo's `extension` folder. If it's already loaded, click its **reload
   arrow**: the extension changed, and it only shows its panel on the practice form
   after a reload.
2. Pin **Launchpad Autofill** to the toolbar (puzzle-piece icon, then the pin).
3. Open <http://localhost:8000/login>. The test account signs in by itself.
4. Click the Launchpad toolbar icon, then **Connect to Launchpad**. It should say
   **Shashank Sekhar** and show `Shashank_Sekhar_Resume.pdf`. If it shows another name,
   click **Disconnect**, then **Connect to Launchpad**.

### 5. Sign in to the career assistant

The **Explore** page's career assistant runs on Puter, a free in-browser AI service.
Open <http://localhost:8000/explore>, ask it anything, and sign in to Puter in the popup
that appears. Do this the night before, so the class doesn't watch a sign-in.

### 6. Rehearse once, then reset

Run the whole script in Part 3. Then reset Shashank: press <kbd>Ctrl</kbd>+<kbd>C</kbd>
in the Launchpad terminal and run the long command from step 3 again. That restores
the original resume, clears the tailored copy and empties the tracker.

---

## Part 2: 10 minutes before class

1. Check that the Launchpad terminal is still running.
2. Open <http://localhost:8000/> in Chrome and close other tabs.
3. Click the extension icon and check that it still says **Shashank Sekhar**.
4. Open `demo/backup/before.png` and `after.png` in Preview, in case you need them.
5. Zoom Chrome to about 125% (<kbd>Cmd</kbd>+<kbd>+</kbd>) so the back row can read it.
6. Turn on Do Not Disturb.

---

## Part 3: The demo script (about 12 minutes)

### 1. Landing page and profile (1.5 minutes)

On <http://localhost:8000/>:

> "Launchpad helps students find jobs, tailor their resume to each one, fill out
> applications, and keep track of where they've applied. I'll show it with a demo
> profile for Shashank. The resume and contact details are made up."

Click **Sign in with email**. The test account signs in by itself and opens the job
feed. Then open **Account → Profile**. It has three steps; click **Next** to move
between them:

1. **Personal information:** name, phone, city, LinkedIn, GitHub, and target
   locations (Ann Arbor first, then remote).
2. **Career and job preferences:** desired roles (Data Engineer, Software Engineer,
   Data Analyst), internships and full-time, plus the **application answers**: work
   authorization, sponsorship, school, graduation year.
3. **Resume:** the saved PDF.

Below the steps, **Your Resume Details** lists the jobs, education and skills read from
the resume, which the student can correct.

> "Students fill this in once. Everything else in Launchpad uses it."

### 2. Job feed (2 minutes)

Click **Jobs**.

- "Jobs are ranked by Shashank's preferences, and each one has a match score against
  the resume."
- Click **Data Engineering Intern** at **Bluewater Analytics**, the strongest match at
  about 77%. Point out **Your match** and its matched skills: Python, SQL, AWS,
  PostgreSQL, Docker and pandas.
- Click **Add to tracker**. The button changes to **In your tracker**.

The feed shows the built-in sample listings, because the demo profile has no saved
live search. To show live listings, type a search like `data engineer` in the search
box. Live results depend on the Wi-Fi and the job sites, so keep this optional.

### 3. Resume enhancer (3 minutes)

Still on the Bluewater listing, click **Tailor my resume**. Applicant Tools opens with
the job already filled in, so there's nothing to paste.

1. Scroll through **1. Your autofill profile**:

   > "This is exactly what our extension will fill on an application, and where each
   > value comes from."

2. Under **2. Tailor your resume**, tick **Reword bullets with AI** and click **Tailor
   my resume**. It takes about 3 seconds.
3. Walk through the results:
   - **Job keywords your resume has:** "Shashank already has Python, SQL, PostgreSQL,
     ETL, pandas and Docker."
   - **What changed:**
     - "In each job, the bullet that best matches the posting moved to the top. The
       Python ETL bullet used to be fourth; now it's first."
     - "The matching skills come first. Python and SQL lead the languages line now."
     - "AI reworded a few bullets in the job's terms. 'ETL job' became 'ETL
       pipeline.'"
   - **Left as it was:** "Every AI rewording is checked. If it adds a number, a skill,
     a company or a claim that isn't already on the resume, Launchpad throws it away."
     Usually one rewording is rejected here. If this list doesn't appear, just explain
     the check.
   - **The PDF preview:** "This is the same PDF, edited in place. Same fonts, same
     layout, still one page."
4. Under **Job keywords your resume doesn't mention**, click **+ spark**, then **Add 1
   skill and tailor again**:

   > "Launchpad never adds a skill on its own. Shashank really does know Spark, so we
   > confirm it."

   The list now says **Added Spark to Developer Tools**.
5. Click **Use this resume for applications**. The banner says it's tailored for Data
   Engineering Intern.

### 4. Apply with autofill (2.5 minutes)

1. Click **Jobs**, open the Bluewater listing again, and click **Apply now**. The
   application opens in a new tab.

   > "Apply now takes you to the employer's real application. For the demo it's a
   > practice form running on our own server, so nothing is actually sent."

2. A **Launchpad** panel appears in the corner of the form, as it does on Greenhouse,
   Lever and Ashby. Click **Autofill this application**.
3. Scroll down the form:
   - Name, email, phone, city, LinkedIn and GitHub are filled.
   - School, degree, major, graduation year, company and title are filled.
   - The **Country** and **work authorization** dropdowns are set, and **sponsorship**
     is answered No.
   - The **resume** is attached: `Resume - Data Engineering Intern.pdf`, the one we
     just tailored.
4. Point at what stayed empty, and at the panel's lists:

   > "'Why do you want to work here' is left for Shashank to write. Date of birth and
   > Social Security number are never filled, by design. Gender and veteran status are
   > only filled from the extension's private Saved answers, which never leave the
   > browser."

5. Click **Submit application**. The form only says "Practice form: nothing was sent."

   > "On a real site, Launchpad never clicks Submit. The student reviews everything and
   > submits it."

If the panel doesn't appear, click the Launchpad toolbar icon and **Fill this page**
instead. It fills the same fields.

The email field shows `testuser@example.com`. That's the built-in test account's email,
which autofill always takes from the account. Mention it if anyone asks.

### 5. Application tracker (2 minutes)

Close the form tab and click **Tracker**.

1. The Bluewater application from step 2 is there.
2. In its **Status** dropdown, choose **Interview**. Refresh the page to show it's
   saved.
3. Open **Insights** to show the statistics, the status chart and the application flow.
4. Click **Export CSV**.

### 6. Career assistant (1 minute, optional)

Click **Explore** and ask something like *"What jobs can I get with a computer science
degree besides software engineering?"* The assistant answers, and the chat is saved to
the account.

This needs the Puter sign-in from step 5 of Part 1. If it shows "Thinking…" for more
than a few seconds, skip it.

### Wrap up

> "So Launchpad covers the whole search: find a job that fits, tailor the resume
> without making anything up, fill the application in one click, and track it."

---

## If something goes wrong

| Problem | What to do |
|---|---|
| The AI rewording doesn't appear, or a note says AI was unavailable | Carry on. Reordering still works without AI. Show `backup/after.png`. |
| Tailoring fails or the preview is blank | Show `backup/before.png` and `backup/after.png` side by side, or open `backup/Shashank_Sekhar_Resume_tailored.pdf`. |
| No Bluewater listing in the feed | Clear the search box and filters. If it's still missing, the server is running old code: restart it with step 3. |
| Applicant Tools opens without the job | Paste `demo/job_posting.txt` into **Job description** and type `Data Engineering Intern` as the title. |
| No Launchpad panel on the practice form | Reload the extension on `chrome://extensions`, then reload the form. Or use the toolbar icon's **Fill this page**. |
| The extension shows the wrong person, or "sign in first" | Keep a `localhost:8000` tab open, click **Disconnect**, then **Connect to Launchpad**. |
| The resume isn't attached | Make sure **Include resume** is ticked in the popup. |
| A build error, or a page that keeps reloading | Press <kbd>Ctrl</kbd>+<kbd>C</kbd> and rerun step 3. It clears the cache first. |
| Shashank's resume or tracker is messy from rehearsal | Press <kbd>Ctrl</kbd>+<kbd>C</kbd> and rerun step 3. It resets the profile. |

## After the demo

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in the Launchpad terminal. To go back to your own
profile, run `export TURSO_DATABASE_URL="$HOME/launchpad-demo.db"` before you start
Launchpad again, and reconnect the extension. The demo database is
`~/launchpad-class-demo.db`. You can delete it when you're done.

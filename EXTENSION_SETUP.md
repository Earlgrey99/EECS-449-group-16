# Set up the Launchpad extension

Launchpad Autofill fills job applications from your Launchpad profile. You run
Launchpad on your own laptop, load the extension into Chrome, and connect the two.
**It never submits an application for you.**

## What you need

- **Google Chrome**, or another Chromium browser like Edge or Brave.
- **Git**, to download the team repo. Run `git --version` to check.
- **Jac 0.37.11**, the language Launchpad is built in. Step 1 installs it.

## Part 1: Run Launchpad on your laptop

This takes about 10 minutes the first time.

1. **Install Jac.** Skip this if `jac --version` already prints 0.37.11.

   ```bash
   curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version 0.37.11
   ```

   Then close the terminal and open a new one.

2. **Download the repo.** Skip this if you already have it. Otherwise this puts it
   on your Desktop:

   ```bash
   cd ~/Desktop && git clone https://github.com/Earlgrey99/EECS-449-group-16.git
   ```

3. **Get the latest code and packages.**

   ```bash
   cd ~/Desktop/EECS-449-group-16 && git switch main && git pull --ff-only origin main && jac install
   ```

4. **Start Launchpad.**

   ```bash
   export TURSO_DATABASE_URL="$HOME/launchpad-demo.db" && jac clean --cache --force && jac run --dev --profile test main.jac
   ```

   Wait for `Server ready`, then leave this terminal open. Launchpad runs at
   <http://localhost:8000> until you press <kbd>Ctrl</kbd>+<kbd>C</kbd>.

5. **Fill in your profile.** Open <http://localhost:8000/login>. The test account
   signs you in by itself. Then go to **Account → Profile** and add your contact
   details, your application answers and a PDF resume.

> **Use fake details for the class demo.** Your profile is saved only on your laptop,
> in `launchpad-demo.db` in your home folder. Never commit that file.

## Part 2: Add the extension to Chrome

This takes about 2 minutes.

1. **Open the extensions page.** Paste `chrome://extensions` into Chrome's address
   bar. Chrome blocks links to it, so you have to type or paste it.
2. **Turn on Developer mode.** It's the switch in the top-right corner of that page.
3. **Load the extension.** Click **Load unpacked** and choose the `extension` folder
   inside the repo, at `Desktop/EECS-449-group-16/extension`.
4. **Pin it to the toolbar.** Click the puzzle-piece icon next to the address bar,
   then the pin next to **Launchpad Autofill**.
5. **Connect it to Launchpad.** Keep a `localhost:8000` tab open and signed in. Click
   the Launchpad icon in the toolbar, then **Connect to Launchpad**. It should show
   your name and your resume.

No git? Ask a teammate for a zip of the `extension` folder, unzip it, and load that
folder in step 3. You still need Launchpad running from Part 1 to connect.

## Part 3: Fill an application

1. **Optional: tailor your resume to the job.** On <http://localhost:8000/tools>,
   under **Tailor your resume**, choose or paste the job and click **Tailor my
   resume**. If the new PDF looks right, click **Use this resume for applications**.
   Click **Switch back to my default resume** when you're done with that job.
2. **Open the application.** On Greenhouse, Lever, Ashby and similar job sites, a
   Launchpad panel appears on the page. Click **Autofill this application**. On other
   sites, click the toolbar icon, then **Fill this page**.
3. **Review everything, then submit it yourself.** The panel lists what it filled,
   what it read from your resume, and the questions it left for you. It never answers
   date of birth or Social Security number, and it never clicks Submit.

## When the team pushes changes

1. **Stop Launchpad, then pull and restart it.** Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in
   the Launchpad terminal, then run steps 3 and 4 of Part 1 again.
2. **Reload the extension.** On `chrome://extensions`, click the circular arrow on the
   Launchpad Autofill card. Then reload any job page you have open.

## If something goes wrong

| What you see | What to do |
|---|---|
| A red build error mentioning `format_salary`, or a page that keeps reloading | Stop Launchpad with <kbd>Ctrl</kbd>+<kbd>C</kbd> and start it again with the command in Part 1, step 4. It clears the cache first. |
| `jac: command not found` | Open a new terminal after installing Jac. If it still fails, run step 1 again. |
| The extension says to sign in first | Open `localhost:8000` in a tab, sign in, keep the tab open, then click **Connect to Launchpad** again. |
| No Launchpad panel on the job page | Reload the page. If it's still missing, use the toolbar icon and **Fill this page**. |
| A field stays empty | Add the missing detail on **Account → Profile**, or fill that field by hand. Launchpad leaves a field blank rather than guess. |
| `git pull` refuses to run | You have local changes. Run `git status` and ask in the team chat before discarding anything. |

Launchpad is a class prototype. Don't put real personal details into it until it's
ready for public use. For what the extension fills and what it leaves alone, see
[extension/README.md](extension/README.md).

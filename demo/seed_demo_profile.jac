"""Fill the test-profile account with a demo profile for Shashank Sekhar (made-up details) for the class demo.

Run from the repo root, with the same TURSO_DATABASE_URL the server will use:

    export TURSO_DATABASE_URL="$HOME/launchpad-class-demo.db"
    jac run --no-takeover demo/seed_demo_profile.jac

It refuses to run on a database that isn't a local .db file, so it can't touch the
shared Turso database. Running it again resets the profile to the same values.
"""

import base64;
import json;
import os;
import sys;
import from db {
    ensure_test_user, save_user_profile, save_contact_details, save_application_answers,
    save_job_preferences_row, save_tailored_resume, create_resume, list_resumes_by_user,
    delete_resume, list_applications_by_user, delete_application, get_db_connection
}
import from services.resume_profile { _save_resume_profile }

glob RESUME_FILE: str = "demo/shashank_sekhar_resume.pdf";
glob RESUME_TITLE: str = "Shashank_Sekhar_Resume.pdf";

with entry {
    url = str(os.environ.get("TURSO_DATABASE_URL") or "");
    if not url.endswith(".db") {
        print("Set TURSO_DATABASE_URL to a local file first, for example:");
        print('  export TURSO_DATABASE_URL="$HOME/launchpad-class-demo.db"');
        sys.exit(1);
    }
    conn = get_db_connection();
    user = ensure_test_user(conn=conn);
    user_id = int(user["id"]);

    save_user_profile(
        user_id=user_id,
        first_name="Shashank",
        last_name="Sekhar",
        location="Ann Arbor, MI, Remote",
        sector="Technology & Software",
        job_titles="Data Engineer, Software Engineer, Data Analyst",
        salary_min=60000,
        contract_type="Internship, Full-time",
        onboarding_completed=1,
        conn=conn
    );
    save_contact_details(
        user_id=user_id,
        phone="(555) 555-0142",
        city="Ann Arbor, MI",
        linkedin="https://linkedin.com/in/shashank-sekhar-demo",
        github="https://github.com/shashanksekhar-demo",
        portfolio="",
        conn=conn
    );
    answers = {
        "work_authorized": "yes",
        "needs_sponsorship": "no",
        "school": "University of Michigan",
        "degree": "Bachelor of Science in Engineering",
        "major": "Computer Science",
        "grad_year": "2027",
        "current_company": "University of Michigan",
        "current_title": "Instructional Aide",
        "salary": "$28 per hour",
        "start_date": "May 2026",
        "country": "United States"
    };
    save_application_answers(user_id, json.dumps(answers), conn=conn);
    save_job_preferences_row(
        user_id,
        json.dumps({
            "role_levels": ["Internship", "New grad"],
            "work_modes": ["Hybrid", "Remote"],
            "company_sizes": [],
            "extra_skills": []
        }),
        conn=conn
    );

    # Start clean: one resume, no tailored copy, an empty tracker.
    for old in list_resumes_by_user(user_id, conn=conn) {
        delete_resume(int(old["id"]), conn=conn);
    }
    for app in list_applications_by_user(user_id, conn=conn) {
        delete_application(int(app["id"]), conn=conn);
    }
    save_tailored_resume(user_id, None, None, None, conn=conn);
    with open(RESUME_FILE, "rb") as f {
        pdf = f.read();
    }
    content = "data:application/pdf;base64," + base64.b64encode(pdf).decode("ascii");
    create_resume(user_id=user_id, title=RESUME_TITLE, content=content, conn=conn);

    # The profile page's "Your Resume Details", saved as clean sections so it
    # doesn't depend on how well the PDF reads.
    sections = _save_resume_profile(user_id, {
        "experience": [
            {
                "title": "Software Engineering Intern", "company": "Lakeshore Health",
                "dates": "May 2025 - Aug. 2025",
                "description": "Redesigned the patient check-in page in React, cutting average check-in time from 4 minutes to 90 seconds\nFixed 30 accessibility issues flagged in an audit of the scheduling app\nWrote unit tests in Jest that raised front-end test coverage from 35% to 70%\nBuilt a Python ETL job that moved nightly appointment data from CSV exports into PostgreSQL\nWrote SQL checks that caught duplicate patient records before they reached the reporting database"
            },
            {
                "title": "Instructional Aide, Intro to Programming", "company": "University of Michigan",
                "dates": "Jan. 2024 - Present",
                "description": "Lead a weekly lab section of 30 students and hold 4 hours of office hours a week\nWrote 12 autograder test suites for C++ programming projects\nBuilt a Python script that pulls grades from the course API and flags students who are falling behind"
            }
        ],
        "education": [
            {
                "school": "University of Michigan",
                "degree": "Bachelor of Science in Engineering, Computer Science",
                "dates": "Aug. 2023 - May 2027", "gpa": "3.7"
            }
        ],
        "skills": [
            "Java", "C++", "JavaScript", "HTML/CSS", "Python", "SQL", "React", "Node.js", "Express",
            "Jest", "pandas", "Git", "VS Code", "Figma", "Docker", "AWS", "Linux"
        ],
        "links": {
            "github": "https://github.com/shashanksekhar-demo",
            "linkedin": "https://linkedin.com/in/shashank-sekhar-demo",
            "portfolio": "", "other": []
        }
    }, conn=conn);
    if not sections["ok"] {
        print("Couldn't save the resume details: " + str(sections.get("error")));
        sys.exit(1);
    }

    conn.close();
    print(f"Shashank Sekhar is ready in {url} (account id {user_id}).", flush=True);
    # The Jac runtime keeps a background thread alive, so exit explicitly.
    os._exit(0);
}

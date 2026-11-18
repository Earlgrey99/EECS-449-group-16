"""Fill the test-profile account with Alex Morgan, a made-up applicant for the class demo.

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

glob RESUME_FILE: str = "demo/alex_morgan_resume.pdf";
glob RESUME_TITLE: str = "Alex_Morgan_Resume.pdf";

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
        first_name="Alex",
        last_name="Morgan",
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
        linkedin="https://linkedin.com/in/alex-morgan-demo",
        github="https://github.com/alexmorgan-demo",
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

    conn.close();
    print(f"Alex Morgan is ready in {url} (account id {user_id}).", flush=True);
    # The Jac runtime keeps a background thread alive, so exit explicitly.
    os._exit(0);
}

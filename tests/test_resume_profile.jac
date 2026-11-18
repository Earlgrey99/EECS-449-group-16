"""Tests for services/resume_profile.jac (resume sections on the profile page).

Run from the project root with:
    jac test tests/test_resume_profile.jac
"""

import base64;
import os;
import sqlite3;
import from db { init_db, register_user, get_user_by_email, create_resume }
import from services.resume_profile {
    split_sections,
    parse_resume_text,
    find_links,
    resume_content_to_text,
    normalize_url,
    clean_profile,
    _load_resume_profile,
    _save_resume_profile,
    _parse_upload
}

glob DATA_DIR: str = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "compatibility");

# A made-up resume laid out differently from the sample files.
glob MESSY_RESUME: str = """Ada Lovelace
ada@umich.edu | github.com/adal | https://www.linkedin.com/in/ada-l | adalovelace.dev
Education:
University of Michigan, B.S. Computer Science   Sep 2022 - May 2026
• GPA: 3.85/4.0
Work Experience
Software Engineering Intern | Google        May 2025 – Aug 2025
• Built a thing in Go.
• Shipped it.
Research Assistant at U-M CSE Lab (2024 - 2025)
- Trained models.
Technical Skills
Languages: Python, Java, C++
Tools: Git, Docker; Figma
""";

# Company in CAPITALS with a place, then "title + dates", then bullets.
# The bullets use a symbol that PDFs often turn into an invisible character
# (written here as \uf0b7), and long lines are broken in two like a PDF does.
glob CAPS_LAYOUT_RESUME: str = """Riley Chen
EDUCATION
UNIVERSITY OF MICHIGAN Ann Arbor, Michigan
Bachelors in Data Science December 2026
\uf0b7GPA: 3.5/4.0
\uf0b7Relevant Coursework: Statistics, Machine Learning, Data Structures and Algorithms in
C++
WORK EXPERIENCE
MICHIGAN DEPARTMENT OF TRANSPORTATION Ann Arbor, Michigan
Planner May 2026 - Present
\uf0b7Built a dashboard of crash counts, enabling risk analysis to flag
intersections for safety work
\uf0b7Checked the 2050 State Long-Range Plan, cross-referencing federal rules
EXTRACURRICULARS
Member September 2024 - Present
BLUE LAB - ECO DATA, Ann Arbor, Michigan
\uf0b7Analyzed food waste data with Pandas
SKILLS
Languages: Python, C++, R
Tools: Git, Excel
""";

# The popular "Jake's Resume" template: title + dates, then company + place.
glob JAKE_LAYOUT_RESUME: str = """Jake Ryan
Education
Southwestern University Georgetown, TX
Bachelor of Arts in Computer Science, Minor in Business Aug. 2018 -- May 2021
Experience
Undergraduate Research Assistant June 2020 -- Present
Texas A&M University College Station, TX
• Developed a REST API using FastAPI and PostgreSQL
Information Technology Support Specialist Sep. 2018 -- Present
Southwestern University Georgetown, TX
• Set up campus computers
""";

# Company, title and dates each on their own line.
glob STACKED_LAYOUT_RESUME: str = """PROFESSIONAL EXPERIENCE
Google
Software Engineer Intern
Jun 2024 - Aug 2024
- Built internal tools in Go.
Ford Motor Company — Engineering Co-op, Jan 2021 – Dec 2021
- Tested parts.
EDUCATION
Michigan State University
B.S. in Computer Engineering, Expected May 2026
""";

def load_resume(name: str) -> str {
    with open(os.path.join(DATA_DIR, f"resume_{name}.txt"), encoding="utf-8") as f {
        return f.read();
    }
}

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

test "users table has the four resume section columns" {
    conn = make_test_db();
    col_names = [c[1] for c in conn.execute("PRAGMA table_info(users);").fetchall()];
    for name in ["experience_json", "education_json", "skills_json", "other_links_json"] {
        assert name in col_names;
    }
}

test "sample resume is split into the right sections" {
    sections = split_sections(load_resume("backend"));
    assert sections["skills"] == ["Python, SQL, PostgreSQL, Docker, AWS, Git, Linux, Flask"];
    assert len(sections["experience"]) == 4;    # 1 job line + 3 bullet points
    assert sections["education"] == ["B.S.E. Computer Science, University of Michigan"];
}

test "sample resume is read into jobs, schools and skills" {
    profile = parse_resume_text(load_resume("backend"));
    job = profile["experience"][0];
    assert job["title"] == "Software Engineer";
    assert job["company"] == "Acme Analytics";
    assert job["dates"] == "2022 - present";
    assert len(job["description"].split("\n")) == 3;
    school = profile["education"][0];
    assert school["school"] == "University of Michigan";
    assert school["degree"] == "B.S.E. Computer Science";
    assert "Flask" in profile["skills"];
    assert len(profile["skills"]) == 8;
}

test "other resume layouts: | and at, month dates, GPA, skill groups" {
    profile = parse_resume_text(MESSY_RESUME);
    assert len(profile["experience"]) == 2;
    assert profile["experience"][0]["company"] == "Google";
    assert profile["experience"][0]["dates"] == "May 2025 – Aug 2025";
    assert profile["experience"][1]["title"] == "Research Assistant";
    assert profile["experience"][1]["company"] == "U-M CSE Lab";
    assert profile["education"][0]["school"] == "University of Michigan";
    assert profile["education"][0]["gpa"] == "3.85";
    assert profile["skills"] == ["Python", "Java", "C++", "Git", "Docker", "Figma"];
}

test "links are sorted by site and emails are skipped" {
    links = find_links(MESSY_RESUME);
    assert links["github"] == "https://github.com/adal";
    assert links["linkedin"] == "https://www.linkedin.com/in/ada-l";
    assert links["portfolio"] == "https://adalovelace.dev";
    assert links["other"] == [];
    assert find_links("jordan.lee@example.com")["portfolio"] == "";
}

test "a resume saved as a data URL is turned back into text" {
    encoded = base64.b64encode(load_resume("backend").encode("utf-8")).decode("ascii");
    text = resume_content_to_text("data:text/plain;base64," + encoded);
    assert "Acme Analytics" in text;
    assert resume_content_to_text("plain text resume") == "plain text resume";
    assert resume_content_to_text("") == "";
}

test "links get https added and bad links are reported" {
    assert normalize_url("github.com/ada") == "https://github.com/ada";
    assert normalize_url("http://x.com") == "http://x.com";
    checked = clean_profile({"links": {"github": "not a link", "other": ["", "site.io"]}});
    assert len(checked[1]) == 1;                       # one problem: the github link
    assert checked[0]["links"]["other"] == ["https://site.io"];
}

test "empty jobs and duplicate skills are dropped when cleaning" {
    checked = clean_profile({
        "experience": [{"title": "", "company": "", "dates": "", "description": ""}, {"title": "Dev"}],
        "skills": ["Python", "python", " SQL "],
    });
    assert len(checked[0]["experience"]) == 1;
    assert checked[0]["experience"][0]["company"] == "";
    assert checked[0]["skills"] == ["Python", "SQL"];
}

test "a just-picked file is read into sections" {
    encoded = base64.b64encode(load_resume("frontend").encode("utf-8")).decode("ascii");
    res = _parse_upload("data:text/plain;base64," + encoded);
    assert res["ok"] is True;
    assert res["profile"]["experience"][0]["company"] == "Brightside Media";
    assert _parse_upload("")["ok"] is False;
}

test "save then load the resume sections" {
    conn = make_test_db();
    register_user(name="Ada", email="ada@example.com", password="password123", conn=conn);
    user = get_user_by_email("ada@example.com", conn=conn);

    # Nothing saved and no resume yet.
    assert _load_resume_profile(user, conn=conn)["source"] == "empty";

    profile = {
        "experience": [{"title": "Engineer", "company": "Acme", "dates": "2024", "description": "Built APIs"}],
        "education": [{"school": "University of Michigan", "degree": "B.S. CS", "dates": "2026", "gpa": ""}],
        "skills": ["Python", "SQL"],
        "links": {"github": "github.com/ada", "linkedin": "", "portfolio": "", "other": ["blog.ada.dev"]},
    };
    saved = _save_resume_profile(int(user["id"]), profile, conn=conn);
    assert saved["ok"] is True;

    # Load again from a fresh copy of the row, like the next page visit would.
    user = get_user_by_email("ada@example.com", conn=conn);
    loaded = _load_resume_profile(user, conn=conn);
    assert loaded["source"] == "saved";
    assert loaded["profile"]["experience"][0]["company"] == "Acme";
    assert loaded["profile"]["skills"] == ["Python", "SQL"];
    assert loaded["profile"]["links"]["github"] == "https://github.com/ada";
    assert loaded["profile"]["links"]["other"] == ["https://blog.ada.dev"];
    # GitHub is stored in the same column as the step 1 contact details.
    assert user["github"] == "https://github.com/ada";
}

test "a saved resume is read when nothing was saved yet" {
    conn = make_test_db();
    register_user(name="Sam", email="sam@example.com", password="password123", conn=conn);
    user = get_user_by_email("sam@example.com", conn=conn);
    create_resume(user_id=int(user["id"]), title="resume.txt", content=load_resume("frontend"), conn=conn);
    loaded = _load_resume_profile(user, conn=conn);
    assert loaded["source"] == "resume";
    assert loaded["has_resume"] is True;
    assert loaded["profile"]["experience"][0]["title"] == "Frontend Developer";
}

test "a link typed in step 1 wins over one read from the resume" {
    conn = make_test_db();
    register_user(name="Ada", email="ada2@example.com", password="password123", conn=conn);
    user = get_user_by_email("ada2@example.com", conn=conn);
    conn.execute("UPDATE users SET github = ? WHERE id = ?", ("https://github.com/real-ada", user["id"]));
    create_resume(user_id=int(user["id"]), title="resume.txt", content=MESSY_RESUME, conn=conn);
    user = get_user_by_email("ada2@example.com", conn=conn);
    loaded = _load_resume_profile(user, conn=conn);
    assert loaded["profile"]["links"]["github"] == "https://github.com/real-ada";
    assert loaded["profile"]["links"]["linkedin"] == "https://www.linkedin.com/in/ada-l";
}

test "a bad link is not saved" {
    conn = make_test_db();
    register_user(name="Bo", email="bo@example.com", password="password123", conn=conn);
    user = get_user_by_email("bo@example.com", conn=conn);
    res = _save_resume_profile(int(user["id"]), {"links": {"portfolio": "not a link"}}, conn=conn);
    assert res["ok"] is False;
}

test "company-in-capitals layout with invisible bullets and wrapped lines" {
    profile = parse_resume_text(CAPS_LAYOUT_RESUME);
    jobs = profile["experience"];
    assert len(jobs) == 2;
    assert jobs[0]["title"] == "Planner";
    assert jobs[0]["company"] == "MICHIGAN DEPARTMENT OF TRANSPORTATION";
    assert jobs[0]["dates"] == "May 2026 - Present";
    # Two points, each glued back together from two lines.
    points = jobs[0]["description"].split("\n");
    assert len(points) == 2;
    assert points[0].endswith("intersections for safety work");
    # A year in the middle of a sentence is not a new job.
    assert "2050" in points[1];
    # Title-and-dates first, company second, also works.
    assert jobs[1]["title"] == "Member";
    assert jobs[1]["company"] == "BLUE LAB - ECO DATA";
    school = profile["education"][0];
    assert len(profile["education"]) == 1;          # coursework is not a school
    assert school["school"] == "UNIVERSITY OF MICHIGAN";
    assert school["degree"] == "Bachelors in Data Science";
    assert school["dates"] == "December 2026";
    assert school["gpa"] == "3.5";
    assert profile["skills"] == ["Python", "C++", "R", "Git", "Excel"];
}

test "Jake's Resume layout" {
    profile = parse_resume_text(JAKE_LAYOUT_RESUME);
    jobs = profile["experience"];
    assert len(jobs) == 2;
    assert jobs[0]["title"] == "Undergraduate Research Assistant";
    assert jobs[0]["dates"] == "June 2020 -- Present";
    assert jobs[1]["company"] == "Southwestern University";
    school = profile["education"][0];
    assert school["school"] == "Southwestern University";
    assert school["degree"] == "Bachelor of Arts in Computer Science, Minor in Business";
    assert school["dates"] == "Aug. 2018 -- May 2021";
}

test "company, title and dates on separate lines" {
    profile = parse_resume_text(STACKED_LAYOUT_RESUME);
    jobs = profile["experience"];
    assert jobs[0]["title"] == "Software Engineer Intern";
    assert jobs[0]["company"] == "Google";
    assert jobs[0]["dates"] == "Jun 2024 - Aug 2024";
    # "Company — Title" gets turned around so the title comes first.
    assert jobs[1]["title"] == "Engineering Co-op";
    assert jobs[1]["company"] == "Ford Motor Company";
    school = profile["education"][0];
    assert school["school"] == "Michigan State University";
    assert school["dates"] == "Expected May 2026";
}

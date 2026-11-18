"""Resume sections for the profile page.

Reads the text of a user's resume and splits it into four parts the user
can check and edit on the profile page:
    experience - list of jobs:    {"title", "company", "dates", "description"}
    education  - list of schools: {"school", "degree", "dates", "gpa"}
    skills     - list of skill names, e.g. ["Python", "SQL"]
    links      - {"github", "linkedin", "portfolio", "other": [urls]}

GitHub, LinkedIn and Portfolio are saved in the same database columns as the
contact details in step 1 of the profile page, so both places always agree.
Only the "other" links get a column of their own.

Reading a resume is a best guess (every resume is laid out differently),
so the user can fix anything on the profile page and save it.
"""

import base64;
import io;
import json;
import re;
import from db { list_resumes_by_user, save_resume_sections }
import from services.auth_sync { _resolve_caller }
import from services.compatibility { resume_text_from_content }

# Heading words that start each section (compared in lowercase).
# Projects, extracurriculars and similar count as experience, so they show
# up as entries the user can keep or remove. Anything under an "other"
# heading (summary, awards...) is skipped.
glob SECTION_HEADINGS: dict[str, list[str]] = {
    "experience": [
        "experience", "work experience", "professional experience",
        "relevant experience", "employment", "employment history", "work history",
        "projects", "project experience", "technical projects", "research experience",
        "research", "extracurriculars", "extracurricular activities",
        "extracurricular experience", "activities", "leadership",
        "leadership experience", "volunteer experience", "involvement"
    ],
    "education": ["education", "academic background", "education and training"],
    "skills": [
        "skills", "technical skills", "core skills", "skills and tools",
        "skills & tools", "technologies", "tools", "skills & interests",
        "skills and interests"
    ],
    "other": [
        "summary", "profile", "objective", "certifications", "awards", "honors",
        "awards and honors", "publications", "interests", "coursework",
        "relevant coursework"
    ],
};

# Words that tell us a piece of text is a school name.
glob SCHOOL_WORDS: list[str] = ["university", "college", "institute", "school", "academy"];

# Words that tell us a piece of text is a degree.
glob DEGREE_RE: any = re.compile(
    r"\b(bachelor|bachelors|bachelor's|master|masters|master's|ph\.?d|doctor|associate|minor|major"
    + r"|b\.?s\.?e?|b\.?a|m\.?s|m\.?b\.?a|b\.?eng|diploma|certificate)\b",
    re.IGNORECASE
);

# Words that tell us a piece of text is a job title, e.g. "Software Engineer Intern".
glob TITLE_WORDS_RE: any = re.compile(
    r"\b(engineer|intern|developer|analyst|manager|assistant|specialist|designer|scientist"
    + r"|consultant|associate|director|lead|researcher|coordinator|tutor|aide|member|programm?er"
    + r"|officer|representative|technician|co-op|fellow|volunteer|president|teacher|instructor"
    + r"|planner|architect|administrator|advisor|founder|owner|editor|writer)s?\b",
    re.IGNORECASE
);

# A bullet point at the start of a line. PDFs use many different symbols
# ("•", "●", "-", and private symbols that look like nothing when printed),
# so any line that starts with a symbol instead of a letter, number or
# bracket counts as a bullet.
glob BULLET_RE: any = re.compile(r"^[^\w\s(\[\"'$]\s*");

# A date or date range: "2022 - present", "May 2025 – Aug 2025", "Aug. 2018 -- May 2021",
# "01/2022 - 05/2023", "Summer 2025", "2026".
glob MONTH: str = r"(?:(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|spring|summer|fall|winter)[a-z]*\.?\s+|\d{1,2}/)";
glob YEAR: str = r"(?:19[5-9]\d|20[0-3]\d)";
glob DATE_PATTERN: str = (
    r"(?:" + MONTH + r")?" + YEAR + r"\s*(?:--|-|–|—|to)\s*(?:(?:" + MONTH + r")?" + YEAR + r"|present|current|now)"
    + r"|(?:" + MONTH + r")?" + YEAR
);
# Dates at the very END of a line, like "Planner May 2026 - Present" or
# "B.S. in CS, Expected May 2026". A year in the middle of a sentence
# ("MDOT's 2050 plan, cross-referencing...") doesn't count.
glob END_DATE_RE: any = re.compile(
    r"\(?\s*(?:(?:expected|anticipated|graduating|graduation)\s*:?\s*)?(?:" + DATE_PATTERN + r")\s*\)?\s*$",
    re.IGNORECASE
);

# A place at the end of a line: "Ann Arbor, Michigan", "Georgetown, TX" or "Remote".
glob STATES: str = (
    "Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia"
    + "|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts"
    + "|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey"
    + "|New Mexico|New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania"
    + "|Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington"
    + "|West Virginia|Wisconsin|Wyoming|District of Columbia|[A-Z]{2}"
);
# Words that belong to a company or school name, never to a city, so
# "Southwestern University Georgetown, TX" keeps "Southwestern University".
glob ORG_WORDS: str = (
    r"(?:University|College|Institute|School|Academy|Inc|Corp|Corporation|Company|Co|LLC|Lab|Labs"
    + r"|Department|Group|Center|Centre|Hospital|Bank|Technologies|Systems|Solutions|Health)"
);
glob CITY_WORD: str = r"(?!" + ORG_WORDS + r"\b)[A-Z][a-z.]+";
glob LOCATION_RE: any = re.compile(
    r"\s*(?:[,|\-–]\s*)?(?:\b" + CITY_WORD + r"(?:\s+" + CITY_WORD + r"){0,2},\s*(?:" + STATES + r")|\bRemote)\s*$"
);

# "GPA: 3.3/4.0" or "GPA 3.85".
glob GPA_RE: any = re.compile(r"gpa[^0-9]*(\d\.\d{1,2})(?:\s*/\s*\d(?:\.\d+)?)?", re.IGNORECASE);

# Lines under a school that aren't the school or degree, like coursework lists.
glob EDU_DETAIL_RE: any = re.compile(r"^(relevant\s+)?(coursework|courses|honors|awards|activities|societies)\b", re.IGNORECASE);

# A web address, with or without "https://", e.g. github.com/ada.
glob URL_RE: any = re.compile(
    r"(?:https?://)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*"
    + r"\.(?:com|io|dev|me|net|org|app|co|edu|ai|xyz|page|site)(?:/[^\s,|)]*)?",
    re.IGNORECASE
);


# ---------- Getting plain text out of a saved resume ----------

"""Pull the words out of a Word (.docx) file's bytes ("" if that fails)."""
def docx_bytes_to_text(data: bytes) -> str {
    try {
        # python-docx is already listed in jac.toml.
        import from docx { Document }
        doc = Document(io.BytesIO(data));
        return "\n".join([str(p.text) for p in doc.paragraphs]);
    } except Exception {
        return "";
    }
}

"""Web links inside a PDF ("" if none).

Many resumes show a word like "GitHub" that you click, so the address is
not in the text at all. PDFs keep those addresses separately, as "link
annotations", and this reads them.
"""
def pdf_link_text(data: bytes) -> str {
    urls: list[str] = [];
    try {
        import from pypdf { PdfReader }
        reader = PdfReader(io.BytesIO(data));
        for page in reader.pages {
            for annot in (page.get("/Annots") or []) {
                action = annot.get_object().get("/A");
                if action is None {
                    continue;
                }
                uri = str(action.get_object().get("/URI") or "");
                if uri.lower().startswith("http") and uri not in urls {
                    urls.append(uri);
                }
            }
        }
    } except Exception {
        return "";
    }
    return "\n".join(urls);
}

"""Turn a saved resume into plain text.

The profile page saves the uploaded file as a "data URL": the whole file
written as text, like "data:application/pdf;base64,JVBERi0...".
PDFs and plain text are handled by resume_text_from_content (the same code
the match score uses). Word files start with the bytes "PK", so we catch
those here first. For PDFs we also put any clickable links at the top.
"""
def resume_content_to_text(content: str | None) -> str {
    raw = str(content or "").strip();
    if raw.startswith("data:") and ";base64," in raw {
        data = b"";
        try {
            data = base64.b64decode(raw.split(";base64,", 1)[1]);
        } except Exception {
            data = b"";
        }
        if data.startswith(b"PK") {
            return docx_bytes_to_text(data);
        }
        if data.startswith(b"%PDF") {
            links = pdf_link_text(data);
            text = resume_text_from_content(raw);
            return (links + "\n" + text) if links else text;
        }
    }
    return resume_text_from_content(raw);
}


# ---------- Splitting the text into sections ----------

"""Which section a line starts ("" if the line isn't a heading)."""
def heading_for(line: str) -> str {
    clean = line.strip().strip(":").strip().lower();
    if not clean or len(clean) > 40 {
        return "";
    }
    for (section, words) in SECTION_HEADINGS.items() {
        if clean in words {
            return section;
        }
    }
    return "";
}

"""Group the resume's lines under the heading they appear below."""
def split_sections(text: str) -> dict[str, list[str]] {
    sections: dict[str, list[str]] = {"experience": [], "education": [], "skills": [], "other": []};
    current = "other";    # the name and contact lines at the top go here
    for raw_line in text.splitlines() {
        line = raw_line.strip();
        if not line {
            continue;
        }
        section = heading_for(line);
        if section {
            current = section;
            continue;
        }
        sections[current].append(line);
    }
    return sections;
}


# ---------- Small helpers for reading one line ----------

def is_bullet(line: str) -> bool {
    return bool(BULLET_RE.match(line));
}

def strip_bullet(line: str) -> str {
    return BULLET_RE.sub("", line).strip();
}

"""Remove a place at the end: "STEM SCHOLARS Ann Arbor, Michigan" -> "STEM SCHOLARS"."""
def strip_location(text: str) -> str {
    return LOCATION_RE.sub("", text).strip().rstrip(",|-–").strip();
}

"""Split a line that ENDS in dates into (text before, the dates). No dates: (line, "")."""
def end_dates(line: str) -> tuple[str, str] {
    found = END_DATE_RE.search(line);
    if not found {
        return (line.strip(), "");
    }
    dates = found.group(0).strip().strip("()").strip();
    before = line[:found.start()].strip().rstrip(",|-–").strip();
    return (before, dates);
}

"""True if most letters are capitals, like "MICHIGAN DEPARTMENT OF TRANSPORTATION"."""
def is_caps(text: str) -> bool {
    letters = [c for c in text if c.isalpha()];
    if len(letters) < 4 {
        return False;
    }
    capitals = len([c for c in letters if c.isupper()]);
    return capitals / len(letters) >= 0.8;
}

"""Split "A, B" / "A | B" / "A at B" / "A - B" into its two halves."""
def split_pair(text: str) -> tuple[str, str] {
    for sep in [" | ", " at ", ", ", " - ", " – ", " — "] {
        if sep in text {
            halves = text.split(sep, 1);
            return (halves[0].strip(), halves[1].strip());
        }
    }
    return (text.strip(), "");
}

"""Glue lines back together when the PDF broke one long line in two.

A line that starts with a small letter continues the line above it, like
"...enabling risk analysis to flag" + "intersections for safety intervention".
"""
def join_wrapped(lines: list[str]) -> list[str] {
    joined: list[str] = [];
    for line in lines {
        if joined and line[:1].islower() {
            joined[-1] = joined[-1] + " " + line;
        } else {
            joined.append(line);
        }
    }
    return joined;
}


# ---------- Reading the Experience section ----------
# Each line gets a "kind":
#   "dated" - a heading line that ends in dates: "Planner May 2026 - Present"
#   "org"   - a company line: in CAPITALS, or ending in a place
#   "name"  - a short line next to a dated/org line: "Google" or "Software Engineer"
#   "point" - anything else: a bullet point / sentence about the job

def line_kind(line: str) -> str {
    if is_bullet(line) {
        return "point";
    }
    split_line = end_dates(line);
    if split_line[1] and len(split_line[0].split()) <= 10 {
        return "dated";
    }
    if is_caps(strip_location(line)) {
        return "org";
    }
    if LOCATION_RE.search(line) and len(line.split()) <= 10 {
        return "org";
    }
    return "point";
}

"""A short line with no full stop, e.g. "Google" or "Software Engineer Intern"."""
def looks_like_name(line: str) -> bool {
    return (not is_bullet(line)) and len(line.split()) <= 6 and not line.rstrip().endswith(".");
}

def line_kinds(lines: list[str]) -> list[str] {
    kinds = [line_kind(line) for line in lines];
    # A short line right BEFORE a heading line is part of that heading.
    i = len(lines) - 2;
    while i >= 0 {
        if kinds[i] == "point" and kinds[i + 1] in ["dated", "org", "name"] and looks_like_name(lines[i]) {
            kinds[i] = "name";
        }
        i = i - 1;
    }
    # A short line right AFTER a heading line is the other half of it.
    for i in range(1, len(lines)) {
        if kinds[i] == "point" and kinds[i - 1] in ["dated", "org"] and looks_like_name(lines[i]) {
            kinds[i] = "name";
        }
    }
    return kinds;
}

def blank_job -> dict[str, str] {
    return {"title": "", "company": "", "dates": "", "description": ""};
}

"""Swap title and company when the "company" is the one that looks like a job title."""
def fix_order(job: dict[str, str]) -> dict[str, str] {
    if job["company"] and TITLE_WORDS_RE.search(job["company"]) and not TITLE_WORDS_RE.search(job["title"]) {
        return {**job, "title": job["company"], "company": job["title"]};
    }
    return job;
}

"""Jobs: heading lines (title, company, dates) followed by points about the job.

The heading can be one line ("Software Engineer, Acme (2022 - present)")
or two ("MICHIGAN DEPARTMENT OF TRANSPORTATION Ann Arbor, Michigan" then
"Planner May 2026 - Present"), in either order.
"""
def parse_experience(raw_lines: list[str]) -> list[dict[str, str]] {
    jobs: list[dict[str, str]] = [];
    lines = join_wrapped(raw_lines);
    kinds = line_kinds(lines);
    for (i, line) in enumerate(lines) {
        kind = kinds[i];
        current: dict[str, str] | None = jobs[-1] if jobs else None;

        if kind == "point" {
            if current is None {
                current = blank_job();
                jobs.append(current);
            }
            point = strip_bullet(line);
            current["description"] = (current["description"] + "\n" + point) if current["description"] else point;
            continue;
        }

        if kind == "dated" {
            split_line = end_dates(line);
            text = split_line[0];
            dates = split_line[1];
            # A line that is only dates finishes the job above it.
            if not text and current is not None and not current["dates"] and not current["description"] {
                current["dates"] = dates;
                continue;
            }
            if current is None or current["description"] or current["dates"] or (current["title"] and current["company"]) {
                current = blank_job();
                jobs.append(current);
            }
            current["dates"] = dates;
            if not text {
                continue;
            }
            if current["company"] {
                current["title"] = text;
            } elif current["title"] {
                current["company"] = text;
            } else {
                halves = split_pair(text);
                current["title"] = halves[0];
                current["company"] = halves[1];
            }
            continue;
        }

        # kind is "org" (company line) or "name" (short heading line).
        if kind == "name" and current is not None and current["title"] and current["company"] and not current["description"] {
            # The heading is already complete, so this is really a point.
            current["description"] = strip_bullet(line);
            continue;
        }
        name = strip_location(line);
        if current is None or current["description"] or (current["company"] and current["title"]) {
            current = blank_job();
            jobs.append(current);
        }
        if kind == "org" or current["title"] {
            if current["company"] {
                current["title"] = name;
            } else {
                current["company"] = name;
            }
        } else {
            halves = split_pair(name);
            current["title"] = halves[0];
            if halves[1] {
                current["company"] = halves[1];
            }
        }
    }
    return [fix_order(job) for job in jobs];
}


# ---------- Reading the Education section ----------

def looks_like_school(text: str) -> bool {
    lowered = text.lower();
    return any(word in lowered for word in SCHOOL_WORDS);
}

def blank_school -> dict[str, str] {
    return {"school": "", "degree": "", "dates": "", "gpa": ""};
}

"""Schools: a school line, a degree line, dates and GPA, in any common layout.

Coursework lists and similar details are skipped.
"""
def parse_education(raw_lines: list[str]) -> list[dict[str, str]] {
    schools: list[dict[str, str]] = [];
    for raw_line in join_wrapped(raw_lines) {
        line = strip_bullet(raw_line) if is_bullet(raw_line) else raw_line;
        current: dict[str, str] | None = schools[-1] if schools else None;

        gpa_found = GPA_RE.search(line);
        if gpa_found {
            if current is None {
                current = blank_school();
                schools.append(current);
            }
            if not current["gpa"] {
                current["gpa"] = gpa_found.group(1);
            }
            line = (line[:gpa_found.start()] + line[gpa_found.end():]).strip().strip(",|;").strip();
            if not line {
                continue;
            }
        }
        if EDU_DETAIL_RE.match(line) {
            continue;
        }

        split_line = end_dates(line);
        text = strip_location(split_line[0]);
        dates = split_line[1];
        has_school_word = looks_like_school(text);
        has_degree_word = bool(DEGREE_RE.search(text));
        is_short_caps = is_caps(text) and len(text.split()) <= 8;
        if not (has_school_word or has_degree_word or dates or is_short_caps) {
            continue;    # e.g. the rest of a coursework list
        }

        school = "";
        degree = "";
        if has_school_word and has_degree_word {
            halves = split_pair(text);
            if looks_like_school(halves[0]) {
                school = halves[0];
                degree = halves[1];
            } else {
                school = halves[1];
                degree = halves[0];
            }
        } elif has_school_word or (is_short_caps and not has_degree_word) {
            school = text;
        } else {
            degree = text;
        }

        if current is None or (school and current["school"]) or (degree and current["degree"]) {
            current = blank_school();
            schools.append(current);
        }
        if school {
            current["school"] = school;
        }
        if degree {
            current["degree"] = degree;
        }
        if dates and not current["dates"] {
            current["dates"] = dates;
        }
    }
    return [s for s in schools if s["school"] or s["degree"]];
}


# ---------- Reading Skills and Links ----------

"""Skills: split on commas, bars and semicolons. "Languages: Python, Java" keeps the part after ':'."""
def parse_skills(raw_lines: list[str]) -> list[str] {
    skills: list[str] = [];
    seen: list[str] = [];
    for raw_line in join_wrapped(raw_lines) {
        line = strip_bullet(raw_line);
        if ":" in line {
            line = line.split(":", 1)[1];
        }
        for piece in re.split(r"[,|;•·]", line) {
            skill = piece.strip();
            if skill and len(skill) <= 40 and skill.lower() not in seen {
                skills.append(skill);
                seen.append(skill.lower());
            }
        }
    }
    return skills;
}

"""Find web addresses anywhere in the resume and sort them by site."""
def find_links(text: str) -> dict[str, any] {
    links: dict[str, any] = {"github": "", "linkedin": "", "portfolio": "", "other": []};
    for found in URL_RE.finditer(text) {
        url = found.group(0).rstrip(".");
        start = found.start();
        # Skip the end of an email address, e.g. "example.com" in "a@example.com".
        if start > 0 and text[start - 1] == "@" {
            continue;
        }
        url = normalize_url(url);
        lowered = url.lower();
        if "github.com" in lowered {
            if not links["github"] {
                links["github"] = url;
            }
        } elif "linkedin.com" in lowered {
            if not links["linkedin"] {
                links["linkedin"] = url;
            }
        } elif not links["portfolio"] {
            links["portfolio"] = url;
        } elif url not in links["other"] {
            links["other"].append(url);
        }
    }
    return links;
}

"""Pull the contact line facts a resume usually carries up top: the person's
name, an email address and a phone number. Everything stays what the file
says - nothing is inferred or invented."""
def find_contact(text: str) -> dict[str, str] {
    contact = {"name": "", "email": "", "phone": ""};
    if not text {
        return contact;
    }
    email_m = re.search(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text);
    if email_m {
        contact["email"] = email_m.group(0);
    }
    phone_m = re.search(r"(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)\d{3}[-.\s]?\d{4}", text);
    if phone_m {
        contact["phone"] = phone_m.group(0).strip();
    }
    # The name is usually the first short line before any bullet or date.
    for line in text.splitlines()[:15] {
        clean = " ".join(str(line).split()).strip().rstrip(",");
        if clean and not is_bullet(line) and looks_like_name(clean) and "@" not in clean and not re.search(r"\d{4}", clean) {
            contact["name"] = clean;
            break;
        }
    }
    return contact;
}

"""Read a whole resume's text into the profile sections plus contact facts."""
def parse_resume_text(text: str) -> dict[str, any] {
    sections = split_sections(text or "");
    return {
        "experience": parse_experience(sections["experience"]),
        "education": parse_education(sections["education"]),
        "skills": parse_skills(sections["skills"]),
        "links": find_links(text or ""),
        "contact": find_contact(text or ""),
    };
}

def empty_profile -> dict[str, any] {
    return {
        "experience": [],
        "education": [],
        "skills": [],
        "links": {"github": "", "linkedin": "", "portfolio": "", "other": []},
    };
}


# ---------- Cleaning what the user sends back ----------

"""Add "https://" when a link has no "http://" or "https://" at the front."""
def normalize_url(url: str) -> str {
    clean = url.strip();
    if not clean {
        return "";
    }
    if not clean.lower().startswith("http://") and not clean.lower().startswith("https://") {
        clean = "https://" + clean;
    }
    return clean;
}

"""A link is OK if it is empty, or looks like https://something.something.

This is the same rule the contact details in services/profile_llm.jac use.
"""
def is_valid_url(url: str) -> bool {
    if not url {
        return True;
    }
    return len(url) <= 300 and bool(re.fullmatch(r"https?://[^\s.]+\.[^\s]+", url));
}

"""Keep only the expected text fields of each entry, and drop empty entries."""
def clean_entries(entries: any, keys: list[str]) -> list[dict[str, str]] {
    cleaned: list[dict[str, str]] = [];
    if not isinstance(entries, list) {
        return cleaned;
    }
    for item in entries {
        if not isinstance(item, dict) {
            continue;
        }
        row: dict[str, str] = {};
        for key in keys {
            row[key] = str(item.get(key) or "").strip();
        }
        if any(row[key] for key in keys) {
            cleaned.append(row);
        }
    }
    return cleaned;
}

"""Check and tidy a profile from the page. Returns (profile, list of problems)."""
def clean_profile(profile: dict[str, any]) -> tuple[dict[str, any], list[str]] {
    problems: list[str] = [];
    raw_skills = profile.get("skills") or [];
    skills: list[str] = [];
    for skill in raw_skills {
        name = str(skill).strip();
        if name and name.lower() not in [s.lower() for s in skills] {
            skills.append(name);
        }
    }
    raw_links: any = profile.get("links") or {};
    links: dict[str, any] = {"github": "", "linkedin": "", "portfolio": "", "other": []};
    for key in ["github", "linkedin", "portfolio"] {
        url = normalize_url(str(raw_links.get(key) or ""));
        if not is_valid_url(url) {
            problems.append(f"The {key} link doesn't look like a web address: {url}");
        }
        links[key] = url;
    }
    for other_url in (raw_links.get("other") or []) {
        url = normalize_url(str(other_url));
        if not url {
            continue;
        }
        if not is_valid_url(url) {
            problems.append(f"This link doesn't look like a web address: {url}");
        }
        links["other"].append(url);
    }
    cleaned = {
        "experience": clean_entries(profile.get("experience"), ["title", "company", "dates", "description"]),
        "education": clean_entries(profile.get("education"), ["school", "degree", "dates", "gpa"]),
        "skills": skills,
        "links": links,
    };
    return (cleaned, problems);
}


# ---------- Loading and saving for one user ----------
# The endpoints at the bottom find the user from the login token, then call
# these. The tests call these directly with a throwaway database.

"""The user's saved sections, or None if they never saved any."""
def saved_profile(user: dict[str, any]) -> dict[str, any] | None {
    has_any = (
        user.get("experience_json") or user.get("education_json")
        or user.get("skills_json") or user.get("other_links_json")
    );
    if not has_any {
        return None;
    }
    profile = empty_profile();
    try {
        profile["experience"] = json.loads(str(user.get("experience_json") or "[]"));
        profile["education"] = json.loads(str(user.get("education_json") or "[]"));
        profile["skills"] = json.loads(str(user.get("skills_json") or "[]"));
        profile["links"]["other"] = json.loads(str(user.get("other_links_json") or "[]"));
    } except Exception {
        return None;
    }
    return clean_profile(profile)[0];
}

"""Text of the user's newest resume that has any text in it ("" if none)."""
def newest_resume_text(user_id: int, conn: any = None) -> str {
    for resume in list_resumes_by_user(user_id, conn=conn) {
        text = resume_content_to_text(str(resume.get("content") or ""));
        if text.strip() {
            return text;
        }
    }
    return "";
}

"""Put the GitHub / LinkedIn / Portfolio already saved on the user row into a profile.

A link the user saved wins over one read from the resume.
"""
def with_saved_links(profile: dict[str, any], user: dict[str, any]) -> dict[str, any] {
    links = {**profile["links"]};
    for key in ["github", "linkedin", "portfolio"] {
        saved_url = str(user.get(key) or "").strip();
        if saved_url {
            links[key] = saved_url;
        }
    }
    return {**profile, "links": links};
}

"""Load the resume sections for one user row (None = no row yet).

Returns {"ok": True, "profile": {...}, "source": ..., "has_resume": bool}.
"source" says where the sections came from:
    "saved"  - the user saved them before
    "resume" - read fresh from their newest resume (not saved yet)
    "empty"  - nothing yet
from_resume=True ignores the saved sections and re-reads the resume.
"""
def _load_resume_profile(user: dict[str, any] | None, from_resume: bool = False, conn: any = None) -> dict[str, any] {
    if user is None {
        return {"ok": True, "profile": empty_profile(), "source": "empty", "has_resume": False};
    }
    resume_text = newest_resume_text(int(user["id"]), conn=conn);
    has_resume = bool(resume_text.strip());
    if not from_resume {
        saved = saved_profile(user);
        if saved is not None {
            return {"ok": True, "profile": with_saved_links(saved, user), "source": "saved", "has_resume": has_resume};
        }
    }
    if has_resume {
        return {"ok": True, "profile": with_saved_links(parse_resume_text(resume_text), user), "source": "resume", "has_resume": True};
    }
    return {"ok": True, "profile": with_saved_links(empty_profile(), user), "source": "empty", "has_resume": False};
}

"""Check and save one user's edited sections."""
def _save_resume_profile(user_id: int, profile: dict[str, any], conn: any = None) -> dict[str, any] {
    checked = clean_profile(profile or {});
    cleaned = checked[0];
    problems = checked[1];
    if problems {
        return {"ok": False, "error": " ".join(problems)};
    }
    links = cleaned["links"];
    save_resume_sections(
        user_id=user_id,
        experience_json=json.dumps(cleaned["experience"]),
        education_json=json.dumps(cleaned["education"]),
        skills_json=json.dumps(cleaned["skills"]),
        other_links_json=json.dumps(links["other"]),
        github=links["github"],
        linkedin=links["linkedin"],
        portfolio=links["portfolio"],
        conn=conn
    );
    return {"ok": True, "profile": cleaned};
}

"""Read a resume file the user just picked (before it is saved) into sections."""
def _parse_upload(resume_content: str) -> dict[str, any] {
    text = resume_content_to_text(resume_content);
    if not text.strip() {
        return {"ok": False, "error": "We couldn't read any text from that file. You can still type your details in by hand."};
    }
    return {"ok": True, "profile": parse_resume_text(text)};
}


# ---------- Web app endpoints (the profile page calls these) ----------
# def:protect means only a logged-in user can call it. The user is always
# found from the login token, never from an email the page sends, so no one
# can read or change someone else's profile.

def:protect get_resume_profile(token: str, from_resume: bool = False) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    return _load_resume_profile(caller["app_user"], from_resume=from_resume);
}

def:protect parse_resume_upload(token: str, resume_content: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    return _parse_upload(resume_content);
}

def:protect save_resume_profile(token: str, profile: dict[str, any]) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first (click Finish at the bottom of the steps), then save these details."};
    }
    return _save_resume_profile(int(user["id"]), profile);
}

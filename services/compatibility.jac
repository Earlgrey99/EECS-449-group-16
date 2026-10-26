"""Job compatibility scoring.

Compares a user's resume (plus any extra skills from their profile) with a
job posting and returns a 0-100 percentage score, with an explanation of
which skills matched and which are missing.

The score is a weighted mix of three parts:
    skills   (60%) - how many of the job's required skills appear in the resume
    keywords (25%) - how many important words from the job text appear in the resume
    title    (15%) - how many words of the job title appear in the resume
"""

import re;

# How much each part counts toward the final score (they add up to 1.0).
glob SKILL_WEIGHT: float = 0.60;
glob KEYWORD_WEIGHT: float = 0.25;
glob TITLE_WEIGHT: float = 0.15;

# Common words that say nothing about a job's requirements, so we ignore them.
# (Same idea as the word list in resume_tailoring.py on the autofill branch.)
glob STOPWORDS: set[str] = set(
    (
        "and the to for with from that this are you your our their have has will "
        + "can into using use these those a an of on in at by as or is be we it "
        + "job work team skills experience required preferred ability strong "
        + "knowledge who what all about across day every alongside small "
        + "new grad senior junior level role position company"
    ).split()
);

# Skills we can recognise inside free-text job descriptions (all lowercase).
glob KNOWN_SKILLS: list[str] = [
    "python", "java", "javascript", "typescript", "c++", "c#", "rust", "kotlin",
    "swift", "ruby", "php", "html", "css", "sql", "nosql", "postgresql", "mysql",
    "mongodb", "react", "angular", "vue", "node.js", "django", "flask", "spring",
    "rest", "apis", "graphql", "aws", "azure", "gcp", "docker", "kubernetes",
    "terraform", "linux", "git", "ci/cd", "pytorch", "tensorflow", "pandas",
    "numpy", "machine learning", "nlp", "data analysis", "dashboards", "tableau",
    "excel", "figma", "ux", "prototyping", "playwright", "selenium", "agile",
    "distributed systems", "research", "jac",
];

# Different ways people write the same skill. Key = alternate spelling,
# value = the canonical name used in KNOWN_SKILLS.
glob SKILL_ALIASES: dict[str, str] = {
    "js": "javascript",
    "ts": "typescript",
    "reactjs": "react",
    "react.js": "react",
    "node": "node.js",
    "nodejs": "node.js",
    "postgres": "postgresql",
    "k8s": "kubernetes",
    "ml": "machine learning",
    "amazon web services": "aws",
    "google cloud": "gcp",
    "api": "apis",
    "rest api": "apis",
    "restful": "rest",
    "dashboard": "dashboards",
    "user experience": "ux",
    "prototype": "prototyping",
    "continuous integration": "ci/cd",
};

"""Turn a skill into its canonical lowercase form (e.g. 'K8s' -> 'kubernetes')."""
def canonical_skill(skill: str) -> str {
    cleaned = skill.strip().lower();
    return SKILL_ALIASES.get(cleaned, cleaned);
}

"""All spellings that count as the given canonical skill."""
def skill_variants(skill: str) -> list[str] {
    variants = [skill];
    for (alias, canonical) in SKILL_ALIASES.items() {
        if canonical == skill {
            variants.append(alias);
        }
    }
    return variants;
}

"""True if `skill` (or one of its aliases) appears in `text` as a whole word.

The lookarounds stop 'java' from matching inside 'javascript'.
"""
def contains_skill(text: str, skill: str) -> bool {
    lowered = text.lower();
    for variant in skill_variants(canonical_skill(skill)) {
        pattern = r"(?<![a-z0-9])" + re.escape(variant) + r"(?![a-z0-9])";
        if re.search(pattern, lowered) {
            return True;
        }
    }
    return False;
}

"""Split text into lowercase meaningful words (no stopwords, no tiny words)."""
def tokenize(text: str) -> list[str] {
    words = [str(w) for w in re.findall(r"[a-z][a-z0-9+#]*", text.lower())];
    return [w for w in words if len(w) > 2 and w not in STOPWORDS];
}

"""Read a text field from a job dict, returning '' when it is missing."""
def _field(job: dict[str, any], key: str) -> str {
    value = job.get(key);
    return str(value) if value is not None else "";
}

"""All descriptive text in a job posting.

Works for the sample jobs in services/jobs.jac ('desc', 'tags') and for
Jooble API results ('snippet').
"""
def job_text(job: dict[str, any]) -> str {
    parts = [
        _field(job, "title"),
        _field(job, "tags"),
        _field(job, "desc"),
        _field(job, "description"),
        _field(job, "snippet"),
    ];
    return " ".join([p for p in parts if p]);
}

"""The list of skills a job asks for: its tags plus known skills in the text."""
def extract_job_skills(job: dict[str, any]) -> list[str] {
    skills: list[str] = [];
    for tag in _field(job, "tags").split(",") {
        skill = canonical_skill(tag);
        if skill and skill not in skills {
            skills.append(skill);
        }
    }
    text = job_text(job);
    for skill in KNOWN_SKILLS {
        if skill not in skills and contains_skill(text, skill) {
            skills.append(skill);
        }
    }
    return skills;
}

"""Fraction (0.0 - 1.0) of `wanted` words that are present in `have`."""
def _overlap(wanted: set[str], have: set[str]) -> float {
    if not wanted {
        return 0.0;
    }
    return len(wanted & have) / len(wanted);
}

"""A short human-friendly label for a score."""
def score_label(score: int) -> str {
    if score >= 75 {
        return "Strong match";
    } elif score >= 50 {
        return "Good match";
    } elif score >= 25 {
        return "Fair match";
    }
    return "Weak match";
}

"""Score how well a resume fits a job posting.

Args:
    resume_text: the plain text of the user's resume.
    job: a job posting dict (needs at least a 'title' or a description).
    profile_skills: optional extra skills from the user's profile.

Returns a dict like:
    {
        "score": 72,                       # 0-100 percentage
        "label": "Good match",
        "matched_skills": ["python", "sql"],
        "missing_skills": ["apis"],
        "breakdown": {"skills": 67, "keywords": 80, "title": 100}
    }
"""
def compute_compatibility(
    resume_text: str,
    job: dict[str, any],
    profile_skills: list[str] | None = None
) -> dict[str, any] {
    if not resume_text or not resume_text.strip() {
        raise ValueError("Resume text cannot be empty.");
    }
    if not job_text(job).strip() {
        raise ValueError("Job posting has no title or description to compare against.");
    }

    # Everything we know about the candidate, as one block of text.
    candidate_text = resume_text;
    if profile_skills {
        candidate_text = candidate_text + "\n" + ", ".join(profile_skills);
    }
    candidate_words = set(tokenize(candidate_text));

    # 1) Skills
    job_skills = extract_job_skills(job);
    matched = [s for s in job_skills if contains_skill(candidate_text, s)];
    missing = [s for s in job_skills if s not in matched];
    skill_ratio = len(matched) / len(job_skills) if job_skills else 0.0;

    # 2) Keywords from the whole job posting
    keyword_ratio = _overlap(set(tokenize(job_text(job))), candidate_words);

    # 3) Job title words
    title_ratio = _overlap(set(tokenize(_field(job, "title"))), candidate_words);

    # If the job lists no skills at all, give the skill weight to keywords
    # so the score can still reach 100%.
    skill_weight = SKILL_WEIGHT;
    keyword_weight = KEYWORD_WEIGHT;
    if not job_skills {
        keyword_weight = KEYWORD_WEIGHT + SKILL_WEIGHT;
        skill_weight = 0.0;
    }

    raw = skill_weight * skill_ratio
        + keyword_weight * keyword_ratio
        + TITLE_WEIGHT * title_ratio;
    score = max(0, min(100, round(raw * 100)));

    return {
        "score": score,
        "label": score_label(score),
        "matched_skills": matched,
        "missing_skills": missing,
        "breakdown": {
            "skills": round(skill_ratio * 100),
            "keywords": round(keyword_ratio * 100),
            "title": round(title_ratio * 100),
        },
    };
}

"""Sort key used by rank_jobs: just the score."""
def _score_of(result: dict[str, any]) -> int {
    return int(result["score"]);
}

"""Score every job and return them best-first.

Each item is the compute_compatibility result plus a "job" key.
"""
def rank_jobs(
    resume_text: str,
    jobs: list[dict[str, any]],
    profile_skills: list[str] | None = None
) -> list[dict[str, any]] {
    results: list[dict[str, any]] = [];
    for job in jobs {
        result = compute_compatibility(resume_text, job, profile_skills);
        result["job"] = job;
        results.append(result);
    }
    return sorted(results, key=_score_of, reverse=True);
}

"""A few readable lines describing one result, for printing in the CLI."""
def format_compatibility(result: dict[str, any], job: dict[str, any]) -> str {
    title = _field(job, "title") or "Untitled job";
    company = _field(job, "company") or "Unknown company";
    matched_skills = [str(s) for s in result["matched_skills"]];
    missing_skills = [str(s) for s in result["missing_skills"]];
    matched = ", ".join(matched_skills) or "none";
    missing = ", ".join(missing_skills) or "none";
    b = result["breakdown"];
    lines = [
        f"{title} - {company}: {result['score']}% ({result['label']})",
        f"   Matched skills: {matched}",
        f"   Missing skills: {missing}",
        f"   Breakdown: skills {b['skills']}%, keywords {b['keywords']}%, title {b['title']}%",
    ];
    return "\n".join(lines);
}

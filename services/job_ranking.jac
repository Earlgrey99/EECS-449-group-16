"""Put the jobs that best fit someone's profile first.

Nothing is removed. Every job gets a score from the preferences saved on the
profile page, and the list is re-ordered with the highest score first. Jobs
with the same score keep their original order.

Each job comes back with two new fields:
    pref_score    a number; higher means a better fit
    pref_reasons  short labels the page shows, e.g. ["Top choice: Michigan", "Hybrid"]
"""

import json;
import re;
import from services.auth_sync { _resolve_caller }
import from services.jobs { parse_multi_locations, _matches_sector, _extract_salary_values }
import from services.locations { location_matches }
import from services.job_preferences { _read_preferences }

# How much each kind of match is worth. Change these to tune the order.
glob POINTS: dict[str, int] = {
    "top_location": 30,
    "other_location": 20,
    "work_mode": 15,
    "role_level": 15,
    "wrong_role_level": -15,
    "industry": 10,
    "salary_ok": 10,
    "salary_low": -10,
    "per_skill": 4,
    "max_skills": 20
};

# The most jobs one call will rank, so nobody can send a huge list.
glob MAX_JOBS: int = 100;

glob INTERN_RE: str = r"\bintern(ship)?s?\b|\bco-?op\b";
glob NEW_GRAD_RE: str = r"new grad|new graduate|recent graduate|entry[- ]level|\bjunior\b|\bjr\b|early career|university grad|\bgraduate (engineer|developer|program)";
glob SENIOR_RE: str = r"\bsenior\b|\bsr\b|\blead\b|\bstaff\b|\bprincipal\b|\bmanager\b|\bdirector\b|\bhead of\b|\b(ii|iii|iv)\b";
glob YEARS_RE: str = r"(\d+)\s*\+?\s*(?:-\s*\d+\s*)?years?";


"""All the text of a job in lower case, for searching."""
def job_text(job: dict[str, any]) -> str {
    parts = [job.get("title"), job.get("type"), job.get("tags"), job.get("desc") or job.get("snippet")];
    return " ".join([str(p or "") for p in parts]).lower();
}


"""Guess whether a job is Remote, Hybrid or In office. "" means we can't tell.
The title and location are checked before the description, because a
description may mention remote work in passing."""
def detect_work_mode(job: dict[str, any]) -> str {
    if str(job.get("source") or "") == "himalayas" {
        return "Remote";    # Himalayas only lists remote jobs.
    }
    short_text = f"{job.get('title') or ''} {job.get('location') or ''}".lower();
    long_text = str(job.get("desc") or job.get("snippet") or "").lower();
    for text in [short_text, long_text] {
        if "hybrid" in text {
            return "Hybrid";
        }
        if re.search(r"\bremote\b", text) {
            return "Remote";
        }
        if re.search(r"\bon-?site\b|\bin[- ]office\b|\bin[- ]person\b", text) {
            return "In office";
        }
    }
    return "";
}


"""Guess the career stage a job is for: Internship, New grad or Experienced.
"" means we can't tell."""
def detect_role_level(job: dict[str, any]) -> str {
    title = f"{job.get('title') or ''} {job.get('type') or ''}".lower().replace(".", "");
    if re.search(INTERN_RE, title) {
        return "Internship";
    }
    if re.search(NEW_GRAD_RE, title) {
        return "New grad";
    }
    if re.search(SENIOR_RE, title) {
        return "Experienced";
    }
    desc = str(job.get("desc") or job.get("snippet") or "").lower();
    if re.search(INTERN_RE, desc) {
        return "Internship";
    }
    if re.search(NEW_GRAD_RE, desc) {
        return "New grad";
    }
    for found in re.findall(YEARS_RE, desc) {
        if int(found) >= 3 and int(found) <= 20 {
            return "Experienced";
        }
    }
    return "";
}


"""The skills from the list that appear in the job's text as whole words.
"Go" does not count inside "good"; "C++" and "Node.js" work."""
def matching_skills(job: dict[str, any], skills: list[str]) -> list[str] {
    text = job_text(job);
    found: list[str] = [];
    for skill in skills {
        clean = skill.strip().lower();
        if len(clean) < 2 {
            continue;
        }
        pattern = r"(?<![a-z0-9])" + re.escape(clean) + r"(?![a-z0-9])";
        if re.search(pattern, text) {
            found.append(skill.strip());
        }
    }
    return found;
}


"""Everything the score needs from one user row."""
def _ranking_profile(user: dict[str, any] | None) -> dict[str, any] {
    row = user or {};
    prefs = _read_preferences(row);

    salary_min: int | None = None;
    try {
        if row.get("salary_min") is not None {
            salary_min = int(row.get("salary_min"));
        }
    } except Exception {
        salary_min = None;
    }

    resume_skills: list[str] = [];
    try {
        loaded = json.loads(str(row.get("skills_json") or "[]"));
        if isinstance(loaded, list) {
            resume_skills = [str(s) for s in loaded];
        }
    } except Exception {
        resume_skills = [];
    }
    skills: list[str] = [];
    for skill in resume_skills + prefs["extra_skills"] {
        if skill.strip() and skill.strip().lower() not in [s.lower() for s in skills] {
            skills.append(skill.strip());
        }
    }

    return {
        "locations": parse_multi_locations(str(row.get("location") or "")),
        "sectors": [s.strip() for s in str(row.get("sector") or "").split(",") if s.strip()],
        "salary_min": salary_min,
        "role_levels": prefs["role_levels"],
        "work_modes": prefs["work_modes"],
        "skills": skills
    };
}


"""Score one job for one profile. Returns {"score": int, "reasons": [str]}."""
def preference_score(job: dict[str, any], profile: dict[str, any]) -> dict[str, any] {
    score = 0;
    reasons: list[str] = [];
    work_mode = detect_work_mode(job);

    # Location: the top choice (first in the list) is worth the most.
    locations = profile.get("locations") or [];
    job_loc = str(job.get("location") or "");
    place_idx = 0;
    while place_idx < len(locations) {
        place = locations[place_idx];
        is_remote_place = place.strip().lower() == "remote";
        if location_matches(place, job_loc) or (is_remote_place and work_mode == "Remote") {
            if place_idx == 0 {
                score = score + POINTS["top_location"];
                reasons.append(("Top choice: " + place) if len(locations) > 1 else place);
            } else {
                score = score + POINTS["other_location"];
                reasons.append(place);
            }
            break;
        }
        place_idx = place_idx + 1;
    }

    # Remote / Hybrid / In office.
    if work_mode and work_mode in (profile.get("work_modes") or []) {
        score = score + POINTS["work_mode"];
        if work_mode not in reasons {
            reasons.append(work_mode);
        }
    }

    # Role level. A clear mismatch (a senior job for a new grad) moves it down.
    wanted_levels = profile.get("role_levels") or [];
    level = detect_role_level(job);
    if wanted_levels and level {
        if level in wanted_levels {
            score = score + POINTS["role_level"];
            reasons.append(level);
        } else {
            score = score + POINTS["wrong_role_level"];
        }
    }

    # Industry, using the same keyword check as the search filter.
    sectors = [s for s in (profile.get("sectors") or []) if s.lower() != "other"];
    if sectors and _matches_sector(job, ", ".join(sectors)) {
        score = score + POINTS["industry"];
        reasons.append("Your industry");
    }

    # Salary: only counts when the job lists one.
    salary_min = profile.get("salary_min");
    if salary_min is not None {
        pay = _extract_salary_values(job.get("salary"));
        if pay {
            if max(pay) >= salary_min {
                score = score + POINTS["salary_ok"];
                reasons.append("Meets your salary");
            } else {
                score = score + POINTS["salary_low"];
            }
        }
    }

    # Skills from the resume and the extra skills box.
    found = matching_skills(job, profile.get("skills") or []);
    if found {
        score = score + min(len(found) * POINTS["per_skill"], POINTS["max_skills"]);
        reasons.append("Skills: " + ", ".join(found[:3]));
    }

    return {"score": score, "reasons": reasons};
}


def _score_of(job: dict[str, any]) -> int {
    return int(job.get("pref_score") or 0);
}


"""Score every job and put the best fits first. The input list is not changed."""
def rank_jobs(jobs: list[dict[str, any]], profile: dict[str, any]) -> list[dict[str, any]] {
    scored: list[dict[str, any]] = [];
    for job in jobs {
        if not isinstance(job, dict) {
            continue;
        }
        result = preference_score(job, profile);
        ranked_job = dict(job);
        ranked_job["pref_score"] = result["score"];
        ranked_job["pref_reasons"] = result["reasons"];
        scored.append(ranked_job);
    }
    # sorted() keeps jobs with equal scores in their original order.
    return sorted(scored, key=_score_of, reverse=True);
}


# ---------- Endpoint the jobs page calls ----------

"""Re-order a list of jobs for the signed-in user."""
def:protect rank_jobs_for_me(token: str, jobs: list[dict[str, any]]) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    job_list = jobs[:MAX_JOBS] if isinstance(jobs, list) else [];
    user = caller["app_user"];
    if user is None {
        return {"ok": True, "jobs": job_list, "ranked": False};
    }
    return {"ok": True, "jobs": rank_jobs(job_list, _ranking_profile(user)), "ranked": True};
}

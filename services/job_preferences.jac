"""Job preferences on the profile page: role level, work style, company size
and extra skills.

Industry (the "sector" column), minimum salary ("salary_min") and locations
("location") already have their own columns, so they are not stored here.
Everything in this file is kept together as one JSON object in the
"job_preferences" column of the users table.
"""

import json;
import from db { save_job_preferences_row }
import from services.auth_sync { _resolve_caller }

# The only values the page may save. The page shows the same lists.
glob ROLE_LEVELS: list[str] = ["Internship", "New grad", "Experienced"];
glob WORK_MODES: list[str] = ["Remote", "Hybrid", "In office"];
glob COMPANY_SIZES: list[str] = ["Startup", "Small", "Mid-size", "Large", "Enterprise"];

glob MAX_EXTRA_SKILLS: int = 30;
glob MAX_SKILL_LENGTH: int = 40;


"""Preferences for someone who hasn't picked anything yet."""
def empty_preferences -> dict[str, any] {
    return {"role_levels": [], "work_modes": [], "company_sizes": [], "extra_skills": []};
}


"""Keep only the values that appear in `allowed`, matched without caring
about capitals, with no repeats, in the same order as `allowed`."""
def pick_allowed(values: any, allowed: list[str]) -> list[str] {
    if not isinstance(values, list) {
        return [];
    }
    wanted = [str(value or "").strip().lower() for value in values];
    return [option for option in allowed if option.lower() in wanted];
}


"""Tidy the extra skills: trim spaces, drop blanks and repeats, cut very
long ones, and keep at most MAX_EXTRA_SKILLS."""
def clean_skill_list(values: any) -> list[str] {
    kept: list[str] = [];
    if not isinstance(values, list) {
        return kept;
    }
    seen: list[str] = [];
    for value in values {
        text = " ".join(str(value or "").split())[:MAX_SKILL_LENGTH].strip();
        if text and text.lower() not in seen {
            kept.append(text);
            seen.append(text.lower());
        }
        if len(kept) >= MAX_EXTRA_SKILLS {
            break;
        }
    }
    return kept;
}


"""Turn whatever the page sent into a safe preferences object."""
def _clean_preferences(prefs: any) -> dict[str, any] {
    source = prefs if isinstance(prefs, dict) else {};
    return {
        "role_levels": pick_allowed(source.get("role_levels"), ROLE_LEVELS),
        "work_modes": pick_allowed(source.get("work_modes"), WORK_MODES),
        "company_sizes": pick_allowed(source.get("company_sizes"), COMPANY_SIZES),
        "extra_skills": clean_skill_list(source.get("extra_skills"))
    };
}


"""Read the saved preferences from a user row. Missing or broken data
reads as empty preferences."""
def _read_preferences(user: dict[str, any] | None) -> dict[str, any] {
    raw = str((user or {}).get("job_preferences") or "").strip();
    if not raw {
        return empty_preferences();
    }
    try {
        return _clean_preferences(json.loads(raw));
    } except Exception {
        return empty_preferences();
    }
}


"""Clean and save the preferences for one user."""
def _save_preferences(user_id: int, prefs: any, conn: any = None) -> dict[str, any] {
    clean = _clean_preferences(prefs);
    save_job_preferences_row(user_id, json.dumps(clean), conn=conn);
    return {"ok": True, "preferences": clean};
}


# ---------- Endpoints the page calls ----------

"""Load the signed-in user's job preferences."""
def:protect get_job_preferences(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": True, "preferences": empty_preferences()};
    }
    return {"ok": True, "preferences": _read_preferences(user)};
}


"""Save the signed-in user's job preferences."""
def:protect save_job_preferences(token: str, preferences: dict[str, any]) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    return _save_preferences(int(user["id"]), preferences);
}

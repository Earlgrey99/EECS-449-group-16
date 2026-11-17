"""Jac RPC for the Launchpad applicant tools.

The resume review is stateless: the server returns only a review of the text it gets.
"""

import base64;
import re;
import applicant_web;
import resume_pdf;
import from db { list_resumes_by_user, save_tailored_resume, load_env_file }
import from .auth_sync { _resolve_caller }
import from .compatibility { resume_text_from_content }
import from .profile_llm { _read_answers, _details_from }

# What the extension fills, in the order the Applicant Tools page lists it.
glob CONTACT_FIELDS: list[list[str]] = [
    ["first_name", "First name"], ["last_name", "Last name"], ["email", "Email"], ["phone", "Phone"],
    ["location", "City"], ["linkedin", "LinkedIn"], ["github", "GitHub"], ["portfolio", "Website"]
];
glob ANSWER_FIELDS: list[list[str]] = [
    ["work_authorized", "Authorized to work in the US"], ["needs_sponsorship", "Needs visa sponsorship"],
    ["school", "School"], ["degree", "Degree"], ["major", "Major"], ["grad_year", "Graduation year"],
    ["current_company", "Current company"], ["current_title", "Current job title"],
    ["salary", "Salary expectations"], ["start_date", "Earliest start date"], ["country", "Country"]
];

def:pub review_resume_text(resume_text: str, job_text: str, role: str) -> str {
    try {
        return str(applicant_web.build_review(resume_text, job_text, role));
    } except Exception as e {
        return f"Unable to generate review: {e}";
    }
}

"""Collect a user's saved details and newest readable resume for the applicant tools."""
def _applicant_details(user: dict[str, any], conn: any = None) -> dict[str, any] {
    resume_title = "";
    resume_text = "";
    for resume in list_resumes_by_user(int(user["id"]), conn=conn) {
        text = resume_text_from_content(str(resume.get("content") or ""));
        if text.strip() {
            resume_title = str(resume.get("title") or "Saved resume");
            resume_text = text[:20000];
            break;
        }
    }
    return {
        "ok": True,
        "name": str(user.get("name") or ""),
        "email": str(user.get("email") or ""),
        "phone": str(user.get("phone") or ""),
        "linkedin": str(user.get("linkedin") or ""),
        "resume_title": resume_title,
        "resume_text": resume_text
    };
}

"""What the extension will fill, and where each value comes from.

Mirrors buildProfile in extension/background.js: a saved value wins, the resume fills
only blanks, and the email always comes from the account. Demographic answers are kept
in the extension only, so they are not listed here.
"""
def _autofill_rows(fields: list[list[str]], saved: dict[str, any], from_resume: dict[str, any]) -> list[dict[str, str]] {
    rows: list[dict[str, str]] = [];
    for field in fields {
        key = field[0];
        value = str(saved.get(key) or "").strip();
        source = "profile";
        if not value {
            value = str(from_resume.get(key) or "").strip();
            source = "resume" if value else "missing";
        }
        if value in ["yes", "no"] {
            value = value.capitalize();
        }
        rows.append({"key": key, "label": field[1], "value": value, "source": source});
    }
    return rows;
}

def _autofill_profile(user: dict[str, any], conn: any = None) -> dict[str, any] {
    resumes = list_resumes_by_user(int(user["id"]), conn=conn);
    latest = resumes[0] if resumes else None;
    details = _details_from(latest);
    saved_contact = {
        "first_name": user.get("first_name"), "last_name": user.get("last_name"),
        "email": user.get("email"), "phone": user.get("phone"), "location": user.get("city"),
        "linkedin": user.get("linkedin"), "github": user.get("github"), "portfolio": user.get("portfolio")
    };
    resume_contact = dict(details.get("contact") or {});
    resume_contact.pop("email", None);
    return {
        "contact": _autofill_rows(CONTACT_FIELDS, saved_contact, resume_contact),
        "answers": _autofill_rows(ANSWER_FIELDS, _read_answers(user), details.get("answers") or {}),
        "resume_title": _application_resume(user, latest)["title"]
    };
}

def:protect get_applicant_details(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    result = _applicant_details(user);
    result["autofill"] = _autofill_profile(user);
    resumes = list_resumes_by_user(int(user["id"]));
    result["application_resume"] = _application_resume(user, resumes[0] if resumes else None);
    return result;
}

"""Make a tailored copy of the user's resume as a PDF (issue #39).

Uses an uploaded resume if one is given, otherwise the newest saved resume. A PDF is
edited in place: bullets and skills that match the job move up, skills the user
confirmed are added, and, with use_ai, an AI model rewords bullets in the job's terms
(each rewrite is checked so it adds no new claims). Returns the PDF and what changed.
add_skills is a comma-separated list, because HTTP calls may send "None" for it.
"""
def _tailor_for(user: dict[str, any], job_text: str, role: str, resume_content: str, add_skills: str = "", use_ai: bool = False, conn: any = None) -> dict[str, any] {
    content = str(resume_content or "");
    if not content.strip() {
        resumes = list_resumes_by_user(int(user["id"]), conn=conn);
        content = str(resumes[0].get("content") or "") if resumes else "";
    }
    if not content.strip() {
        return {"ok": False, "error": "Upload a resume first, here or in your profile."};
    }
    try {
        skills_text = "" if add_skills is None or str(add_skills) == "None" else str(add_skills);
        skills = [item.strip() for item in skills_text.split(",") if item.strip()];
        if use_ai {
            load_env_file();
        }
        result = resume_pdf.tailor_resume(content, str(job_text or ""), job_title=str(role or ""), extra_skills=skills, use_ai=bool(use_ai) and str(use_ai) != "False");
    } except ValueError as e {
        return {"ok": False, "error": str(e)};
    } except Exception {
        return {"ok": False, "error": "Couldn't read that resume. Try a PDF exported from a document, not a scan."};
    }
    safe_role = re.sub(r"[^A-Za-z0-9 ._-]+", "", str(role or "")).strip()[:60] or "job";
    return {
        "ok": True,
        "pdf": "data:application/pdf;base64," + base64.b64encode(result["pdf"]).decode("ascii"),
        "filename": f"Resume - {safe_role}.pdf",
        "changes": result["changes"],
        "notes": result.get("notes") or [],
        "ai": result.get("ai") or "off",
        "method": result.get("method") or "rebuilt",
        "keywords": result["keywords"]
    };
}

"""The resume that applications attach: the chosen tailored one, else the newest saved one."""
def _application_resume(user: dict[str, any], latest: dict[str, any] | None) -> dict[str, any] {
    if user.get("tailored_resume") {
        return {
            "title": str(user.get("tailored_resume_title") or "Tailored resume.pdf"),
            "tailored": True,
            "tailored_for": str(user.get("tailored_for") or "")
        };
    }
    return {"title": str(latest.get("title") or "Saved resume") if latest else "", "tailored": False, "tailored_for": ""};
}

glob MAX_TAILORED_BYTES: int = 5 * 1024 * 1024;

"""Use a tailored PDF for applications instead of the default resume."""
def _use_tailored(user: dict[str, any], pdf: str, filename: str, job_title: str, conn: any = None) -> dict[str, any] {
    prefix = "data:application/pdf;base64,";
    raw = str(pdf or "");
    if not raw.startswith(prefix) {
        return {"ok": False, "error": "Create a tailored PDF first."};
    }
    try {
        data = base64.b64decode(raw[len(prefix):], validate=True);
    } except Exception {
        return {"ok": False, "error": "That PDF couldn't be read."};
    }
    if not data.startswith(b"%PDF") or len(data) > MAX_TAILORED_BYTES {
        return {"ok": False, "error": "That PDF couldn't be read."};
    }
    name = re.sub(r"[^A-Za-z0-9 ._()-]+", "", str(filename or "")).strip()[:100] or "Tailored resume.pdf";
    if not name.lower().endswith(".pdf") {
        name = name + ".pdf";
    }
    job = re.sub(r"\s+", " ", str(job_title or "")).strip()[:120];
    updated = save_tailored_resume(int(user["id"]), raw, name, job, conn=conn);
    return {"ok": True, "application_resume": _application_resume(updated or user, None)};
}

def:protect use_tailored_resume(token: str, pdf: str, filename: str, job_title: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    return _use_tailored(user, pdf, filename, job_title);
}

def:protect use_default_resume(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    save_tailored_resume(int(user["id"]), None, None, None);
    resumes = list_resumes_by_user(int(user["id"]));
    return {"ok": True, "application_resume": _application_resume({}, resumes[0] if resumes else None)};
}

def:protect tailor_resume_pdf(token: str, job_text: str, role: str, resume_content: str, add_skills: str = "", use_ai: bool = False) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    return _tailor_for(user, job_text, role, resume_content, add_skills, use_ai);
}

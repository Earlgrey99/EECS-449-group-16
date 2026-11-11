"""Jac RPC for the Launchpad applicant tools.

The resume review is stateless: the server returns only a review of the text it gets.
"""

import applicant_web;
import from db { list_resumes_by_user }
import from .auth_sync { _resolve_caller }
import from .compatibility { resume_text_from_content }

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

def:protect get_applicant_details(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    return _applicant_details(user);
}

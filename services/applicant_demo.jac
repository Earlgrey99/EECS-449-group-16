"""Jac RPC for the Launchpad applicant tools.

The resume review is stateless: the server returns only a review of the text it gets.
"""

import base64;
import re;
import applicant_web;
import resume_pdf;
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

"""Make a tailored copy of the user's resume as a PDF (issue #39).

Uses an uploaded resume if one is given, otherwise the newest saved resume. It only
reorders what the resume already says, and returns the PDF with a list of changes.
"""
def _tailor_for(user: dict[str, any], job_text: str, role: str, resume_content: str, conn: any = None) -> dict[str, any] {
    content = str(resume_content or "");
    if not content.strip() {
        resumes = list_resumes_by_user(int(user["id"]), conn=conn);
        content = str(resumes[0].get("content") or "") if resumes else "";
    }
    if not content.strip() {
        return {"ok": False, "error": "Upload a resume first, here or in your profile."};
    }
    try {
        result = resume_pdf.tailor_resume(content, str(job_text or ""));
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
        "changes": result["changes"]
    };
}

def:protect tailor_resume_pdf(token: str, job_text: str, role: str, resume_content: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        return {"ok": False, "error": "Save your profile first."};
    }
    return _tailor_for(user, job_text, role, resume_content);
}

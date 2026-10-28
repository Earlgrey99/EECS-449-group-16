"""Stateless Jac RPC for the Jaccit resume prototype.

The user controls inputs in browser state, and the server returns only a review.
No applicant data is persisted. The existing CLI retains its local Playwright
autofill for testing external forms separately.
"""

import applicant_web;

def:pub review_resume_text(resume_text: str, job_text: str, role: str) -> str {
    try {
        return str(applicant_web.build_review(resume_text, job_text, role));
    } except Exception as e {
        return f"Unable to generate review: {e}";
    }
}

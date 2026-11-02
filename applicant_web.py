"""Stateless, size-bounded adapter for the local Jaccit resume prototype.

The web UI sends text to this function but does not store it. No third-party AI
API is contacted. Keep personal data out of shared screenshots and server logs.
"""
from resume_tailoring import generate_tailored_markdown

MAX_RESUME = 20000
MAX_JOB = 12000

def build_review(resume_text: str, job_text: str, role: str) -> str:
    if not isinstance(resume_text, str) or not isinstance(job_text, str):
        raise ValueError("Resume and job description must be text.")
    if len(resume_text) > MAX_RESUME or len(job_text) > MAX_JOB:
        raise ValueError("Text exceeds the size limit (20,000 resume / 12,000 job characters).")
    if not resume_text.strip() or not job_text.strip():
        raise ValueError("Enter both a resume and a job description.")
    safe_role = (role or "Target position").strip()[:120]
    markdown, _ = generate_tailored_markdown(resume_text, job_text, safe_role)
    return markdown

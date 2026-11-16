"""Tailor a resume PDF to a job and produce a new PDF (issue #39).

Tailoring only reorders what the resume already says:
  - within each job or project, the bullets most relevant to the posting move first
  - within each skills line, skills the posting asks for move first
Nothing is added, removed, or reworded, and section order stays the same.
"""
from __future__ import annotations

import base64
import io
import re
from dataclasses import dataclass, field

from resume_tailoring import tokens

MAX_PDF_BYTES = 5 * 1024 * 1024
MAX_JOB_CHARS = 12000

SECTION_NAMES = {
    "summary", "professional summary", "profile", "objective", "about", "about me",
    "experience", "work experience", "professional experience", "employment", "employment history",
    "relevant experience", "work history", "education", "skills", "technical skills", "core skills",
    "skills and interests", "projects", "personal projects", "academic projects", "selected projects",
    "leadership", "leadership experience", "activities", "extracurricular activities", "involvement",
    "certifications", "certificates", "awards", "honors", "honors and awards", "publications",
    "research", "research experience", "volunteer", "volunteer experience", "languages", "interests",
    "coursework", "relevant coursework",
}
# Bullet marks as text extraction returns them: real symbols, plus the private-use and
# control characters that Word, Google Docs, and basic PDF fonts produce instead.
BULLET = re.compile(
    "^\\s*[•●▪◦‣⁃∙·■►➢❖–—*\\-"
    "\x7f\x95]\\s*(?=\\S)"
)
SKILL_LINE = re.compile(r"^([^:]{2,40}):\s*(.+)$")


@dataclass
class Entry:
    """A job, project, or school: its heading lines, then its bullets."""
    lines: list[str] = field(default_factory=list)
    bullets: list[str] = field(default_factory=list)


@dataclass
class Section:
    title: str
    entries: list[Entry] = field(default_factory=list)


@dataclass
class Resume:
    header: list[str] = field(default_factory=list)
    sections: list[Section] = field(default_factory=list)


def _clean(line: str) -> str:
    return re.sub(r"\s+", " ", line.replace(" ", " ")).strip()


def _section_title(line: str) -> str | None:
    text = _clean(line).rstrip(":")
    if not text or len(text) > 40:
        return None
    if text.lower() in SECTION_NAMES:
        return text
    letters = re.sub(r"[^A-Za-z]", "", text)
    if letters and text.upper() == text and len(text.split()) <= 4 and not any(ch.isdigit() for ch in text):
        return text
    return None


def _ends_sentence(text: str) -> bool:
    return text.rstrip().endswith((".", "!", "?", ";"))


def parse_resume(text: str) -> Resume:
    """Split resume text into a header and sections of entries and bullets."""
    resume = Resume()
    section: Section | None = None
    entry: Entry | None = None
    for raw in text.splitlines():
        line = _clean(raw)
        if not line:
            continue
        title = _section_title(line)
        if title:
            section = Section(title=title)
            resume.sections.append(section)
            entry = None
            continue
        if section is None:
            resume.header.append(line)
            continue
        if BULLET.match(raw) or BULLET.match(line):
            if entry is None:
                entry = Entry()
                section.entries.append(entry)
            entry.bullets.append(BULLET.sub("", line, count=1).strip())
            continue
        # A wrapped bullet continues on the next line without a bullet mark.
        if entry is not None and entry.bullets and (line[0].islower() or not _ends_sentence(entry.bullets[-1])) and not SKILL_LINE.match(line):
            entry.bullets[-1] = entry.bullets[-1] + " " + line
            continue
        if entry is None or entry.bullets:
            entry = Entry()
            section.entries.append(entry)
        entry.lines.append(line)
    return resume


def _job_weights(job_text: str) -> dict[str, int]:
    weights: dict[str, int] = {}
    for word in tokens(job_text):
        weights[word] = weights.get(word, 0) + 1
    return weights


def keyword_match(resume_text: str, job_text: str, limit: int = 12) -> dict[str, list[str]]:
    """The job's most frequent keywords, split by whether the resume already has them."""
    weights = _job_weights(job_text)
    order = {word: index for index, word in reversed(list(enumerate(tokens(job_text))))}
    ranked = sorted(
        (word for word in weights if not word.replace(".", "").isdigit()),
        key=lambda word: (-weights[word], order[word]),
    )
    have = set(tokens(resume_text))
    return {
        "matched": [word for word in ranked if word in have][:limit],
        "missing": [word for word in ranked if word not in have][: limit // 2],
    }


def _score(text: str, weights: dict[str, int]) -> int:
    return sum(weights.get(word, 0) for word in set(tokens(text)))


def _reorder_skills(line: str, weights: dict[str, int]) -> tuple[str, bool]:
    match = SKILL_LINE.match(line)
    label, rest = (match.group(1), match.group(2)) if match else ("", line)
    parts = [part.strip() for part in rest.split(",")]
    if len(parts) < 2 or any(not part for part in parts):
        return line, False
    ordered = sorted(parts, key=lambda part: -_score(part, weights))
    if ordered == parts:
        return line, False
    joined = ", ".join(ordered)
    return (f"{label}: {joined}" if match else joined), True


def tailor(resume: Resume, job_text: str) -> tuple[Resume, list[str]]:
    """Reorder bullets and skills by relevance. Returns the new resume and what changed."""
    weights = _job_weights(job_text)
    changes: list[str] = []
    tailored = Resume(header=list(resume.header))
    for section in resume.sections:
        new_section = Section(title=section.title)
        is_skills = "skill" in section.title.lower()
        for entry in section.entries:
            lines = list(entry.lines)
            bullets = list(entry.bullets)
            if is_skills:
                updated = []
                for item in lines + bullets:
                    new_item, moved = _reorder_skills(item, weights)
                    updated.append(new_item)
                    if moved:
                        changes.append(f"{section.title}: put matching skills first in \"{new_item[:60]}\"")
                lines, bullets = updated[: len(lines)], updated[len(lines):]
            elif len(bullets) > 1:
                ordered = sorted(bullets, key=lambda bullet: -_score(bullet, weights))
                if ordered != bullets:
                    name = (lines[0] if lines else section.title)[:60]
                    changes.append(f"{name}: moved \"{ordered[0][:60]}\" to the top")
                    bullets = ordered
            new_section.entries.append(Entry(lines=lines, bullets=bullets))
        tailored.sections.append(new_section)
    return tailored, changes


# Base PDF fonts only cover Latin-1, so common typographic characters become close matches.
_REPLACEMENTS = {
    "–": "-", "—": "-", "‘": "'", "’": "'", "“": '"', "”": '"',
    "…": "...", "•": "-", "·": "-", "→": "->", "™": "(TM)", "✕": "x",
}


def _latin1(text: str) -> str:
    for old, new in _REPLACEMENTS.items():
        text = text.replace(old, new)
    return text.encode("latin-1", errors="replace").decode("latin-1")


def render_pdf(resume: Resume, scale: float = 1.0) -> bytes:
    """Lay out the resume. scale below 1 shrinks the type, spacing, and margins together."""
    from xml.sax.saxutils import escape

    from reportlab.lib.colors import HexColor
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.platypus import HRFlowable, KeepTogether, ListFlowable, ListItem, Paragraph, SimpleDocTemplate, Spacer

    def para(text: str, style: ParagraphStyle) -> Paragraph:
        return Paragraph(escape(_latin1(text)), style)

    ink = HexColor("#1c2521")
    k = scale
    name = ParagraphStyle("name", fontName="Helvetica-Bold", fontSize=18 * k, leading=22 * k, alignment=TA_CENTER, textColor=ink)
    contact = ParagraphStyle("contact", fontName="Helvetica", fontSize=9.5 * k, leading=13 * k, alignment=TA_CENTER, textColor=ink)
    heading = ParagraphStyle("heading", fontName="Helvetica-Bold", fontSize=11 * k, leading=14 * k, spaceBefore=8 * k, textColor=ink)
    entry_first = ParagraphStyle("entry", fontName="Helvetica-Bold", fontSize=10 * k, leading=13 * k, spaceBefore=4 * k, textColor=ink)
    entry_rest = ParagraphStyle("entry_rest", fontName="Helvetica", fontSize=10 * k, leading=13 * k, textColor=ink)
    bullet = ParagraphStyle("bullet", fontName="Helvetica", fontSize=10 * k, leading=13 * k, textColor=ink)

    story = []
    if resume.header:
        story.append(para(resume.header[0], name))
        if len(resume.header) > 1:
            story.append(para("  |  ".join(resume.header[1:]), contact))
    for section in resume.sections:
        block = [para(section.title.upper(), heading), HRFlowable(width="100%", thickness=0.6, color=ink, spaceAfter=3)]
        for entry in section.entries:
            for index, line in enumerate(entry.lines):
                block.append(para(line, entry_first if index == 0 and entry.bullets else entry_rest))
            if entry.bullets:
                block.append(ListFlowable(
                    [ListItem(para(text, bullet), leftIndent=12) for text in entry.bullets],
                    bulletType="bullet", start="•", bulletFontName="Helvetica", leftIndent=12, bulletFontSize=11 * k,
                ))
            story.append(KeepTogether(block))
            block = []
        story.extend(block)
        story.append(Spacer(1, 2 * k))

    out = io.BytesIO()
    # Margins narrow with the type: 0.7 in at full size, 0.5 in at the smallest scale.
    margin = max(0.7 - (1 - k), 0.5) * inch
    doc = SimpleDocTemplate(out, pagesize=letter, leftMargin=margin, rightMargin=margin,
                            topMargin=min(margin, 0.6 * inch), bottomMargin=min(margin, 0.6 * inch), title="Resume", author="")
    doc.build(story)
    return out.getvalue()


def page_count(data: bytes) -> int:
    from pypdf import PdfReader

    return len(PdfReader(io.BytesIO(data)).pages)


# Smallest scale tried: 10 pt body text becomes 8 pt, still readable on a resume.
SCALES = (1.0, 0.95, 0.9, 0.85, 0.8)


def render_to_fit(resume: Resume, max_pages: int | None) -> bytes:
    """Render at full size, shrinking a little at a time until it fits in max_pages."""
    pdf = render_pdf(resume)
    if not max_pages:
        return pdf
    for scale in SCALES[1:]:
        if page_count(pdf) <= max_pages:
            break
        pdf = render_pdf(resume, scale)
    return pdf


def pdf_text(data: bytes) -> str:
    from pypdf import PdfReader

    return "\n".join(page.extract_text() or "" for page in PdfReader(io.BytesIO(data)).pages)


def resume_bytes(content: str) -> tuple[bytes, str]:
    """Decode a saved or uploaded resume (a data URL, or plain text). Returns (bytes, kind)."""
    raw = str(content or "").strip()
    match = re.match(r"^data:([^;,]*)(;base64)?,(.*)$", raw, re.S)
    if not match:
        return raw.encode("utf-8"), "text"
    data = base64.b64decode(match.group(3)) if match.group(2) else match.group(3).encode("utf-8")
    return data, ("pdf" if data.startswith(b"%PDF") else "text")


def tailor_resume(content: str, job_text: str) -> dict:
    """Tailor a resume (PDF or text) to a job. Returns the new PDF and a list of changes."""
    if not str(job_text or "").strip():
        raise ValueError("Paste the job description first.")
    if len(job_text) > MAX_JOB_CHARS:
        raise ValueError("The job description is too long.")
    data, kind = resume_bytes(content)
    if len(data) > MAX_PDF_BYTES:
        raise ValueError("The resume file is larger than 5 MB.")
    text = pdf_text(data) if kind == "pdf" else data.decode("utf-8", errors="replace")
    resume = parse_resume(text)
    if not resume.sections:
        raise ValueError("Couldn't find resume sections such as Experience or Education. Try a PDF exported from a document, not a scan.")
    tailored, changes = tailor(resume, job_text)
    # Keep the original page count, so a one-page resume stays one page.
    return {
        "pdf": render_to_fit(tailored, page_count(data) if kind == "pdf" else None),
        "changes": changes,
        "sections": [section.title for section in tailored.sections],
        "keywords": keyword_match(text, job_text),
    }

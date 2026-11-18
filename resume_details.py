"""Read application details from a saved resume, so autofill can fill what the profile lacks.

Only reads what the resume states plainly. Anything unclear is left out, because a
wrong answer on an application is worse than a blank one. The current job is read
only when the resume marks it as ongoing ("present", "current", "now").
"""
from __future__ import annotations

import io
import re

from resume_pdf import Resume, _clean, parse_resume, pdf_text, resume_bytes

MAX_RESUME_BYTES = 5 * 1024 * 1024

PHONE = re.compile(r"(?<![\w.])(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?![\w.])")
URL = re.compile(
    r"(?<![\w@.])(?:https?://)?(?:www\.)?((?:[a-z0-9-]+\.)+(?:com|org|net|io|dev|me|co|ai|app|page|site|tech|xyz|us|info)"
    r"(?:/[^\s|,;()]*)?)(?![\w@])",
    re.I,
)
EMAIL = re.compile(r"\S+@\S+\.\S+")
CITY = re.compile(r"^([A-Z][A-Za-z.'-]+(?: [A-Z][A-Za-z.'-]+){0,3}), ([A-Z]{2}|[A-Z][a-z]+(?: [A-Z][a-z]+)?)$")
# "City, ST" inside a longer piece of text, such as "Ann Arbor, MI 48104".
CITY_IN = re.compile(r"(?<![\w])([A-Z][A-Za-z.'-]+(?: [A-Z][A-Za-z.'-]+){0,2}), ([A-Z]{2})(?:\s+\d{5}(?:-\d{4})?)?(?![\w])")
YEAR = re.compile(r"\b(19[6-9]\d|20\d\d)\b")
ONGOING = re.compile(r"\b(present|current|now|ongoing)\b", re.I)
DATES = re.compile(
    r"\(?\b((jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+)?(19|20)\d\d\b.*$"
    r"|\(?\b(present|current)\b.*$",
    re.I,
)
SCHOOL = re.compile(r"\b(university|college|institute|school|academy|polytechnic)\b", re.I)
TITLE_WORDS = re.compile(
    r"\b(engineer|developer|intern|analyst|manager|designer|scientist|assistant|researcher|consultant|"
    r"associate|lead|specialist|coordinator|architect|administrator|director|officer|technician|"
    r"representative|instructor|tutor|fellow|founder|programmer|writer|editor|accountant|teacher)\b",
    re.I,
)
# Each degree is reported in the wording application dropdowns use.
DEGREES = [
    ("PhD", re.compile(r"\b(ph\.?\s?d\.?|doctor(ate)? of)\b", re.I)),
    ("MBA", re.compile(r"\bm\.?b\.?a\.?(?![a-z])", re.I)),
    ("Master's", re.compile(r"\b(master'?s?|m\.\s?s\.?(\s?e\.?)?|m\.\s?a\.|m\.?eng\.?|ms|mse|msc)(?![a-z])", re.I)),
    ("Bachelor's", re.compile(r"\b(bachelor'?s?|b\.\s?s\.?(\s?e\.?)?|b\.\s?a\.|b\.?eng\.?|bs|bse|ba|bsc)(?![a-z])", re.I)),
    ("Associate's", re.compile(r"\b(associate'?s? (degree|of)|a\.\s?a\.|a\.\s?s\.)", re.I)),
]
MAJOR = re.compile(
    r"(?:\bin\b|(?i:\bof (?:science|arts|engineering|business administration)(?: in)?\b|"
    r"\b[bm]\.?\s?[sa]\.?(?:\s?e\.?)?(?![a-z])))\s+([A-Z][A-Za-z&/ ]{2,60})"
)


Cells = dict[str, list[str]]


def _layout_cells(data: bytes) -> Cells:
    """Map each PDF line to its columns, like ["Acme Inc", "Ann Arbor, MI"].

    Plain text extraction joins a right-aligned location or date onto the line with a
    single space. Layout extraction keeps the gap, which tells the parts apart.
    """
    try:
        from pypdf import PdfReader

        pages = PdfReader(io.BytesIO(data)).pages
        text = "\n".join(page.extract_text(extraction_mode="layout") or "" for page in pages)
    except Exception:
        return {}
    cells: Cells = {}
    for raw in text.splitlines():
        parts = [_clean(part) for part in re.split(r"\s{3,}", raw.strip()) if part.strip()]
        if len(parts) > 1:
            cells[_clean(" ".join(parts))] = parts
    return cells


def _is_place_or_date(cell: str) -> bool:
    rest = DATES.sub("", cell).strip(" ,|-–—()")
    return not rest or bool(CITY_IN.fullmatch(cell)) or cell.lower() in ("remote", "hybrid")


def _main_part(line: str, cells: Cells) -> str:
    """The line without a separate location or date column."""
    kept = [cell for cell in cells.get(line, [line]) if not _is_place_or_date(cell)]
    return " ".join(kept) if kept else ""


def _sections(resume: Resume, *words: str) -> list:
    return [section for section in resume.sections if any(word in section.title.lower() for word in words)]


def _contact(resume: Resume, text: str, cells: Cells) -> dict[str, str]:
    found: dict[str, str] = {}
    head = "\n".join("   ".join(cells.get(line, [line])) for line in resume.header) or text[:600]
    phone = PHONE.search(head)
    if phone:
        found["phone"] = phone.group(0).strip()
    for part in re.split(r"\s*[|•·]\s*|\s{2,}|\n", head):
        part = part.strip()
        if not part or EMAIL.fullmatch(part):
            continue
        if "location" in found or SCHOOL.search(part) or EMAIL.search(part):
            continue
        if CITY.match(part):
            found["location"] = part
        elif (city := CITY_IN.search(part)):
            found["location"] = f"{city.group(1)}, {city.group(2)}"
    # Links are read from the contact lines only: a link inside a project
    # description belongs to the project, not the applicant.
    emails = [match.span() for match in EMAIL.finditer(head)]
    for match in URL.finditer(head):
        if any(begin <= match.start() < stop for begin, stop in emails):
            continue
        link = match.group(1).rstrip("./")
        host = link.split("/")[0].lower()
        if host.endswith("linkedin.com"):
            if "/in/" in link and "linkedin" not in found:
                found["linkedin"] = "https://www.linkedin.com" + link[link.index("/in/"):]
        elif host == "github.com":
            user = link.split("/")[1] if "/" in link else ""
            if user and "github" not in found:
                found["github"] = "https://github.com/" + user
        elif "portfolio" not in found:
            found["portfolio"] = "https://" + link
    return found


def _name(resume: Resume, cells: Cells) -> dict[str, str]:
    if not resume.header:
        return {}
    first_line = resume.header[0]
    name = cells.get(first_line, [first_line])[0]
    # The name can share its line with an email, phone, or link.
    name = _clean(PHONE.sub(" ", EMAIL.sub(" ", URL.sub(" ", name))).strip(" |,"))
    words = name.split()
    if 2 <= len(words) <= 4 and all(re.fullmatch(r"[A-Z][A-Za-z.'-]*", word) for word in words):
        return {"first_name": words[0], "last_name": " ".join(words[1:])}
    return {}


def _education(resume: Resume, cells: Cells) -> dict[str, str]:
    found: dict[str, str] = {}
    for section in _sections(resume, "education"):
        for entry in section.entries[:1]:
            lines = entry.lines + entry.bullets
            blob = " | ".join(lines)
            for line in lines:
                for part in re.split(r"\s*[,|–—]\s*|\s{2,}", _main_part(line, cells) or line):
                    if "school" not in found and SCHOOL.search(part) and len(part) <= 80:
                        found["school"] = DATES.sub("", part).strip(" ,-")
            for name, pattern in DEGREES:
                if pattern.search(blob):
                    found["degree"] = name
                    break
            major = MAJOR.search(blob)
            if major:
                field = re.split(r"\s*(?:,|\||–|—|\(|\bat\b|\bfrom\b|\d)", major.group(1))[0].strip()
                if field and not SCHOOL.search(field):
                    found["major"] = field
            years = [int(year) for year in YEAR.findall(blob)]
            if years:
                found["grad_year"] = str(max(years))
    return found


def _split_role(line: str) -> tuple[str, str]:
    """Split "Title, Company" or "Company - Title" into (title, company)."""
    clean = DATES.sub("", line).strip(" ,|-–—")
    if " at " in clean:
        title, company = clean.split(" at ", 1)
        return title.strip(), company.strip()
    parts = [part.strip() for part in re.split(r"\s*(?:,|\||–|—| - )\s*", clean) if part.strip()]
    if len(parts) < 2:
        return ("", "") if not parts else ((parts[0], "") if TITLE_WORDS.search(parts[0]) else ("", parts[0]))
    first, second = parts[0], parts[1]
    if TITLE_WORDS.search(first) and not TITLE_WORDS.search(second):
        return first, second
    if TITLE_WORDS.search(second) and not TITLE_WORDS.search(first):
        return second, first
    return "", ""


def _current_job(resume: Resume, cells: Cells) -> dict[str, str]:
    for section in _sections(resume, "experience", "employment", "work history"):
        for entry in section.entries[:1]:
            # A heading is one to four lines: role, company, and often a separate
            # line or column for the place and dates.
            heading = entry.lines[:4]
            if not any(ONGOING.search(line) for line in heading):
                return {}
            parts = [part for part in (_main_part(line, cells) for line in heading) if part][:2]
            if not parts:
                return {}
            title, company = _split_role(parts[0])
            if len(parts) > 1 and not (title and company):
                other_title, other_company = _split_role(parts[1])
                title, company = title or other_title, company or other_company
            found = {}
            if title:
                found["current_title"] = title
            if company:
                found["current_company"] = company
            return found
    return {}


def resume_details(content: str) -> dict:
    """Return {"contact": {...}, "answers": {...}} read from a saved resume (PDF or text)."""
    try:
        data, kind = resume_bytes(content)
        if not data or len(data) > MAX_RESUME_BYTES:
            return {"contact": {}, "answers": {}}
        text = pdf_text(data) if kind == "pdf" else data.decode("utf-8", errors="replace")
    except Exception:
        return {"contact": {}, "answers": {}}
    cells = _layout_cells(data) if kind == "pdf" else {}
    resume = parse_resume(text)
    contact = {**_name(resume, cells), **_contact(resume, text, cells)}
    answers = {**_education(resume, cells), **_current_job(resume, cells)}
    return {
        "contact": {key: value[:200] for key, value in contact.items() if value},
        "answers": {key: value[:200] for key, value in answers.items() if value},
    }

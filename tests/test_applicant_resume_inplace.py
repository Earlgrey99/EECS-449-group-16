"""In-place resume tailoring (resume_inplace.py) and AI rewording checks (resume_ai.py).

Fixtures:
  - data/resumes/latex_resume.pdf: a pdfLaTeX resume (Type 1 Computer Modern fonts),
    built from latex_resume.tex. Fake person.
  - a Word-style resume drawn here with reportlab's bundled Vera fonts, embedded as
    subsets without a letter map, like many Word and Google Docs exports.
"""
from __future__ import annotations

import base64
import io
import json
import os
import re
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import pymupdf  # noqa: E402
from pypdf import PdfReader  # noqa: E402

import resume_ai  # noqa: E402
import resume_inplace  # noqa: E402
from resume_pdf import tailor_resume  # noqa: E402

LATEX = (ROOT / "tests" / "data" / "resumes" / "latex_resume.pdf").read_bytes()
DATA_JOB = (
    "Data Engineer. Build ETL pipelines in Python and SQL on PostgreSQL. Experience with Docker "
    "and data pipelines. Kubernetes a plus. Strong SQL and data modeling."
)
ANALYST_JOB = "Data Analyst. Build dashboards in Tableau, write SQL, automate reporting with Python."


def word_style_resume() -> bytes:
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas
    import reportlab

    fonts = Path(reportlab.__file__).parent / "fonts"
    pdfmetrics.registerFont(TTFont("Vera", str(fonts / "Vera.ttf")))
    pdfmetrics.registerFont(TTFont("Vera-Bold", str(fonts / "VeraBd.ttf")))
    out = io.BytesIO()
    pdf = canvas.Canvas(out, pagesize=letter)
    y = 740

    def line(x, text, font="Vera", size=10.5):
        pdf.setFont(font, size)
        pdf.drawString(x, y, text)

    line(54, "Avery Chen", "Vera-Bold", 18)
    y -= 30
    line(54, "EXPERIENCE", "Vera-Bold", 12)
    y -= 18
    line(54, "Data Analyst Intern, Lakeshore Health", "Vera-Bold")
    pdf.setFont("Vera", 10.5)
    pdf.drawRightString(558, y, "Jun 2025 - Aug 2025")
    y -= 15
    for text in [
        "Answered phones and scheduled meetings for the analytics team",
        "Built Tableau dashboards that tracked wait times across 12 clinics",
        "Automated a monthly Excel report with Python, saving 5 hours a month",
    ]:
        line(64, "•")
        line(78, text)
        y -= 14
    y -= 6
    line(54, "SKILLS", "Vera-Bold", 12)
    y -= 18
    line(54, "Tools:", "Vera-Bold")
    line(54 + pdfmetrics.stringWidth("Tools: ", "Vera-Bold", 10.5), "Excel, Git, Tableau, Python, SQL")
    pdf.save()
    return out.getvalue()


def page_text(data: bytes) -> str:
    """Text in the order a simple reader (like many applicant tracking systems) sees it."""
    return re.sub(r"\s+", " ", "\n".join(page.extract_text() or "" for page in PdfReader(io.BytesIO(data)).pages))


def plain_text(data: bytes) -> str:
    """Words as they look on the page, without the reader's kerning splits ("T ools")."""
    return re.sub(r"\s+", " ", " ".join(page.get_text() for page in pymupdf.open(stream=data)))


def changed_bands(before: bytes, after: bytes) -> list[tuple[float, float]]:
    """Vertical ranges (in points) where the two first pages render differently."""
    images = [pymupdf.open(stream=data)[0].get_pixmap(dpi=72, colorspace=pymupdf.csGRAY) for data in (before, after)]
    width = images[0].width
    rows = [y for y in range(images[0].height) if images[0].samples[y * width:(y + 1) * width] != images[1].samples[y * width:(y + 1) * width]]
    bands: list[list[float]] = []
    for y in rows:
        if bands and y - bands[-1][1] <= 2:
            bands[-1][1] = y
        else:
            bands.append([y, y])
    return [(start, end) for start, end in bands]


def rewrite_with(changes: dict[str, str]):
    """A stand-in for the AI: replaces text in any candidate bullet that contains the key."""
    def rewriter(candidates):
        out = {}
        for candidate in candidates:
            for old, new in changes.items():
                if old in candidate["text"]:
                    out[candidate["id"]] = candidate["text"].replace(old, new)
        return out
    return rewriter


class ReorderTests(unittest.TestCase):
    def test_matching_bullets_move_up_and_nothing_else_changes(self):
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB)
        text = page_text(result["pdf"])
        # Bullets move within their job; the job headings stay where they were.
        self.assertLess(text.index("Built a Python ETL job"), text.index("Designed a React dashboard"))
        self.assertLess(text.index("Software Engineering Intern"), text.index("Built a Python ETL job"))
        self.assertLess(text.index("Built a Python ETL job"), text.index("Research Assistant"))
        self.assertLess(text.index("Cleaned survey data"), text.index("Organized lab meetings"))
        self.assertTrue(any("Software Engineering Intern: moved" in change for change in result["changes"]))
        # Every word is still there, and only the bullet lines render differently.
        self.assertEqual(sorted(page_text(LATEX).split()), sorted(text.split()))
        bands = changed_bands(LATEX, result["pdf"])
        self.assertTrue(bands)
        self.assertGreater(min(start for start, _ in bands), 200, "the header and education must not change")
        self.assertEqual(len(pymupdf.open(stream=result["pdf"])), 1)

    def test_fonts_are_the_resumes_own(self):
        # Rewritten skills lines reuse the resume's own font programs (renamed by the
        # PDF writer), never a stand-in such as Helvetica.
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB)
        names = {font[3].split("+")[-1] for page in pymupdf.open(stream=result["pdf"]) for font in page.get_fonts()}
        stand_ins = {name for name in names if re.search(r"helv|arial|times|courier|noto|symbol", name, re.I)}
        self.assertEqual(stand_ins, set())

    def test_links_still_work(self):
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB)
        uris = lambda data: sorted(link.get("uri") for link in pymupdf.open(stream=data)[0].get_links())
        self.assertEqual(uris(result["pdf"]), uris(LATEX))

    def test_unrelated_job_returns_the_original(self):
        result = resume_inplace.tailor_pdf(LATEX, "Pastry chef. Laminated dough and plated desserts.")
        self.assertEqual(result["changes"], [])
        self.assertEqual(result["pdf"], LATEX)

    def test_matching_skills_move_first(self):
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB)
        text = plain_text(result["pdf"])
        self.assertIn("Languages: SQL, Python, Java", text)
        self.assertIn("Developer Tools: Docker, Git", text)


class AddedSkillTests(unittest.TestCase):
    def test_confirmed_skill_goes_on_a_tools_line(self):
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB, ["Airflow"])
        self.assertIn("Linux, Airflow", plain_text(result["pdf"]))
        self.assertIn("Added Airflow to Developer Tools", result["changes"])

    def test_skill_the_font_cant_draw_is_left_out(self):
        # The resume's font subset has no capital K.
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB, ["Kubernetes"])
        self.assertNotIn("Kubernetes", plain_text(result["pdf"]))
        self.assertTrue(any("Kubernetes" in note and "K" in note for note in result["notes"]))

    def test_skills_use_the_jobs_capitalization(self):
        result = tailor_resume("data:application/pdf;base64," + base64.b64encode(LATEX).decode(), DATA_JOB, extra_skills=["postgresql"])
        self.assertEqual(result["method"], "in_place")
        self.assertNotIn("Added postgresql", result["changes"])
        self.assertTrue(any(change.startswith("Added Postgre") for change in result["changes"]) or any("PostgreSQL" in note for note in result["notes"]))


class RewordTests(unittest.TestCase):
    def test_checked_rewrites_are_drawn_in_the_resumes_font(self):
        rewriter = rewrite_with({"Built a Python ETL job": "Built a Python ETL pipeline"})
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB, rewriter=rewriter)
        self.assertEqual(result["ai"], "used")
        text = plain_text(result["pdf"])
        self.assertIn("Built a Python ETL pipeline that loaded carrier data", text)
        self.assertNotIn("ETL job", text)
        self.assertTrue(any(change.startswith("Reworded") for change in result["changes"]))
        names = " ".join(font[3] for font in pymupdf.open(stream=result["pdf"])[0].get_fonts())
        self.assertNotRegex(names, r"(?i)helv|noto|times")

    def test_rewrites_that_add_claims_are_dropped(self):
        rewriter = rewrite_with({
            "Wrote unit tests in Jest": "Wrote unit tests in Jest on Kubernetes",  # job keyword the resume lacks
            "Organized lab meetings": "Organized 12 lab meetings",  # new number
        })
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB + " Organized research teams.", rewriter=rewriter)
        text = page_text(result["pdf"])
        self.assertNotIn("Kubernetes", text)
        self.assertNotIn("12 lab", text)
        self.assertEqual(len([note for note in result["notes"] if note.startswith("Skipped a rewording")]), 2)

    def test_rewrites_that_dont_fit_are_dropped(self):
        long = " with a long explanation of every detail of the work that would never fit on the page" * 2
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB, rewriter=rewrite_with({"every night": "every night" + long}))
        self.assertNotIn("long explanation", page_text(result["pdf"]))
        self.assertTrue(any("too long" in note for note in result["notes"]))

    def test_ai_failure_still_reorders(self):
        def broken(candidates):
            raise TimeoutError()
        result = resume_inplace.tailor_pdf(LATEX, DATA_JOB, rewriter=broken)
        self.assertEqual(result["ai"], "failed")
        self.assertTrue(any("moved" in change for change in result["changes"]))

    def test_subset_fonts_without_a_letter_map_can_be_reused(self):
        source = word_style_resume()
        rewriter = rewrite_with({"Automated a monthly Excel report": "Automated monthly reporting in Excel"})
        result = resume_inplace.tailor_pdf(source, ANALYST_JOB, rewriter=rewriter)
        text = page_text(result["pdf"])
        # page_text reads like a tracking system would: words keep their spaces.
        self.assertIn("Automated monthly reporting in Excel with Python", text)
        self.assertIn("Tools: Tableau, Python, SQL, Excel, Git", text)
        self.assertLess(text.index("Built Tableau dashboards"), text.index("Answered phones"))


class CheckRewriteTests(unittest.TestCase):
    RESUME = "Built a Python ETL job with PostgreSQL. Wrote reports for faculty. Cleaned survey data. Used Docker."

    def check(self, original, new, job=DATA_JOB):
        return resume_ai.check_rewrite(original, new, self.RESUME, job)

    def test_allowed(self):
        self.assertEqual(self.check("Wrote reports for faculty", "Wrote data reports for faculty"), "")
        self.assertEqual(self.check("Built a Python ETL job", "Built a Python ETL pipeline"), "")

    def test_rejected(self):
        self.assertIn("number", self.check("Wrote reports for faculty", "Wrote 40 reports for faculty"))
        self.assertIn("kubernetes", self.check("Wrote reports for faculty", "Wrote Kubernetes reports for faculty"))
        self.assertIn("snowflake", self.check("Wrote reports for faculty", "Wrote reports in Snowflake for faculty"))
        self.assertIn("dropped", self.check("Wrote reports for faculty about student outcomes", "Wrote reports"))


class SuggestRewritesTests(unittest.TestCase):
    def test_needs_a_key(self):
        with mock.patch.dict(os.environ, {"DEEPSEEK_API_KEY": ""}):
            self.assertFalse(resume_ai.has_key())
            with self.assertRaises(RuntimeError):
                resume_ai.suggest_rewrites([{"id": "0", "text": "x", "max_chars": 10}], "Job", "job")

    def test_reads_the_reply_and_ignores_unknown_ids(self):
        reply = {"choices": [{"message": {"content": json.dumps({"rewrites": [
            {"id": "0", "text": "Built a  Python ETL pipeline"}, {"id": "9", "text": "invented"},
        ]})}}]}
        response = mock.MagicMock()
        response.read.return_value = json.dumps(reply).encode()
        response.__enter__.return_value = response
        with mock.patch("urllib.request.urlopen", return_value=response) as opened:
            found = resume_ai.suggest_rewrites([{"id": "0", "text": "Built a Python ETL job", "max_chars": 40}], "Data Engineer", DATA_JOB, api_key="test-key")
        self.assertEqual(found, {"0": "Built a Python ETL pipeline"})
        sent = json.loads(opened.call_args[0][0].data)
        self.assertIn("Built a Python ETL job", sent["messages"][1]["content"])


class EndpointPathTests(unittest.TestCase):
    def test_ai_without_a_key_is_reported(self):
        with mock.patch.dict(os.environ, {"DEEPSEEK_API_KEY": ""}):
            result = tailor_resume("data:application/pdf;base64," + base64.b64encode(LATEX).decode(), DATA_JOB, use_ai=True)
        self.assertEqual(result["ai"], "no_key")
        self.assertEqual(result["method"], "in_place")

    def test_ai_is_used_when_asked(self):
        with mock.patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-key"}), \
                mock.patch("resume_ai.suggest_rewrites", return_value={}) as suggest:
            result = tailor_resume("data:application/pdf;base64," + base64.b64encode(LATEX).decode(), DATA_JOB, job_title="Data Engineer", use_ai=True)
        self.assertTrue(suggest.called)
        self.assertEqual(suggest.call_args[0][1], "Data Engineer")
        self.assertEqual(result["ai"], "none")


if __name__ == "__main__":
    unittest.main()

"""Tests for PDF-to-PDF resume tailoring (issue #39)."""
import base64
import io
import re
import unittest

from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

import resume_pdf
from resume_pdf import parse_resume, pdf_text, resume_bytes, tailor, tailor_resume

RESUME_LINES = [
    "Jordan Lee",
    "jordan@example.com | (555) 555-0100 | Ann Arbor, MI",
    "EXPERIENCE",
    "Software Engineering Intern, Northwind Data",
    "May 2025 - Aug 2025",
    "• Organized team events and planned weekly social activities",
    "• Built Python data pipelines that load events into PostgreSQL, cutting",
    "  report time by 40%",
    "• Wrote SQL dashboards for the analytics team.",
    "Teaching Assistant, University of Michigan",
    "• Held office hours for 60 students",
    "• Graded Python assignments and wrote SQL autograder tests.",
    "PROJECTS",
    "Course Planner",
    "• Designed a Figma prototype for course planning",
    "• Built a REST API in Python with Flask and SQL",
    "EDUCATION",
    "University of Michigan - B.S. Computer Science, 2027",
    "SKILLS",
    "Languages: Java, C++, Python, SQL",
    "Tools: Figma, Git, Docker, PostgreSQL",
]
JOB = "Data Engineer. Build Python data pipelines and SQL dashboards. Experience with PostgreSQL and Docker required."


def make_pdf(lines):
    out = io.BytesIO()
    pdf = canvas.Canvas(out, pagesize=letter)
    y = 740
    for line in lines:
        pdf.drawString(54, y, line)
        y -= 16
    pdf.save()
    return out.getvalue()


def data_url(data, kind="application/pdf"):
    return f"data:{kind};base64," + base64.b64encode(data).decode("ascii")


def words(text):
    return set(re.findall(r"[a-z0-9+#]+", text.lower()))


class ParseTests(unittest.TestCase):
    def setUp(self):
        self.resume = parse_resume(pdf_text(make_pdf(RESUME_LINES)))

    def test_header_and_sections(self):
        self.assertEqual(self.resume.header, ["Jordan Lee", "jordan@example.com | (555) 555-0100 | Ann Arbor, MI"])
        self.assertEqual([s.title for s in self.resume.sections], ["EXPERIENCE", "PROJECTS", "EDUCATION", "SKILLS"])

    def test_entries_and_wrapped_bullets(self):
        jobs = self.resume.sections[0].entries
        self.assertEqual(jobs[0].lines, ["Software Engineering Intern, Northwind Data", "May 2025 - Aug 2025"])
        self.assertEqual(len(jobs[0].bullets), 3)
        self.assertIn("cutting report time by 40%", jobs[0].bullets[1])
        self.assertEqual(jobs[1].lines, ["Teaching Assistant, University of Michigan"])
        self.assertEqual(len(jobs[1].bullets), 2)

    def test_plain_text_resume(self):
        resume = parse_resume("\n".join(RESUME_LINES))
        self.assertEqual(len(resume.sections), 4)


class BulletTests(unittest.TestCase):
    def test_bullet_marks_from_real_exports(self):
        for mark in ["\u2022", "\u25cf", "\uf0b7", "\uf0a7", "\x7f", "\u25aa", "-", "*", "\u2013"]:
            resume = parse_resume(f"Name\nEXPERIENCE\nJob\n{mark} Built things.\n{mark} Shipped stuff.")
            self.assertEqual(resume.sections[0].entries[0].bullets, ["Built things.", "Shipped stuff."], repr(mark))


class TailorTests(unittest.TestCase):
    def test_relevant_bullets_move_first_and_nothing_changes_otherwise(self):
        resume = parse_resume("\n".join(RESUME_LINES))
        tailored, changes = tailor(resume, JOB)
        first_job = tailored.sections[0].entries[0]
        self.assertTrue(first_job.bullets[0].startswith("Built Python data pipelines"))
        self.assertTrue(first_job.bullets[-1].startswith("Organized team events"))
        self.assertEqual(sorted(first_job.bullets), sorted(resume.sections[0].entries[0].bullets))
        self.assertEqual(tailored.sections[0].entries[0].lines, resume.sections[0].entries[0].lines)
        self.assertEqual([s.title for s in tailored.sections], [s.title for s in resume.sections])
        self.assertEqual(tailored.header, resume.header)
        self.assertTrue(any("to the top" in change for change in changes))

    def test_matching_skills_move_first(self):
        tailored, changes = tailor(parse_resume("\n".join(RESUME_LINES)), JOB)
        skills = tailored.sections[3].entries[0].lines
        self.assertEqual(skills[0], "Languages: Python, SQL, Java, C++")
        self.assertTrue(skills[1].startswith("Tools: Docker, PostgreSQL") or skills[1].startswith("Tools: PostgreSQL, Docker"), skills[1])
        self.assertTrue(any("matching skills first" in change for change in changes))

    def test_unrelated_job_changes_nothing(self):
        resume = parse_resume("\n".join(RESUME_LINES))
        tailored, changes = tailor(resume, "Pastry chef. Croissants and laminated dough.")
        self.assertEqual(changes, [])
        self.assertEqual(tailored.sections[0].entries[0].bullets, resume.sections[0].entries[0].bullets)


class PdfToPdfTests(unittest.TestCase):
    def test_pdf_in_pdf_out_with_only_the_resumes_own_words(self):
        source = make_pdf(RESUME_LINES)
        result = tailor_resume(data_url(source), JOB)
        self.assertTrue(result["pdf"].startswith(b"%PDF"))
        out_text = pdf_text(result["pdf"])
        new_words = words(out_text) - words("\n".join(RESUME_LINES))
        self.assertEqual(new_words, set(), f"tailoring added words: {new_words}")
        for line in RESUME_LINES:
            if not line.startswith(("•", "  ")):
                self.assertIn(line.split(",")[0].split(":")[0].lower(), out_text.lower())
        flat = re.sub(r"\s+", " ", out_text)
        self.assertLess(flat.index("Built Python data pipelines"), flat.index("Organized team events"))

    def test_text_resume_and_errors(self):
        self.assertTrue(tailor_resume(data_url("\n".join(RESUME_LINES).encode(), "text/plain"), JOB)["pdf"].startswith(b"%PDF"))
        with self.assertRaises(ValueError):
            tailor_resume(data_url(make_pdf(RESUME_LINES)), "")
        with self.assertRaises(ValueError):
            tailor_resume(data_url(make_pdf(["Just a name", "and a line"])), JOB)
        with self.assertRaises(ValueError):
            tailor_resume(data_url(make_pdf(RESUME_LINES)), "x" * 20000)

    def test_unusual_characters_do_not_break_the_pdf(self):
        lines = RESUME_LINES + ["AWARDS", "• Dean’s List – Fall 2025 ✓ café 中文"]
        result = tailor_resume(data_url("\n".join(lines).encode(), "text/plain"), JOB)
        self.assertIn("Dean's List - Fall 2025", pdf_text(result["pdf"]))

    def test_decodes_saved_resume_formats(self):
        self.assertEqual(resume_bytes("plain words")[1], "text")
        self.assertEqual(resume_bytes(data_url(make_pdf(RESUME_LINES)))[1], "pdf")


class KeywordsAndFitTest(unittest.TestCase):
    def test_keywords_split_by_what_the_resume_has(self):
        words = resume_pdf.keyword_match(
            "Built Python pipelines and SQL reports.",
            "Python Python SQL Kubernetes. Python and Kubernetes experience.",
        )
        self.assertEqual(words["matched"], ["python", "sql"])
        self.assertEqual(words["missing"][0], "kubernetes")
        self.assertNotIn("python", words["missing"])

    def test_a_one_page_resume_stays_one_page(self):
        lines = ["Jordan Lee", "jordan@example.com", "EXPERIENCE"]
        for job in range(7):
            lines.append(f"Engineer, Company {job} (2020 - 2021)")
            lines.extend(f"- Built Python service {job}-{n} that handled reporting and data checks for the team." for n in range(6))
        lines += ["SKILLS", "Python, SQL, Docker, AWS"]
        resume = resume_pdf.parse_resume("\n".join(lines))
        full = resume_pdf.render_pdf(resume)
        self.assertEqual(resume_pdf.page_count(full), 2, "fixture should overflow at full size")
        fitted = resume_pdf.render_to_fit(resume, 1)
        self.assertEqual(resume_pdf.page_count(fitted), 1)
        self.assertIn("handled reporting", resume_pdf.pdf_text(fitted))

    def test_fitting_gives_up_rather_than_shrinking_forever(self):
        lines = ["Jordan Lee", "EXPERIENCE"] + [f"- Bullet {n} about building Python services for reporting." for n in range(160)]
        resume = resume_pdf.parse_resume("\n".join(lines))
        self.assertGreater(resume_pdf.page_count(resume_pdf.render_to_fit(resume, 1)), 1)


if __name__ == "__main__":
    unittest.main()

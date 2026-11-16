"""Tests for reading application details from a resume (resume_details.py)."""
import base64
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import resume_pdf  # noqa: E402
from resume_details import resume_details  # noqa: E402

STUDENT = """Priya Natarajan
(734) 555-0182 | priya.n@umich.edu | linkedin.com/in/priya-n | github.com/priyan | priya.dev
Detroit, MI
EDUCATION
University of Michigan, Ann Arbor  Expected May 2027
Bachelor of Science in Computer Engineering, GPA 3.8
EXPERIENCE
Acme Robotics  Jun 2025 - Present
Software Engineering Intern
- Built ROS nodes in C++ and Node.js.
SKILLS
Python, C++
"""


class ResumeDetailsTest(unittest.TestCase):
    def test_reads_contact_and_education(self):
        found = resume_details(STUDENT)
        self.assertEqual(found["contact"], {
            "first_name": "Priya",
            "last_name": "Natarajan",
            "phone": "(734) 555-0182",
            "location": "Detroit, MI",
            "linkedin": "https://www.linkedin.com/in/priya-n",
            "github": "https://github.com/priyan",
            "portfolio": "https://priya.dev",
        })
        self.assertEqual(found["answers"], {
            "school": "University of Michigan",
            "degree": "Bachelor's",
            "major": "Computer Engineering",
            "grad_year": "2027",
            "current_title": "Software Engineering Intern",
            "current_company": "Acme Robotics",
        })

    def test_reads_a_pdf_data_url(self):
        pdf = (ROOT / "tests/data/compatibility/resume_backend.pdf").read_bytes()
        found = resume_details("data:application/pdf;base64," + base64.b64encode(pdf).decode())
        self.assertEqual(found["contact"]["location"], "Ann Arbor, MI")
        self.assertEqual(found["answers"]["school"], "University of Michigan")
        self.assertEqual(found["answers"]["degree"], "Bachelor's")
        self.assertEqual(found["answers"]["major"], "Computer Science")
        self.assertEqual(found["answers"]["current_company"], "Acme Analytics")

    def test_round_trips_through_a_generated_pdf(self):
        pdf = resume_pdf.render_pdf(resume_pdf.parse_resume(STUDENT))
        found = resume_details("data:application/pdf;base64," + base64.b64encode(pdf).decode())
        self.assertEqual(found["contact"]["phone"], "(734) 555-0182")
        self.assertEqual(found["answers"]["grad_year"], "2027")

    def test_past_job_is_not_the_current_company(self):
        text = "Sam Park\nEXPERIENCE\nSoftware Intern, Old Co (May 2023 - Aug 2023)\n- Did things.\n"
        self.assertNotIn("current_company", resume_details(text)["answers"])

    def test_email_is_never_read_from_the_resume(self):
        found = resume_details(STUDENT)
        self.assertNotIn("email", found["contact"])
        self.assertNotIn("umich.edu", " ".join(found["contact"].values()))

    def test_degree_words_and_tools_are_not_websites(self):
        text = "Lee Kim\nB.S.E. student | Node.js | Vue.js\nEDUCATION\nB.S.E. Computer Science, University of Michigan\n"
        self.assertNotIn("portfolio", resume_details(text)["contact"])

    def test_unreadable_input_gives_nothing(self):
        for content in ["", "data:application/pdf;base64,bm90IGEgcGRm", "just some words"]:
            found = resume_details(content)
            self.assertEqual(found["answers"], {}, content)


if __name__ == "__main__":
    unittest.main()

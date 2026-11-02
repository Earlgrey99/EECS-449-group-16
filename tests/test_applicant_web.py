import unittest
from applicant_web import build_review

class WebReviewTests(unittest.TestCase):
    def test_matches_and_missing(self):
        result = build_review(
            "- Built Python ETL pipelines for analytics.",
            "Seeking Python, SQL and dashboard experience.",
            "Data Analyst",
        )
        self.assertIn("python", result.lower())
        self.assertIn("sql", result.lower())
        self.assertIn("Original resume", result)

    def test_empty_input_rejected(self):
        with self.assertRaises(ValueError):
            build_review("", "Seeking Python", "Analyst")

    def test_length_limit(self):
        with self.assertRaises(ValueError):
            build_review("x" * 20001, "Seeking Python", "Analyst")

if __name__ == "__main__":
    unittest.main()

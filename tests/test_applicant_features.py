import tempfile,unittest
from pathlib import Path
from applicant_profile import load_profile,update_profile,validate_field
from application_autofill import resolve_field
from resume_tailoring import generate_tailored_markdown,export_tailoring
class TestFeatures(unittest.TestCase):
 def test_profile(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/"profile.json"
   update_profile([("name","Ada"),("email","ada@example.org")],p)
   self.assertEqual(load_profile(p)["name"],"Ada")
 def test_bad_email(self):
  with self.assertRaises(ValueError):validate_field("email","invalid")
 def test_mapping(self):
  self.assertEqual(resolve_field({"name":"candidate[email]"},{"email":"a@b.org"}),"email")
 def test_sensitive(self):
  self.assertIsNone(resolve_field({"name":"password"},{"password":"secret","name":"Ada"}))
 def test_resume(self):
  md,report=generate_tailored_markdown("Built Python data pipelines for analysis.","Seeking Python developer with SQL experience.","Developer")
  self.assertIn("python",report["verified_terms"])
  self.assertIn("sql",report["not_verified_in_resume"])
  self.assertIn("Original resume",md)
 def test_export(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/"review.md"; export_tailoring("hello",p); self.assertEqual(p.read_text(),"hello")
if __name__=="__main__":unittest.main()

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
 def test_resume_ignores_punctuation(self):
  _,report=generate_tailored_markdown("Skills: Python, SQL, Excel.","Must know SQL. Must have Python, and Excel.")
  self.assertEqual(sorted(report["verified_terms"]),["excel","python","sql"])
  self.assertEqual(report["not_verified_in_resume"],[])
 def test_resume_keeps_skill_punctuation(self):
  _,report=generate_tailored_markdown("Wrote C++ and C# on .NET with Node.js.","Need C++, C#, .NET, Node.js, and Rust.")
  self.assertEqual(sorted(report["verified_terms"]),[".net","c#","c++","node.js"])
  self.assertEqual(report["not_verified_in_resume"],["rust"])
 def test_resume_short_skills_need_their_capitalization(self):
  _,report=generate_tailored_markdown("Built services in Go and R.","Requires Go, R, C, and AI.")
  self.assertEqual(sorted(report["verified_terms"]),["go","r"])
  self.assertEqual(sorted(report["not_verified_in_resume"]),["ai","c"])
  _,report=generate_tailored_markdown("Led R&D and a go to market plan.","Experience with Go and R.")
  self.assertEqual(report["verified_terms"],[])
 def test_resume_skips_filler_words(self):
  _,report=generate_tailored_markdown("Python","Must know Python. Looking for a strong candidate with relevant technologies.")
  self.assertEqual(report["not_verified_in_resume"],[])
 def test_resume_bullets_keep_one_marker(self):
  md,_=generate_tailored_markdown("- Built Python tools","Python")
  self.assertIn("\n- Built Python tools\n",md)
  self.assertNotIn("- - Built",md)
if __name__=="__main__":unittest.main()

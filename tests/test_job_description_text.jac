"""Tests for cleaning up job descriptions and job tags.

Run from the project root with:
    jac test tests/test_job_description_text.jac
"""

import from services.jobs { html_to_text, normalize_himalayas_job }
import from services.compatibility { extract_job_skills, compute_compatibility }

test "html_to_text turns headings and lists into readable lines" {
    raw = "<h3>Requirements</h3><ul>\n<li>Python &amp; SQL</li>\n<li>2+ years</li>\n</ul>";
    assert html_to_text(raw) == "Requirements\n• Python & SQL\n• 2+ years";
}

test "html_to_text keeps plain text as it is" {
    assert html_to_text("Line one\nLine two") == "Line one\nLine two";
}

test "html_to_text handles empty input" {
    assert html_to_text("") == "";
    assert html_to_text(None) == "";
}

test "html_to_text drops scripts completely" {
    assert html_to_text("<script>alert(1)</script>Hi") == "Hi";
}

test "himalayas jobs get a clean description and readable tags" {
    job = normalize_himalayas_job({
        "guid": "him-1",
        "title": "Data Science Teaching Expert",
        "companyName": "TripleTen",
        "description": "<h3>Description</h3><strong>TripleTen</strong> teaches Q&amp;A.",
        "categories": ["Data-Science-Teacher", "Python"]
    });
    assert "<" not in job["desc"], job["desc"];
    assert "&amp;" not in job["desc"], job["desc"];
    assert job["desc"] == "Description\nTripleTen teaches Q&A.";
    assert job["tags"] == "Data Science Teacher, Python";
}

test "only real skills from tags become required skills" {
    job = {"title": "Teacher", "tags": "Data Science Teacher, Mentorship, Python"};
    assert extract_job_skills(job) == ["python"];
}

test "job-title tags no longer show up as missing skills" {
    job = {
        "title": "Data Science Teacher",
        "tags": "Data Science Teacher, Data Science Tutor, Python",
        "desc": "Teach Python and pandas to bootcamp students."
    };
    result = compute_compatibility("Python, pandas, teaching", job);
    assert result["missing_skills"] == [], result;
}

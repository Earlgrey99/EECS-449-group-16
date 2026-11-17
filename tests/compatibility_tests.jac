"""Tests for services/compatibility.jac (the job compatibility score).

Run from the project root with:
    jac test tests/compatibility_tests.jac
"""

import json;
import os;
import from services.compatibility {
    canonical_skill,
    contains_skill,
    tokenize,
    extract_job_skills,
    compute_compatibility,
    rank_jobs,
    score_label,
    format_compatibility,
    resume_text_from_content,
    _match_scores_for
}
import base64;
import sqlite3;
import from db { init_db, create_user, create_resume }
import from services.jobs { list_jobs }

# Folder that holds the sample resumes and jobs used by these tests.
glob DATA_DIR: str = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "compatibility");

"""Read one of the sample resumes, e.g. load_resume("backend")."""
def load_resume(name: str) -> str {
    with open(os.path.join(DATA_DIR, f"resume_{name}.txt"), encoding="utf-8") as f {
        return f.read();
    }
}

"""Read all sample job postings."""
def load_jobs() -> list[dict[str, any]] {
    with open(os.path.join(DATA_DIR, "jobs.json"), encoding="utf-8") as f {
        return [dict(job) for job in json.load(f)];
    }
}

"""Find a sample job by its title."""
def job_titled(title: str) -> dict[str, any] {
    for job in load_jobs() {
        if job["title"] == title {
            return job;
        }
    }
    raise KeyError(title);
}

# ---------- Small helper functions ----------

test "canonical_skill lowercases and resolves aliases" {
    assert canonical_skill("  Python ") == "python";
    assert canonical_skill("K8s") == "kubernetes";
    assert canonical_skill("Postgres") == "postgresql";
}

test "contains_skill matches whole words only" {
    assert contains_skill("I write Java every day", "java");
    assert not contains_skill("I write JavaScript every day", "java");
    assert contains_skill("Comfortable with C++ and Rust", "c++");
    assert contains_skill("Set up CI/CD pipelines", "ci/cd");
}

test "contains_skill understands aliases" {
    assert contains_skill("Deployed apps on k8s", "Kubernetes");
    assert contains_skill("Built frontends in ReactJS", "react");
}

test "tokenize drops stopwords and short words" {
    words = tokenize("We are looking for a Python developer with SQL skills");
    assert "python" in words;
    assert "developer" in words;
    assert "sql" in words;
    assert "with" not in words;
    assert "are" not in words;
}

test "extract_job_skills uses tags and description" {
    job = job_titled("Backend Engineer");
    assert extract_job_skills(job) == ["python", "sql", "apis"];

    # A Jooble-style job has no tags, only a text snippet.
    skills = extract_job_skills(job_titled("Python Developer"));
    for expected in ["python", "flask", "postgresql", "docker", "aws"] {
        assert expected in skills, f"missing {expected} in {skills}";
    }
}

test "score_label buckets" {
    assert score_label(90) == "Strong match";
    assert score_label(60) == "Good match";
    assert score_label(30) == "Fair match";
    assert score_label(5) == "Weak match";
}

# ---------- compute_compatibility ----------

test "result has the expected shape" {
    result = compute_compatibility(load_resume("backend"), job_titled("Backend Engineer"));
    assert set(result.keys()) == {"score", "label", "matched_skills", "missing_skills", "breakdown"};
    assert set(result["breakdown"].keys()) == {"skills", "keywords", "title"};
    assert 0 <= int(result["score"]) <= 100;
}

test "backend resume is a strong match for the backend job" {
    result = compute_compatibility(load_resume("backend"), job_titled("Backend Engineer"));
    assert int(result["score"]) >= 75, result;
    assert result["label"] == "Strong match";
    assert result["matched_skills"] == ["python", "sql", "apis"];
    assert result["missing_skills"] == [];
}

test "frontend resume is a weak match for the backend job" {
    result = compute_compatibility(load_resume("frontend"), job_titled("Backend Engineer"));
    assert int(result["score"]) < 25, result;
    assert result["missing_skills"] == ["python", "sql", "apis"];
}

test "partial match lists matched and missing skills" {
    # The backend resume has AWS but not Kubernetes or Terraform.
    result = compute_compatibility(load_resume("backend"), job_titled("DevOps Engineer"));
    assert result["matched_skills"] == ["aws"];
    assert result["missing_skills"] == ["kubernetes", "terraform"];
    assert result["breakdown"]["skills"] == 33;
    assert 25 <= int(result["score"]) < 50, result;
}

test "matching is case insensitive" {
    job = {"title": "Engineer", "tags": "Python, SQL"};
    lower = compute_compatibility("python and sql", job);
    upper = compute_compatibility("PYTHON AND SQL", job);
    assert lower["score"] == upper["score"];
    assert upper["matched_skills"] == ["python", "sql"];
}

test "profile skills count toward the score" {
    job = job_titled("DevOps Engineer");
    resume = load_resume("backend");
    without_profile = compute_compatibility(resume, job);
    with_profile = compute_compatibility(resume, job, ["Kubernetes", "Terraform"]);
    assert int(with_profile["score"]) > int(without_profile["score"]);
    assert with_profile["missing_skills"] == [];
}

test "job with no skills still gets a keyword based score" {
    job = job_titled("Barista");
    assert extract_job_skills(job) == [];
    good = compute_compatibility("Barista who prepares espresso drinks and greets customers", job);
    bad = compute_compatibility(load_resume("backend"), job);
    assert int(good["score"]) > int(bad["score"]);
    assert good["breakdown"]["skills"] == 0;
}

test "perfect resume scores 100" {
    job = {"title": "Python Developer", "tags": "Python", "desc": "Python developer"};
    result = compute_compatibility("Python developer", job);
    assert result["score"] == 100, result;
}

test "empty resume raises ValueError" {
    try {
        compute_compatibility("   ", job_titled("Backend Engineer"));
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}

test "empty job raises ValueError" {
    try {
        compute_compatibility(load_resume("backend"), {"company": "Nobody"});
        assert False, "should have raised";
    } except ValueError {
        assert True;
    }
}

# ---------- rank_jobs and formatting ----------

test "rank_jobs puts the best job first for each resume" {
    jobs = load_jobs();
    expected_best = {
        "backend": "Backend Engineer",
        "frontend": "Frontend Engineer",
        "designer": "Product Designer",
    };
    for (name, best_title) in expected_best.items() {
        ranked = rank_jobs(load_resume(name), jobs);
        assert len(ranked) == len(jobs);
        assert ranked[0]["job"]["title"] == best_title, f"{name}: got {ranked[0]['job']['title']}";
        scores = [r["score"] for r in ranked];
        assert scores == sorted(scores, reverse=True);
    }
}

test "rank_jobs with no jobs returns empty list" {
    assert rank_jobs(load_resume("backend"), []) == [];
}

test "format_compatibility shows score and skills" {
    job = job_titled("DevOps Engineer");
    text = format_compatibility(compute_compatibility(load_resume("backend"), job), job);
    assert "DevOps Engineer - Halcyon Cloud" in text;
    assert "%" in text;
    assert "Missing skills: kubernetes, terraform" in text;
}

# ---------- Scores from the resume saved in the user's profile ----------

"""A fresh, empty database that only lives in memory (nothing saved to disk)."""
def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

"""The sample PDF resume as a data URL, exactly how the profile page saves uploads."""
def pdf_resume_data_url() -> str {
    with open(os.path.join(DATA_DIR, "resume_backend.pdf"), "rb") as f {
        encoded = base64.b64encode(f.read()).decode("ascii");
    }
    return "data:application/pdf;base64," + encoded;
}

"""Find one job's row in the scores list by its id."""
def score_for(scores: list[dict[str, any]], job_id: str) -> dict[str, any] {
    for row in scores {
        if row["id"] == job_id {
            return row;
        }
    }
    raise KeyError(job_id);
}

test "resume_text_from_content reads an uploaded PDF" {
    text = resume_text_from_content(pdf_resume_data_url());
    assert "Jordan Lee" in text, text;
    assert "PostgreSQL" in text;
}

test "resume_text_from_content handles plain text and empty values" {
    assert resume_text_from_content("I know Python") == "I know Python";
    encoded = base64.b64encode("I know SQL".encode("utf-8")).decode("ascii");
    assert resume_text_from_content("data:text/plain;base64," + encoded) == "I know SQL";
    assert resume_text_from_content("") == "";
    assert resume_text_from_content(None) == "";
}

test "get_resume_match_scores uses the resume saved in the profile" {
    conn = make_test_db();
    user = create_user(name="Jordan Lee", email="jordan@example.com", conn=conn);
    create_resume(user_id=int(user["id"]), title="resume.pdf", content=pdf_resume_data_url(), conn=conn);

    res = _match_scores_for([dict(j) for j in list_jobs()], "jordan@example.com", conn=conn);
    assert res["ok"];
    assert res["has_resume"];
    assert len(res["scores"]) == 8;
    backend = score_for(res["scores"], "2");
    assert backend["score"] == 95, backend;
    assert backend["label"] == "Strong match";
    assert backend["matched"] == "python, sql, apis";
    devops = score_for(res["scores"], "5");
    assert devops["missing"] == "kubernetes, terraform";
}

test "get_resume_match_scores uses the newest resume" {
    conn = make_test_db();
    user = create_user(name="Sam Rivera", email="sam@example.com", conn=conn);
    uid = int(user["id"]);
    create_resume(user_id=uid, title="old.txt", content="I only know Figma.", conn=conn);
    create_resume(user_id=uid, title="new.pdf", content=pdf_resume_data_url(), conn=conn);
    res = _match_scores_for([dict(j) for j in list_jobs()], "sam@example.com", conn=conn);
    assert score_for(res["scores"], "2")["score"] == 95;
}

test "get_resume_match_scores reports when there is no resume" {
    conn = make_test_db();
    create_user(name="No Resume", email="noresume@example.com", conn=conn);
    jobs = [dict(j) for j in list_jobs()];

    no_resume = _match_scores_for(jobs, "noresume@example.com", conn=conn);
    assert no_resume["ok"];
    assert not no_resume["has_resume"];
    assert no_resume["scores"] == [];

    unknown_user = _match_scores_for(jobs, "nobody@example.com", conn=conn);
    assert not unknown_user["has_resume"];
}

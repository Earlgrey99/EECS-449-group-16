"""Tests for services/job_ranking.jac and location_matches in services/locations.jac.

Run from the project root with:
    jac test tests/test_job_ranking.jac
"""

import json;
import from services.locations { location_matches }
import from services.job_ranking {
    detect_work_mode,
    detect_role_level,
    matching_skills,
    preference_score,
    rank_jobs,
    _ranking_profile
}

# A few made-up jobs, in the order a job board might return them.
glob SENIOR_OHIO: dict[str, any] = {"id": "a", "title": "Senior Backend Engineer", "company": "Acme", "location": "Columbus, OH", "salary": "150,000", "tags": "Java", "desc": "On-site role. 7+ years of experience."};
glob NEW_GRAD_DETROIT: dict[str, any] = {"id": "b", "title": "Software Engineer, New Grad", "company": "Motor Labs", "location": "Detroit, MI", "salary": "105,000", "tags": "Python, SQL", "desc": "Hybrid, 3 days a week in office."};
glob REMOTE_JOB: dict[str, any] = {"id": "c", "title": "Data Analyst", "company": "Northwind", "location": "Remote", "salary": "", "tags": "SQL, Dashboards", "desc": "Work from anywhere."};
glob INTERN_MADISON: dict[str, any] = {"id": "d", "title": "Machine Learning Intern", "company": "Badger AI", "location": "Madison, WI", "salary": "42,000", "tags": "PyTorch", "desc": "Summer internship."};

def sample_profile -> dict[str, any] {
    return {
        "locations": ["Michigan", "Ohio", "Wisconsin"],
        "sectors": ["Technology & Software"],
        "salary_min": 90000,
        "role_levels": ["New grad"],
        "work_modes": ["Hybrid"],
        "skills": ["Python", "SQL", "Go"]
    };
}

test "a picked state matches its cities" {
    assert location_matches("Michigan", "Detroit, MI");
    assert location_matches("Michigan", "Ann Arbor, Michigan, USA");
    assert location_matches("Ohio", "Columbus, OH, United States");
    assert not location_matches("Ohio", "Detroit, MI");
    assert not location_matches("Michigan", "Miami, FL");
    assert location_matches("Columbus, OH", "Columbus, OH");
    assert location_matches("Remote", "Remote - US");
    assert not location_matches("Remote", "Detroit, MI");
    assert not location_matches("Michigan", "");
}

test "work style is read from the job" {
    assert detect_work_mode(NEW_GRAD_DETROIT) == "Hybrid";
    assert detect_work_mode(REMOTE_JOB) == "Remote";
    assert detect_work_mode(SENIOR_OHIO) == "In office";
    assert detect_work_mode({"title": "Engineer", "location": "Austin, TX", "desc": ""}) == "";
    assert detect_work_mode({"title": "Engineer", "location": "Anywhere", "source": "himalayas"}) == "Remote";
}

test "role level is read from the job" {
    assert detect_role_level(SENIOR_OHIO) == "Experienced";
    assert detect_role_level(NEW_GRAD_DETROIT) == "New grad";
    assert detect_role_level(INTERN_MADISON) == "Internship";
    assert detect_role_level({"title": "Sr. Data Engineer"}) == "Experienced";
    assert detect_role_level({"title": "Software Engineer II"}) == "Experienced";
    assert detect_role_level({"title": "Entry-Level Analyst"}) == "New grad";
    assert detect_role_level({"title": "Data Analyst", "desc": "3+ years of SQL"}) == "Experienced";
    assert detect_role_level({"title": "Data Analyst", "desc": "Great team."}) == "";
    # "International" and "internal" are not internships.
    assert detect_role_level({"title": "International Sales Rep"}) == "";
}

test "skills only count as whole words" {
    assert matching_skills(NEW_GRAD_DETROIT, ["Python", "SQL", "Go"]) == ["Python", "SQL"];
    assert matching_skills({"title": "Good engineer"}, ["Go"]) == [];
    assert matching_skills({"title": "C++ developer", "desc": "Node.js too"}, ["C++", "node.js", "C"]) == ["C++", "node.js"];
}

test "the best fit comes first and nothing is dropped" {
    jobs = [SENIOR_OHIO, REMOTE_JOB, INTERN_MADISON, NEW_GRAD_DETROIT];
    ranked = rank_jobs(jobs, sample_profile());
    assert len(ranked) == 4;
    assert ranked[0]["id"] == "b";
    assert "Top choice: Michigan" in ranked[0]["pref_reasons"];
    assert "Hybrid" in ranked[0]["pref_reasons"];
    assert "New grad" in ranked[0]["pref_reasons"];
    # The internship is in a picked state, but it's the wrong level and pays
    # under the minimum, so it ends up last.
    assert [j["id"] for j in ranked] == ["b", "a", "c", "d"];
    # The original list is not changed.
    assert "pref_score" not in jobs[0];
}

test "jobs with equal scores keep their order" {
    plain_a = {"id": "x", "title": "Analyst", "location": "Austin, TX"};
    plain_b = {"id": "y", "title": "Analyst", "location": "Austin, TX"};
    ranked = rank_jobs([plain_a, plain_b], sample_profile());
    assert [j["id"] for j in ranked] == ["x", "y"];
}

test "the top choice location beats the others" {
    ohio = preference_score({"title": "Analyst", "location": "Toledo, OH"}, sample_profile());
    michigan = preference_score({"title": "Analyst", "location": "Lansing, MI"}, sample_profile());
    assert michigan["score"] > ohio["score"];
    assert "Ohio" in ohio["reasons"];
}

test "low pay moves a job down, missing pay does not" {
    low = preference_score({"title": "Analyst", "location": "Austin, TX", "salary": "50,000"}, sample_profile());
    unknown = preference_score({"title": "Analyst", "location": "Austin, TX", "salary": ""}, sample_profile());
    assert low["score"] < unknown["score"];
}

test "an empty profile leaves the order alone" {
    ranked = rank_jobs([SENIOR_OHIO, NEW_GRAD_DETROIT], _ranking_profile(None));
    assert [j["id"] for j in ranked] == ["a", "b"];
}

test "the profile is read from the saved user row" {
    user = {
        "location": "Michigan, Columbus, OH, Remote",
        "sector": "Technology & Software, Other",
        "salary_min": 80000,
        "skills_json": json.dumps(["Python", "SQL"]),
        "job_preferences": json.dumps({"role_levels": ["New grad"], "work_modes": ["Hybrid"], "extra_skills": ["sql", "Rust"]})
    };
    profile = _ranking_profile(user);
    assert profile["locations"] == ["Michigan", "Columbus, OH", "Remote"];
    assert profile["salary_min"] == 80000;
    assert profile["role_levels"] == ["New grad"];
    assert profile["skills"] == ["Python", "SQL", "Rust"];
}

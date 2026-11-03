"""Unit and integration tests for custom parameter search on the jobs page."""

import json;
import from unittest.mock { patch, MagicMock }
import from services.jobs {
    search_jobs,
    list_jobs,
    JOBS
}

test "search_jobs returns default fallback jobs when no params provided" {
    res = search_jobs(source="local");
    assert res["ok"] is True;
    assert res["is_custom"] is True;
    assert len(res["jobs"]) > 0;
    assert res["count"] == len(res["jobs"]);
}

test "search_jobs filters by keyword in title, company, desc, and tags" {
    res = search_jobs(search="Frontend", source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        combined = f"{j.get('title', '')} {j.get('company', '')} {j.get('tags', '')}".lower();
        assert "frontend" in combined or "react" in combined;
    }
}

test "search_jobs filters by location including Remote" {
    res = search_jobs(search="Engineer", location="Remote", source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        assert "remote" in str(j.get("location", "")).lower();
    }
}

test "search_jobs filters by specific city location" {
    res = search_jobs(search="Engineer", location="Cleveland, OH", source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        assert "cleveland" in str(j.get("location", "")).lower();
    }
}

test "search_jobs filters by minimum salary threshold" {
    res = search_jobs(salary=120000, source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        sal_clean = str(j.get("salary", "0")).replace(",", "");
        assert float(sal_clean) >= 120000;
    }
}

test "search_jobs filters by contract type" {
    res = search_jobs(contract_type="Contract", source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        assert str(j.get("type", "")).lower() == "contract";
    }

    res_intern = search_jobs(contract_type="Internship", source="local");
    assert res_intern["ok"] is True;
    assert len(res_intern["jobs"]) > 0;
    for j in res_intern["jobs"] {
        assert str(j.get("type", "")).lower() == "internship";
    }
}

test "search_jobs filters by company name" {
    res = search_jobs(company="Orbit AI", source="local");
    assert res["ok"] is True;
    assert len(res["jobs"]) == 1;
    assert res["jobs"][0]["company"] == "Orbit AI";
}

test "search_jobs with multiple combined parameters" {
    res = search_jobs(
        search="Engineer",
        location="Remote",
        salary=100000,
        contract_type="Full-time",
        source="local"
    );
    assert res["ok"] is True;
    assert len(res["jobs"]) > 0;
    for j in res["jobs"] {
        assert "remote" in str(j.get("location", "")).lower();
        assert str(j.get("type", "")).lower() == "full-time";
    }
}

test "search_jobs returns structured query metadata in response" {
    res = search_jobs(
        search="Data",
        location="Chicago, IL",
        salary=80000,
        contract_type="Full-time",
        company="Cascade Health",
        source="all"
    );
    assert res["ok"] is True;
    assert res["is_custom"] is True;
    q = res["query"];
    assert q["search"] == "Data";
    assert q["location"] == "Chicago, IL";
    assert q["salary"] == 80000;
    assert q["contract_type"] == "Full-time";
    assert q["company"] == "Cascade Health";
    assert q["source"] == "all";
}

test "search_jobs handles non-matching queries gracefully" {
    res = search_jobs(search="Astronaut", location="Mars", source="local");
    assert res["ok"] is True;
    assert res["jobs"] == [];
    assert res["count"] == 0;
}

test "search_jobs integrates with external fetch results" {
    mock_jobs = [
        {
            "id": "ext-1",
            "title": "Cloud Architect",
            "company": "Apex Corp",
            "location": "Remote",
            "salary": "$160,000",
            "type": "Full-time",
            "desc": "Build scalable cloud systems",
            "tags": "AWS, GCP, Kubernetes",
            "source": "himalayas"
        }
    ];
    with patch("services.jobs.fetch", return_value=mock_jobs) as mock_fetch {
        res = search_jobs(search="Cloud Architect", location="Remote", source="himalayas");
        assert res["ok"] is True;
        assert res["is_custom"] is True;
        assert len(res["jobs"]) == 1;
        assert res["jobs"][0]["id"] == "ext-1";
        assert res["jobs"][0]["company"] == "Apex Corp";
        assert mock_fetch.called;
    }
}

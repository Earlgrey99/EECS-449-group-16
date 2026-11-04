"""Unit tests for Issue #25: User onboarding, profile preferences, city search, and DeepSeek query caching."""

import json;
import os;
import sqlite3;
import from unittest.mock { patch, MagicMock }
import from db {
    init_db,
    register_user,
    get_user_by_email,
    get_user_profile,
    get_user_profile_by_email,
    save_user_profile,
    sync_oauth_user,
    ensure_test_user,
    list_resumes_by_user
}
import from services.locations { search_cities }
import from services.profile_llm {
    generate_fallback_query,
    generate_job_search_params,
    submit_profile_and_generate_query,
    get_user_profile_data
}
import from services.jobs { get_user_tailored_jobs }

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

test "users table contains all onboarding profile columns" {
    conn = make_test_db();
    cols = conn.execute("PRAGMA table_info(users);").fetchall();
    col_names = [c[1] for c in cols];
    expected = [
        "first_name",
        "last_name",
        "location",
        "sector",
        "job_titles",
        "salary_min",
        "contract_type",
        "cached_job_query",
        "onboarding_completed"
    ];
    for exp in expected {
        assert exp in col_names;
    }
}

test "save_user_profile updates fields and marks onboarding_completed" {
    conn = make_test_db();
    u = register_user(name="Ada Lovelace", email="ada@example.com", password="password123", conn=conn);
    assert u is not None;
    assert u.get("onboarding_completed") == 0;

    saved = save_user_profile(
        user_id=int(u["id"]),
        first_name="Ada",
        last_name="Lovelace",
        location="London, UK",
        sector="Technology & Software",
        job_titles="Algorithm Engineer, Mathematician",
        salary_min=120000,
        contract_type="Full-time",
        cached_job_query=json.dumps({"search": "Algorithm Engineer", "location": "Remote"}),
        onboarding_completed=1,
        conn=conn
    );
    assert saved is not None;
    assert saved["first_name"] == "Ada";
    assert saved["last_name"] == "Lovelace";
    assert saved["location"] == "London, UK";
    assert saved["sector"] == "Technology & Software";
    assert saved["salary_min"] == 120000;
    assert saved["contract_type"] == "Full-time";
    assert saved["onboarding_completed"] == 1;

    prof = get_user_profile(int(u["id"]), conn=conn);
    assert prof is not None;
    assert prof["first_name"] == "Ada";
    assert prof["onboarding_completed"] == 1;

    prof_by_email = get_user_profile_by_email("ada@example.com", conn=conn);
    assert prof_by_email is not None;
    assert prof_by_email["id"] == u["id"];
}

test "sync_oauth_user infers first and last name from full name" {
    conn = make_test_db();
    oauth_user = sync_oauth_user(
        email="grace.hopper@example.com",
        name="Grace Hopper",
        oauth_id="google_12345",
        auth_provider="google",
        conn=conn
    );
    assert oauth_user is not None;
    assert oauth_user["first_name"] == "Grace";
    assert oauth_user["last_name"] == "Hopper";
    assert oauth_user.get("onboarding_completed") == 0;
}

test "search_cities returns Remote and matches from uscities.csv" {
    # Empty query should include Remote and major cities
    default_cities = search_cities("", limit=5);
    assert len(default_cities) > 0;
    assert "Remote" in default_cities;

    # Searching 'Remote'
    rem_matches = search_cities("Remote", limit=5);
    assert "Remote" in rem_matches;

    # Searching 'Seat' should match Seattle, WA
    seat_matches = search_cities("Seat", limit=5);
    assert any("Seattle" in c for c in seat_matches);

    # Searching 'Chicago' should match Chicago, IL
    chi_matches = search_cities("Chicago", limit=5);
    assert any("Chicago" in c for c in chi_matches);
}

test "generate_fallback_query synthesizes parameters from profile inputs" {
    profile = {
        "first_name": "Alan",
        "last_name": "Turing",
        "location": "Remote",
        "sector": "Technology & Software",
        "job_titles": "Cryptanalyst, Computer Scientist",
        "salary_min": 150000,
        "contract_type": "Full-time"
    };
    query = generate_fallback_query(profile);
    assert query["search"] == "Cryptanalyst";
    assert query["location"] == "Remote";
    assert query["salary"] == 150000;
    assert query["contract_type"] == "Full-time";
    assert query["source"] == "all";
}

test "generate_job_search_params uses DeepSeek API when mock response is received" {
    mock_resp_json = json.dumps({
        "choices": [
            {
                "message": {
                    "content": json.dumps({
                        "search": "Senior Python Backend Engineer",
                        "location": "Remote",
                        "salary": 140000,
                        "contract_type": "Full-time",
                        "company": None,
                        "source": "all"
                    })
                }
            }
        ]
    }).encode("utf-8");

    mock_resp = MagicMock();
    mock_resp.read.return_value = mock_resp_json;
    mock_resp.__enter__.return_value = mock_resp;

    with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test_deepseek_key_123"}) {
        with patch("urllib.request.urlopen", return_value=mock_resp) {
            profile = {
                "first_name": "Guido",
                "last_name": "van Rossum",
                "location": "Remote",
                "sector": "Technology",
                "job_titles": "Python Developer",
                "salary_min": 140000,
                "contract_type": "Full-time"
            };
            params = generate_job_search_params(profile);
            assert params["search"] == "Senior Python Backend Engineer";
            assert params["location"] == "Remote";
            assert params["salary"] == 140000;
            assert params["source"] == "all";
        }
    }
}

test "submit_profile_and_generate_query saves resume and caches query in database" {
    conn = make_test_db();
    test_user_email = "onboarding_test@example.com";
    try {
        register_user(name="Onboarding User", email=test_user_email, password="password123", conn=conn);
    } except Exception {}

    result = submit_profile_and_generate_query(
        email=test_user_email,
        first_name="Onboarding",
        last_name="User",
        location="Chicago, IL",
        sector="Technology & Software",
        job_titles="Frontend Engineer, React Developer",
        salary_min=110000,
        contract_type="Full-time",
        resume_title="MyResume.pdf",
        resume_content="Skills: React, TypeScript, Tailwind CSS, JavaScript",
        conn=conn
    );

    assert result["ok"] is True;
    assert "cached_query" in result;
    cached = result["cached_query"];
    assert "search" in cached;
    assert cached["search"] == "Frontend Engineer";
    assert cached["salary"] == 110000;

    user = result["user"];
    assert user is not None;
    assert user["onboarding_completed"] == 1;

    # Verify profile data endpoint
    prof_data = get_user_profile_data(email=test_user_email, conn=conn);
    assert prof_data["ok"] is True;
    assert prof_data["onboarding_completed"] is True;
    assert prof_data["cached_query"] is not None;
    assert prof_data["cached_query"]["search"] == "Frontend Engineer";
}

test "submit_profile_and_generate_query auto-provisions non-existent user instead of erroring" {
    conn = make_test_db();
    brand_new_email = "auto_provisioned_google_user@example.com";
    result = submit_profile_and_generate_query(
        email=brand_new_email,
        first_name="Auto",
        last_name="Provisioned",
        location="Austin, TX",
        sector="Technology & Software",
        job_titles="DevOps Engineer",
        salary_min=135000,
        contract_type="Full-time",
        conn=conn
    );

    assert result["ok"] is True;
    assert "cached_query" in result;
    user = result["user"];
    assert user is not None;
    assert user["email"] == brand_new_email;
    assert user["first_name"] == "Auto";
    assert user["last_name"] == "Provisioned";
    assert user["location"] == "Austin, TX";
    assert user["onboarding_completed"] == 1;

    # Verify DB user is created and retrievable
    db_u = get_user_by_email(brand_new_email, conn=conn);
    assert db_u is not None;
    assert db_u["first_name"] == "Auto";
}

test "get_user_profile_data returns synthetic profile for unknown user without failing" {
    prof_data = get_user_profile_data(email=None, token="");
    assert prof_data["ok"] is True;
    assert prof_data["user"] is not None;
    assert prof_data["onboarding_completed"] is False;
}

test "get_user_tailored_jobs retrieves tailored jobs for onboarded user" {
    conn = make_test_db();
    email = "tailored_jobs_test@example.com";
    try {
        register_user(name="Tailored User", email=email, password="password123", conn=conn);
    } except Exception {}

    # Submit profile to cache query
    submit_profile_and_generate_query(
        email=email,
        first_name="Tailored",
        last_name="User",
        location="Remote",
        sector="Technology & Software",
        job_titles="Backend Engineer",
        salary_min=120000,
        contract_type="Full-time",
        conn=conn
    );

    # Retrieve tailored jobs
    tailored = get_user_tailored_jobs(email=email, conn=conn);
    assert tailored["ok"] is True;
    assert tailored["tailored"] is True;
    assert tailored["query"] is not None;
    assert tailored["query"]["search"] == "Backend Engineer";
    assert len(tailored["jobs"]) > 0;
}

test "multi-select contract types, locations, and sectors are saved and retrievable" {
    conn = make_test_db();
    email = "multiselect_user@example.com";
    register_user(name="Multi User", email=email, password="password123", conn=conn);

    res = submit_profile_and_generate_query(
        email=email,
        first_name="Multi",
        last_name="User",
        location="Remote, Chicago, IL, Seattle, WA",
        sector="Technology & Software, Finance & Banking",
        job_titles="Full Stack Developer, Data Engineer",
        salary_min=115000,
        contract_type="Full-time, Contract",
        conn=conn
    );

    assert res["ok"] is True;
    prof_data = get_user_profile_data(email=email, conn=conn);
    assert prof_data["ok"] is True;
    u = prof_data["user"];
    assert "Remote" in u["location"] and "Chicago" in u["location"];
    assert "Technology & Software" in u["sector"] and "Finance & Banking" in u["sector"];
    assert "Full-time" in u["contract_type"] and "Contract" in u["contract_type"];
}

test "get_user_tailored_jobs matches listings with multi-select contract types and locations" {
    conn = make_test_db();
    email = "multi_tailored@example.com";
    register_user(name="Multi Tailored", email=email, password="password123", conn=conn);

    submit_profile_and_generate_query(
        email=email,
        first_name="Multi",
        last_name="Tailored",
        location="Remote, Chicago, IL",
        sector="Technology & Software",
        job_titles="Data Analyst",
        salary_min=80000,
        contract_type="Full-time, Contract",
        conn=conn
    );

    tailored = get_user_tailored_jobs(email=email, conn=conn);
    assert tailored["ok"] is True;
    assert len(tailored["jobs"]) > 0;
}

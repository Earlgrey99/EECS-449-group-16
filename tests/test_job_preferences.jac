"""Tests for services/job_preferences.jac and the state search in
services/locations.jac.

Run from the project root with:
    jac test tests/test_job_preferences.jac
"""

import sqlite3;
import from db { init_db, register_user, get_user_by_email, get_user_by_id }
import from services.job_preferences {
    empty_preferences,
    pick_allowed,
    clean_skill_list,
    _clean_preferences,
    _read_preferences,
    _save_preferences,
    ROLE_LEVELS,
    WORK_MODES
}
import from services.locations { search_cities, search_states }

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

test "users table has the job_preferences column" {
    conn = make_test_db();
    col_names = [c[1] for c in conn.execute("PRAGMA table_info(users);").fetchall()];
    assert "job_preferences" in col_names;
}

test "only allowed choices are kept, in the usual order" {
    picked = pick_allowed(["experienced", "Internship", "CEO", "internship"], ROLE_LEVELS);
    assert picked == ["Internship", "Experienced"];
    assert pick_allowed("Remote", WORK_MODES) == [];
    assert pick_allowed(None, WORK_MODES) == [];
}

test "extra skills are trimmed, de-duplicated and capped" {
    skills = clean_skill_list(["  React ", "react", "", "Machine   Learning", None, "x" * 100]);
    assert skills == ["React", "Machine Learning", "x" * 40];
    many = clean_skill_list([f"skill {i}" for i in range(50)]);
    assert len(many) == 30;
}

test "junk from the page becomes empty preferences" {
    assert _clean_preferences(None) == empty_preferences();
    assert _clean_preferences("hello") == empty_preferences();
    cleaned = _clean_preferences({"work_modes": ["Hybrid", "on the moon"], "company_sizes": ["large", "startup"], "extra": 1});
    assert cleaned["work_modes"] == ["Hybrid"];
    assert cleaned["company_sizes"] == ["Startup", "Large"];
    assert "extra" not in cleaned;
}

test "save then load job preferences" {
    conn = make_test_db();
    register_user(name="Ada", email="ada@example.com", password="password123", conn=conn);
    uid = int(get_user_by_email("ada@example.com", conn=conn)["id"]);

    # Nothing saved yet reads as empty.
    assert _read_preferences(get_user_by_id(uid, conn=conn)) == empty_preferences();

    saved = _save_preferences(uid, {
        "role_levels": ["New grad", "Internship"],
        "work_modes": ["Hybrid"],
        "company_sizes": ["Mid-size"],
        "extra_skills": ["Rust", "rust", "SQL"]
    }, conn=conn);
    assert saved["ok"];
    loaded = _read_preferences(get_user_by_id(uid, conn=conn));
    assert loaded["role_levels"] == ["Internship", "New grad"];
    assert loaded["work_modes"] == ["Hybrid"];
    assert loaded["company_sizes"] == ["Mid-size"];
    assert loaded["extra_skills"] == ["Rust", "SQL"];

    # Saving empty lists clears them.
    _save_preferences(uid, empty_preferences(), conn=conn);
    assert _read_preferences(get_user_by_id(uid, conn=conn)) == empty_preferences();
}

test "broken saved data reads as empty preferences" {
    assert _read_preferences({"job_preferences": "{not json"}) == empty_preferences();
    assert _read_preferences(None) == empty_preferences();
}

test "typing part of a state suggests the whole state" {
    assert search_states("Mich") == ["Michigan"];
    assert search_states("MI")[0] == "Michigan";
    assert search_states("new") == ["New Hampshire", "New Jersey", "New Mexico", "New York"];
    assert search_states("o") == [];

    results = search_cities("Mich", limit=10);
    assert "Michigan" in results;
    # States come before cities.
    assert results.index("Michigan") == 0;
    assert "Ohio" in search_cities("ohio", limit=5);
    assert "Wisconsin" in search_cities("wis", limit=5);
}

test "city search still works the same with no state match" {
    assert search_cities("", limit=5)[0] == "Remote";
    assert not any(c in ["Washington", "Michigan"] for c in search_cities("Seat", limit=5));
    assert any("Seattle" in c for c in search_cities("Seat", limit=5));
}

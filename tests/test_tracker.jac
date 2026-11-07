"""Unit tests for saved tracker applications."""

import sqlite3;
import from db { create_application, create_user, init_db }
import from services.tracker { _add_for, _list_for, _remove_for, _set_status_for }

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

def make_user(email: str, conn: any) -> int {
    return int(create_user(name="Test", email=email, conn=conn)["id"]);
}

test "tracker applications are saved and listed newest first" {
    conn = make_test_db();
    uid = make_user("a@example.com", conn);
    assert _list_for(uid, conn=conn)["applications"] == [];

    first = _add_for(uid, "Engineer", "Acme", "2026-11-04", "Backend role", 90000, "Interview", conn=conn);
    assert first["ok"] is True;
    row = first["application"];
    assert row["role"] == "Engineer";
    assert row["company"] == "Acme";
    assert row["date"] == "11-04-2026";
    assert row["description"] == "Backend role";
    assert row["pay"] == 90000;
    assert row["status"] == "Interview";

    _add_for(uid, "Analyst", "Beta", "2026-11-05", conn=conn);
    rows = _list_for(uid, conn=conn)["applications"];
    assert [r["role"] for r in rows] == ["Analyst", "Engineer"];
    assert rows[0]["status"] == "Applied";
    assert rows[0]["pay"] == 0;
    assert rows[0]["description"] == "None found";
}

test "tracker rejects incomplete applications" {
    conn = make_test_db();
    uid = make_user("a@example.com", conn);
    assert _add_for(uid, "", "Acme", "2026-11-04", conn=conn)["ok"] is False;
    assert _add_for(uid, "Engineer", " ", "2026-11-04", conn=conn)["ok"] is False;
    assert _add_for(uid, "Engineer", "Acme", "", conn=conn)["ok"] is False;
    assert _add_for(uid, "Engineer", "Acme", "11/04/2026", conn=conn)["ok"] is False;
    assert _add_for(uid, "Engineer", "Acme", "2026-11-04", pay=-1, conn=conn)["ok"] is False;
    assert _list_for(uid, conn=conn)["applications"] == [];
}

test "status changes save the status that was chosen" {
    conn = make_test_db();
    uid = make_user("a@example.com", conn);
    app_id = _add_for(uid, "Engineer", "Acme", "2026-11-04", conn=conn)["application"]["id"];
    for status in ["Interview", "Offer", "Rejected", "Withdrawn", "Applied"] {
        assert _set_status_for(uid, app_id, status, conn=conn)["application"]["status"] == status;
        assert _list_for(uid, conn=conn)["applications"][0]["status"] == status;
    }
    assert _set_status_for(uid, app_id, "Hired?", conn=conn)["ok"] is False;
}

test "one user cannot change or remove another user's application" {
    conn = make_test_db();
    owner = make_user("owner@example.com", conn);
    other = make_user("other@example.com", conn);
    app_id = _add_for(owner, "Engineer", "Acme", "2026-11-04", status="Offer", conn=conn)["application"]["id"];

    assert _list_for(other, conn=conn)["applications"] == [];
    assert _set_status_for(other, app_id, "Rejected", conn=conn)["ok"] is False;
    assert _remove_for(other, app_id, conn=conn)["ok"] is False;
    rows = _list_for(owner, conn=conn)["applications"];
    assert len(rows) == 1;
    assert rows[0]["status"] == "Offer";

    assert _remove_for(owner, app_id, conn=conn)["ok"] is True;
    assert _list_for(owner, conn=conn)["applications"] == [];
    assert _remove_for(owner, app_id, conn=conn)["ok"] is False;
}

test "older lowercase statuses display correctly" {
    conn = make_test_db();
    uid = make_user("a@example.com", conn);
    create_application(user_id=uid, job_title="Engineer", company="Acme", status="applied", conn=conn);
    rows = _list_for(uid, conn=conn)["applications"];
    assert rows[0]["status"] == "Applied";
}

test "init_db adds the pay column to an existing applications table" {
    conn = sqlite3.connect(":memory:");
    conn.execute("CREATE TABLE applications (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, job_title TEXT NOT NULL, company TEXT NOT NULL, status TEXT);");
    init_db(conn=conn);
    columns = [column[1] for column in conn.execute("PRAGMA table_info(applications);").fetchall()];
    assert "pay" in columns;
    init_db(conn=conn);
}

test "tracker keeps job links, skips duplicates, and rejects unsafe links" {
    conn = make_test_db();
    uid = make_user("a@example.com", conn);
    url = "https://jobs.example.com/1";
    first = _add_for(uid, "Engineer", "Acme", "2026-11-04", job_url=url, conn=conn);
    assert first["application"]["job_url"] == url;
    assert "already_tracked" not in first;

    same_url = _add_for(uid, "Software Engineer", "Acme Inc", "2026-11-05", job_url=url, conn=conn);
    assert same_url["already_tracked"] is True;
    same_job = _add_for(uid, "engineer", "ACME", "2026-11-05", conn=conn);
    assert same_job["already_tracked"] is True;
    different = _add_for(uid, "Engineer", "Acme", "2026-11-05", job_url="https://jobs.example.com/2", conn=conn);
    assert "already_tracked" not in different;
    assert len(_list_for(uid, conn=conn)["applications"]) == 2;

    unsafe = _add_for(uid, "Analyst", "Beta", "2026-11-05", job_url="javascript:alert(1)", conn=conn);
    assert unsafe["application"]["job_url"] == "";
}

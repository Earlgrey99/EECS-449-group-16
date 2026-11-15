"""Unit tests for saved tracker applications."""

import sqlite3;
import from unittest.mock { patch }
import from db { create_application, create_user, init_db }
import from services.tracker {
    _add_for,
    _edit_for,
    _list_for,
    _remove_for,
    _save_status_options_for,
    _set_status_for,
    _status_options_for,
    _user_id_for
}

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

def make_user(email: str, conn: any) -> int {
    return int(create_user(name="Test", email=email, conn=conn)["id"]);
}

test "tracker access initializes an account without completed onboarding" {
    incomplete_user = {"id": 42, "onboarding_completed": 0};
    with patch(
        "services.tracker._resolve_caller",
        return_value={"ok": True, "app_user": None, "email": "", "oauth_id": "google-user"}
    ) {
        with patch("services.tracker._sync_caller", return_value={"ok": True, "user": incomplete_user}) {
            result = _user_id_for("verified-session-token");
            assert result == {"ok": True, "user_id": 42};
        }
    }
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

test "tracker applications can be edited without changing another user's row" {
    conn = make_test_db();
    owner = make_user("owner@example.com", conn);
    other = make_user("other@example.com", conn);
    app_id = _add_for(owner, "Engineer", "Acme", "2026-11-04", "Old notes", 90000, "Applied", conn=conn)["application"]["id"];

    updated = _edit_for(owner, app_id, "Senior Engineer", "Acme Corp", "2026-11-05", "Updated notes", 105000, "Interview", conn=conn);
    assert updated["ok"] is True;
    assert updated["application"]["role"] == "Senior Engineer";
    assert updated["application"]["company"] == "Acme Corp";
    assert updated["application"]["date"] == "11-05-2026";
    assert updated["application"]["description"] == "Updated notes";
    assert updated["application"]["pay"] == 105000;
    assert updated["application"]["status"] == "Interview";

    assert _edit_for(other, app_id, "Other", "Company", "2026-11-05", "", 0, "Applied", conn=conn)["ok"] is False;
    assert _edit_for(owner, app_id, "Other", "Company", "bad-date", "", 0, "Applied", conn=conn)["ok"] is False;
}

test "tracker applications save and replace optional PDF attachments" {
    conn = make_test_db();
    uid = make_user("pdf@example.com", conn);
    pdf_content = "data:application/pdf;base64,JVBERi0xLjQgdGVzdA==";
    added = _add_for(
        uid,
        "Engineer",
        "Acme",
        "2026-11-04",
        resume_pdf_name="resume.pdf",
        resume_pdf_content=pdf_content,
        cover_letter_pdf_name="cover.pdf",
        cover_letter_pdf_content=pdf_content,
        conn=conn
    );
    assert added["ok"] is True;
    app_id = added["application"]["id"];
    assert added["application"]["resume"] == "resume.pdf";
    assert added["application"]["cover_letter"] == "cover.pdf";
    assert _list_for(uid, conn=conn)["applications"][0]["resume"] == "resume.pdf";

    replaced = _edit_for(
        uid, app_id, "Engineer", "Acme", "2026-11-04", "", 0, "Applied",
        resume_pdf_name="updated.pdf", resume_pdf_content=pdf_content,
        conn=conn
    );
    assert replaced["ok"] is True;
    assert replaced["application"]["resume"] == "updated.pdf";
    assert replaced["application"]["cover_letter"] == "cover.pdf";

    cleared = _edit_for(
        uid, app_id, "Engineer", "Acme", "2026-11-04", "", 0, "Applied",
        clear_resume_pdf=True, clear_cover_letter_pdf=True, conn=conn
    );
    assert cleared["ok"] is True;
    assert cleared["application"]["resume"] == "None found";
    assert cleared["application"]["cover_letter"] == "None found";
    assert _add_for(
        uid, "Bad PDF", "Acme", "2026-11-04",
        resume_pdf_name="resume.pdf",
        resume_pdf_content="data:application/pdf;base64,SGVsbG8=",
        conn=conn
    )["ok"] is False;
    assert _add_for(
        uid, "Wrong extension", "Acme", "2026-11-04",
        resume_pdf_name="resume.txt",
        resume_pdf_content=pdf_content,
        conn=conn
    )["ok"] is False;
}

test "tracker status options are customizable and cannot remove a status in use" {
    conn = make_test_db();
    owner = make_user("owner@example.com", conn);
    other = make_user("other@example.com", conn);
    app_id = _add_for(owner, "Engineer", "Acme", "2026-11-04", status="Applied", conn=conn)["application"]["id"];
    defaults = _status_options_for(owner, conn=conn);
    assert defaults[0] == {"name": "Applied", "color": "#64748b"};

    custom = [
        {"name": "Applied", "color": "#123456"},
        {"name": "Phone screen", "color": "#abcdef"}
    ];
    assert _save_status_options_for(owner, custom, conn=conn)["ok"] is True;
    assert _set_status_for(owner, app_id, "Phone screen", conn=conn)["ok"] is True;

    only_custom_in_use = [
        {"name": "Applied", "color": "#123456"},
        {"name": "Interview", "color": "#2563eb"}
    ];
    assert _save_status_options_for(owner, only_custom_in_use, conn=conn)["ok"] is False;
    assert _save_status_options_for(other, [{"name": "Hired", "color": "#abcdef"}], conn=conn)["ok"] is True;
    assert _status_options_for(other, conn=conn) == [{"name": "Hired", "color": "#abcdef"}];
    assert _status_options_for(owner, conn=conn)[1]["name"] == "Phone screen";
    assert _save_status_options_for(owner, [{"name": "Duplicate", "color": "#abcdef"}, {"name": "duplicate", "color": "#123456"}], conn=conn)["ok"] is False;
    assert _save_status_options_for(owner, [{"name": "Bad color", "color": "red"}], conn=conn)["ok"] is False;
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
    assert "resume_pdf_name" in columns;
    assert "resume_pdf_content" in columns;
    assert "cover_letter_pdf_name" in columns;
    assert "cover_letter_pdf_content" in columns;
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

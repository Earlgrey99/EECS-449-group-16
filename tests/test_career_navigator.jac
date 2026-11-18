"""Tests for persisted Career Navigator conversations."""

import sqlite3;
import from unittest.mock { patch }
import from db {
    create_user,
    delete_career_chat,
    get_career_chat,
    init_db,
    list_career_chat_messages,
    list_career_chats,
    save_career_chat_exchange
}
import from services.career_navigator {
    _job_search_request,
    _search_job_listings,
    _user_id_for,
    send_career_message
}

test "Career Navigator access initializes an account without completed onboarding" {
    incomplete_user = {"id": 42, "onboarding_completed": 0};
    with patch(
        "services.career_navigator._resolve_caller",
        return_value={"ok": True, "app_user": None, "email": "", "oauth_id": "google-user"}
    ) {
        with patch("services.career_navigator._sync_caller", return_value={"ok": True, "user": incomplete_user}) {
            result = _user_id_for("verified-session-token");
            assert result == {"ok": True, "user_id": 42};
        }
    }
}

test "Career Navigator recognizes job searches and extracts role and location" {
    request = _job_search_request(
        "Find entry-level data analyst jobs near Chicago, IL",
        "Biology",
        "Become a physician assistant"
    );
    assert request is not None;
    assert request["search"] == "entry-level data analyst";
    assert request["location"] == "Chicago, IL";

    education_question = _job_search_request(
        "What should I study to become a physician assistant?",
        "Biology",
        "Become a physician assistant"
    );
    assert education_question is None;
}

test "Career Navigator sends detected job searches to the listing service" {
    expected_jobs = [
        {
            "id": "job-1",
            "title": "Data Analyst",
            "company": "Cascade Health",
            "location": "Chicago, IL",
            "link": "https://example.com/jobs/1"
        }
    ];
    with patch(
        "services.career_navigator.search_jobs",
        return_value={"ok": True, "jobs": expected_jobs}
    ) as mock_search {
        result = _search_job_listings(
            "Find data analyst jobs in Chicago, IL",
            "Biology",
            "Become a physician assistant"
        );
        assert result["searched"] is True;
        assert result["jobs"] == expected_jobs;
        assert mock_search.called;
    }

    with patch("services.career_navigator.search_jobs") as mock_search {
        result = _search_job_listings(
            "How can I prepare for an interview?",
            "Biology",
            "Become a physician assistant"
        );
        assert result["searched"] is False;
        assert result["jobs"] == [];
        assert not mock_search.called;
    }
}

test "Career Navigator saves a Puter-generated AI response" {
    with patch(
        "services.career_navigator._user_id_for",
        return_value={"ok": True, "user_id": 42}
    ) {
        with patch(
            "services.career_navigator._search_job_listings",
            return_value={"searched": False, "jobs": []}
        ) {
            with patch(
                "services.career_navigator.save_career_chat_exchange",
                return_value=7
            ) as mock_save {
                result = send_career_message(
                    token="verified-session-token",
                    message="What careers connect biology and data?",
                    reply="Consider bioinformatics and clinical data analysis.",
                    major="Biology",
                    career_goal="Work with healthcare data"
                );
                assert result["ok"];
                assert result["chat_id"] == 7;
                assert result["reply"] == "Consider bioinformatics and clinical data analysis.";
                assert result["job_results"] == [];
                assert mock_save.called;
            }
        }
    }
}

test "Career Navigator rejects an empty Puter response before saving" {
    with patch(
        "services.career_navigator._user_id_for",
        return_value={"ok": True, "user_id": 42}
    ) {
        with patch("services.career_navigator.save_career_chat_exchange") as mock_save {
            result = send_career_message(
                token="verified-session-token",
                message="What careers connect biology and data?",
                reply="",
                major="Biology",
                career_goal="Work with healthcare data"
            );
            assert not result["ok"];
            assert "empty response" in result["error"];
            assert not mock_save.called;
        }
    }
}

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

def make_user(email: str, conn: any) -> int {
    return int(create_user(name="Student", email=email, conn=conn)["id"]);
}

test "Career Navigator saves a new chat and appends later exchanges" {
    conn = make_test_db();
    owner = make_user("student@example.com", conn);

    chat_id = save_career_chat_exchange(
        owner,
        None,
        "Career paths with biology",
        "Biology",
        "Become a physician assistant",
        "What roles should I explore?",
        "Consider clinical and research paths.",
        conn=conn
    );
    chat = get_career_chat(owner, chat_id, conn=conn);
    assert chat is not None;
    assert chat["major"] == "Biology";
    assert chat["career_goal"] == "Become a physician assistant";
    assert len(list_career_chats(owner, conn=conn)) == 1;
    assert [row["role"] for row in list_career_chat_messages(owner, chat_id, conn=conn)] == ["user", "assistant"];

    save_career_chat_exchange(
        owner,
        chat_id,
        "ignored title",
        "ignored major",
        "ignored goal",
        "How do I get experience?",
        "Look for internships and clinical volunteering.",
        conn=conn
    );
    rows = list_career_chat_messages(owner, chat_id, conn=conn);
    assert len(rows) == 4;
    assert rows[-2]["content"] == "How do I get experience?";
}

test "Career Navigator conversations are isolated by user and can be deleted" {
    conn = make_test_db();
    owner = make_user("owner@example.com", conn);
    other = make_user("other@example.com", conn);
    chat_id = save_career_chat_exchange(
        owner,
        None,
        "Explore engineering",
        "Physics",
        "Aerospace engineering",
        "What should I study?",
        "Start with math and physics.",
        conn=conn
    );

    assert get_career_chat(other, chat_id, conn=conn) is None;
    assert list_career_chat_messages(other, chat_id, conn=conn) == [];
    assert delete_career_chat(other, chat_id, conn=conn) is False;
    assert delete_career_chat(owner, chat_id, conn=conn) is True;
    assert get_career_chat(owner, chat_id, conn=conn) is None;
    assert list_career_chat_messages(owner, chat_id, conn=conn) == [];
}

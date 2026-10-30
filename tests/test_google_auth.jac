"""Unit tests for Google OAuth integration, schema migrations, and user sync."""

import base64;
import json;
import sqlite3;
import from db {
    init_db,
    create_user,
    get_user_by_id,
    get_user_by_email,
    get_user_by_oauth_id,
    sync_oauth_user,
    register_user
}
import from services.auth_sync { sync_user_session }

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

def make_dummy_jwt(payload: dict[str, any]) -> str {
    header = {"alg": "HS256", "typ": "JWT"};
    header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode("utf-8")).decode("utf-8").rstrip("=");
    payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8").rstrip("=");
    return f"{header_b64}.{payload_b64}.dummy_signature";
}

test "init_db provisions auth_provider and oauth_id columns and index" {
    conn = make_test_db();
    cols = conn.execute("PRAGMA table_info(users);").fetchall();
    col_names = [c[1] for c in cols];
    assert "auth_provider" in col_names;
    assert "oauth_id" in col_names;
    assert "password_hash" in col_names;

    # Running init_db again is idempotent (safe migration)
    init_db(conn=conn);
    cols2 = conn.execute("PRAGMA table_info(users);").fetchall();
    assert len(cols) == len(cols2);
}

test "create_user and get_user_by_oauth_id" {
    conn = make_test_db();
    user = create_user(
        name="Google Tester",
        email="googletest@example.com",
        phone=None,
        password_hash=None,
        auth_provider="google",
        oauth_id="google-sub-1001",
        conn=conn
    );
    assert user["name"] == "Google Tester";
    assert user["email"] == "googletest@example.com";
    assert user["auth_provider"] == "google";
    assert user["oauth_id"] == "google-sub-1001";
    assert user["password_hash"] is None;

    found = get_user_by_oauth_id("google-sub-1001", auth_provider="google", conn=conn);
    assert found is not None;
    assert found["id"] == user["id"];

    not_found = get_user_by_oauth_id("non-existent-sub", auth_provider="google", conn=conn);
    assert not_found is None;
}

test "sync_oauth_user provisions new user" {
    conn = make_test_db();
    synced = sync_oauth_user(
        email="newuser@gmail.com",
        name="New Google User",
        oauth_id="google-sub-2001",
        auth_provider="google",
        conn=conn
    );
    assert synced is not None;
    assert synced["email"] == "newuser@gmail.com";
    assert synced["name"] == "New Google User";
    assert synced["auth_provider"] == "google";
    assert synced["oauth_id"] == "google-sub-2001";
    assert "password_hash" not in synced;
}

test "sync_oauth_user subsequent login resolves to existing user without duplicates" {
    conn = make_test_db();
    first = sync_oauth_user(
        email="repeat@gmail.com",
        name="Repeat User",
        oauth_id="google-sub-3001",
        auth_provider="google",
        conn=conn
    );

    second = sync_oauth_user(
        email="repeat@gmail.com",
        name="Repeat User Updated",
        oauth_id="google-sub-3001",
        auth_provider="google",
        conn=conn
    );

    assert first["id"] == second["id"];
    total_users = conn.execute("SELECT COUNT(*) FROM users WHERE email = 'repeat@gmail.com'").fetchone()[0];
    assert total_users == 1;
}

test "sync_oauth_user links existing local account by email" {
    conn = make_test_db();
    local_user = register_user(
        name="Local User",
        email="shared@example.com",
        password="secretpassword",
        conn=conn
    );
    assert local_user["email"] == "shared@example.com";

    synced = sync_oauth_user(
        email="shared@example.com",
        name="Local User",
        oauth_id="google-sub-4001",
        auth_provider="google",
        conn=conn
    );

    assert synced["id"] == local_user["id"];
    user_in_db = get_user_by_id(local_user["id"], conn=conn);
    assert user_in_db["oauth_id"] == "google-sub-4001";
    assert user_in_db["auth_provider"] == "google";
    assert user_in_db["password_hash"] is not None;

    total_count = conn.execute("SELECT COUNT(*) FROM users WHERE email = 'shared@example.com'").fetchone()[0];
    assert total_count == 1;
}

test "sync_oauth_user validates email" {
    conn = make_test_db();
    threw = False;
    try {
        sync_oauth_user("", conn=conn);
    } except ValueError {
        threw = True;
    }
    assert threw;
}

test "services/auth_sync decodes JWT token and synchronizes user" {
    conn = make_test_db();
    jwt = make_dummy_jwt({
        "email": "tokenuser@gmail.com",
        "name": "Token User",
        "sub": "google-sub-5001"
    });

    res = sync_user_session(token=jwt, auth_provider="google", conn=conn);
    assert res["ok"] is True;
    user = res["user"];
    assert user["email"] == "tokenuser@gmail.com";
    assert user["name"] == "Token User";
    assert user["oauth_id"] == "google-sub-5001";
    assert user["auth_provider"] == "google";
}

test "services/auth_sync handles invalid or empty inputs" {
    res = sync_user_session(token="", email="");
    assert res["ok"] is False;
    assert "error" in res;
}

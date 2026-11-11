"""Unit tests for Google OAuth integration, schema migrations, and user sync."""

import base64;
import hashlib;
import hmac;
import json;
import secrets;
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
import from services.profile_llm { _email_for_caller, _load_profile, _submit_profile }
import from jaclang.scale.sso.oauth_session { complete_identity }
import from jaclang.scale.sso.provider { SSOUserInfo }
import from jaclang.server.identity.user_manager { UserManager }
import from services.auth_sync {
    _caller_from_identity,
    _find_app_user,
    _identity_from_account,
    _public_user,
    _resolve_caller,
    _sync_caller,
    _verified_identity
}

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

def b64url(raw: bytes) -> str {
    return base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=");
}

def make_forged_jwt(payload: dict[str, any], key: str | None = None) -> str {
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode("utf-8"));
    body = b64url(json.dumps(payload).encode("utf-8"));
    if key is None {
        return f"{header}.{body}.dummy_signature";
    }
    sig = hmac.new(key.encode("utf-8"), f"{header}.{body}".encode("ascii"), hashlib.sha256).digest();
    return f"{header}.{body}.{b64url(sig)}";
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

test "forged tokens never produce an identity" {
    claims = {"email": "victim@example.com", "sub": "victim", "user_id": "victim", "exp": 4102444800};
    assert _verified_identity(make_forged_jwt(claims)) is None;
    assert _verified_identity(make_forged_jwt(claims, key="not-the-server-signing-key")) is None;
    assert _verified_identity("") is None;
    assert _verified_identity(None) is None;
    assert _verified_identity("not.a.jwt") is None;
    assert _resolve_caller(make_forged_jwt(claims))["ok"] is False;
}

test "email comes from an email identity or an email-shaped username" {
    # jacSignup(email, password) stores the address as a username.
    signup = {"identities": [{"type": "username", "value_raw": "User@Example.com"}]};
    identity = _identity_from_account("u1", signup, []);
    assert identity["email"] == "user@example.com";

    plain_username = {"identities": [{"type": "username", "value_raw": "google_google_abc"}]};
    assert _identity_from_account("u1", plain_username, [])["email"] is None;

    both = {"identities": [
        {"type": "username", "value_raw": "other@example.com"},
        {"type": "email", "value_raw": "real@example.com"}
    ]};
    assert _identity_from_account("u1", both, [])["email"] == "real@example.com";
}

test "a password account cannot claim a row bound to a Google account" {
    conn = make_test_db();
    sync_oauth_user(email="gmail-user@example.com", name="G User", oauth_id="google-owner", auth_provider="google", conn=conn);

    squatter = {"user_id": "attacker", "email": "gmail-user@example.com"};
    caller = _caller_from_identity(squatter, conn=conn);
    assert caller["ok"] is False;
    assert "already linked" in caller["error"];

    owner = {"user_id": "google-owner", "email": None, "is_sso": True};
    assert _caller_from_identity(owner, conn=conn)["app_user"]["email"] == "gmail-user@example.com";
}

test "a Google account has no email, even with a self-edited profile" {
    spoofed = {"identities": [], "profile": {"sso": {"google": {"email": "victim@example.com", "first_name": "Goo"}}}};
    unlinked = _identity_from_account("u1", spoofed, []);
    assert unlinked["email"] is None;
    assert unlinked["is_sso"] is False;

    linked = _identity_from_account("u1", spoofed, [{"platform": "google", "external_id": "g1"}]);
    assert linked["email"] is None;
    assert linked["is_sso"] is True;
    assert linked["first_name"] == "Goo";
}

test "a Google account finds only the row bound to its own id" {
    conn = make_test_db();
    create_user(name="Victim", email="victim@example.com", conn=conn);
    newcomer = {"user_id": "google-user", "email": None, "is_sso": True, "name": "New User"};

    first = _caller_from_identity(newcomer, conn=conn);
    assert first["ok"] is True;
    assert first["app_user"] is None;
    assert first["email"] == "";
    assert first["oauth_id"] == "google-user";
    assert first["auth_provider"] == "google";
    assert _sync_caller(first, conn=conn) == {"ok": True, "user": None};

    # The email they supply cannot be someone else's.
    assert _email_for_caller(first, "victim@example.com", conn=conn)["ok"] is False;
    assert _email_for_caller(first, "not-an-email", conn=conn)["ok"] is False;
    assert _email_for_caller(first, "", conn=conn)["ok"] is False;
    chosen = _email_for_caller(first, "New@Example.com", conn=conn);
    assert chosen == {"ok": True, "email": "new@example.com"};

    _submit_profile(
        email=chosen["email"], first_name="New", oauth_id=first["oauth_id"],
        auth_provider=first["auth_provider"], conn=conn
    );
    again = _caller_from_identity(newcomer, conn=conn);
    assert again["app_user"]["email"] == "new@example.com";
    assert again["email"] == "new@example.com";
    assert _sync_caller(again, conn=conn)["user"]["onboarding_completed"] == 1;
    assert _load_profile(email=again["email"], identity=again, conn=conn)["onboarding_completed"] is True;

    # Once the row exists, a different supplied email changes nothing.
    assert _email_for_caller(again, "other@example.com", conn=conn)["email"] == "new@example.com";
}

test "a real Google sign-in resolves to a caller" {
    # Runs Jac's own SSO account code. Only Google's response is simulated.
    manager = UserManager();
    tag = secrets.token_hex(6);
    info = SSOUserInfo(
        email=f"g{tag}@gmail.com", external_id=f"google-{tag}", display_name="Goo User",
        first_name="Goo", last_name="User"
    );
    login = complete_identity(manager, info, "google");
    assert login.ok, login.error;

    conn = make_test_db();
    caller = _resolve_caller(login.token, conn=conn);
    assert caller["ok"] is True, caller;
    assert caller["email"] == "";
    assert caller["is_sso"] is True;
    assert caller["first_name"] == "Goo";
    assert caller["last_name"] == "User";
    assert caller["auth_provider"] == "google";
    assert caller["oauth_id"] == str(manager.validate_jwt_token(login.token));
}

test "email identities map to their own row and hide the password hash" {
    conn = make_test_db();
    register_user(name="Local", email="local@example.com", password="password123", conn=conn);
    identity = {"user_id": "jac-user", "email": "local@example.com", "name": "Local"};
    caller = _caller_from_identity(identity, conn=conn);
    assert caller["ok"] is True;
    assert caller["app_user"]["email"] == "local@example.com";
    assert "password_hash" not in _public_user(caller["app_user"]);
    synced = _sync_caller(caller, conn=conn);
    assert synced["ok"] is True;
    assert "password_hash" not in synced["user"];
}

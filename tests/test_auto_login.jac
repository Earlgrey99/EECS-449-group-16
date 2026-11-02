"""Unit tests for development auto-login profile and test user session generation."""

import datetime;
import os;
import sqlite3;
import from db {
    init_db,
    get_user_by_email,
    authenticate_user,
    ensure_test_user
}
import from services.auth_sync {
    is_test_profile,
    get_test_user_session
}
import from jaclang.project.config { get_config }
import from jaclang.server.identity.config { signing_secret, signing_algorithm }
import from jaclang.server.serving.authcrypt { jwt_decode }

def make_test_db -> any {
    conn = sqlite3.connect(":memory:");
    conn.execute("PRAGMA foreign_keys = ON;");
    init_db(conn=conn);
    return conn;
}

test "ensure_test_user provisions testuser@example.com" {
    conn = make_test_db();
    user = ensure_test_user(conn=conn);
    assert user is not None;
    assert user["email"] == "testuser@example.com";
    assert user["name"] == "Test User";
    assert user["auth_provider"] == "local";
    assert user["oauth_id"] == "testuser_dev";
    assert "password_hash" not in user;

    # Verify user exists in database
    db_user = get_user_by_email("testuser@example.com", conn=conn);
    assert db_user is not None;
    assert db_user["email"] == "testuser@example.com";
    assert db_user["id"] == user["id"];
}

test "ensure_test_user is idempotent" {
    conn = make_test_db();
    first = ensure_test_user(conn=conn);
    second = ensure_test_user(conn=conn);
    assert first["id"] == second["id"];

    total_count = conn.execute("SELECT COUNT(*) FROM users WHERE email = 'testuser@example.com'").fetchone()[0];
    assert total_count == 1;
}

test "test user can authenticate with default development password" {
    conn = make_test_db();
    ensure_test_user(conn=conn);

    # Correct password
    auth_res = authenticate_user("testuser@example.com", "testpassword123", conn=conn);
    assert auth_res is not None;
    assert auth_res["email"] == "testuser@example.com";
    assert auth_res["name"] == "Test User";
    assert "session_token" in auth_res;

    # Wrong password
    fail_res = authenticate_user("testuser@example.com", "wrongpassword", conn=conn);
    assert fail_res is None;
}

test "is_test_profile detects test profile and env override" {
    old_profile = os.environ.get("JAC_PROFILE");
    old_auto = os.environ.get("DEV_AUTO_LOGIN");

    try {
        if "JAC_PROFILE" in os.environ {
            del os.environ["JAC_PROFILE"];
        }
        if "DEV_AUTO_LOGIN" in os.environ {
            del os.environ["DEV_AUTO_LOGIN"];
        }

        # With env var set
        os.environ["DEV_AUTO_LOGIN"] = "1";
        assert is_test_profile() is True;

        del os.environ["DEV_AUTO_LOGIN"];
        os.environ["JAC_PROFILE"] = "test";
        assert is_test_profile() is True;

        del os.environ["JAC_PROFILE"];
        # Default without test profile
        cfg: any = get_config();
        if cfg and getattr(cfg, "active_profile", "") != "test" {
            assert is_test_profile() is False;
        }
    } finally {
        if old_profile is not None {
            os.environ["JAC_PROFILE"] = old_profile;
        } elif "JAC_PROFILE" in os.environ {
            del os.environ["JAC_PROFILE"];
        }
        if old_auto is not None {
            os.environ["DEV_AUTO_LOGIN"] = old_auto;
        } elif "DEV_AUTO_LOGIN" in os.environ {
            del os.environ["DEV_AUTO_LOGIN"];
        }
    }
}

test "get_test_user_session rejects requests when not in test profile" {
    conn = make_test_db();
    old_profile = os.environ.get("JAC_PROFILE");
    old_auto = os.environ.get("DEV_AUTO_LOGIN");

    try {
        if "JAC_PROFILE" in os.environ {
            del os.environ["JAC_PROFILE"];
        }
        if "DEV_AUTO_LOGIN" in os.environ {
            del os.environ["DEV_AUTO_LOGIN"];
        }

        cfg: any = get_config();
        if cfg and getattr(cfg, "active_profile", "") != "test" {
            res = get_test_user_session(conn=conn);
            assert res["ok"] is False;
            assert "error" in res;
            assert "only available in test profile" in res["error"];
        }
    } finally {
        if old_profile is not None {
            os.environ["JAC_PROFILE"] = old_profile;
        }
        if old_auto is not None {
            os.environ["DEV_AUTO_LOGIN"] = old_auto;
        }
    }
}

test "get_test_user_session generates signed JWT session in test profile" {
    conn = make_test_db();
    old_auto = os.environ.get("DEV_AUTO_LOGIN");

    try {
        os.environ["DEV_AUTO_LOGIN"] = "1";
        res = get_test_user_session(conn=conn);
        assert res["ok"] is True;
        assert "token" in res;
        assert "user" in res;

        user = res["user"];
        assert user["email"] == "testuser@example.com";
        assert user["name"] == "Test User";

        token = res["token"];
        assert token and len(token) > 20;

        # Validate JWT token claims and signature
        sec = "eecs449-group16-dev-secret-key-32chars";
        algo = "HS256";
        try {
            resolved_sec = signing_secret();
            if resolved_sec {
                sec = resolved_sec;
            }
            resolved_algo = signing_algorithm();
            if resolved_algo {
                algo = resolved_algo;
            }
        } except Exception {}

        claims = jwt_decode(token, sec, algorithms=[algo]);
        assert claims is not None;
        assert claims.get("email") == "testuser@example.com";
        assert claims.get("preferred_username") == "Test User";
        assert claims.get("sub") == str(user["id"]);
    } finally {
        if old_auto is not None {
            os.environ["DEV_AUTO_LOGIN"] = old_auto;
        } elif "DEV_AUTO_LOGIN" in os.environ {
            del os.environ["DEV_AUTO_LOGIN"];
        }
    }
}

test "jac.test.toml profile overlay activates test profile" {
    cfg: any = get_config();
    assert cfg is not None;
    cfg.apply_profile_overlay("test");
    assert cfg.active_profile == "test";
    assert is_test_profile() is True;
}

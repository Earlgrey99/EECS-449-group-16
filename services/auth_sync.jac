"""Service for syncing authenticated OAuth user sessions with the application database."""

import datetime;
import os;
import from db { init_db, sync_oauth_user, get_user_by_oauth_id, get_user_by_email, ensure_test_user }
import from jaclang.project.config { get_config }
import from jaclang.server.identity.config { signing_secret, signing_algorithm }
import from jaclang.server.identity.user_manager { UserManager }
import from jaclang.server.serving.authcrypt { jwt_encode }

glob schema_ready: bool = False;

"""Create the tables on first use, so a new database works without running db-init."""
def _ensure_schema {
    if not schema_ready {
        init_db();
        schema_ready = True;
    }
}

def is_test_profile -> bool {
    if os.environ.get("JAC_PROFILE") == "test" or os.environ.get("DEV_AUTO_LOGIN") == "1" {
        return True;
    }
    try {
        cfg: any = get_config();
        if cfg {
            if str(cfg?.active_profile) == "test" {
                return True;
            }
            auth_cfg: any = cfg?.serve?.auth;
            if isinstance(auth_cfg, dict) and bool(auth_cfg.get("auto_login")) {
                return True;
            }
            if auth_cfg and bool(auth_cfg?.auto_login) {
                return True;
            }
        }
    } except Exception {
        # Config lookup fallback
    }
    return False;
}

def _test_user_session(conn: any = None) -> dict[str, any] {
    if not is_test_profile() {
        return {"ok": False, "error": "Auto-login is only available in test profile."};
    }
    try {
        user = ensure_test_user(conn=conn);
        now = datetime.datetime.now(datetime.timezone.utc);
        payload = {
            "sub": str(user.get("id", "testuser")),
            "user_id": str(user.get("id", "testuser")),
            "exp": int((now + datetime.timedelta(days=7)).timestamp()),
            "iat": int(now.timestamp()),
            "preferred_username": user.get("name", "Test User"),
            "email": user.get("email", "testuser@example.com")
        };
        token = jwt_encode(payload, signing_secret(), algorithm=signing_algorithm());
        return {
            "ok": True,
            "token": token,
            "user": user
        };
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
}

def:pub get_test_user_session -> dict[str, any] {
    return _test_user_session();
}

"""Build a caller identity from a verified Jac account.

jacSignup(email, password) stores the address as a username, so a username holding
an email counts as an email. Jac allows one account per identity value, but signup
does not verify addresses: _find_app_user is what protects Google-owned rows.

Jac does not store the email from a Google sign-in, and users can edit their own
profile, so a Google account is identified by its Jac user id and has no email here.
"""
def _identity_from_account(
    user_id: str,
    account: dict[str, any],
    sso_accounts: list[dict[str, str]]
) -> dict[str, any] {
    res: dict[str, any] = {
        "user_id": user_id,
        "email": None,
        "is_sso": bool(sso_accounts),
        "first_name": None,
        "last_name": None,
        "name": None
    };
    found_email: str = "";
    for wanted in ["email", "username"] {
        for ident in account.get("identities") or [] {
            if not found_email and isinstance(ident, dict) and ident.get("type") == wanted {
                val = str(ident.get("value_raw") or ident.get("value_normalized") or "");
                if "@" in val {
                    found_email = val.strip().lower();
                }
            }
        }
    }
    if found_email {
        res["email"] = found_email;
    }

    profiles = (account.get("profile") or {}).get("sso") or {};
    if not isinstance(profiles, dict) {
        profiles = {};
    }
    for linked in sso_accounts {
        data = profiles.get(str(linked.get("platform", "")));
        if not isinstance(data, dict) {
            continue;
        }
        if not res["first_name"] and data.get("first_name") {
            res["first_name"] = str(data["first_name"]).strip();
        }
        if not res["last_name"] and data.get("last_name") {
            res["last_name"] = str(data["last_name"]).strip();
        }
        if not res["name"] and data.get("display_name") {
            res["name"] = str(data["display_name"]).strip();
        }
    }

    if res["name"] and not res["first_name"] and not res["last_name"] {
        parts = str(res["name"]).split(" ", 1);
        res["first_name"] = parts[0].strip();
        if len(parts) > 1 {
            res["last_name"] = parts[1].strip();
        }
    }
    return res;
}

"""Return the identity for a validly signed session token, or None."""
def _verified_identity(token: str | None) -> dict[str, any] | None {
    if not token or not str(token).strip() {
        return None;
    }
    manager = UserManager();
    detail = manager.validate_jwt_token_detail(str(token).strip(), check_existence=True);
    if detail.get("status") != "ok" {
        return None;
    }
    user_id = str(detail["user_id"]);
    account = manager.get_user(user_id);
    if not account or account.get("status", "active") != "active" {
        return None;
    }
    return _identity_from_account(user_id, account, manager.get_sso_accounts(user_id));
}

"""Find the app database row that belongs to this identity.

A Google account owns only the row bound to its Jac user id. A row bound to a Google
account belongs to that account alone, because anyone can register a password account
using an unclaimed address.
"""
def _find_app_user(identity: dict[str, any], conn: any = None) -> dict[str, any] | None {
    user_id = str(identity["user_id"]);
    if identity.get("is_sso") and not identity.get("email") {
        return get_user_by_oauth_id(user_id, auth_provider="google", conn=conn);
    }
    row = get_user_by_email(str(identity.get("email") or ""), conn=conn);
    if row and row.get("auth_provider") == "google" and row.get("oauth_id") and str(row["oauth_id"]) != user_id {
        raise PermissionError("This email is already linked to another account.");
    }
    return row;
}

"""Resolve the caller from a session token. This is the only source of user identity.

Returns {"ok": True, "email", "oauth_id", "auth_provider", "app_user", ...} or
{"ok": False, "error"}. Endpoints must not use an email or user id from the client to
choose a user. "email" is "" for a Google user who has not completed onboarding.
"""
def _resolve_caller(token: str | None, conn: any = None) -> dict[str, any] {
    identity = _verified_identity(token);
    if identity is None {
        return {"ok": False, "error": "Not authenticated."};
    }
    if not identity.get("email") and not identity.get("is_sso") {
        return {"ok": False, "error": "Not authenticated."};
    }
    if conn is None {
        _ensure_schema();
    }
    return _caller_from_identity(identity, conn);
}

def _caller_from_identity(identity: dict[str, any], conn: any = None) -> dict[str, any] {
    try {
        app_user = _find_app_user(identity, conn=conn);
    } except PermissionError as e {
        return {"ok": False, "error": str(e)};
    }
    is_sso = bool(identity.get("is_sso")) and not identity.get("email");
    return {
        **identity,
        "ok": True,
        "email": str(app_user["email"]) if app_user else str(identity.get("email") or ""),
        "oauth_id": str(identity["user_id"]) if is_sso else None,
        "auth_provider": "google" if is_sso else "local",
        "app_user": app_user
    };
}

"""Return a user row without its password hash, for sending to the client."""
def _public_user(user: dict[str, any] | None) -> dict[str, any] | None {
    if user is None {
        return None;
    }
    clean = dict(user);
    clean.pop("password_hash", None);
    return clean;
}

def _sync_caller(caller: dict[str, any], conn: any = None) -> dict[str, any] {
    # A Google user gets a row during onboarding, once they provide an email.
    if not caller.get("email") {
        return {"ok": True, "user": None};
    }
    try {
        user = sync_oauth_user(
            email=str(caller["email"]),
            name=str(caller["name"]) if caller.get("name") else None,
            oauth_id=caller.get("oauth_id"),
            auth_provider=str(caller.get("auth_provider") or "local"),
            conn=conn
        );
        return {"ok": True, "user": _public_user(user)};
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
}

def:protect sync_user_session(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    return _sync_caller(caller);
}

"""Service for syncing authenticated OAuth user sessions with the application database."""

import base64;
import datetime;
import json;
import os;
import from db { sync_oauth_user, get_user_by_oauth_id, get_user_by_email, ensure_test_user }
import from jaclang.project.config { get_config }
import from jaclang.server.identity.config { signing_secret, signing_algorithm }
import from jaclang.server.identity.user_manager { UserManager }
import from jaclang.server.serving.authcrypt { jwt_encode }

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

def:pub get_test_user_session(conn: any = None) -> dict[str, any] {
    if not is_test_profile() {
        return {"ok": False, "error": "Auto-login is only available in test profile."};
    }
    try {
        actual_conn = conn if (conn is not None and not isinstance(conn, str)) else None;
        user = ensure_test_user(conn=actual_conn);
        now = datetime.datetime.now(datetime.timezone.utc);
        payload = {
            "sub": str(user.get("id", "testuser")),
            "user_id": str(user.get("id", "testuser")),
            "exp": int((now + datetime.timedelta(days=7)).timestamp()),
            "iat": int(now.timestamp()),
            "preferred_username": user.get("name", "Test User"),
            "email": user.get("email", "testuser@example.com")
        };
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
        } except Exception {
            # Use defaults
        }
        token = jwt_encode(payload, sec, algorithm=algo);
        return {
            "ok": True,
            "token": token,
            "user": user
        };
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
}

def:pub resolve_token_identity(token: str) -> dict[str, any] {
    res: dict[str, any] = {
        "user_id": None,
        "email": None,
        "first_name": None,
        "last_name": None,
        "name": None
    };
    if not token or not token.strip() {
        return res;
    }
    claims: dict[str, any] = {};
    try {
        parts = token.strip().split(".");
        if len(parts) >= 2 {
            raw = parts[1];
            padded = raw + ("=" * ((4 - len(raw) % 4) % 4));
            claims = json.loads(base64.urlsafe_b64decode(padded.encode("utf-8")).decode("utf-8"));
        }
    } except Exception {}

    user_id = claims.get("user_id") or claims.get("sub");
    if user_id {
        res["user_id"] = str(user_id);
    }

    # Inspect direct claims
    for k in ["email", "email_address", "upn"] {
        v = claims.get(k);
        if v and "@" in str(v) {
            res["email"] = str(v).strip().lower();
            break;
        }
    }

    pref = claims.get("preferred_username");
    if pref and "@" in str(pref) and not res["email"] {
        res["email"] = str(pref).strip().lower();
    }

    if claims.get("given_name") {
        res["first_name"] = str(claims["given_name"]).strip();
    }
    if claims.get("family_name") {
        res["last_name"] = str(claims["family_name"]).strip();
    }
    if claims.get("name") {
        res["name"] = str(claims["name"]).strip();
    } elif pref and "@" not in str(pref) and not str(pref).startswith("google_google_") {
        res["name"] = str(pref).strip();
    }

    # Inspect Jac UserManager if available
    if user_id {
        try {
            um = UserManager();
            jac_user = um.get_user(str(user_id));
            if jac_user {
                prof = jac_user.get("profile") or {};
                sso_prof = prof.get("sso") or {};
                for (prov, p_data) in sso_prof.items() {
                    if isinstance(p_data, dict) {
                        if not res["first_name"] and p_data.get("first_name") {
                            res["first_name"] = str(p_data["first_name"]).strip();
                        }
                        if not res["last_name"] and p_data.get("last_name") {
                            res["last_name"] = str(p_data["last_name"]).strip();
                        }
                        if not res["name"] and p_data.get("display_name") {
                            res["name"] = str(p_data["display_name"]).strip();
                        }
                        if not res["email"] and p_data.get("email") and "@" in str(p_data.get("email")) {
                            res["email"] = str(p_data["email"]).strip().lower();
                        }
                    }
                }
                for ident in jac_user.get("identities", []) {
                    if isinstance(ident, dict) and ident.get("type") == "email" {
                        val = ident.get("value_raw") or ident.get("value_normalized");
                        if val and "@" in str(val) and not res["email"] {
                            res["email"] = str(val).strip().lower();
                        }
                    }
                }
            }
        } except Exception {}
    }

    if res["name"] and not res["first_name"] and not res["last_name"] {
        n_str = str(res["name"]).strip();
        if " " in n_str {
            n_parts = n_str.split(" ", 1);
            res["first_name"] = n_parts[0].strip();
            res["last_name"] = n_parts[1].strip();
        } else {
            res["first_name"] = n_str;
        }
    }

    return res;
}

def:pub sync_user_session(
    token: str = "",
    email: str | None = None,
    name: str | None = None,
    oauth_id: str | None = None,
    auth_provider: str = "google",
    conn: any = None
) -> dict[str, any] {
    resolved_email = email;
    resolved_name = name;
    resolved_oauth_id = oauth_id;

    if token {
        info = resolve_token_identity(token);
        if not resolved_email and info.get("email") {
            resolved_email = info["email"];
        }
        if not resolved_name and info.get("name") {
            resolved_name = info["name"];
        }
        if not resolved_oauth_id and info.get("user_id") {
            resolved_oauth_id = info["user_id"];
        }
    }

    if resolved_oauth_id and not resolved_email {
        try {
            existing = get_user_by_oauth_id(str(resolved_oauth_id), auth_provider=auth_provider, conn=conn);
            if existing is not None {
                return {"ok": True, "user": existing};
            }
        } except Exception {}
    }

    if not resolved_email or not str(resolved_email).strip() or "@" not in str(resolved_email) {
        return {"ok": False, "error": "Email is required to sync user."};
    }

    try {
        user = sync_oauth_user(
            email=str(resolved_email),
            name=str(resolved_name) if resolved_name else None,
            oauth_id=str(resolved_oauth_id) if resolved_oauth_id else None,
            auth_provider=auth_provider,
            conn=conn
        );
        return {"ok": True, "user": user};
    } except Exception as e {
        return {"ok": False, "error": str(e)};
    }
}

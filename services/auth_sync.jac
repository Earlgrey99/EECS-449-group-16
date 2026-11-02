"""Service for syncing authenticated OAuth user sessions with the application database."""

import base64;
import datetime;
import json;
import os;
import from db { sync_oauth_user, get_user_by_oauth_id, get_user_by_email, ensure_test_user }
import from jaclang.project.config { get_config }
import from jaclang.server.identity.config { signing_secret, signing_algorithm }
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

    if token and not resolved_email {
        try {
            parts = token.split(".");
            if len(parts) >= 2 {
                payload_raw = parts[1];
                padded = payload_raw + ("=" * ((4 - len(payload_raw) % 4) % 4));
                decoded_bytes = base64.urlsafe_b64decode(padded.encode("utf-8"));
                claims = json.loads(decoded_bytes.decode("utf-8"));
                resolved_email = claims.get("email") or claims.get("preferred_username") or claims.get("sub");
                resolved_name = claims.get("name") or claims.get("preferred_username") or (str(resolved_email).split("@")[0] if resolved_email else None);
                resolved_oauth_id = claims.get("sub") or claims.get("user_id");
            }
        } except Exception {
            # Continue with whatever values were supplied
        }
    }

    if not resolved_email or not str(resolved_email).strip() {
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

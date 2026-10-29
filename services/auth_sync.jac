"""Service for syncing authenticated OAuth user sessions with the application database."""

import base64;
import json;
import from db { sync_oauth_user, get_user_by_oauth_id, get_user_by_email }

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

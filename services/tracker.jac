"""Saved job applications for the tracker page.

Every endpoint acts only on the signed-in user's rows, found from their verified token.
"""

import from db {
    create_application,
    delete_application,
    get_application_by_id,
    list_applications_by_user,
    update_application
}
import from .auth_sync { _resolve_caller, _sync_caller }

glob TRACKER_STATUSES: list[str] = ["Applied", "Interview", "Offer", "Rejected", "Withdrawn"];
glob MAX_TEXT: int = 500;

def _clean_status(status: any) -> str {
    value = str(status or "").strip().capitalize();
    return value if value in TRACKER_STATUSES else "Applied";
}

def _display_date(iso_date: any) -> str {
    parts = str(iso_date or "").split("-");
    return f"{parts[1]}-{parts[2]}-{parts[0]}" if len(parts) == 3 else str(iso_date or "");
}

def _to_row(app: dict[str, any]) -> dict[str, any] {
    return {
        "id": int(app["id"]),
        "role": str(app.get("job_title") or ""),
        "company": str(app.get("company") or ""),
        "date": _display_date(app.get("applied_date")),
        "description": str(app.get("notes") or "None found"),
        "pay": int(app.get("pay") or 0),
        "resume": "None found",
        "cover_letter": "None found",
        "status": _clean_status(app.get("status"))
    };
}

def _is_iso_date(value: str) -> bool {
    parts = value.split("-");
    return len(parts) == 3 and len(parts[0]) == 4 and all([part.isdigit() for part in parts]);
}

def _list_for(user_id: int, conn: any = None) -> dict[str, any] {
    apps = list_applications_by_user(user_id, conn=conn);
    return {"ok": True, "applications": [_to_row(app) for app in reversed(apps)]};
}

def _add_for(
    user_id: int,
    role: str,
    company: str,
    applied_date: str,
    description: str = "",
    pay: int | None = None,
    status: str = "Applied",
    conn: any = None
) -> dict[str, any] {
    clean_role = str(role or "").strip()[:MAX_TEXT];
    clean_company = str(company or "").strip()[:MAX_TEXT];
    clean_date = str(applied_date or "").strip();
    if not clean_role or not clean_company or not _is_iso_date(clean_date) {
        return {"ok": False, "error": "Company, job title, and application date are required."};
    }
    if pay is not None and int(pay) < 0 {
        return {"ok": False, "error": "Pay available must be a whole number."};
    }
    app = create_application(
        user_id=user_id,
        job_title=clean_role,
        company=clean_company,
        status=_clean_status(status),
        applied_date=clean_date,
        notes=str(description or "").strip()[:MAX_TEXT] or None,
        pay=int(pay) if pay is not None else None,
        conn=conn
    );
    return {"ok": True, "application": _to_row(app)};
}

def _owned_application(user_id: int, app_id: int, conn: any = None) -> dict[str, any] | None {
    app = get_application_by_id(int(app_id), conn=conn);
    if app is None or int(app["user_id"]) != user_id {
        return None;
    }
    return app;
}

def _set_status_for(user_id: int, app_id: int, status: str, conn: any = None) -> dict[str, any] {
    if _owned_application(user_id, app_id, conn=conn) is None {
        return {"ok": False, "error": "Application not found."};
    }
    if status not in TRACKER_STATUSES {
        return {"ok": False, "error": "Unknown status."};
    }
    updated = update_application(int(app_id), status=status, conn=conn);
    return {"ok": True, "application": _to_row(updated)} if updated else {"ok": False, "error": "Application not found."};
}

def _remove_for(user_id: int, app_id: int, conn: any = None) -> dict[str, any] {
    if _owned_application(user_id, app_id, conn=conn) is None {
        return {"ok": False, "error": "Application not found."};
    }
    delete_application(int(app_id), conn=conn);
    return {"ok": True};
}

"""Find the caller's app user id, creating the row for a new password account."""
def _user_id_for(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    user = caller["app_user"];
    if user is None {
        synced = _sync_caller(caller);
        if not synced["ok"] {
            return synced;
        }
        user = synced["user"];
    }
    if user is None {
        return {"ok": False, "error": "Finish your profile to use the tracker."};
    }
    return {"ok": True, "user_id": int(user["id"])};
}

def:protect list_tracker_applications(token: str) -> dict[str, any] {
    found = _user_id_for(token);
    return _list_for(found["user_id"]) if found["ok"] else found;
}

def:protect add_tracker_application(
    token: str,
    role: str,
    company: str,
    applied_date: str,
    description: str,
    pay: int | None,
    status: str
) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    return _add_for(found["user_id"], role, company, applied_date, description, pay, status);
}

def:protect set_tracker_status(token: str, app_id: int, status: str) -> dict[str, any] {
    found = _user_id_for(token);
    return _set_status_for(found["user_id"], app_id, status) if found["ok"] else found;
}

def:protect remove_tracker_application(token: str, app_id: int) -> dict[str, any] {
    found = _user_id_for(token);
    return _remove_for(found["user_id"], app_id) if found["ok"] else found;
}

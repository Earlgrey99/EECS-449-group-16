"""Saved job applications for the tracker page.

Every endpoint acts only on the signed-in user's rows, found from their verified token.
"""

import base64;
import binascii;
import from db {
    create_application,
    delete_application,
    get_application_by_id,
    list_tracker_status_options,
    list_applications_by_user,
    replace_tracker_status_options,
    update_application
}
import from .auth_sync { _resolve_caller, _sync_caller }
import from .jobs { _extract_salary_values }

glob DEFAULT_STATUS_OPTIONS: list[dict[str, str]] = [
    {"name": "Applied", "color": "#64748b"},
    {"name": "Interview", "color": "#2563eb"},
    {"name": "Offer", "color": "#16a34a"},
    {"name": "Rejected", "color": "#dc2626"},
    {"name": "Withdrawn", "color": "#78716c"}
];
glob MAX_TEXT: int = 500;
glob MAX_PDF_BYTES: int = 2097152;

def _status_options_for(user_id: int, conn: any = None) -> list[dict[str, str]] {
    saved = list_tracker_status_options(user_id, conn=conn);
    return saved if saved else DEFAULT_STATUS_OPTIONS;
}

def _clean_status(status: any, options: list[dict[str, str]]) -> str {
    value = str(status or "").strip();
    for option in options {
        if value.lower() == option["name"].lower() {
            return option["name"];
        }
    }
    return "Applied";
}

def _is_valid_status(status: any, options: list[dict[str, str]]) -> bool {
    value = str(status or "").strip().lower();
    return any([value == option["name"].lower() for option in options]);
}

def _display_date(iso_date: any) -> str {
    parts = str(iso_date or "").split("-");
    return f"{parts[1]}-{parts[2]}-{parts[0]}" if len(parts) == 3 else str(iso_date or "");
}

def _to_row(app: dict[str, any], options: list[dict[str, str]]) -> dict[str, any] {
    return {
        "id": int(app["id"]),
        "role": str(app.get("job_title") or ""),
        "company": str(app.get("company") or ""),
        "date": _display_date(app.get("applied_date")),
        "description": str(app.get("notes") or "None found"),
        "pay": int(app.get("pay") or 0),
        "job_url": str(app.get("job_url") or ""),
        "resume": str(app.get("resume_pdf_name") or "None found"),
        "cover_letter": str(app.get("cover_letter_pdf_name") or "None found"),
        "status": _clean_status(app.get("status"), options)
    };
}

def _validated_pdf(name: any, content: any) -> dict[str, any] {
    clean_name = str(name or "").strip().split("/")[-1].split("\\")[-1][:120];
    clean_content = str(content or "").strip();
    if not clean_name and not clean_content {
        return {"ok": True, "name": "", "content": ""};
    }
    if not clean_name.lower().endswith(".pdf") or not clean_content.startswith("data:application/pdf;base64,") {
        return {"ok": False, "error": "Choose a PDF file for each attachment."};
    }
    encoded = clean_content.split(",", 1)[1];
    if len(encoded) > 2800000 {
        return {"ok": False, "error": "Each PDF must be 2 MB or smaller."};
    }
    try {
        decoded = base64.b64decode(encoded, validate=True);
    } except binascii.Error {
        return {"ok": False, "error": "The selected PDF could not be read."};
    }
    if len(decoded) > MAX_PDF_BYTES {
        return {"ok": False, "error": "Each PDF must be 2 MB or smaller."};
    }
    if not decoded.startswith(b"%PDF-") {
        return {"ok": False, "error": "The selected file is not a valid PDF."};
    }
    return {"ok": True, "name": clean_name, "content": clean_content};
}

def _is_iso_date(value: str) -> bool {
    parts = value.split("-");
    return len(parts) == 3 and len(parts[0]) == 4 and all([part.isdigit() for part in parts]);
}

"""Keep only http(s) links, because the tracker page renders this as a link."""
def _clean_url(job_url: any) -> str {
    url = str(job_url or "").strip()[:MAX_TEXT];
    return url if url.lower().startswith(("http://", "https://")) else "";
}

def _find_existing(
    user_id: int,
    role: str,
    company: str,
    job_url: str,
    conn: any = None
) -> dict[str, any] | None {
    for app in list_applications_by_user(user_id, conn=conn) {
        if job_url and str(app.get("job_url") or "") == job_url {
            return app;
        }
        same_role = str(app.get("job_title") or "").lower() == role.lower();
        same_company = str(app.get("company") or "").lower() == company.lower();
        if same_role and same_company and (not job_url or not app.get("job_url")) {
            return app;
        }
    }
    return None;
}

def _list_for(user_id: int, conn: any = None) -> dict[str, any] {
    apps = list_applications_by_user(user_id, conn=conn);
    options = _status_options_for(user_id, conn=conn);
    return {"ok": True, "applications": [_to_row(app, options) for app in reversed(apps)]};
}

def _add_for(
    user_id: int,
    role: str,
    company: str,
    applied_date: str,
    description: str = "",
    pay: int | None = None,
    status: str = "Applied",
    job_url: str = "",
    resume_pdf_name: str = "",
    resume_pdf_content: str = "",
    cover_letter_pdf_name: str = "",
    cover_letter_pdf_content: str = "",
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
    resume_file = _validated_pdf(resume_pdf_name, resume_pdf_content);
    cover_letter_file = _validated_pdf(cover_letter_pdf_name, cover_letter_pdf_content);
    if not resume_file["ok"] {
        return resume_file;
    }
    if not cover_letter_file["ok"] {
        return cover_letter_file;
    }
    options = _status_options_for(user_id, conn=conn);
    clean_status = _clean_status(status, options);
    if not _is_valid_status(status, options) {
        return {"ok": False, "error": "Choose a status from your tracker options."};
    }
    clean_url = _clean_url(job_url);
    existing = _find_existing(user_id, clean_role, clean_company, clean_url, conn=conn);
    if existing is not None {
        return {"ok": True, "application": _to_row(existing, options), "already_tracked": True};
    }
    app = create_application(
        user_id=user_id,
        job_title=clean_role,
        company=clean_company,
        status=clean_status,
        applied_date=clean_date,
        job_url=clean_url or None,
        notes=str(description or "").strip()[:MAX_TEXT] or None,
        pay=int(pay) if pay is not None else None,
        resume_pdf_name=resume_file["name"] or None,
        resume_pdf_content=resume_file["content"] or None,
        cover_letter_pdf_name=cover_letter_file["name"] or None,
        cover_letter_pdf_content=cover_letter_file["content"] or None,
        conn=conn
    );
    return {"ok": True, "application": _to_row(app, options)};
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
    options = _status_options_for(user_id, conn=conn);
    clean_status = _clean_status(status, options);
    if not _is_valid_status(status, options) {
        return {"ok": False, "error": "Unknown status."};
    }
    updated = update_application(int(app_id), status=clean_status, conn=conn);
    return {"ok": True, "application": _to_row(updated, options)} if updated else {"ok": False, "error": "Application not found."};
}

def _edit_for(
    user_id: int,
    app_id: int,
    role: str,
    company: str,
    applied_date: str,
    description: str,
    pay: int | None,
    status: str,
    resume_pdf_name: str | None = None,
    resume_pdf_content: str | None = None,
    cover_letter_pdf_name: str | None = None,
    cover_letter_pdf_content: str | None = None,
    clear_resume_pdf: bool = False,
    clear_cover_letter_pdf: bool = False,
    conn: any = None
) -> dict[str, any] {
    if _owned_application(user_id, app_id, conn=conn) is None {
        return {"ok": False, "error": "Application not found."};
    }
    clean_role = str(role or "").strip()[:MAX_TEXT];
    clean_company = str(company or "").strip()[:MAX_TEXT];
    clean_date = str(applied_date or "").strip();
    if not clean_role or not clean_company or not _is_iso_date(clean_date) {
        return {"ok": False, "error": "Company, job title, and application date are required."};
    }
    if pay is not None and int(pay) < 0 {
        return {"ok": False, "error": "Pay available must be a whole number."};
    }
    resume_file = _validated_pdf(resume_pdf_name, resume_pdf_content) if resume_pdf_name or resume_pdf_content else None;
    cover_letter_file = _validated_pdf(cover_letter_pdf_name, cover_letter_pdf_content) if cover_letter_pdf_name or cover_letter_pdf_content else None;
    if resume_file is not None and not resume_file["ok"] {
        return resume_file;
    }
    if cover_letter_file is not None and not cover_letter_file["ok"] {
        return cover_letter_file;
    }
    options = _status_options_for(user_id, conn=conn);
    clean_status = _clean_status(status, options);
    if not _is_valid_status(status, options) {
        return {"ok": False, "error": "Choose a status from your tracker options."};
    }
    update_fields: dict[str, any] = {
        "job_title": clean_role,
        "company": clean_company,
        "status": clean_status,
        "applied_date": clean_date,
        "notes": str(description or "").strip()[:MAX_TEXT],
        "pay": int(pay) if pay is not None else 0
    };
    if clear_resume_pdf {
        update_fields["resume_pdf_name"] = "";
        update_fields["resume_pdf_content"] = "";
    } elif resume_file is not None {
        update_fields["resume_pdf_name"] = resume_file["name"];
        update_fields["resume_pdf_content"] = resume_file["content"];
    }
    if clear_cover_letter_pdf {
        update_fields["cover_letter_pdf_name"] = "";
        update_fields["cover_letter_pdf_content"] = "";
    } elif cover_letter_file is not None {
        update_fields["cover_letter_pdf_name"] = cover_letter_file["name"];
        update_fields["cover_letter_pdf_content"] = cover_letter_file["content"];
    }
    updated = update_application(int(app_id), **update_fields, conn=conn);
    return {"ok": True, "application": _to_row(updated, options)} if updated else {"ok": False, "error": "Application not found."};
}

def _save_status_options_for(
    user_id: int,
    raw_options: any,
    conn: any = None
) -> dict[str, any] {
    if not isinstance(raw_options, list) or not raw_options or len(raw_options) > 20 {
        return {"ok": False, "error": "Keep between 1 and 20 status options."};
    }
    options: list[dict[str, str]] = [];
    names: list[str] = [];
    for raw in raw_options {
        if not isinstance(raw, dict) {
            return {"ok": False, "error": "Each status needs a name and color."};
        }
        name = str(raw.get("name") or "").strip();
        color = str(raw.get("color") or "").strip();
        if not name or len(name) > 40 or any([char in name for char in ["\n", "\r"]]) {
            return {"ok": False, "error": "Status names must be 1 to 40 characters."};
        }
        if name.lower() in [existing.lower() for existing in names] {
            return {"ok": False, "error": "Status names must be unique."};
        }
        if len(color) != 7 or color[0] != "#" or not all([char in "0123456789abcdefABCDEF" for char in color[1:]]) {
            return {"ok": False, "error": "Choose a valid color for every status."};
        }
        options.append({"name": name, "color": color.lower()});
        names.append(name);
    }
    valid_names = [name.lower() for name in names];
    for app in list_applications_by_user(user_id, conn=conn) {
        if str(app.get("status") or "").strip().lower() not in valid_names {
            return {"ok": False, "error": "Reassign applications before removing a status option."};
        }
    }
    replace_tracker_status_options(user_id, options, conn=conn);
    return {"ok": True, "options": options};
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
        return {"ok": False, "error": "Could not initialize your tracker account."};
    }
    return {"ok": True, "user_id": int(user["id"])};
}

def:protect list_tracker_applications(token: str) -> dict[str, any] {
    found = _user_id_for(token);
    return _list_for(found["user_id"]) if found["ok"] else found;
}

def:protect get_tracker_status_options(token: str) -> dict[str, any] {
    found = _user_id_for(token);
    return {"ok": True, "options": _status_options_for(found["user_id"])} if found["ok"] else found;
}

def:protect save_tracker_status_options(token: str, options: any) -> dict[str, any] {
    found = _user_id_for(token);
    return _save_status_options_for(found["user_id"], options) if found["ok"] else found;
}

def:protect add_tracker_application(
    token: str,
    role: str,
    company: str,
    applied_date: str,
    description: str,
    pay: int | None,
    status: str,
    job_url: str = "",
    salary_text: str = "",
    resume_pdf_name: str = "",
    resume_pdf_content: str = "",
    cover_letter_pdf_name: str = "",
    cover_letter_pdf_content: str = ""
) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    amount = pay;
    if amount is None and salary_text {
        values = _extract_salary_values(salary_text);
        amount = int(max(values)) if values else None;
    }
    return _add_for(
        found["user_id"], role, company, applied_date, description, amount, status, job_url,
        resume_pdf_name, resume_pdf_content, cover_letter_pdf_name, cover_letter_pdf_content
    );
}

def:protect set_tracker_status(token: str, app_id: int, status: str) -> dict[str, any] {
    found = _user_id_for(token);
    return _set_status_for(found["user_id"], app_id, status) if found["ok"] else found;
}

def:protect edit_tracker_application(
    token: str,
    app_id: int,
    role: str,
    company: str,
    applied_date: str,
    description: str,
    pay: int | None,
    status: str,
    resume_pdf_name: str = "",
    resume_pdf_content: str = "",
    cover_letter_pdf_name: str = "",
    cover_letter_pdf_content: str = "",
    clear_resume_pdf: bool = False,
    clear_cover_letter_pdf: bool = False
) -> dict[str, any] {
    found = _user_id_for(token);
    return _edit_for(
        found["user_id"], app_id, role, company, applied_date, description, pay, status,
        resume_pdf_name, resume_pdf_content, cover_letter_pdf_name, cover_letter_pdf_content,
        clear_resume_pdf, clear_cover_letter_pdf
    ) if found["ok"] else found;
}

def:protect remove_tracker_application(token: str, app_id: int) -> dict[str, any] {
    found = _user_id_for(token);
    return _remove_for(found["user_id"], app_id) if found["ok"] else found;
}

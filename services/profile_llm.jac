"""Profile management and DeepSeek LLM job search parameter generator."""

import base64;
import json;
import os;
import re;
import urllib.error;
import urllib.parse;
import urllib.request;
import from db {
    load_env_file,
    get_user_by_email,
    get_user_by_id,
    get_user_by_oauth_id,
    sync_oauth_user,
    save_user_profile,
    create_resume,
    list_resumes_by_user
}
import from .auth_sync { _resolve_caller, _public_user }

def extract_resume_text(raw_content: str) -> str {
    if not raw_content {
        return "";
    }
    clean = raw_content.strip();
    if clean.startswith("data:") and ";base64," in clean {
        clean = clean.split(";base64,", 1)[1];
    }
    # Attempt base64 decode if applicable
    decoded_bytes: bytes | None = None;
    try {
        decoded_bytes = base64.b64decode(clean);
    } except Exception {
        decoded_bytes = None;
    }
    if decoded_bytes is not None {
        try {
            # Try plain text UTF-8 first
            text_candidate = decoded_bytes.decode("utf-8");
            if len(re.findall(r"[a-zA-Z]{3,}", text_candidate)) > 5 {
                return text_candidate[:4000];
            }
        } except Exception {}
        # Simple PDF text stream extractor: finds text within (string) Tj or TJ
        try {
            extracted_words = re.findall(rb"\(([^\)\\]{2,100})\)\s*(?:Tj|TJ)", decoded_bytes);
            if extracted_words {
                words_str = [w.decode("latin1", errors="ignore") for w in extracted_words];
                return " ".join(words_str)[:4000];
            }
        } except Exception {}
    }
    # Fallback to the raw string if it's already text
    return clean[:4000];
}

def generate_fallback_query(profile_data: dict[str, any]) -> dict[str, any] {
    raw_titles = str(profile_data.get("job_titles", "")).strip();
    primary_search = "Software Engineer";
    if raw_titles {
        primary_search = raw_titles.split(",")[0].strip();
    } elif profile_data.get("sector") {
        primary_search = str(profile_data.get("sector")).strip();
    }

    loc = profile_data.get("location");
    clean_loc = str(loc).strip() if loc else "Remote";
    if not clean_loc {
        clean_loc = "Remote";
    }

    sal = profile_data.get("salary_min");
    clean_sal: int | None = None;
    if sal is not None {
        try {
            clean_sal = int(sal);
        } except ValueError {
            clean_sal = None;
        }
    }

    ct = profile_data.get("contract_type");
    clean_ct = str(ct).strip() if ct else "Full-time";

    return {
        "search": primary_search,
        "location": clean_loc,
        "salary": clean_sal,
        "contract_type": clean_ct,
        "company": None,
        "source": "all"
    };
}

def generate_job_search_params(profile_data: dict[str, any]) -> dict[str, any] {
    load_env_file();
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip();

    if not api_key or api_key == "your_deepseek_key_here" {
        return generate_fallback_query(profile_data);
    }

    url = "https://api.deepseek.com/chat/completions";
    sys_prompt = (
        "You are an expert career agent and job search query synthesizer. "
        + "Given the candidate's personal info, sector, target job titles, minimum salary, contract type, "
        + "and resume summary, output a single JSON object with the best search parameters for fetching jobs. "
        + "The JSON must contain exact keys: "
        + "'search' (string: primary target job title or keywords, e.g. 'Frontend Engineer'), "
        + "'location' (string: city/state like 'Chicago, IL' or 'Remote'), "
        + "'salary' (integer or null: minimum desired annual pay in USD), "
        + "'contract_type' (string or null: e.g. 'Full-time', 'Part-time', 'Internship', 'Contract'), "
        + "'company' (string or null: specific target company or null), "
        + "'source' ('all'). "
        + "Respond with valid JSON only."
    );

    user_content = (
        f"Candidate Name: {profile_data.get('first_name', '')} {profile_data.get('last_name', '')}\n"
        + f"Location: {profile_data.get('location', 'Remote')}\n"
        + f"Sector: {profile_data.get('sector', '')}\n"
        + f"Job Titles: {profile_data.get('job_titles', '')}\n"
        + f"Salary Minimum: {profile_data.get('salary_min', '')}\n"
        + f"Contract Type: {profile_data.get('contract_type', '')}\n"
        + f"Resume Summary: {profile_data.get('resume_summary', '')}\n"
    );

    payload = {
        "model": "deepseek-chat",
        "messages": [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": user_content}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2
    };

    req_data = json.dumps(payload).encode("utf-8");
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "User-Agent": "Launchpad/1.0"
    };

    req = urllib.request.Request(url, data=req_data, headers=headers);
    try {
        with urllib.request.urlopen(req, timeout=10) as resp {
            resp_body = resp.read().decode("utf-8");
            parsed_resp = json.loads(resp_body);
            choices = parsed_resp.get("choices", []);
            if choices and isinstance(choices, list) {
                msg = choices[0].get("message", {});
                content_str = msg.get("content", "");
                structured_query = json.loads(content_str);
                # Validate expected keys
                if "search" in structured_query {
                    if "source" not in structured_query {
                        structured_query["source"] = "all";
                    }
                    return structured_query;
                }
            }
        }
    } except Exception {
        # Fall back gracefully to deterministic query extraction
        return generate_fallback_query(profile_data);
    }

    return generate_fallback_query(profile_data);
}

def _submit_profile(
    email: str = "",
    first_name: str = "",
    last_name: str = "",
    location: str = "Remote",
    sector: str = "",
    job_titles: str = "",
    salary_min: int | None = None,
    contract_type: str | None = None,
    resume_title: str | None = None,
    resume_content: str | None = None,
    oauth_id: str | None = None,
    auth_provider: str = "google",
    conn: any = None
) -> dict[str, any] {
    actual_conn = conn;
    if not email or not email.strip() {
        return {"ok": False, "error": "Email is required."};
    }
    if not first_name or not first_name.strip() {
        return {"ok": False, "error": "First name is required."};
    }
    clean_email = email.strip().lower();
    clean_fn = first_name.strip() if first_name else "";
    clean_ln = last_name.strip() if last_name else "";
    clean_loc = location.strip() if location else "Remote";
    clean_sec = sector.strip() if sector else "";
    clean_titles = job_titles.strip() if job_titles else "";
    clean_ct = contract_type.strip() if contract_type else "Full-time";


    user: any = get_user_by_email(clean_email, conn=actual_conn);
    if user is None and oauth_id {
        user = get_user_by_oauth_id(str(oauth_id), auth_provider=auth_provider, conn=actual_conn);
    }

    if user is None {
        clean_name = f"{clean_fn} {clean_ln}".strip() if (clean_fn or clean_ln) else clean_email.split("@")[0];
        try {
            user = sync_oauth_user(
                email=clean_email,
                name=clean_name,
                oauth_id=str(oauth_id) if oauth_id else None,
                auth_provider=auth_provider,
                conn=actual_conn
            );
        } except Exception as err {
            return {"ok": False, "error": f"Failed to initialize user record: {str(err)}"};
        }
    }
    user_id = int(user["id"]);

    resume_summary = "";
    if resume_content and resume_content.strip() {
        clean_title = (resume_title or "Base Resume.pdf").strip();
        resume_summary = extract_resume_text(resume_content);
        try {
            create_resume(
                user_id=user_id,
                title=clean_title,
                content=resume_content,
                file_path=None,
                conn=actual_conn
            );
        } except Exception {}
    }

    profile_data = {
        "first_name": clean_fn,
        "last_name": clean_ln,
        "location": clean_loc,
        "sector": clean_sec,
        "job_titles": clean_titles,
        "salary_min": salary_min,
        "contract_type": clean_ct,
        "resume_summary": resume_summary
    };

    structured_query = generate_job_search_params(profile_data);
    query_json_str = json.dumps(structured_query);

    updated_user = save_user_profile(
        user_id=user_id,
        first_name=clean_fn if clean_fn else None,
        last_name=clean_ln if clean_ln else None,
        location=clean_loc,
        sector=clean_sec if clean_sec else None,
        job_titles=clean_titles if clean_titles else None,
        salary_min=salary_min,
        contract_type=clean_ct,
        cached_job_query=query_json_str,
        onboarding_completed=1,
        conn=actual_conn
    );

    return {
        "ok": True,
        "cached_query": structured_query,
        "user": _public_user(updated_user)
    };
}

def:protect submit_profile_and_generate_query(
    token: str,
    first_name: str = "",
    last_name: str = "",
    location: str = "Remote",
    sector: str = "",
    job_titles: str = "",
    salary_min: int | None = None,
    contract_type: str | None = None,
    resume_title: str | None = None,
    resume_content: str | None = None
) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    return _submit_profile(
        email=caller["email"],
        first_name=first_name,
        last_name=last_name,
        location=location,
        sector=sector,
        job_titles=job_titles,
        salary_min=salary_min,
        contract_type=contract_type,
        resume_title=resume_title,
        resume_content=resume_content,
        oauth_id=caller["oauth_id"],
        auth_provider=caller["auth_provider"]
    );
}

def _load_profile(
    email: str | None = None,
    identity: dict[str, any] | None = None,
    conn: any = None
) -> dict[str, any] {
    actual_conn = conn;
    clean_email = str(email).strip().lower() if (email and str(email).strip()) else None;
    resolved_info = identity or {};
    oauth_id = resolved_info.get("oauth_id");
    auth_provider = str(resolved_info.get("auth_provider") or "local");

    user: any = None;
    if clean_email {
        user = get_user_by_email(clean_email, conn=actual_conn);
    }
    if user is None and oauth_id {
        user = get_user_by_oauth_id(str(oauth_id), auth_provider=auth_provider, conn=actual_conn);
    }

    if user is not None {
        user_id = int(user["id"]);
        fn = user.get("first_name") or resolved_info.get("first_name");
        ln = user.get("last_name") or resolved_info.get("last_name");
        if (not user.get("first_name") and fn) or (not user.get("last_name") and ln) {
            user = save_user_profile(user_id=user_id, first_name=fn, last_name=ln, conn=actual_conn);
        }

        resumes = list_resumes_by_user(user_id, conn=actual_conn);
        latest_resume = resumes[0] if resumes else None;

        cached_query_dict = None;
        if user.get("cached_job_query") {
            try {
                cached_query_dict = json.loads(str(user["cached_job_query"]));
            } except Exception {}
        }

        return {
            "ok": True,
            "user": _public_user(user),
            "latest_resume": latest_resume,
            "cached_query": cached_query_dict,
            "onboarding_completed": bool(user.get("onboarding_completed"))
        };
    }

    if clean_email and "@" in clean_email {
        name_val = resolved_info.get("name") or (f"{resolved_info.get('first_name', '')} {resolved_info.get('last_name', '')}".strip()) or clean_email.split("@")[0];
        try {
            created_user = sync_oauth_user(
                email=clean_email,
                name=name_val,
                oauth_id=str(oauth_id) if oauth_id else None,
                auth_provider=auth_provider,
                conn=actual_conn
            );
            return {
                "ok": True,
                "user": _public_user(created_user),
                "latest_resume": None,
                "cached_query": None,
                "onboarding_completed": False
            };
        } except Exception {}
    }

    synthetic_user = {
        "id": None,
        "email": "",
        "first_name": resolved_info.get("first_name") or "",
        "last_name": resolved_info.get("last_name") or "",
        "name": resolved_info.get("name") or "",
        "location": "Remote",
        "onboarding_completed": 0
    };
    return {
        "ok": True,
        "user": synthetic_user,
        "latest_resume": None,
        "cached_query": None,
        "onboarding_completed": False
    };
}

def:protect get_user_profile_data(token: str) -> dict[str, any] {
    caller = _resolve_caller(token);
    if not caller["ok"] {
        return caller;
    }
    return _load_profile(email=caller["email"], identity=caller);
}

"""Saved Career Navigator conversations and job-search context."""

import re;
import from .jobs { search_jobs }
import from db {
    delete_career_chat as delete_chat_row,
    get_career_chat,
    list_career_chat_messages,
    list_career_chats as list_career_chats_rows,
    save_career_chat_exchange
}
import from .auth_sync { _resolve_caller, _sync_caller }

glob MAX_MESSAGE_LENGTH: int = 4000;
glob MAX_ASSISTANT_REPLY_LENGTH: int = 12000;
glob MAX_JOB_SEARCH_RESULTS: int = 5;

def _job_search_request(message: str, major: str, career_goal: str) -> dict[str, str] | None {
    if not re.search(
        r"\b(?:find|search|look for|show|list|browse|recommend|what|which)\b",
        message,
        re.IGNORECASE
    ) or not re.search(
        r"\b(?:jobs?|roles?|positions?|openings?|internships?)\b",
        message,
        re.IGNORECASE
    ) {
        return None;
    }

    query_text = message;
    location = "";
    location_match = re.search(
        r"\b(?:in|near|around)\s+([A-Za-z][A-Za-z .'-]*(?:,\s*[A-Za-z]{2})?)\s*$",
        message,
        re.IGNORECASE
    );
    if location_match {
        location = location_match.group(1).strip(" .");
        query_text = message[:location_match.start()];
    } elif re.search(r"\bremote\b", message, re.IGNORECASE) {
        location = "Remote";
        query_text = re.sub(r"\bremote\b", " ", message, flags=re.IGNORECASE);
    }

    query_text = re.sub(
        r"\b(?:find|search|look|for|show|list|browse|recommend|what|which|can|could|would|you|me|please|jobs?|roles?|positions?|openings?|internships?|available|some|any|a|an|the|in|near|around|to|with|my|career|goal|major|related|based|on|get|are|is|do|i|need|that)\b",
        " ",
        query_text,
        flags=re.IGNORECASE
    );
    search_term = " ".join(query_text.split()).strip(" .,?!")
        or career_goal.strip()
        or major.strip();
    return {"search": search_term, "location": location};
}

def _search_job_listings(message: str, major: str, career_goal: str) -> dict[str, any] {
    request = _job_search_request(message, major, career_goal);
    if request is None {
        return {"searched": False, "jobs": []};
    }
    results = search_jobs(
        search=request["search"],
        location=request["location"] or None,
        source="all",
        n=MAX_JOB_SEARCH_RESULTS
    );
    if not results.get("ok") {
        return {
            "searched": True,
            "jobs": [],
            "error": str(results.get("error") or "Job search could not be completed.")
        };
    }
    return {"searched": True, "jobs": results.get("jobs") or []};
}

def _saved_job_search_reply(reply: str, jobs: list[dict[str, any]], searched: bool) -> str {
    if not searched {
        return reply;
    }
    if not jobs {
        return reply + "\n\nI searched Launchpad's job listings but found no matching listings.";
    }
    lines = [reply, "", "Matching Launchpad listings:"];
    for job in jobs[:MAX_JOB_SEARCH_RESULTS] {
        details = [
            str(job.get("title") or "Untitled role"),
            str(job.get("company") or "Company not listed"),
            str(job.get("location") or "Location not listed")
        ];
        salary = str(job.get("salary") or "").strip();
        if salary {
            details.append(salary);
        }
        job_type = str(job.get("type") or "").strip();
        if job_type {
            details.append(job_type);
        }
        line = "- " + " | ".join(details);
        link = str(job.get("link") or "").strip();
        if link {
            line += " | " + link;
        }
        lines.append(line);
    }
    return "\n".join(lines);
}

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
        return {"ok": False, "error": "Could not initialize your Career Navigator account."};
    }
    return {"ok": True, "user_id": int(user["id"])};
}

def:protect list_career_chats(token: str) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    return {"ok": True, "chats": list_career_chats_rows(found["user_id"])};
}

def:protect get_career_chat_details(token: str, chat_id: int) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    chat = get_career_chat(found["user_id"], chat_id);
    if chat is None {
        return {"ok": False, "error": "Conversation not found."};
    }
    return {
        "ok": True,
        "chat": chat,
        "messages": list_career_chat_messages(found["user_id"], chat_id)
    };
}

def:protect send_career_message(
    token: str,
    message: str,
    reply: str,
    chat_id: int | None = None,
    major: str = "",
    career_goal: str = ""
) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    clean_message = str(message or "").strip();
    clean_reply = str(reply or "").strip();
    clean_major = str(major or "").strip();
    clean_goal = str(career_goal or "").strip();
    if not clean_message {
        return {"ok": False, "error": "Write a message before sending."};
    }
    if len(clean_message) > MAX_MESSAGE_LENGTH {
        return {"ok": False, "error": f"Messages must be {MAX_MESSAGE_LENGTH} characters or fewer."};
    }
    if not clean_reply {
        return {"ok": False, "error": "The AI assistant returned an empty response. Please try again."};
    }
    if len(clean_reply) > MAX_ASSISTANT_REPLY_LENGTH {
        return {"ok": False, "error": "The AI response was too long to save. Please try a shorter question."};
    }
    if len(clean_major) > 160 {
        return {"ok": False, "error": "Major must be 160 characters or fewer."};
    }
    if len(clean_goal) > 200 {
        return {"ok": False, "error": "Career goal must be 200 characters or fewer."};
    }

    if chat_id is not None {
        chat = get_career_chat(found["user_id"], chat_id);
        if chat is None {
            return {"ok": False, "error": "Conversation not found."};
        }
        clean_major = str(chat["major"]);
        clean_goal = str(chat["career_goal"]);
    } elif not clean_major or not clean_goal {
        return {"ok": False, "error": "Enter your major and career goal to start a conversation."};
    }

    job_search = _search_job_listings(clean_message, clean_major, clean_goal);
    if job_search.get("error") {
        return {"ok": False, "error": str(job_search["error"])};
    }
    job_results: list[dict[str, any]] = job_search.get("jobs") or [];
    searched = bool(job_search["searched"]);
    saved_reply = _saved_job_search_reply(clean_reply, job_results, searched);
    title = clean_message[:97] + "..." if len(clean_message) > 100 else clean_message;
    try {
        saved_chat_id = save_career_chat_exchange(
            found["user_id"],
            chat_id,
            title,
            clean_major,
            clean_goal,
            clean_message,
            saved_reply
        );
    } except ValueError as error {
        return {"ok": False, "error": str(error)};
    }
    return {
        "ok": True,
        "chat_id": saved_chat_id,
        "reply": clean_reply,
        "job_results": job_results,
        "job_search_performed": searched,
        "warning": str(job_search["error"]) if job_search.get("error") else "",
        "major": clean_major,
        "career_goal": clean_goal
    };
}

def:protect remove_career_chat(token: str, chat_id: int) -> dict[str, any] {
    found = _user_id_for(token);
    if not found["ok"] {
        return found;
    }
    if not delete_chat_row(found["user_id"], chat_id) {
        return {"ok": False, "error": "Conversation not found."};
    }
    return {"ok": True};
}

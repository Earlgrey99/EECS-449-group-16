"""Job listings served to the search feed and multi-provider API fetcher."""

import json;
import os;
import re;
import urllib.error;
import urllib.parse;
import urllib.request;
import from db { load_env_file }

glob JOBS: list[dict[str, str | int]] = [
    {"id": 1, "title": "Frontend Engineer", "company": "Lumen Labs", "location": "Cleveland, OH", "salary": "115,000", "type": "Full-time", "tags": "React, TypeScript, CSS", "desc": "Build accessible, fast interfaces for our analytics product alongside a small design-minded team.", "link": "", "snippet": "Build accessible, fast interfaces for our analytics product alongside a small design-minded team.", "source": "local"},
    {"id": 2, "title": "Backend Engineer", "company": "Northwind Data", "location": "Remote", "salary": "128,000", "type": "Full-time", "tags": "Python, SQL, APIs", "desc": "Design and scale the data services behind our real-time reporting pipelines.", "link": "", "snippet": "Design and scale the data services behind our real-time reporting pipelines.", "source": "local"},
    {"id": 3, "title": "Data Analyst", "company": "Cascade Health", "location": "Chicago, IL", "salary": "84,000", "type": "Full-time", "tags": "SQL, Dashboards, Python", "desc": "Turn clinical data into clear dashboards that care teams use every day.", "link": "", "snippet": "Turn clinical data into clear dashboards that care teams use every day.", "source": "local"},
    {"id": 4, "title": "Machine Learning Intern", "company": "Orbit AI", "location": "Pittsburgh, PA", "salary": "42,000", "type": "Internship", "tags": "PyTorch, NLP, Research", "desc": "Work with our research group on language models for document understanding.", "link": "", "snippet": "Work with our research group on language models for document understanding.", "source": "local"},
    {"id": 5, "title": "DevOps Engineer", "company": "Halcyon Cloud", "location": "Remote", "salary": "135,000", "type": "Full-time", "tags": "Kubernetes, Terraform, AWS", "desc": "Own the deployment platform that keeps our customer workloads healthy.", "link": "", "snippet": "Own the deployment platform that keeps our customer workloads healthy.", "source": "local"},
    {"id": 6, "title": "Product Designer", "company": "Marigold Studio", "location": "Cleveland, OH", "salary": "96,000", "type": "Contract", "tags": "Figma, Prototyping, UX", "desc": "Shape product experiences for consumer apps from first sketch to shipped UI.", "link": "", "snippet": "Shape product experiences for consumer apps from first sketch to shipped UI.", "source": "local"},
    {"id": 7, "title": "Software Engineer, New Grad", "company": "Bluepeak Systems", "location": "Columbus, OH", "salary": "98,000", "type": "Full-time", "tags": "Java, Spring, Distributed systems", "desc": "Join our platform team building reliable services for logistics customers.", "link": "", "snippet": "Join our platform team building reliable services for logistics customers.", "source": "local"},
    {"id": 8, "title": "QA Automation Engineer", "company": "Riverbend Software", "location": "Remote", "salary": "89,000", "type": "Part-time", "tags": "Playwright, Python, CI/CD", "desc": "Grow our end-to-end test suite so releases stay fast and dependable.", "link": "", "snippet": "Grow our end-to-end test suite so releases stay fast and dependable.", "source": "local"},
];

def:pub list_jobs -> list[dict[str, str | int]] {
    return JOBS;
}

def _extract_salary_values(salary_val: any) -> list[float] {
    if salary_val is None {
        return [];
    }
    if isinstance(salary_val, (int, float)) {
        return [float(salary_val)];
    }
    text = str(salary_val).strip();
    if not text {
        return [];
    }
    cleaned = text.replace(",", "");
    matches = re.findall(r"(\d+(?:\.\d+)?)\s*([kK])?", cleaned);
    values: list[float] = [];
    for (num_str, k_suffix) in matches {
        try {
            val = float(num_str);
            if k_suffix.lower() == "k" {
                val = val * 1000.0;
            }
            values.append(val);
        } except ValueError {
            continue;
        }
    }
    return values;
}

def _matches_contract_type(job_type: any, target_type: str) -> bool {
    if not job_type or not target_type {
        return False;
    }
    jt = str(job_type).strip().lower();
    tt = str(target_type).strip().lower();
    if tt == jt or tt in jt {
        return True;
    }
    jt_norm = jt.replace("-", " ");
    tt_norm = tt.replace("-", " ");
    if tt_norm == jt_norm or tt_norm in jt_norm {
        return True;
    }
    return False;
}

def _matches_company(job_company: any, target_company: str) -> bool {
    if not job_company or not target_company {
        return False;
    }
    jc = str(job_company).strip().lower();
    tc = str(target_company).strip().lower();
    return tc in jc;
}

# --- URL Builders ---

def build_jooble_url(api_key: str, domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        if "{key}" in endpoint {
            return endpoint.replace("{key}", api_key);
        }
        clean_ep = endpoint.rstrip("/");
        if clean_ep.endswith("/api") {
            return f"{clean_ep}/{api_key}";
        }
        return endpoint;
    }
    raw_domain = domain or os.environ.get("JOOBLE_API_DOMAIN") or "jooble.org";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/{api_key}";
}

def build_usajobs_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("USAJOBS_API_DOMAIN") or "data.usajobs.gov";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/search";
}

def build_himalayas_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("HIMALAYAS_API_DOMAIN") or "himalayas.app";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/jobs/api/search";
}

def build_themuse_url(domain: str | None = None, endpoint: str | None = None) -> str {
    if endpoint {
        return endpoint;
    }
    raw_domain = domain or os.environ.get("THEMUSE_API_DOMAIN") or "www.themuse.com";
    clean_domain = raw_domain.strip();
    if clean_domain.startswith("https://") {
        clean_domain = clean_domain[8:];
    } elif clean_domain.startswith("http://") {
        clean_domain = clean_domain[7:];
    }
    clean_domain = clean_domain.strip("/");
    return f"https://{clean_domain}/api/public/jobs";
}

# --- Normalizers ---

def normalize_jooble_job(raw: dict[str, any]) -> dict[str, any] {
    return {
        "id": str(raw.get("id", "")),
        "title": raw.get("title", ""),
        "company": raw.get("company", ""),
        "location": raw.get("location", ""),
        "salary": str(raw.get("salary", "")) if raw.get("salary") is not None else "",
        "type": raw.get("type", "") or "",
        "link": raw.get("link", "") or "",
        "snippet": raw.get("snippet", "") or "",
        "desc": raw.get("snippet", "") or "",
        "source": "jooble",
        "tags": str(raw.get("tags", "")) if raw.get("tags") is not None else ""
    };
}

def normalize_usajobs_job(item: dict[str, any]) -> dict[str, any] {
    descriptor = item.get("MatchedObjectDescriptor", {}) if isinstance(item, dict) else {};
    pos_rem = descriptor.get("PositionRemuneration", []);
    salary_str = "";
    if isinstance(pos_rem, list) and len(pos_rem) > 0 and isinstance(pos_rem[0], dict) {
        min_r = pos_rem[0].get("MinimumRange");
        max_r = pos_rem[0].get("MaximumRange");
        if min_r is not None and max_r is not None and str(min_r) != str(max_r) {
            try {
                salary_str = f"${int(float(min_r)):,} - ${int(float(max_r)):,}";
            } except Exception {
                salary_str = f"${min_r} - ${max_r}";
            }
        } elif min_r is not None {
            try {
                salary_str = f"${int(float(min_r)):,}";
            } except Exception {
                salary_str = f"${min_r}";
            }
        }
    }
    pos_sched = descriptor.get("PositionSchedule", []);
    job_type = "";
    if isinstance(pos_sched, list) and len(pos_sched) > 0 and isinstance(pos_sched[0], dict) {
        job_type = pos_sched[0].get("Name", "") or "";
    }
    if not job_type {
        pos_off = descriptor.get("PositionOfferingType", []);
        if isinstance(pos_off, list) and len(pos_off) > 0 and isinstance(pos_off[0], dict) {
            job_type = pos_off[0].get("Name", "") or "";
        }
    }
    loc_display = descriptor.get("PositionLocationDisplay", "");
    if not loc_display {
        pos_locs = descriptor.get("PositionLocation", []);
        if isinstance(pos_locs, list) {
            loc_display = ", ".join([l.get("LocationName", "") for l in pos_locs if isinstance(l, dict) and l.get("LocationName")]);
        }
    }
    user_area = descriptor.get("UserArea", {}) if isinstance(descriptor.get("UserArea"), dict) else {};
    details = user_area.get("Details", {}) if isinstance(user_area.get("Details"), dict) else {};
    job_desc = details.get("JobSummary") or descriptor.get("QualificationSummary") or "";
    job_cats = descriptor.get("JobCategory", []);
    tags_str = "";
    if isinstance(job_cats, list) {
        tags_str = ", ".join([c.get("Name", "") for c in job_cats if isinstance(c, dict) and c.get("Name")]);
    }
    app_uri = descriptor.get("PositionURI", "");
    apply_uris = descriptor.get("ApplyURI");
    if not app_uri and isinstance(apply_uris, list) and len(apply_uris) > 0 {
        app_uri = apply_uris[0];
    }
    return {
        "id": str(item.get("MatchedObjectId") or descriptor.get("PositionID", "")),
        "title": descriptor.get("PositionTitle", ""),
        "company": descriptor.get("OrganizationName") or descriptor.get("DepartmentName", ""),
        "location": loc_display,
        "salary": salary_str,
        "type": job_type,
        "link": app_uri,
        "snippet": job_desc,
        "desc": job_desc,
        "source": "usajobs",
        "tags": tags_str
    };
}

def normalize_himalayas_job(job: dict[str, any]) -> dict[str, any] {
    loc_restr = job.get("locationRestrictions", []);
    loc_names = [];
    if isinstance(loc_restr, list) {
        for loc in loc_restr {
            if isinstance(loc, dict) and loc.get("name") {
                loc_names.append(loc["name"]);
            } elif isinstance(loc, str) {
                loc_names.append(loc);
            }
        }
    }
    location = ", ".join(loc_names) if loc_names else "Remote";
    salary_str = "";
    min_s = job.get("minSalary");
    max_s = job.get("maxSalary");
    if min_s is not None and max_s is not None and min_s != max_s {
        try {
            salary_str = f"${int(min_s):,} - ${int(max_s):,}";
        } except Exception {
            salary_str = f"${min_s} - ${max_s}";
        }
    } elif min_s is not None {
        try {
            salary_str = f"${int(min_s):,}";
        } except Exception {
            salary_str = f"${min_s}";
        }
    }
    cats = job.get("categories", []);
    tags_str = ", ".join(cats) if isinstance(cats, list) else str(cats or "");
    desc = job.get("description") or job.get("excerpt") or "";
    return {
        "id": str(job.get("guid", "")),
        "title": job.get("title", ""),
        "company": job.get("companyName", ""),
        "location": location,
        "salary": salary_str,
        "type": job.get("employmentType", "") or "",
        "link": job.get("applicationLink", "") or "",
        "snippet": job.get("excerpt", "") or "",
        "desc": desc,
        "source": "himalayas",
        "tags": tags_str
    };
}

def normalize_themuse_job(job: dict[str, any]) -> dict[str, any] {
    comp_obj = job.get("company");
    company_name = "";
    if isinstance(comp_obj, dict) {
        company_name = comp_obj.get("name", "");
    } elif comp_obj {
        company_name = str(comp_obj);
    }
    locs = job.get("locations", []);
    loc_names = [];
    if isinstance(locs, list) {
        for l in locs {
            if isinstance(l, dict) and l.get("name") {
                loc_names.append(l["name"]);
            } elif isinstance(l, str) {
                loc_names.append(l);
            }
        }
    }
    location = ", ".join(loc_names);
    refs = job.get("refs", {}) if isinstance(job.get("refs"), dict) else {};
    link = refs.get("landing_page", "") if isinstance(refs, dict) else "";
    cats = job.get("categories", []);
    cat_names = [];
    if isinstance(cats, list) {
        for c in cats {
            if isinstance(c, dict) and c.get("name") {
                cat_names.append(c["name"]);
            } elif isinstance(c, str) {
                cat_names.append(c);
            }
        }
    }
    tags_str = ", ".join(cat_names);
    contents = job.get("contents", "") or "";
    snippet = re.sub(r"<[^>]+>", " ", contents).strip() if contents else "";
    if len(snippet) > 250 {
        snippet = snippet[:247] + "...";
    }
    return {
        "id": str(job.get("id", "")),
        "title": job.get("name", ""),
        "company": company_name,
        "location": location,
        "salary": "",
        "type": job.get("type", "") or "",
        "link": link,
        "snippet": snippet,
        "desc": contents,
        "source": "themuse",
        "tags": tags_str
    };
}

# --- Fetchers ---

def fetch_jooble(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("JOOBLE_API_KEY", "");
    if not key {
        raise ValueError("Jooble API key must be provided via JOOBLE_API_KEY env var, .env file, or --api-key argument.");
    }
    url = build_jooble_url(key, domain=domain, endpoint=endpoint);
    req_payload = {"keywords": search, "ResultOnPage": n};
    if location {
        req_payload["location"] = location;
    }
    if salary is not None {
        req_payload["salary"] = int(salary);
    }
    body = json.dumps(req_payload).encode("utf-8");
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"}
    );
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Jooble API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Jooble API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("jobs", []) if isinstance(resp_payload, dict) else [];
    return [normalize_jooble_job(j) for j in raw_jobs];
}

def fetch_usajobs(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("USAJOBS_API_KEY", "");
    if not key {
        raise ValueError("USAJobs API key must be provided via USAJOBS_API_KEY env var, .env file, or --api-key argument.");
    }
    base_url = build_usajobs_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"Keyword": search, "ResultsPerPage": n};
    if location {
        query_params["LocationName"] = location;
    }
    if salary is not None {
        query_params["RemunerationMinimumAmount"] = int(salary);
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    host = domain or "data.usajobs.gov";
    if host.startswith("https://") {
        host = host[8:];
    } elif host.startswith("http://") {
        host = host[7:];
    }
    host = host.split("/")[0];
    email = os.environ.get("USAJOBS_EMAIL", "robieli@umich.edu");
    req = urllib.request.Request(
        url,
        headers={
            "Host": host,
            "User-Agent": email,
            "Authorization-Key": key
        }
    );
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"USAJobs API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"USAJobs API network error: {e.reason}");
    }
    search_result = resp_payload.get("SearchResult", {}) if isinstance(resp_payload, dict) else {};
    items = search_result.get("SearchResultItems", []) if isinstance(search_result, dict) else [];
    return [normalize_usajobs_job(item) for item in items];
}

def fetch_himalayas(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("HIMALAYAS_API_KEY", "");
    base_url = build_himalayas_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"q": search, "limit": min(max(n, 1), 20)};
    if location {
        query_params["country"] = location;
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    headers: dict[str, str] = {"User-Agent": "Mozilla/5.0"};
    if key {
        headers["Authorization"] = f"Bearer {key}";
    }
    req = urllib.request.Request(url, headers=headers);
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"Himalayas API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"Himalayas API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("jobs", []) if isinstance(resp_payload, dict) else [];
    normalized = [normalize_himalayas_job(j) for j in raw_jobs];
    if salary is not None {
        sal_jobs = [];
        for job in normalized {
            sal_vals = _extract_salary_values(job.get("salary"));
            if sal_vals and max(sal_vals) >= int(salary) {
                sal_jobs.append(job);
            }
        }
        return sal_jobs[:n];
    }
    return normalized[:n];
}

def fetch_themuse(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    company: str | None = None,
    api_key: str | None = None,
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    key = api_key or os.environ.get("THEMUSE_API_KEY", os.environ.get("MUSE_API_KEY", ""));
    base_url = build_themuse_url(domain=domain, endpoint=endpoint);
    query_params: dict[str, any] = {"page": 1};
    if key {
        query_params["api_key"] = key;
    }
    if company {
        query_params["company"] = company;
    }
    if location {
        query_params["location"] = location;
    }
    if search {
        query_params["category"] = search;
    }
    url = f"{base_url}?{urllib.parse.urlencode(query_params)}";
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"});
    try {
        with urllib.request.urlopen(req) as resp {
            resp_payload = json.loads(resp.read().decode("utf-8"));
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"The Muse API HTTP error: {e.code} {e.reason}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"The Muse API network error: {e.reason}");
    }
    raw_jobs = resp_payload.get("results", []) if isinstance(resp_payload, dict) else [];
    normalized = [normalize_themuse_job(j) for j in raw_jobs];
    if salary is not None {
        # The Muse does not provide structured salary
        _ = salary;
    }
    return normalized[:n];
}

# --- Unified Fetch ---

def fetch(
    n: int,
    search: str,
    location: str | None = None,
    salary: int | None = None,
    contract_type: str | None = None,
    company: str | None = None,
    api_key: str | None = None,
    source: str = "jooble",
    domain: str | None = None,
    endpoint: str | None = None
) -> list[dict[str, any]] {
    if n <= 0 {
        return [];
    }
    load_env_file();
    src = (source or "jooble").strip().lower();
    raw_jobs: list[dict[str, any]] = [];

    if src == "all" or "," in src {
        sources_to_query = ["jooble", "usajobs", "himalayas", "themuse"] if src == "all" else [s.strip() for s in src.split(",") if s.strip()];
        for s in sources_to_query {
            try {
                if s == "jooble" {
                    raw_jobs.extend(fetch_jooble(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "usajobs" {
                    raw_jobs.extend(fetch_usajobs(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "himalayas" {
                    raw_jobs.extend(fetch_himalayas(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint));
                } elif s == "themuse" {
                    raw_jobs.extend(fetch_themuse(n, search, location=location, salary=salary, company=company, api_key=api_key, domain=domain, endpoint=endpoint));
                }
            } except Exception as e {
                if len(sources_to_query) == 1 {
                    raise e;
                }
            }
        }
    } elif src == "usajobs" {
        raw_jobs = fetch_usajobs(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    } elif src == "himalayas" {
        raw_jobs = fetch_himalayas(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    } elif src == "themuse" {
        raw_jobs = fetch_themuse(n, search, location=location, salary=salary, company=company, api_key=api_key, domain=domain, endpoint=endpoint);
    } else {
        raw_jobs = fetch_jooble(n, search, location=location, salary=salary, api_key=api_key, domain=domain, endpoint=endpoint);
    }

    filtered_jobs = [];
    for job in raw_jobs {
        if company is not None and str(company).strip() != "" {
            if not _matches_company(job.get("company"), str(company).strip()) {
                continue;
            }
        }
        if contract_type is not None and str(contract_type).strip() != "" {
            if not _matches_contract_type(job.get("type"), str(contract_type).strip()) {
                continue;
            }
        }
        if salary is not None {
            sal_vals = _extract_salary_values(job.get("salary"));
            if not sal_vals or max(sal_vals) < int(salary) {
                continue;
            }
        }
        if location is not None and str(location).strip() != "" {
            loc_target = str(location).strip().lower();
            job_loc = str(job.get("location", "")).lower();
            if job_loc and loc_target not in job_loc and "remote" not in loc_target {
                if job_loc not in loc_target {
                    continue;
                }
            }
        }
        if search and src in ["themuse", "all"] {
            s_low = search.strip().lower();
            content = f"{job.get('title', '')} {job.get('company', '')} {job.get('desc', '')} {job.get('tags', '')}".lower();
            words = [w for w in s_low.split() if len(w) > 2];
            if words and not any([w in content for w in words]) {
                continue;
            }
        }
        filtered_jobs.append(job);
    }
    return filtered_jobs[:n];
}

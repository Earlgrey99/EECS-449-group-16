import from "@jac/runtime" { Link, useNavigate, jacIsLoggedIn, Navigate, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Search01Icon,
    Bookmark01Icon,
    Logout01Icon,
    SparklesIcon,
    FilterHorizontalIcon,
    CheckmarkCircle02Icon,
    Location01Icon
}
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.badge { Badge }
import from .ui.card { Card, CardContent }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.jobs { list_jobs, get_user_tailored_jobs, search_jobs }
import from ..services.compatibility { get_resume_match_scores }
import from ..services.locations { search_cities }
import from ..lib.utils { format_salary, format_desc }

glob ALL_CONTRACT_TYPES: list[str] = [
    "Full-time",
    "Part-time",
    "Contract",
    "Internship"
];

glob POPULAR_SECTORS: list[str] = [
    "Technology & Software",
    "Finance & Banking",
    "Healthcare & Biotech",
    "Education & Research",
    "Aerospace & Defense",
    "E-Commerce & Retail",
    "Consulting & Professional Services",
    "Media & Entertainment",
    "Government & Non-Profit",
    "Other"
];

def:pub JobCard(
    title: str,
    company: str,
    location: str,
    salary: str,
    tags: str,
    active: bool,
    saved: bool,
    onSelect: Callable[[], None],
    onSave: Callable[[], None],
    logo: str = "",
    source: str = "",
    match_score: int = -1
) -> JsxElement {
    sal_display = format_salary(salary);
    return <Card className={"cursor-pointer transition-all hover:-translate-y-0.5 hover:shadow-md " + ("ring-2 ring-primary" if active else "shadow-sm")} onClick={onSelect}>
        <CardContent className="flex flex-col gap-1.5 pt-5">
            <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-2.5 min-w-0">
                    {bool(logo) and <img src={logo} alt={company + " logo"} className="size-8 rounded border bg-background object-contain shrink-0 mt-0.5 p-0.5" />}
                    <div className="min-w-0">
                        <h3 className="font-semibold leading-tight truncate">{title}</h3>
                        <p className="text-sm text-muted-foreground">{company}</p>
                    </div>
                </div>
                <button onClick={onSave} className="shrink-0 rounded p-1 transition-colors hover:bg-muted" aria-label="Save job">
                    <HugeiconsIcon icon={Bookmark01Icon} strokeWidth={2} className={"size-4 " + ("fill-current text-primary" if saved else "text-muted-foreground")} />
                </button>
            </div>
            <p className="text-sm text-muted-foreground">{location}</p>
            {bool(sal_display) and <p className="text-sm font-medium tabular-nums">{sal_display}</p>}
            {match_score >= 0 and <Badge variant={("default" if match_score >= 75 else ("secondary" if match_score >= 50 else "outline"))} className="w-fit tabular-nums">{str(match_score) + "% match"}</Badge>}
            <div className="mt-1 flex items-center justify-between gap-2">
                <div className="flex flex-wrap gap-1.5">
                    {for tag in tags.split(", ")[:2] {
                        <Badge key={tag} variant="secondary" className="font-normal">{tag}</Badge>
                    }}
                </div>
                {bool(source) and <span className="text-xs text-muted-foreground shrink-0">{"via " + source}</span>}
            </div>
        </CardContent>
    </Card>;
}

def:pub JobSearchFeed -> JsxElement {
    nav = useNavigate();
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }
    has jobs: list[dict[str, any]] = [];
    has tailored_jobs: list[dict[str, any]] = [];
    has loading: bool = True;
    has searching: bool = False;
    has query: str = "";
    has loc_query: str = "";
    has locations_filter: list[str] = [];
    has city_suggestions: list[str] = [];
    has city_dropdown_open: bool = False;
    has tailored_query: str = "";
    has tailored_loc_query: str = "";
    has tailored_locations: list[str] = [];
    has selected_id: str = "";
    has saved_ids: list[str] = [];
    has is_tailored: bool = False;
    has tailored_summary: str = "";
    has is_custom_search: bool = False;
    has custom_summary: str = "";
    has show_filters: bool = False;
    has salary_min_filter: str = "";
    has contract_types_filter: list[str] = [];
    has sectors_filter: list[str] = [];
    has company_filter: str = "";
    has source_filter: str = "all";
    has did_load_jobs: bool = False;
    has match_rows: list[dict[str, any]] = [];
    has has_resume: bool = True;

    async can with entry {
        if did_load_jobs {
            return;
        }
        did_load_jobs = True;
        tok: str = "";
        try {
            tok = str(localStorage.getItem("jac_token") or "");
        } except Exception {}
        tailored_res: any = None;
        try {
            tailored_res = await get_user_tailored_jobs(token=tok);
        } except Exception {}

        init_jobs: list[dict[str, any]] = [];
        if tailored_res and tailored_res.get("ok") {
            if tailored_res.get("jobs") {
                init_jobs = tailored_res.get("jobs");
            }
            if tailored_res.get("query") {
                q_dict = tailored_res.get("query");
                is_tailored = True;
                s_val = str(q_dict.get("search", "Software Engineer"));
                l_val = str(q_dict.get("location", "Remote"));
                sal_val = f" · ${q_dict.get('salary')}+" if q_dict.get("salary") else "";
                ct_val = f" · {q_dict.get('contract_type')}" if q_dict.get("contract_type") else "";
                tailored_summary = f"{s_val} · {l_val}{sal_val}{ct_val}";
                if q_dict.get("search") {
                    query = str(q_dict.get("search"));
                    tailored_query = str(q_dict.get("search"));
                }
                if q_dict.get("location") {
                    loc_val = str(q_dict.get("location"));
                    tailored_loc_query = loc_val;
                    split_locs = [x.strip() for x in loc_val.split(",") if x.strip()];
                    norm_locs: list[str] = [];
                    idx = 0;
                    while idx < len(split_locs) {
                        part = split_locs[idx];
                        if idx + 1 < len(split_locs) and len(split_locs[idx + 1]) == 2 and split_locs[idx + 1].isupper() {
                            norm_locs.append(f"{part}, {split_locs[idx + 1]}");
                            idx = idx + 2;
                        } else {
                            norm_locs.append(part);
                            idx = idx + 1;
                        }
                    }
                    locs_to_set = norm_locs if norm_locs else [loc_val];
                    locations_filter = locs_to_set;
                    tailored_locations = list(locs_to_set);
                }
                if q_dict.get("contract_type") {
                    raw_ct = str(q_dict.get("contract_type")).strip();
                    if raw_ct {
                        parsed_ct = [c.strip() for c in raw_ct.split(",") if c.strip()];
                        if parsed_ct {
                            contract_types_filter = parsed_ct;
                        }
                    }
                }
                if q_dict.get("sector") {
                    raw_sec = str(q_dict.get("sector")).strip();
                    if raw_sec {
                        parsed_sec = [s.strip() for s in raw_sec.split(",") if s.strip()];
                        if parsed_sec {
                            sectors_filter = parsed_sec;
                        }
                    }
                }
            }
        }
        if not init_jobs {
            init_jobs = await list_jobs();
        }
        jobs = init_jobs;
        tailored_jobs = init_jobs;
        loading = False;

        # Score every job against the resume saved in the user's profile.
        # This runs after the jobs are on screen, so the badges appear a
        # moment later instead of slowing down the page.
        match_res: any = None;
        try {
            match_res = await get_resume_match_scores(jobs=init_jobs, token=tok);
        } except Exception {}
        if match_res and match_res.get("ok") {
            has_resume = bool(match_res.get("has_resume"));
            if match_res.get("scores") {
                match_rows = match_res.get("scores");
            }
        }
    }

    # Find the score row for one job (None if it has no score).
    def match_for(j: dict[str, any]) -> dict[str, any] | None {
        jid = str(j.get("id", ""));
        for m in match_rows {
            if str(m.get("id", "")) == jid {
                return m;
            }
        }
        return None;
    }

    # The number to show on a job card, or -1 to show no badge.
    def card_score(j: dict[str, any]) -> int {
        m = match_for(j);
        if m is None {
            return -1;
        }
        return int(m.get("score", 0));
    }

    async def open_city_dropdown(e: any = None) {
        city_dropdown_open = True;
        query_to_search = "" if loc_query == "Remote" else loc_query;
        try {
            matches = await search_cities(query_to_search, 10);
            city_suggestions = matches if matches else ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        } except Exception {
            city_suggestions = ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        }
    }

    async def handle_loc_search(e: ChangeEvent) {
        val = e.target.value;
        loc_query = val;
        city_dropdown_open = True;
        try {
            matches = await search_cities(val, 10);
            city_suggestions = matches if matches else ["Remote"];
        } except Exception {
            city_suggestions = ["Remote"];
        }
    }

    def add_location(city_label: str) {
        clean_lbl = city_label.strip();
        if clean_lbl and clean_lbl not in locations_filter {
            locations_filter = locations_filter + [clean_lbl];
        }
        loc_query = "";
        city_dropdown_open = False;
    }

    def remove_location(city_label: str) {
        locations_filter = [l for l in locations_filter if l != city_label];
    }

    def toggle_remote {
        if "Remote" in locations_filter {
            locations_filter = [l for l in locations_filter if l != "Remote"];
        } else {
            locations_filter = locations_filter + ["Remote"];
        }
    }

    def toggle_contract_type_filter(ct: str) {
        if ct in contract_types_filter {
            contract_types_filter = [c for c in contract_types_filter if c != ct];
        } else {
            contract_types_filter = contract_types_filter + [ct];
        }
    }

    def toggle_sector_filter(sec: str) {
        if sec in sectors_filter {
            sectors_filter = [s for s in sectors_filter if s != sec];
        } else {
            sectors_filter = sectors_filter + [sec];
        }
    }

    async def execute_search(e: any = None) {
        if e and hasattr(e, "preventDefault") {
            try {
                e.preventDefault();
            } except Exception {}
        }
        city_dropdown_open = False;
        searching = True;
        sal_val_num: int | None = None;
        if salary_min_filter.strip() {
            try {
                sal_val_num = int(salary_min_filter.replace(",", "").replace("$", "").strip());
            } except Exception {
                sal_val_num = None;
            }
        }

        active_locs = list(locations_filter);
        if loc_query.strip() and loc_query.strip() not in active_locs {
            active_locs.append(loc_query.strip());
        }

        loc_arg = ", ".join(active_locs) if active_locs else None;
        ct_arg = ", ".join(contract_types_filter) if contract_types_filter else None;
        sec_arg = ", ".join(sectors_filter) if sectors_filter else None;

        res: any = None;
        try {
            res = await search_jobs(
                search=query.strip(),
                location=loc_arg,
                salary=sal_val_num,
                contract_type=ct_arg,
                company=company_filter.strip() if company_filter.strip() else None,
                sector=sec_arg,
                source=source_filter if source_filter else "all",
                n=20
            );
        } except Exception {}

        if res and res.get("ok") and isinstance(res.get("jobs"), list) {
            jobs = res.get("jobs");
        } else {
            jobs = [];
        }
        is_custom_search = True;

        parts: list[str] = [];
        if query.strip() {
            parts.append(query.strip());
        }
        if active_locs {
            parts.append(", ".join(active_locs));
        }
        if sectors_filter {
            parts.append(", ".join(sectors_filter));
        }
        if sal_val_num {
            parts.append(f"${sal_val_num:,}+");
        }
        if contract_types_filter {
            parts.append(", ".join(contract_types_filter));
        }
        if company_filter.strip() {
            parts.append(company_filter.strip());
        }
        if source_filter and source_filter != "all" {
            parts.append(f"via {source_filter}");
        }
        custom_summary = " · ".join(parts) if parts else "Custom criteria";

        if len(jobs) > 0 {
            selected_id = str(jobs[0].get("id", ""));
        } else {
            selected_id = "";
        }
        searching = False;
    }

    def reset_to_tailored {
        jobs = tailored_jobs;
        is_custom_search = False;
        custom_summary = "";
        salary_min_filter = "";
        contract_types_filter = [];
        sectors_filter = [];
        company_filter = "";
        source_filter = "all";
        query = tailored_query;
        loc_query = "";
        locations_filter = list(tailored_locations) if tailored_locations else (["Remote"] if tailored_loc_query else []);
        city_dropdown_open = False;
        if len(tailored_jobs) > 0 {
            selected_id = str(tailored_jobs[0].get("id", ""));
        }
    }

    def clear_filters {
        query = "";
        loc_query = "";
        locations_filter = [];
        salary_min_filter = "";
        contract_types_filter = [];
        sectors_filter = [];
        company_filter = "";
        source_filter = "all";
        city_dropdown_open = False;
    }

    def matches(j: dict[str, any]) -> bool {
        if is_custom_search {
            return True;
        }
        hay = (str(j.get("title", "")) + " " + str(j.get("company", "")) + " " + str(j.get("tags", ""))).lower();
        matches_q = query.strip().lower() in hay if query.strip() else True;
        matches_l = True;
        if locations_filter {
            j_loc = str(j.get("location", "")).lower();
            matched_any = False;
            for loc_f in locations_filter {
                lf_low = loc_f.lower();
                if "remote" in lf_low {
                    if "remote" in j_loc {
                        matched_any = True;
                        break;
                    }
                } elif lf_low in j_loc or j_loc in lf_low {
                    matched_any = True;
                    break;
                }
            }
            matches_l = matched_any;
        } elif loc_query.strip() {
            matches_l = loc_query.strip().lower() in str(j.get("location", "")).lower();
        }
        return matches_q and matches_l;
    }

    filtered = [j for j in jobs if matches(j)];
    sel: dict[str, any] | None = None;
    for j in filtered {
        if str(j.get("id", "")) == str(selected_id) {
            sel = j;
        }
    }
    if sel is None and len(filtered) > 0 {
        sel = filtered[0];
    }
    sel_match = match_for(sel) if sel is not None else None;

    def is_saved(j: dict[str, any]) -> bool {
        jid = str(j.get("id", ""));
        for sid in saved_ids {
            if sid == jid {
                return True;
            }
        }
        return False;
    }

    def toggle_save(j: dict[str, any]) {
        jid = str(j.get("id", ""));
        if is_saved(j) {
            saved_ids = [sid for sid in saved_ids if sid != jid];
        } else {
            saved_ids = saved_ids + [jid];
        }
    }

    def toggle_selected_save {
        if sel is not None {
            toggle_save(sel);
        }
    }

    def handle_query(e: ChangeEvent) { query = e.target.value; }
    def handle_salary_filter(e: ChangeEvent) { salary_min_filter = e.target.value; }
    def handle_company_filter(e: ChangeEvent) { company_filter = e.target.value; }
    def handle_source_filter(e: ChangeEvent) { source_filter = e.target.value; }

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-6 pt-8 pb-16 pl-6 pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
            {loading and <div className="flex items-center justify-center p-16"><Spinner /></div>}
            {(not loading) and <div className="flex flex-col gap-6">
                {(not is_custom_search) and is_tailored and bool(tailored_summary) and <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/30 bg-primary/10 px-5 py-3 text-sm text-foreground shadow-xs animate-in fade-in duration-300">
                    <div className="flex items-center gap-2">
                        <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} className="size-4 text-primary shrink-0" />
                        <span>
                            {"Showing jobs tailored to your preferences: "}
                            <strong className="font-semibold text-primary">{tailored_summary}</strong>
                        </span>
                    </div>
                    <Link to="/me" className="inline-flex items-center gap-1 font-medium text-primary hover:underline text-xs">
                        Edit in Profile →
                    </Link>
                </div>}

                {(not has_resume) and <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-dashed bg-card px-5 py-3 text-sm text-muted-foreground">
                    <span>Upload your resume in your profile to see how well you match each job.</span>
                    <Link to="/me" className="font-medium text-primary hover:underline text-xs">Add resume →</Link>
                </div>}
                {is_custom_search and <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/30 bg-card px-5 py-3 text-sm text-foreground shadow-xs animate-in fade-in duration-300">
                    <div className="flex items-center gap-2">
                        <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="size-4 text-primary shrink-0" />
                        <span>
                            {"Custom search: "}
                            <strong className="font-semibold text-primary">{custom_summary}</strong>
                            <span className="text-muted-foreground ml-1.5">{str(len(filtered)) + " results"}</span>
                        </span>
                    </div>
                    <button type="button" onClick={reset_to_tailored} className="inline-flex items-center gap-1.5 font-medium text-primary hover:underline text-xs cursor-pointer">
                        <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} className="size-3.5" />
                        Reset to Profile Recommendations
                    </button>
                </div>}

                <form onSubmit={execute_search} className="mx-auto flex w-full max-w-3xl flex-col gap-3">
                    <div className="flex flex-col items-stretch gap-2 rounded-2xl border border-primary/40 bg-card p-3 shadow-sm sm:flex-row sm:items-center">
                        <div className="relative flex-1">
                            <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                            <Input value={query} onChange={handle_query} placeholder="Job title, keywords, or company" className="border-0 bg-transparent pl-9 shadow-none focus-visible:ring-0" />
                        </div>
                        <div className="hidden h-8 w-px bg-border sm:block" />
                        <div className="relative flex flex-1 items-center gap-2">
                            <div className="relative flex-1">
                                <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="pointer-events-none absolute left-2 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input
                                    value={loc_query}
                                    onChange={handle_loc_search}
                                    onFocus={open_city_dropdown}
                                    placeholder="Add city or location..."
                                    className="border-0 bg-transparent pl-8 shadow-none focus-visible:ring-0"
                                />
                                {city_dropdown_open and len(city_suggestions) > 0 and <div className="absolute top-full left-0 mt-2 max-h-48 w-64 overflow-y-auto rounded-xl border border-border bg-popover p-1 shadow-lg z-50">
                                    <div className="px-2 py-1 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Suggested Locations</div>
                                    {for suggestion in city_suggestions {
                                        <div
                                            key={suggestion}
                                            onMouseDown={lambda { add_location(suggestion); }}
                                            className="cursor-pointer rounded-lg px-2.5 py-1.5 text-xs text-foreground hover:bg-muted transition-colors flex items-center justify-between"
                                        >
                                            <span>{suggestion}</span>
                                            {suggestion in locations_filter and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2.5} className="size-3.5 text-primary" />}
                                        </div>
                                    }}
                                </div>}
                            </div>
                            <Button
                                type="button"
                                variant={("secondary" if show_filters else "ghost")}
                                size="sm"
                                className="shrink-0 rounded-full px-3 text-xs"
                                onClick={lambda { show_filters = not show_filters; }}
                                aria-label="Toggle search filters"
                            >
                                <HugeiconsIcon icon={FilterHorizontalIcon} strokeWidth={2} className="size-3.5 mr-1" />
                                Filters
                            </Button>
                            <Button type="submit" disabled={searching} className="shrink-0 rounded-full shadow-sm">
                                {("Searching..." if searching else "Search")}
                            </Button>
                        </div>
                    </div>

                    {(len(locations_filter) > 0) and <div className="flex flex-wrap items-center gap-1.5 px-2">
                        <span className="text-[11px] font-medium text-muted-foreground mr-1">Locations:</span>
                        <button
                            type="button"
                            onClick={toggle_remote}
                            className={"inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors cursor-pointer " + ("bg-primary text-primary-foreground shadow-xs" if "Remote" in locations_filter else "border border-dashed border-primary/40 bg-background text-primary hover:bg-primary/5")}
                        >
                            {("✓ Remote" if "Remote" in locations_filter else "+ Remote")}
                        </button>
                        {for loc_item in locations_filter {
                            if loc_item != "Remote" {
                                <span key={loc_item} className="inline-flex items-center gap-1 rounded-full border border-primary/20 bg-primary/10 px-2.5 py-0.5 text-xs font-medium text-primary">
                                    {loc_item}
                                    <button
                                        type="button"
                                        onClick={lambda { remove_location(loc_item); }}
                                        className="hover:text-destructive text-primary/70 ml-0.5 cursor-pointer"
                                        aria-label={"Remove " + loc_item}
                                    >
                                        ✕
                                    </button>
                                </span>
                            }
                        }}
                        <button
                            type="button"
                            onClick={lambda { locations_filter = []; }}
                            className="text-[11px] text-muted-foreground hover:text-foreground cursor-pointer ml-1"
                        >
                            Clear all
                        </button>
                    </div>}

                    {(len(locations_filter) == 0) and <div className="flex items-center gap-1.5 px-2">
                        <button
                            type="button"
                            onClick={toggle_remote}
                            className="inline-flex items-center gap-1 rounded-full border border-dashed border-primary/40 bg-background px-2.5 py-0.5 text-xs font-medium text-primary hover:bg-primary/5 cursor-pointer"
                        >
                            + Remote
                        </button>
                    </div>}

                    {show_filters and <div className="rounded-2xl border border-border bg-card p-4 shadow-sm flex flex-col gap-4 animate-in fade-in slide-in-from-top-2 duration-200">
                        <div className="flex items-center justify-between pb-2 border-b">
                            <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Custom Search Parameters</span>
                            <button
                                type="button"
                                onClick={clear_filters}
                                className="text-xs text-muted-foreground hover:text-foreground hover:underline cursor-pointer"
                            >
                                Clear filters
                            </button>
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Min Salary ($/yr)</label>
                                <Input
                                    value={salary_min_filter}
                                    onChange={handle_salary_filter}
                                    placeholder="e.g. 100000"
                                    className="h-8 text-xs"
                                />
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Company</label>
                                <Input
                                    value={company_filter}
                                    onChange={handle_company_filter}
                                    placeholder="e.g. Google, Lumen"
                                    className="h-8 text-xs"
                                />
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Job Board Source</label>
                                <select
                                    value={source_filter}
                                    onChange={handle_source_filter}
                                    className="h-8 rounded-md border border-input bg-background px-2 text-xs text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary"
                                >
                                    <option value="all">All Sources</option>
                                    <option value="jooble">Jooble</option>
                                    <option value="usajobs">USAJobs</option>
                                    <option value="himalayas">Himalayas</option>
                                    <option value="themuse">The Muse</option>
                                </select>
                            </div>
                        </div>

                        <div className="flex flex-col gap-1.5 pt-2 border-t">
                            <div className="flex items-center justify-between">
                                <label className="text-xs font-medium text-foreground">Contract Type (select multiple)</label>
                                <span className="text-[11px] text-muted-foreground">
                                    {(str(len(contract_types_filter)) + " selected") if len(contract_types_filter) > 0 else "Any Type (All)"}
                                </span>
                            </div>
                            <div className="flex flex-wrap gap-1.5 pt-0.5">
                                {for ct in ALL_CONTRACT_TYPES {
                                    <button
                                        key={ct}
                                        type="button"
                                        onClick={lambda { toggle_contract_type_filter(ct); }}
                                        className={"inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-medium transition-all cursor-pointer " + ("bg-primary text-primary-foreground shadow-xs ring-1 ring-primary" if ct in contract_types_filter else "border border-input bg-background hover:bg-muted text-muted-foreground")}
                                    >
                                        {ct in contract_types_filter and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2.5} className="size-3.5" />}
                                        {ct}
                                    </button>
                                }}
                            </div>
                        </div>

                        <div className="flex flex-col gap-1.5 pt-2 border-t">
                            <div className="flex items-center justify-between">
                                <label className="text-xs font-medium text-foreground">Sector / Industry (select multiple)</label>
                                <div className="flex items-center gap-2">
                                    <span className="text-[11px] text-muted-foreground">
                                        {(str(len(sectors_filter)) + " selected") if len(sectors_filter) > 0 else "All Sectors"}
                                    </span>
                                    {len(sectors_filter) > 0 and <button
                                        type="button"
                                        onClick={lambda { sectors_filter = []; }}
                                        className="text-[11px] text-muted-foreground hover:text-foreground hover:underline cursor-pointer"
                                    >
                                        Clear
                                    </button>}
                                </div>
                            </div>
                            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-1.5 pt-0.5">
                                {for sec in POPULAR_SECTORS {
                                    <button
                                        key={sec}
                                        type="button"
                                        onClick={lambda { toggle_sector_filter(sec); }}
                                        className={"inline-flex items-center justify-between gap-1 rounded-lg border px-2.5 py-1.5 text-xs font-medium transition-all text-left cursor-pointer " + ("border-primary bg-primary/10 text-primary font-semibold ring-1 ring-primary/30" if sec in sectors_filter else "border-input bg-background hover:bg-muted text-foreground/80")}
                                    >
                                        <span className="truncate">{sec}</span>
                                        {sec in sectors_filter and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2.5} className="size-3.5 shrink-0 text-primary" />}
                                    </button>
                                }}
                            </div>
                        </div>

                        <div className="flex items-center justify-end gap-2 pt-1 border-t">
                            <Button type="submit" size="sm" disabled={searching} className="rounded-full shadow-xs text-xs">
                                {("Searching..." if searching else "Apply Parameters & Search")}
                            </Button>
                        </div>
                    </div>}
                </form>

                {len(filtered) == 0 and <Empty className="border border-dashed bg-card pt-12 pb-12">
                    <EmptyHeader>
                        <EmptyMedia variant="icon"><HugeiconsIcon icon={Search01Icon} strokeWidth={2} /></EmptyMedia>
                        <EmptyTitle>No matching jobs</EmptyTitle>
                        <EmptyDescription>Try adjusting your search terms, removing filters, or searching remote roles.</EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent className="flex flex-wrap items-center justify-center gap-2">
                        <Button variant="outline" onClick={clear_filters}>Clear filters</Button>
                        {is_custom_search and <Button onClick={reset_to_tailored}>Reset to Profile Matches</Button>}
                    </EmptyContent>
                </Empty>}

                {len(filtered) > 0 and <div className="grid gap-6 lg:grid-cols-5">
                    <section className="flex flex-col gap-3 lg:col-span-2">
                        <div className="flex items-center justify-between">
                            <h2 className="text-lg font-semibold tracking-tight">
                                {("Custom Search Results" if is_custom_search else "Based on your preferences")}
                            </h2>
                            <span className="text-xs text-muted-foreground">{str(len(filtered)) + " jobs"}</span>
                        </div>
                        {for j in filtered {
                            <JobCard
                                key={str(j.get("id", ""))}
                                title={str(j.get("title", ""))}
                                company={str(j.get("company", ""))}
                                location={str(j.get("location", ""))}
                                salary={str(j.get("salary", ""))}
                                tags={str(j.get("tags", ""))}
                                logo={str(j.get("logo") or j.get("companyLogo") or j.get("company_logo") or "")}
                                source={str(j.get("source") or j.get("site") or "")}
                                match_score={card_score(j)}
                                active={sel is not None and str(sel.get("id", "")) == str(j.get("id", ""))}
                                saved={is_saved(j)}
                                onSelect={lambda { selected_id = str(j.get("id", "")); }}
                                onSave={lambda { toggle_save(j); }}
                            />
                        }}
                    </section>
                    <section className="lg:col-span-3">
                        {sel is not None and <Card className="shadow-sm lg:sticky lg:top-24 max-h-[calc(100vh-7rem)] flex flex-col overflow-hidden">
                            <CardContent className="flex flex-col gap-4 pt-8 pb-8 overflow-y-auto">
                                <div className="flex flex-wrap items-start justify-between gap-3">
                                    <div className="flex items-center gap-3 min-w-0">
                                        {bool(str(sel.get("logo") or sel.get("companyLogo") or sel.get("company_logo") or "")) and <img
                                            src={str(sel.get("logo") or sel.get("companyLogo") or sel.get("company_logo") or "")}
                                            alt={str(sel.get("company", "")) + " logo"}
                                            className="size-12 rounded-lg border bg-background object-contain shrink-0 p-1"
                                        />}
                                        <div className="flex flex-col gap-1 min-w-0">
                                            <h2 className="text-2xl font-semibold tracking-tight">{str(sel.get("title", ""))}</h2>
                                            <p className="text-muted-foreground">{str(sel.get("company", ""))}</p>
                                        </div>
                                    </div>
                                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                                        <Badge variant="outline">{str(sel.get("type", "Full-time"))}</Badge>
                                        {bool(str(sel.get("source") or sel.get("site") or "")) and <span className="text-xs text-muted-foreground">{"via " + str(sel.get("source") or sel.get("site") or "")}</span>}
                                    </div>
                                </div>
                                <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                                    <span>{str(sel.get("location", ""))}</span>
                                    {bool(format_salary(str(sel.get("salary", "")))) and <span aria-hidden="true">·</span>}
                                    {bool(format_salary(str(sel.get("salary", "")))) and <span className="tabular-nums font-medium text-foreground">{format_salary(str(sel.get("salary", "")))}</span>}
                                </div>
                                {sel_match is not None and <div className="flex flex-col gap-1 rounded-lg border border-primary/30 bg-primary/5 p-3 text-sm">
                                    <p className="font-medium">{"Your match: " + str(sel_match.get("score", 0)) + "% (" + str(sel_match.get("label", "")) + ")"}</p>
                                    <p className="text-muted-foreground">{"Matched skills: " + (str(sel_match.get("matched", "")) or "none")}</p>
                                    <p className="text-muted-foreground">{"Missing skills: " + (str(sel_match.get("missing", "")) or "none")}</p>
                                </div>}
                                <div className="text-sm leading-relaxed text-foreground/90 space-y-2 whitespace-pre-wrap">{str(sel.get("desc", "")).replace("<br />", "\n").replace("<br>", "\n").replace("</p>", "\n").replace("<p>", "")}</div>
                                <div className="flex flex-wrap gap-1.5">
                                    {for tag in str(sel["tags"] if (sel and "tags" in sel) else "").split(", ") {
                                        <Badge key={tag} variant="secondary" className="font-normal">{tag}</Badge>
                                    }}
                                </div>
                                <div className="mt-2 flex flex-wrap items-center gap-3 border-t pt-4">
                                    <Button className="shadow-sm" onClick={lambda { nav("/tools?job=" + str(sel["id"])); }}>Apply now (demo)</Button>
                                    <Button variant="outline" onClick={lambda { toggle_selected_save(); }}>{("Saved" if is_saved(sel) else "Save job")}</Button>
                                    <Button variant="ghost" size="sm" onClick={lambda { jacLogout(); }}>
                                        <HugeiconsIcon icon={Logout01Icon} strokeWidth={2} className="size-4" /> Sign out
                                    </Button>
                                </div>
                            </CardContent>
                        </Card>}
                    </section>
                </div>}
            </div>}
        </main>
        <SiteFooter />
    </div>;
}

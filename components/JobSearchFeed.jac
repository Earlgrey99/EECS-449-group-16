import from "@jac/runtime" { Link, useNavigate, jacIsLoggedIn, Navigate, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, Bookmark01Icon, Logout01Icon, SparklesIcon, FilterHorizontalIcon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.badge { Badge }
import from .ui.card { Card, CardContent }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.jobs { list_jobs, get_user_tailored_jobs, search_jobs }
import from ..lib.utils { format_salary, format_desc }

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
    source: str = ""
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

def:pub JobSearchFeed() -> JsxElement {
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
    has tailored_query: str = "";
    has tailored_loc_query: str = "";
    has selected_id: int = 0;
    has saved_ids: list[int] = [];
    has is_tailored: bool = False;
    has tailored_summary: str = "";
    has is_custom_search: bool = False;
    has custom_summary: str = "";
    has show_filters: bool = False;
    has salary_min_filter: str = "";
    has contract_type_filter: str = "";
    has company_filter: str = "";
    has source_filter: str = "all";

    async can with entry {
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
                sal_val = f" · ${q_dict.get("salary")}+" if q_dict.get("salary") else "";
                ct_val = f" · {q_dict.get("contract_type")}" if q_dict.get("contract_type") else "";
                tailored_summary = f"{s_val} · {l_val}{sal_val}{ct_val}";
                if q_dict.get("search") {
                    query = str(q_dict.get("search"));
                    tailored_query = str(q_dict.get("search"));
                }
                if q_dict.get("location") {
                    loc_query = str(q_dict.get("location"));
                    tailored_loc_query = str(q_dict.get("location"));
                }
            }
        }
        if not init_jobs {
            init_jobs = await list_jobs();
        }
        jobs = init_jobs;
        tailored_jobs = init_jobs;
        loading = False;
    }

    async def execute_search(e: any = None) {
        if e and hasattr(e, "preventDefault") {
            try {
                e.preventDefault();
            } except Exception {}
        }
        searching = True;
        sal_val_num: int | None = None;
        if salary_min_filter.strip() {
            try {
                sal_val_num = int(salary_min_filter.replace(",", "").replace("$", "").strip());
            } except Exception {
                sal_val_num = None;
            }
        }
        res: any = None;
        try {
            res = await search_jobs(
                search=query.strip(),
                location=loc_query.strip() if loc_query.strip() else None,
                salary=sal_val_num,
                contract_type=contract_type_filter if (contract_type_filter != "All" and contract_type_filter) else None,
                company=company_filter.strip() if company_filter.strip() else None,
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
        if loc_query.strip() {
            parts.append(loc_query.strip());
        }
        if sal_val_num {
            parts.append(f"${sal_val_num:,}+");
        }
        if contract_type_filter and contract_type_filter != "All" {
            parts.append(contract_type_filter);
        }
        if company_filter.strip() {
            parts.append(company_filter.strip());
        }
        if source_filter and source_filter != "all" {
            parts.append(f"via {source_filter}");
        }
        custom_summary = " · ".join(parts) if parts else "Custom criteria";

        if len(jobs) > 0 {
            selected_id = int(jobs[0].get("id", 0));
        } else {
            selected_id = 0;
        }
        searching = False;
    }

    def reset_to_tailored {
        jobs = tailored_jobs;
        is_custom_search = False;
        custom_summary = "";
        salary_min_filter = "";
        contract_type_filter = "";
        company_filter = "";
        source_filter = "all";
        query = tailored_query;
        loc_query = tailored_loc_query;
        if len(tailored_jobs) > 0 {
            selected_id = int(tailored_jobs[0].get("id", 0));
        }
    }

    def clear_filters {
        query = "";
        loc_query = "";
        salary_min_filter = "";
        contract_type_filter = "";
        company_filter = "";
        source_filter = "all";
    }

    def matches(j: dict[str, any]) -> bool {
        if is_custom_search {
            return True;
        }
        hay = (str(j.get("title", "")) + " " + str(j.get("company", "")) + " " + str(j.get("tags", ""))).lower();
        return query.strip().lower() in hay and loc_query.strip().lower() in str(j.get("location", "")).lower();
    }

    filtered = [j for j in jobs if matches(j)];
    sel: dict[str, any] | None = None;
    for j in filtered {
        if int(j.get("id", 0)) == selected_id {
            sel = j;
        }
    }
    if sel is None and len(filtered) > 0 {
        sel = filtered[0];
    }

    def is_saved(j: dict[str, any]) -> bool {
        jid = int(j.get("id", 0));
        for sid in saved_ids {
            if sid == jid {
                return True;
            }
        }
        return False;
    }

    def toggle_save(j: dict[str, any]) {
        jid = int(j.get("id", 0));
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
    def handle_loc(e: ChangeEvent) { loc_query = e.target.value; }
    def handle_salary_filter(e: ChangeEvent) { salary_min_filter = e.target.value; }
    def handle_contract_type_filter(e: ChangeEvent) { contract_type_filter = e.target.value; }
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
                        <div className="flex flex-1 items-center gap-2">
                            <Input value={loc_query} onChange={handle_loc} placeholder="City, State, or Remote" className="border-0 bg-transparent shadow-none focus-visible:ring-0" />
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

                        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3">
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
                                <label className="text-xs font-medium text-foreground">Job Type</label>
                                <select
                                    value={contract_type_filter}
                                    onChange={handle_contract_type_filter}
                                    className="h-8 rounded-md border border-input bg-background px-2 text-xs text-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary"
                                >
                                    <option value="">Any Type</option>
                                    <option value="Full-time">Full-time</option>
                                    <option value="Part-time">Part-time</option>
                                    <option value="Contract">Contract</option>
                                    <option value="Internship">Internship</option>
                                </select>
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

                        <div className="flex items-center justify-end gap-2 pt-1">
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
                                active={sel is not None and int(sel.get("id", 0)) == int(j.get("id", 0))}
                                saved={is_saved(j)}
                                onSelect={lambda { selected_id = int(j.get("id", 0)); }}
                                onSave={lambda { toggle_save(j); }}
                            />
                        }}
                    </section>
                    <section className="lg:col-span-3">
                        {sel is not None and <Card className="shadow-sm lg:sticky lg:top-24">
                            <CardContent className="flex flex-col gap-4 pt-8 pb-8">
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
                                <div className="text-sm leading-relaxed text-foreground/90 space-y-2" dangerouslySetInnerHTML={{"__html": format_desc(str(sel.get("desc", "")))}}></div>
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

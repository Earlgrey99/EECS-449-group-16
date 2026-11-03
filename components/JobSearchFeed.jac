import from "@jac/runtime" { Link, useNavigate, jacIsLoggedIn, Navigate, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, Bookmark01Icon, Logout01Icon, SparklesIcon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.badge { Badge }
import from .ui.card { Card, CardContent }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.jobs { list_jobs, get_user_tailored_jobs }
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
    has loading: bool = True;
    has query: str = "";
    has loc_query: str = "";
    has selected_id: int = 0;
    has saved_ids: list[int] = [];
    has is_tailored: bool = False;
    has tailored_summary: str = "";

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
                sal_val = f" · ${q_dict.get('salary')}+" if q_dict.get("salary") else "";
                ct_val = f" · {q_dict.get('contract_type')}" if q_dict.get("contract_type") else "";
                tailored_summary = f"{s_val} · {l_val}{sal_val}{ct_val}";
                if q_dict.get("search") {
                    query = str(q_dict.get("search"));
                }
                if q_dict.get("location") {
                    loc_query = str(q_dict.get("location"));
                }
            }
        }
        if not init_jobs {
            init_jobs = await list_jobs();
        }
        jobs = init_jobs;
        loading = False;
    }

    def matches(j: dict[str, any]) -> bool {
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

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-6 pt-8 pb-16 pl-6 pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
            {loading and <div className="flex items-center justify-center p-16"><Spinner /></div>}
            {(not loading) and <div className="flex flex-col gap-6">
                {is_tailored and bool(tailored_summary) and <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-primary/30 bg-primary/10 px-5 py-3 text-sm text-foreground shadow-xs animate-in fade-in duration-300">
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

                <div className="mx-auto flex w-full max-w-2xl flex-col items-stretch gap-2 rounded-2xl border border-primary/40 bg-card p-3 shadow-sm sm:flex-row sm:items-center">
                    <div className="relative flex-1">
                        <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                        <Input value={query} onChange={handle_query} placeholder="Find jobs" className="border-0 bg-transparent pl-9 shadow-none focus-visible:ring-0" />
                    </div>
                    <div className="hidden h-8 w-px bg-border sm:block" />
                    <div className="flex flex-1 items-center gap-2">
                        <Input value={loc_query} onChange={handle_loc} placeholder="Current Location" className="border-0 bg-transparent shadow-none focus-visible:ring-0" />
                        <Button className="shrink-0 rounded-full shadow-sm">Search</Button>
                    </div>
                </div>

                {len(filtered) == 0 and <Empty className="border border-dashed bg-card pt-12 pb-12">
                    <EmptyHeader>
                        <EmptyMedia variant="icon"><HugeiconsIcon icon={Search01Icon} strokeWidth={2} /></EmptyMedia>
                        <EmptyTitle>No matching jobs</EmptyTitle>
                        <EmptyDescription>Try a different role, company, or location.</EmptyDescription>
                    </EmptyHeader>
                    <EmptyContent><Button variant="outline" onClick={lambda { query = ""; loc_query = ""; }}>Clear search</Button></EmptyContent>
                </Empty>}

                {len(filtered) > 0 and <div className="grid gap-6 lg:grid-cols-5">
                    <section className="flex flex-col gap-3 lg:col-span-2">
                        <h2 className="text-lg font-semibold tracking-tight">Based on your preferences</h2>
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

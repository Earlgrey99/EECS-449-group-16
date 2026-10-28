import from "@jac/runtime" { jacIsLoggedIn, Navigate, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, Bookmark01Icon, Logout01Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.badge { Badge }
import from .ui.card { Card, CardContent }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.jobs { list_jobs }
import from ..services.compatibility { score_jobs }

def:pub JobCard(title: str, company: str, location: str, salary: str, tags: str, match_score: int, active: bool, saved: bool, onSelect: Callable[[], None], onSave: Callable[[], None]) -> JsxElement {
    return <Card className={"cursor-pointer transition-all hover:-translate-y-0.5 hover:shadow-md " + ("ring-2 ring-primary" if active else "shadow-sm")} onClick={onSelect}>
        <CardContent className="flex flex-col gap-1.5 pt-5">
            <div className="flex items-start justify-between gap-2">
                <h3 className="font-semibold leading-tight">{title}</h3>
                <button onClick={onSave} className="shrink-0 rounded p-1 transition-colors hover:bg-muted" aria-label="Save job">
                    <HugeiconsIcon icon={Bookmark01Icon} strokeWidth={2} className={"size-4 " + ("fill-current text-primary" if saved else "text-muted-foreground")} />
                </button>
            </div>
            <p className="text-sm text-muted-foreground">{company}</p>
            <p className="text-sm text-muted-foreground">{location}</p>
            <p className="text-sm font-medium tabular-nums">{"$" + salary}</p>
            {match_score >= 0 and <Badge variant={("default" if match_score >= 75 else ("secondary" if match_score >= 50 else "outline"))} className="w-fit tabular-nums">{str(match_score) + "% match"}</Badge>}
            <div className="mt-1 flex flex-wrap gap-1.5">
                {for tag in tags.split(", ")[:2] {
                    <Badge key={tag} variant="secondary" className="font-normal">{tag}</Badge>
                }}
            </div>
        </CardContent>
    </Card>;
}

def:pub JobSearchFeed() -> JsxElement {
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }
    has jobs: list[dict[str, str | int]] = [];
    has loading: bool = True;
    has query: str = "";
    has loc_query: str = "";
    has selected_id: int = 0;
    has saved_ids: list[int] = [];
    has resume_text: str = "";
    has match_rows: list[dict[str, str | int]] = [];
    has scoring: bool = False;
    has score_message: str = "";

    async can with entry {
        jobs = await list_jobs();
        loading = False;
    }

    def matches(j: dict[str, str | int]) -> bool {
        hay = (str(j["title"]) + " " + str(j["company"]) + " " + str(j["tags"])).lower();
        return query.strip().lower() in hay and loc_query.strip().lower() in str(j["location"]).lower();
    }

    filtered = [j for j in jobs if matches(j)];
    sel: dict[str, str | int] | None = None;
    for j in filtered {
        if int(j["id"]) == selected_id {
            sel = j;
        }
    }
    if sel is None and len(filtered) > 0 {
        sel = filtered[0];
    }

    def is_saved(j: dict[str, str | int]) -> bool {
        for sid in saved_ids {
            if sid == int(j["id"]) {
                return True;
            }
        }
        return False;
    }

    def toggle_save(j: dict[str, str | int]) {
        jid = int(j["id"]);
        if is_saved(j) {
            saved_ids = [sid for sid in saved_ids if sid != jid];
        } else {
            saved_ids = saved_ids + [jid];
        }
    }

    def toggle_selected_save() {
        if sel is not None {
            toggle_save(sel);
        }
    }

    def handle_query(e: ChangeEvent) { query = e.target.value; }
    def handle_loc(e: ChangeEvent) { loc_query = e.target.value; }
    def handle_resume(e: ChangeEvent) { resume_text = e.target.value; }

    # Ask the server to score every job against the pasted resume.
    async def check_matches() {
        if not resume_text.strip() {
            score_message = "Paste your resume first.";
            return;
        }
        scoring = True;
        score_message = "";
        try {
            match_rows = await score_jobs(resume_text, jobs);
        } except Exception {
            score_message = "Could not score the jobs. Please try again.";
        }
        scoring = False;
    }

    # Find the score row for one job (None if not scored yet).
    def match_for(j: dict[str, str | int]) -> dict[str, str | int] | None {
        for m in match_rows {
            if int(m["id"]) == int(j["id"]) {
                return m;
            }
        }
        return None;
    }

    # The number to show on a job card, or -1 to show nothing.
    def card_score(j: dict[str, str | int]) -> int {
        m = match_for(j);
        if m is None {
            return -1;
        }
        return int(m["score"]);
    }

    sel_match = match_for(sel) if sel is not None else None;

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-6 pt-8 pb-16 pl-6 pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
            {loading and <div className="flex items-center justify-center p-16"><Spinner /></div>}
            {not loading and <div className="flex flex-col gap-6">
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

                <Card className="mx-auto w-full max-w-2xl shadow-sm">
                    <CardContent className="flex flex-col gap-3 pt-5">
                        <h2 className="text-lg font-semibold tracking-tight">Check your match</h2>
                        <p className="text-sm text-muted-foreground">Paste your resume to see how well you fit each job.</p>
                        <textarea
                            value={resume_text}
                            onChange={handle_resume}
                            rows={6}
                            placeholder="Paste your resume text here"
                            className="w-full rounded-lg border border-input bg-transparent p-2.5 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-3 focus-visible:ring-ring/50"
                        />
                        <div className="flex flex-wrap items-center gap-3">
                            <Button onClick={lambda { check_matches(); }} disabled={scoring} className="shadow-sm">{"Scoring..." if scoring else "Check my match"}</Button>
                            {score_message and <p className="text-sm text-destructive">{score_message}</p>}
                        </div>
                    </CardContent>
                </Card>

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
                                key={str(j["id"])}
                                title={str(j["title"])}
                                company={str(j["company"])}
                                location={str(j["location"])}
                                salary={str(j["salary"])}
                                tags={str(j["tags"])}
                                match_score={card_score(j)}
                                active={sel is not None and int(sel["id"]) == int(j["id"])}
                                saved={is_saved(j)}
                                onSelect={lambda { selected_id = int(j["id"]); }}
                                onSave={lambda { toggle_save(j); }}
                            />
                        }}
                    </section>
                    <section className="lg:col-span-3">
                        {sel is not None and <Card className="shadow-sm lg:sticky lg:top-24">
                            <CardContent className="flex flex-col gap-4 pt-8 pb-8">
                                <div className="flex flex-wrap items-start justify-between gap-3">
                                    <div className="flex flex-col gap-1">
                                        <h2 className="text-2xl font-semibold tracking-tight">{str(sel["title"])}</h2>
                                        <p className="text-muted-foreground">{str(sel["company"])}</p>
                                    </div>
                                    <Badge variant="outline">{str(sel["type"])}</Badge>
                                </div>
                                <div className="flex flex-wrap gap-2 text-sm text-muted-foreground">
                                    <span>{str(sel["location"])}</span>
                                    <span aria-hidden="true">·</span>
                                    <span className="tabular-nums font-medium text-foreground">{"$" + str(sel["salary"])}</span>
                                </div>
                                {sel_match is not None and <div className="flex flex-col gap-1 rounded-lg border border-primary/30 bg-primary/5 p-3 text-sm">
                                    <p className="font-medium">{"Your match: " + str(sel_match["score"]) + "% (" + str(sel_match["label"]) + ")"}</p>
                                    <p className="text-muted-foreground">{"Matched skills: " + (str(sel_match["matched"]) or "none")}</p>
                                    <p className="text-muted-foreground">{"Missing skills: " + (str(sel_match["missing"]) or "none")}</p>
                                </div>}
                                <p className="text-sm leading-relaxed text-foreground/90">{str(sel["desc"])}</p>
                                <div className="flex flex-wrap gap-1.5">
                                    {for tag in str(sel["tags"]).split(", ") {
                                        <Badge key={tag} variant="secondary" className="font-normal">{tag}</Badge>
                                    }}
                                </div>
                                <div className="mt-2 flex flex-wrap items-center gap-3 border-t pt-4">
                                    <Button className="shadow-sm">Apply now</Button>
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
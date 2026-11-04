import from "@jac/runtime" {
    Link,
    useNavigate,
    jacIsLoggedIn,
}
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    UserAccountIcon,
    Location01Icon,
    Briefcase01Icon,
    File01Icon,
    CheckmarkCircle02Icon,
    Search01Icon,
    Upload01Icon,
    DollarCircleIcon
}
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.card { Card, CardContent }
import from .ui.badge { Badge }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.profile_llm { submit_profile_and_generate_query, get_user_profile_data }
import from ..services.locations { search_cities }

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

glob POPULAR_TITLES: list[str] = [
    "Software Engineer",
    "Frontend Developer",
    "Backend Engineer",
    "Full Stack Developer",
    "Data Analyst",
    "Data Scientist",
    "Machine Learning Engineer",
    "DevOps Engineer",
    "Product Designer",
    "Product Manager"
];

def:pub UserProfilePage -> JsxElement {
    nav = useNavigate();

    has email: str = "";
    has first_name: str = "";
    has last_name: str = "";
    has locations: list[str] = ["Remote"];
    has loc_search: str = "";
    has sectors: list[str] = ["Technology & Software"];
    has job_titles: str = "";
    has salary_min: str = "100000";
    has contract_types: list[str] = ["Full-time"];
    has resume_title: str = "";
    has resume_content: str = "";
    has existing_resume_title: str = "";

    has city_suggestions: list[str] = [];
    has city_dropdown_open: bool = False;

    has loading_initial: bool = True;
    has submitting: bool = False;
    has message: str = "";
    has is_returning_user: bool = False;
    has did_init_profile: bool = False;

    async can with entry {
        if did_init_profile {
            return;
        }
        did_init_profile = True;
        if not jacIsLoggedIn() {
            nav("/login");
            return;
        }

        # Initialize city suggestions with default top cities
        init_cities: list[str] = [];
        try {
            init_cities = await search_cities("", 10);
        } except Exception {
            init_cities = ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        }
        if not init_cities {
            init_cities = ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        }
        city_suggestions = init_cities;

        try {
            tok: str = "";
            try {
                tok = str(localStorage.getItem("jac_token") or "");
            } except Exception {}
            res = await get_user_profile_data(token=tok);
            if res and res.get("ok") {
                u = res.get("user", {});
                email_val = str(u.get("email", "") or "");
                if email_val and "@" in email_val {
                    email = email_val;
                }

                loaded_fn = str(u.get("first_name", "") or "");
                loaded_ln = str(u.get("last_name", "") or "");
                if not loaded_fn and u.get("name") {
                    full = str(u.get("name", "")).strip();
                    if " " in full {
                        parts = full.split(" ", 1);
                        loaded_fn = parts[0].strip();
                        loaded_ln = parts[1].strip();
                    } else {
                        loaded_fn = full;
                    }
                }
                first_name = loaded_fn;
                last_name = loaded_ln;

                if u.get("location") {
                    raw_loc = str(u.get("location")).strip();
                    if raw_loc {
                        split_locs = [x.strip() for x in raw_loc.split(",") if x.strip()];
                        # Detect composite labels like City, State
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
                        if norm_locs {
                            locations = norm_locs;
                        }
                    }
                }

                if u.get("sector") {
                    raw_sec = str(u.get("sector")).strip();
                    if raw_sec {
                        sec_list = [s.strip() for s in raw_sec.split(",") if s.strip()];
                        if sec_list {
                            sectors = sec_list;
                        }
                    }
                }
                if u.get("job_titles") {
                    job_titles = str(u.get("job_titles"));
                }
                if u.get("salary_min") is not None {
                    salary_min = str(u.get("salary_min"));
                }
                if u.get("contract_type") {
                    raw_ct = str(u.get("contract_type")).strip();
                    if raw_ct {
                        ct_list = [c.strip() for c in raw_ct.split(",") if c.strip()];
                        if ct_list {
                            contract_types = ct_list;
                        }
                    }
                }
                if bool(u.get("onboarding_completed")) {
                    is_returning_user = True;
                }
                latest_res = res.get("latest_resume");
                if latest_res and isinstance(latest_res, dict) {
                    existing_resume_title = str(latest_res.get("title", "Base Resume.pdf"));
                }
            }
        } except Exception {}
        loading_initial = False;
    }

    def handle_first_name(e: ChangeEvent) { first_name = e.target.value; }
    def handle_last_name(e: ChangeEvent) { last_name = e.target.value; }
    def handle_email(e: ChangeEvent) { email = e.target.value; }
    def handle_job_titles(e: ChangeEvent) { job_titles = e.target.value; }
    def handle_salary(e: ChangeEvent) { salary_min = e.target.value; }

    async def open_city_dropdown(e: any = None) {
        city_dropdown_open = True;
        query_to_search = "" if loc_search == "Remote" else loc_search;
        try {
            matches = await search_cities(query_to_search, 15);
            city_suggestions = matches if matches else ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        } except Exception {
            city_suggestions = ["Remote", "New York, NY", "Los Angeles, CA", "Chicago, IL", "Houston, TX", "Seattle, WA"];
        }
    }

    async def handle_loc_search(e: ChangeEvent) {
        val = e.target.value;
        loc_search = val;
        city_dropdown_open = True;
        try {
            matches = await search_cities(val, 15);
            city_suggestions = matches if matches else ["Remote"];
        } except Exception {
            city_suggestions = ["Remote"];
        }
    }

    def add_location(city_label: str) {
        clean_lbl = city_label.strip();
        if clean_lbl and clean_lbl not in locations {
            locations = locations + [clean_lbl];
        }
        loc_search = "";
        city_dropdown_open = False;
    }

    def remove_location(city_label: str) {
        locations = [l for l in locations if l != city_label];
        if len(locations) == 0 {
            locations = ["Remote"];
        }
    }

    def toggle_sector(sec: str) {
        if sec in sectors {
            if len(sectors) > 1 {
                sectors = [s for s in sectors if s != sec];
            }
        } else {
            sectors = sectors + [sec];
        }
    }

    def toggle_contract_type(ct: str) {
        if ct in contract_types {
            if len(contract_types) > 1 {
                contract_types = [c for c in contract_types if c != ct];
            }
        } else {
            contract_types = contract_types + [ct];
        }
    }

    def append_title(title: str) {
        if not job_titles.strip() {
            job_titles = title;
        } elif title.lower() not in job_titles.lower() {
            job_titles = job_titles + ", " + title;
        }
    }

    def handle_file(e: ChangeEvent) {
        target: any = e.target;
        files: any = target.files;
        if files {
            file_obj: any = files[0];
            if file_obj {
                resume_title = str(file_obj.name);
                reader: any = None;
                try {
                    reader = Reflect.construct(FileReader, []);
                } except Exception {
                    reader = None;
                }
                if reader {
                    reader.onload = lambda (load_ev: any) {
                        resume_content = str(load_ev.target.result);
                    };
                    reader.readAsDataURL(file_obj);
                }
            }
        }
    }

    async def handle_submit(e: FormEvent) {
        e.preventDefault();
        message = "";

        if not first_name.strip() {
            message = "Please enter your first name.";
            return;
        }
        if not email.strip() {
            message = "Please enter your email.";
            return;
        }
        if len(locations) == 0 {
            locations = ["Remote"];
        }
        if len(sectors) == 0 {
            sectors = ["Technology & Software"];
        }
        if len(contract_types) == 0 {
            contract_types = ["Full-time"];
        }

        submitting = True;
        sal_int: int | None = None;
        if salary_min.strip() {
            try {
                sal_int = int(salary_min.replace(",", "").replace("$", "").strip());
            } except Exception {
                sal_int = None;
            }
        }

        tok = "";
        try {
            tok = str(localStorage.getItem("jac_token") or "");
        } except Exception {}

        loc_str = ", ".join(locations);
        sec_str = ", ".join(sectors);
        ct_str = ", ".join(contract_types);

        try {
            res = await submit_profile_and_generate_query(
                email=email.strip(),
                first_name=first_name.strip(),
                last_name=last_name.strip(),
                location=loc_str,
                sector=sec_str,
                job_titles=job_titles.strip(),
                salary_min=sal_int,
                contract_type=ct_str,
                resume_title=resume_title.strip() if resume_title else None,
                resume_content=resume_content if resume_content else None,
                token=tok
            );

            if res and res.get("ok") {
                submitting = False;
                nav("/jobs");
            } else {
                err_msg = str(res.get("error") if res else "Failed to save profile.");
                message = err_msg;
                submitting = False;
            }
        } except Exception as err {
            message = f"Error saving profile: {str(err)}";
            submitting = False;
        }
    }

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 pt-10 pb-20 pl-6 pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
            {loading_initial and <div className="flex items-center justify-center p-20"><Spinner className="size-8 text-primary" /></div>}
            {(not loading_initial) and <div className="flex flex-col gap-8">
                <div className="flex flex-col gap-2 text-center sm:text-left">
                    <div className="inline-flex items-center gap-2 self-center sm:self-start rounded-full bg-primary/10 px-3 py-1 text-xs font-semibold text-primary">
                        <HugeiconsIcon icon={UserAccountIcon} strokeWidth={2} className="size-3.5" />
                        {("Profile Settings" if is_returning_user else "Applicant Onboarding (Step 1 of 1)")}
                    </div>
                    <h1 className="text-3xl font-bold tracking-tight text-foreground sm:text-4xl">
                        {("Update Your Job Preferences" if is_returning_user else "Let's personalize your job feed")}
                    </h1>
                    <p className="text-muted-foreground text-sm max-w-xl">
                        {("Adjust your preferences and resume below to regenerate your tailored job query." if is_returning_user else "Tell us about yourself and your target roles to synthesize custom search parameters and personalize your job feed.")}
                    </p>
                </div>

                <form onSubmit={handle_submit} className="flex flex-col gap-6">
                    <Card className="border border-border/80 shadow-sm !overflow-visible relative z-20 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6 !overflow-visible">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">1</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Personal Information</h2>
                                    <p className="text-xs text-muted-foreground">Inferred from your login where available</p>
                                </div>
                            </div>

                            <div className="grid gap-4 sm:grid-cols-2">
                                <div className="flex flex-col gap-1.5">
                                    <label className="text-xs font-medium text-foreground">First Name *</label>
                                    <Input
                                        placeholder="Ada"
                                        value={first_name}
                                        onChange={handle_first_name}
                                        required
                                        className="h-10 bg-background"
                                    />
                                </div>
                                <div className="flex flex-col gap-1.5">
                                    <label className="text-xs font-medium text-foreground">Last Name</label>
                                    <Input
                                        placeholder="Lovelace"
                                        value={last_name}
                                        onChange={handle_last_name}
                                        className="h-10 bg-background"
                                    />
                                </div>
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Email Address *</label>
                                <Input
                                    type="email"
                                    placeholder="ada@example.com"
                                    value={email}
                                    onChange={handle_email}
                                    required
                                    className="h-10 bg-background"
                                />
                            </div>

                            <div className="flex flex-col gap-1.5 relative">
                                <div className="flex items-center justify-between">
                                    <label className="text-xs font-medium text-foreground">Target Locations (select multiple) *</label>
                                    <button
                                        type="button"
                                        onClick={lambda { add_location("Remote"); }}
                                        className={"text-xs font-medium px-2 py-0.5 rounded transition-colors " + ("bg-primary text-primary-foreground font-semibold" if "Remote" in locations else "bg-muted text-muted-foreground hover:bg-muted/80")}
                                    >
                                        + Remote
                                    </button>
                                </div>

                                <div className="flex flex-wrap items-center gap-1.5 pb-1">
                                    {for loc in locations {
                                        <Badge key={loc} variant="secondary" className="gap-1 pl-2.5 pr-1.5 py-1 text-xs">
                                            <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-3 text-muted-foreground" />
                                            <span>{loc}</span>
                                            <button
                                                type="button"
                                                onClick={lambda { remove_location(loc); }}
                                                className="ml-1 rounded-full p-0.5 hover:bg-muted text-muted-foreground hover:text-foreground cursor-pointer"
                                                aria-label={f"Remove {loc}"}
                                            >
                                                ✕
                                            </button>
                                        </Badge>
                                    }}
                                </div>

                                <div className="relative">
                                    <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground pointer-events-none" />
                                    <Input
                                        placeholder="Type city name to add (e.g. Seattle, WA, Chicago, IL)..."
                                        value={loc_search}
                                        onChange={handle_loc_search}
                                        onFocus={open_city_dropdown}
                                        onClick={open_city_dropdown}
                                        className="h-10 pl-9 bg-background"
                                    />
                                </div>
                                {city_dropdown_open and <div className="absolute top-full left-0 right-0 mt-1 max-h-60 overflow-y-auto rounded-xl border border-border bg-card p-1 shadow-2xl z-50 animate-in fade-in zoom-in-95 duration-100">
                                    <div className="flex items-center justify-between px-3 py-1.5 text-xs text-muted-foreground border-b mb-1">
                                        <span>Click city to add to your target locations</span>
                                        <button
                                            type="button"
                                            onClick={lambda { city_dropdown_open = False; }}
                                            className="hover:text-foreground font-semibold px-1 text-xs cursor-pointer"
                                        >
                                            ✕ Close
                                        </button>
                                    </div>
                                    {len(city_suggestions) == 0 and <div className="p-3 text-xs text-muted-foreground text-center">No matching cities found. Try typing another city or select "Remote".</div>}
                                    {for c in city_suggestions {
                                        <button
                                            key={c}
                                            type="button"
                                            onClick={lambda { add_location(c); }}
                                            className={"flex w-full items-center justify-between rounded-lg px-3 py-2 text-sm text-left transition-colors hover:bg-muted " + ("font-semibold text-primary bg-primary/5" if c in locations else "text-foreground")}
                                        >
                                            <span className="flex items-center gap-2">
                                                <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-3.5 text-muted-foreground" />
                                                <span>{c}</span>
                                            </span>
                                            {c in locations and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-4 text-primary" />}
                                        </button>
                                    }}
                                </div>}
                            </div>
                        </CardContent>
                    </Card>

                    <Card className="border border-border/80 shadow-sm overflow-visible relative z-10 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">2</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Career & Job Preferences</h2>
                                    <p className="text-xs text-muted-foreground">Select multiple sectors, contract types, target roles, and pay expectation</p>
                                </div>
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <div className="flex items-center justify-between">
                                    <label className="text-xs font-medium text-foreground">Industry / Sector (select multiple) *</label>
                                    <span className="text-xs text-muted-foreground">{str(len(sectors)) + " selected"}</span>
                                </div>
                                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 pt-1">
                                    {for sec in POPULAR_SECTORS {
                                        <button
                                            key={sec}
                                            type="button"
                                            onClick={lambda { toggle_sector(sec); }}
                                            className={"flex items-center justify-between rounded-lg border px-3 py-2 text-xs font-medium transition-colors text-left " + ("border-primary bg-primary/10 text-primary font-semibold shadow-xs" if sec in sectors else "border-border bg-background text-foreground hover:bg-muted")}
                                        >
                                            <span className="truncate pr-1">{sec}</span>
                                            {sec in sectors and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-3.5 shrink-0 text-primary" />}
                                        </button>
                                    }}
                                </div>
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Target Job Titles (comma-separated)</label>
                                <Input
                                    placeholder="e.g. Software Engineer, Frontend Developer, Data Analyst"
                                    value={job_titles}
                                    onChange={handle_job_titles}
                                    className="h-10 bg-background"
                                />
                                <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                    <span className="text-xs text-muted-foreground mr-1">Suggestions:</span>
                                    {for t in POPULAR_TITLES[:6] {
                                        <button
                                            key={t}
                                            type="button"
                                            onClick={lambda { append_title(t); }}
                                            className="rounded-full bg-muted/80 px-2.5 py-0.5 text-xs text-muted-foreground hover:bg-primary/10 hover:text-primary transition-colors cursor-pointer"
                                        >
                                            {"+ " + t}
                                        </button>
                                    }}
                                </div>
                            </div>

                            <div className="grid gap-4 sm:grid-cols-2">
                                <div className="flex flex-col gap-1.5">
                                    <div className="flex items-center justify-between">
                                        <label className="text-xs font-medium text-foreground">Salary Minimum ($/year)</label>
                                    </div>
                                    <div className="relative">
                                        <HugeiconsIcon icon={DollarCircleIcon} strokeWidth={2} className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground pointer-events-none" />
                                        <Input
                                            type="number"
                                            placeholder="100000"
                                            value={salary_min}
                                            onChange={handle_salary}
                                            className="h-10 pl-9 bg-background"
                                        />
                                    </div>
                                    <div className="flex flex-wrap gap-1.5 pt-1">
                                        {for s_opt in ["60000", "80000", "100000", "125000", "150000"] {
                                            <button
                                                key={s_opt}
                                                type="button"
                                                onClick={lambda { salary_min = s_opt; }}
                                                className={"rounded px-2 py-0.5 text-xs font-medium transition-colors cursor-pointer " + ("bg-primary text-primary-foreground" if salary_min == s_opt else "bg-muted text-muted-foreground hover:bg-muted/80")}
                                            >
                                                {"$" + str(int(int(s_opt) / 1000)) + "k"}
                                            </button>
                                        }}
                                    </div>
                                </div>

                                <div className="flex flex-col gap-1.5">
                                    <div className="flex items-center justify-between">
                                        <label className="text-xs font-medium text-foreground">Contract Type (select multiple) *</label>
                                        <span className="text-xs text-muted-foreground">{str(len(contract_types)) + " selected"}</span>
                                    </div>
                                    <div className="grid grid-cols-2 gap-2">
                                        {for ct in ["Full-time", "Part-time", "Internship", "Contract"] {
                                            <button
                                                key={ct}
                                                type="button"
                                                onClick={lambda { toggle_contract_type(ct); }}
                                                className={"flex items-center justify-between rounded-lg border px-3 py-2 text-xs font-medium transition-colors cursor-pointer " + ("border-primary bg-primary/10 text-primary font-semibold shadow-xs" if ct in contract_types else "border-border bg-background text-foreground hover:bg-muted")}
                                            >
                                                <span>{ct}</span>
                                                {ct in contract_types and <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-3.5 text-primary" />}
                                            </button>
                                        }}
                                    </div>
                                </div>
                            </div>
                        </CardContent>
                    </Card>

                    <Card className="border border-border/80 shadow-sm overflow-visible relative z-0 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">3</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Resume Upload</h2>
                                    <p className="text-xs text-muted-foreground">Upload your resume to extract skills and tailor job listings (PDF, DOCX, or TXT)</p>
                                </div>
                            </div>

                            <div className="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-border p-6 text-center hover:border-primary/50 transition-colors bg-muted/20">
                                <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} className="size-8 text-muted-foreground mb-2" />
                                <div className="flex flex-col gap-1">
                                    <p className="text-sm font-medium text-foreground">
                                        {resume_title if resume_title else ("Current resume: " + existing_resume_title if existing_resume_title else "Drag and drop or browse to upload")}
                                    </p>
                                    <p className="text-xs text-muted-foreground">Supported formats: PDF, DOCX, TXT up to 5MB</p>
                                </div>
                                <label className="mt-4 inline-flex items-center justify-center rounded-lg bg-primary px-4 py-2 text-xs font-semibold text-primary-foreground shadow-sm hover:bg-primary/90 transition-colors cursor-pointer">
                                    <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-3.5 mr-1.5" />
                                    <span>Browse PDF</span>
                                    <input
                                        id="resume-upload"
                                        type="file"
                                        accept=".pdf,.docx,.txt"
                                        onChange={handle_file}
                                        className="sr-only"
                                    />
                                </label>
                            </div>
                        </CardContent>
                    </Card>

                    {bool(message) and <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
                        {message}
                    </div>}

                    <div className="flex items-center justify-end gap-3 pt-2">
                        <Button
                            type="button"
                            variant="outline"
                            onClick={lambda { nav("/jobs"); }}
                            disabled={submitting}
                        >
                            Skip for now
                        </Button>
                        <Button
                            type="submit"
                            disabled={submitting}
                            className="min-w-32 shadow-sm font-semibold"
                        >
                            {("Saving Profile..." if submitting else ("Update Preferences" if is_returning_user else "Complete Onboarding →"))}
                        </Button>
                    </div>
                </form>
            </div>}
        </main>
        <SiteFooter />
    </div>;
}

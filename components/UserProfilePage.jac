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
import from ..services.profile_llm { submit_profile_and_generate_query, get_user_profile_data, save_contact_details }
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
    has email_locked: bool = False;
    has phone: str = "";
    has city: str = "";
    has linkedin: str = "";
    has github: str = "";
    has portfolio: str = "";
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
    has has_existing_resume: bool = False;
    has reading_file: bool = False;

    has city_suggestions: list[str] = [];
    has city_dropdown_open: bool = False;

    has loading_initial: bool = True;
    has submitting: bool = False;
    has message: str = "";
    has is_returning_user: bool = False;
    has did_init_profile: bool = False;
    has step: int = 1;

    def step1_valid -> bool {
        return bool(first_name.strip()) and bool(email.strip()) and len(locations) > 0;
    }

    def step2_valid -> bool {
        return len(sectors) > 0 and len(contract_types) > 0;
    }

    def can_next -> bool {
        return step1_valid() if step == 1 else step2_valid();
    }

    def go_next {
        if can_next() and step < 3 {
            message = "";
            step = step + 1;
        }
    }

    def go_back {
        if step > 1 {
            message = "";
            step = step - 1;
        }
    }

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
            # Immediate fast load of locally saved resume title if available
            saved_res_title = "";
            try {
                saved_res_title = str(localStorage.getItem("user_resume_title") or "");
            } except Exception {}
            if saved_res_title and saved_res_title.strip() {
                existing_resume_title = saved_res_title.strip();
                has_existing_resume = True;
            }

            tok: str = "";
            try {
                tok = str(localStorage.getItem("jac_token") or "");
            } except Exception {}
            # The server finds the user from the token alone.
            res = await get_user_profile_data(token=tok);
            if res and res.get("ok") {
                u = res.get("user", {});
                email_val = str(u.get("email", "") or "");
                if email_val and "@" in email_val {
                    email = email_val;
                    email_locked = True;
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
                phone = str(u.get("phone", "") or "");
                city = str(u.get("city", "") or "");
                linkedin = str(u.get("linkedin", "") or "");
                github = str(u.get("github", "") or "");
                portfolio = str(u.get("portfolio", "") or "");

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
                if latest_res {
                    raw_title = "";
                    try {
                        raw_title = str(latest_res.get("title") or "");
                    } except Exception {
                        try {
                            raw_title = str(latest_res["title"] or "");
                        } except Exception {}
                    }
                    clean_title = raw_title.strip() if (raw_title and raw_title.strip() and raw_title.strip() != "None") else "Base Resume.pdf";
                    existing_resume_title = clean_title;
                    has_existing_resume = True;
                    try {
                        localStorage.setItem("user_resume_title", clean_title);
                    } except Exception {}
                }
            }
        } except Exception {}
        loading_initial = False;
    }

    def handle_first_name(e: ChangeEvent) { first_name = e.target.value; }
    def handle_last_name(e: ChangeEvent) { last_name = e.target.value; }
    def handle_email(e: ChangeEvent) { email = e.target.value; }
    def handle_phone(e: ChangeEvent) { phone = e.target.value; }
    def handle_city(e: ChangeEvent) { city = e.target.value; }
    def handle_linkedin(e: ChangeEvent) { linkedin = e.target.value; }
    def handle_github(e: ChangeEvent) { github = e.target.value; }
    def handle_portfolio(e: ChangeEvent) { portfolio = e.target.value; }
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
                reading_file = True;
                reader: any = None;
                try {
                    reader = Reflect.construct(FileReader, []);
                } except Exception {
                    reader = None;
                }
                if reader {
                    reader.onload = lambda (load_ev: any) {
                        resume_content = str(load_ev.target.result);
                        reading_file = False;
                    };
                    reader.onerror = lambda (err_ev: any) {
                        reading_file = False;
                    };
                    reader.readAsDataURL(file_obj);
                } else {
                    reading_file = False;
                }
            }
        }
    }

    def handle_drag_over(e: any) {
        e.preventDefault();
    }

    def handle_drop(e: any) {
        e.preventDefault();
        files: any = None;
        try {
            files = e.dataTransfer.files;
        } except Exception {}
        if files and len(files) > 0 {
            file_obj: any = files[0];
            if file_obj {
                resume_title = str(file_obj.name);
                reading_file = True;
                reader: any = None;
                try {
                    reader = Reflect.construct(FileReader, []);
                } except Exception {
                    reader = None;
                }
                if reader {
                    reader.onload = lambda (load_ev: any) {
                        resume_content = str(load_ev.target.result);
                        reading_file = False;
                    };
                    reader.onerror = lambda (err_ev: any) {
                        reading_file = False;
                    };
                    reader.readAsDataURL(file_obj);
                } else {
                    reading_file = False;
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
                token=tok,
                email=email.strip(),
                first_name=first_name.strip(),
                last_name=last_name.strip(),
                location=loc_str,
                sector=sec_str,
                job_titles=job_titles.strip(),
                salary_min=sal_int,
                contract_type=ct_str,
                resume_title=resume_title.strip() if resume_title else None,
                resume_content=resume_content if resume_content else None
            );

            if res and res.get("ok") {
                if resume_title.strip() {
                    existing_resume_title = resume_title.strip();
                    has_existing_resume = True;
                    try {
                        localStorage.setItem("user_resume_title", resume_title.strip());
                    } except Exception {}
                    resume_title = "";
                    resume_content = "";
                }
                contact: any = await save_contact_details(
                    token=tok,
                    phone=phone.strip(),
                    city=city.strip(),
                    linkedin=linkedin.strip(),
                    github=github.strip(),
                    portfolio=portfolio.strip()
                );
                submitting = False;
                if contact and contact.get("ok") {
                    nav("/jobs");
                } else {
                    step = 1;
                    message = str(contact.get("error") if contact else "Could not save your contact details.");
                }
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
                        {("Profile Settings" if is_returning_user else "Onboarding - Step " + str(step) + " of 3")}
                    </div>
                    <h1 className="text-3xl font-bold tracking-tight text-foreground sm:text-4xl">
                        {("Update Your Job Preferences" if is_returning_user else "Let's personalize your job feed")}
                    </h1>
                    <p className="text-muted-foreground text-sm max-w-xl">
                        {("Update your details and we'll refresh your job matches." if is_returning_user else "Tell us about yourself and your target roles so we can match you with positions ideal for you.")}
                    </p>
                </div>

                <form onSubmit={handle_submit} className="flex flex-col gap-6">
                    {step == 1 and <Card className="border border-border/80 shadow-sm not overflow-visible relative z-20 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6 !overflow-visible">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">1</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Personal Information</h2>
                                    <p className="text-xs text-muted-foreground">Basic details about you</p>
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
                                    readOnly={email_locked}
                                    required
                                    className={"h-10 " + ("bg-muted text-muted-foreground" if email_locked else "bg-background")}
                                />
                            </div>

                            <div className="grid gap-4 sm:grid-cols-2">
                                <div className="flex flex-col gap-1.5">
                                    <label htmlFor="profile-phone" className="text-xs font-medium text-foreground">Phone</label>
                                    <Input id="profile-phone" type="tel" placeholder="(555) 555-0100" value={phone} onChange={handle_phone} className="h-10 bg-background" />
                                </div>
                                <div className="flex flex-col gap-1.5">
                                    <label htmlFor="profile-city" className="text-xs font-medium text-foreground">City you live in</label>
                                    <Input id="profile-city" placeholder="Ann Arbor" value={city} onChange={handle_city} className="h-10 bg-background" />
                                </div>
                                <div className="flex flex-col gap-1.5">
                                    <label htmlFor="profile-linkedin" className="text-xs font-medium text-foreground">LinkedIn URL</label>
                                    <Input id="profile-linkedin" type="url" placeholder="https://linkedin.com/in/you" value={linkedin} onChange={handle_linkedin} className="h-10 bg-background" />
                                </div>
                                <div className="flex flex-col gap-1.5">
                                    <label htmlFor="profile-github" className="text-xs font-medium text-foreground">GitHub URL</label>
                                    <Input id="profile-github" type="url" placeholder="https://github.com/you" value={github} onChange={handle_github} className="h-10 bg-background" />
                                </div>
                                <div className="flex flex-col gap-1.5 sm:col-span-2">
                                    <label htmlFor="profile-portfolio" className="text-xs font-medium text-foreground">Portfolio URL</label>
                                    <Input id="profile-portfolio" type="url" placeholder="https://your-site.com" value={portfolio} onChange={handle_portfolio} className="h-10 bg-background" />
                                    <p className="text-xs text-muted-foreground">Optional. The Launchpad extension uses these details to fill job applications.</p>
                                </div>
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
                                <div className="flex flex-wrap gap-1.5 min-h-10 p-2 border rounded-md bg-background focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2">
                                    {for loc_item in locations {
                                        <Badge
                                            key={loc_item}
                                            variant="secondary"
                                            className="gap-1.5 py-1 px-2.5 text-xs font-medium bg-primary/10 text-primary border-primary/20 hover:bg-primary/20"
                                        >
                                            <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-3" />
                                            <span>{loc_item}</span>
                                            {len(locations) > 1 and <button
                                                type="button"
                                                onClick={lambda { remove_location(loc_item); }}
                                                className="ml-1 rounded-full hover:bg-primary/20 p-0.5 text-primary"
                                            >
                                                ×
                                            </button>}
                                        </Badge>
                                    }}
                                    <div className="flex-1 min-w-[140px] relative">
                                        <input
                                            type="text"
                                            placeholder="Type city (e.g. Seattle, Austin)..."
                                            value={loc_search}
                                            onChange={handle_loc_search}
                                            onFocus={open_city_dropdown}
                                            className="w-full bg-transparent text-sm focus:outline-none placeholder:text-muted-foreground text-foreground h-7"
                                        />
                                    </div>
                                </div>
                                {city_dropdown_open and <div className="absolute left-0 right-0 top-full mt-1 max-h-60 overflow-y-auto rounded-lg border border-border bg-card p-1 shadow-lg z-50">
                                    <div className="p-1.5 text-[11px] font-semibold text-muted-foreground flex justify-between items-center border-b border-border/50">
                                        <span>SUGGESTED CITIES</span>
                                        <button
                                            type="button"
                                            onClick={lambda { city_dropdown_open = False; }}
                                            className="text-xs text-muted-foreground hover:text-foreground"
                                        >
                                            Close ✕
                                        </button>
                                    </div>
                                    <div className="flex flex-col py-1">
                                        {for city in city_suggestions {
                                            <button
                                                key={city}
                                                type="button"
                                                onClick={lambda { add_location(city); }}
                                                className={"flex items-center gap-2 rounded-md px-3 py-2 text-xs text-left transition-colors " + ("bg-muted text-muted-foreground cursor-not-allowed" if city in locations else "hover:bg-primary/10 hover:text-primary text-foreground")}
                                                disabled={city in locations}
                                            >
                                                <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="size-3.5 text-muted-foreground" />
                                                <span className="flex-1 font-medium">{city}</span>
                                                {city in locations and <span className="text-[10px] text-muted-foreground">Added</span>}
                                            </button>
                                        }}
                                    </div>
                                </div>}
                            </div>
                        </CardContent>
                    </Card>}

                    {step == 2 and <Card className="border border-border/80 shadow-sm overflow-visible relative z-10 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">2</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Career & Job Preferences</h2>
                                    <p className="text-xs text-muted-foreground">Pick the roles, type of work, and pay you're looking for</p>
                                </div>
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <label className="text-xs font-medium text-foreground">Sectors of Interest (select multiple) *</label>
                                <div className="flex flex-wrap gap-1.5">
                                    {for sec in POPULAR_SECTORS {
                                        <button
                                            key={sec}
                                            type="button"
                                            onClick={lambda { toggle_sector(sec); }}
                                            className={"rounded-full px-3 py-1.5 text-xs font-medium transition-colors cursor-pointer border " + ("border-primary bg-primary text-primary-foreground shadow-xs" if sec in sectors else "border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground")}
                                        >
                                            {sec}
                                        </button>
                                    }}
                                </div>
                            </div>

                            <div className="flex flex-col gap-1.5">
                                <div className="flex items-center justify-between">
                                    <label className="text-xs font-medium text-foreground">Desired Job Titles / Keywords *</label>
                                    <span className="text-xs text-muted-foreground">Comma-separated</span>
                                </div>
                                <div className="relative">
                                    <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground pointer-events-none" />
                                    <Input
                                        placeholder="Software Engineer, Backend Engineer, Platform"
                                        value={job_titles}
                                        onChange={handle_job_titles}
                                        required
                                        className="h-10 pl-9 bg-background"
                                    />
                                </div>
                                <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                    <span className="text-[11px] text-muted-foreground font-medium">Quick add:</span>
                                    {for t in POPULAR_TITLES {
                                        <button
                                            key={t}
                                            type="button"
                                            onClick={lambda { append_title(t); }}
                                            className="rounded border border-border/80 bg-background px-2 py-0.5 text-[11px] text-muted-foreground hover:bg-muted hover:text-foreground transition-colors cursor-pointer"
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
                    </Card>}

                    {step == 3 and <Card className="border border-border/80 shadow-sm overflow-visible relative z-0 pt-1 pb-4">
                        <CardContent className="flex flex-col gap-4 pt-1.5 pb-2 px-6">
                            <div className="flex items-center gap-2.5 border-b pb-3">
                                <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary text-xs font-bold">3</span>
                                <div className="flex flex-col">
                                    <h2 className="text-base font-semibold text-foreground">Resume Upload</h2>
                                    <p className="text-xs text-muted-foreground">Upload your resume so we can match you to better roles</p>
                                </div>
                            </div>

                            {(bool(resume_title) or bool(existing_resume_title)) and <div className="flex flex-col gap-3 rounded-xl border border-primary/20 bg-primary/5 p-4 sm:p-5">
                                <div className="flex items-center justify-between gap-3 flex-wrap sm:flex-nowrap">
                                    <div className="flex items-center gap-3 min-w-0">
                                        <div className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                                            <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-5" />
                                        </div>
                                        <div className="flex flex-col min-w-0">
                                            <div className="flex items-center gap-2 flex-wrap">
                                                <span className="text-sm font-semibold text-foreground truncate max-w-[280px] sm:max-w-[360px]">
                                                    {resume_title if resume_title else existing_resume_title}
                                                </span>
                                                <span className={"inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium shrink-0 " + ("bg-amber-500/10 text-amber-600 dark:text-amber-400" if reading_file else ("bg-primary/20 text-primary" if resume_title else "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"))}>
                                                    <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-3" />
                                                    {("Reading file..." if reading_file else ("New file selected" if resume_title else "Uploaded & Active"))}
                                                </span>
                                            </div>
                                            <p className="text-xs text-muted-foreground">
                                                {("Reading file content..." if reading_file else ("Ready to upload. Click Save below to update your profile resume." if resume_title else "Currently saved to your profile and used for job match scoring."))}
                                            </p>
                                        </div>
                                    </div>
                                    <label className="shrink-0 inline-flex items-center justify-center rounded-lg border border-input bg-background px-3 py-1.5 text-xs font-medium text-foreground shadow-sm hover:bg-muted transition-colors cursor-pointer">
                                        <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} className="size-3.5 mr-1.5" />
                                        <span>{("Change file" if resume_title else "Upload different file")}</span>
                                        <input
                                            id="resume-upload-change"
                                            type="file"
                                            accept=".pdf,.docx,.txt"
                                            onChange={handle_file}
                                            className="sr-only"
                                        />
                                    </label>
                                </div>
                            </div>}

                            {((not resume_title) and (not existing_resume_title)) and <div
                                onDragOver={handle_drag_over}
                                onDrop={handle_drop}
                                className="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-border p-6 text-center hover:border-primary/50 transition-colors bg-muted/20"
                            >
                                <HugeiconsIcon icon={Upload01Icon} strokeWidth={2} className="size-8 text-muted-foreground mb-2" />
                                <div className="flex flex-col gap-1">
                                    <p className="text-sm font-medium text-foreground">
                                        Drag and drop or browse to upload
                                    </p>
                                    <p className="text-xs text-muted-foreground">Supported formats: PDF, DOCX, TXT up to 5MB</p>
                                </div>
                                <label className="mt-4 inline-flex items-center justify-center rounded-lg bg-primary px-4 py-2 text-xs font-semibold text-primary-foreground shadow-sm hover:bg-primary/90 transition-colors cursor-pointer">
                                    <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-3.5 mr-1.5" />
                                    <span>Browse PDF</span>
                                    <input
                                        id="resume-upload-new"
                                        type="file"
                                        accept=".pdf,.docx,.txt"
                                        onChange={handle_file}
                                        className="sr-only"
                                    />
                                </label>
                            </div>}
                        </CardContent>
                    </Card>}

                    {bool(message) and <div className="rounded-xl border border-destructive/30 bg-destructive/10 p-3 text-xs text-destructive">
                        {message}
                    </div>}

                    <div className="flex items-center justify-between gap-3 pt-2">
                        {step > 1 and <Button
                            type="button"
                            variant="ghost"
                            onClick={go_back}
                            disabled={submitting or reading_file}
                        >
                            Back
                        </Button>}
                        <div className="flex items-center gap-3">
                            {step == 1 and <Button
                                type="button"
                                variant="outline"
                                onClick={lambda { nav("/jobs"); }}
                                disabled={submitting or reading_file}
                            >
                                Skip for now
                            </Button>}
                            {step < 3 and <Button
                                type="button"
                                disabled={not can_next() or submitting or reading_file}
                                className="min-w-28 shadow-sm font-semibold"
                                onClick={go_next}
                            >
                                Next
                            </Button>}
                            {step == 3 and <Button
                                type="submit"
                                disabled={submitting or reading_file}
                                className="min-w-32 shadow-sm font-semibold"
                            >
                                {("Saving Profile..." if submitting else ("Reading File..." if reading_file else ("Update Preferences" if is_returning_user else "Finish")))}
                            </Button>}
                        </div>
                    </div>
                </form>
            </div>}
        </main>
        <SiteFooter />
    </div>;
}

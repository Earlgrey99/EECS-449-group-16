import from "@jac/runtime" { jacIsLoggedIn, Link, Navigate, useLocation, useNavigate }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .ui.button { Button }
import from ..services.applicant_demo { get_applicant_details, tailor_resume_pdf, use_tailored_resume, use_default_resume }
import from ..services.jobs { list_jobs }

def:pub ApplicantTools() -> JsxElement {
    location = useLocation();
    nav = useNavigate();
    job_id = decodeURIComponent(location.search.replace("?job=", "").split("&")[0]);
    if not jacIsLoggedIn() and not globalThis.__DEV_AUTO_LOGIN__ {
        return <Navigate to="/login" replace={True} />;
    }

    # What the extension will fill, from the server, with where each value comes from.
    has contact_rows: list[any] = [];
    has answer_rows: list[any] = [];
    has autofill_resume: str = "";
    has autofill_loaded: bool = False;
    has autofill_error: str = "";

    # The job to tailor for. The jobs page passes it along; otherwise the user pastes it.
    has role: str = "";
    has job_description: str = "";
    has job_from_feed: bool = False;
    has editing_job: bool = False;
    has did_init_tools: bool = False;

    has job_notice: str = "";
    has saved_resume_title: str = "";
    has upload_name: str = "";
    has upload_content: str = "";
    has tailoring: bool = False;
    has tailor_error: str = "";
    has tailored_pdf: str = "";
    has tailored_name: str = "";
    has tailored_role: str = "";
    has preview_url: str = "";
    has tailor_changes: list[str] = [];
    has matched_keywords: list[str] = [];
    has missing_keywords: list[str] = [];
    # Skills from the job that the user says they have; tailoring adds them to a skills line.
    has confirmed_skills: list[str] = [];
    has use_ai: bool = True;
    has ai_status: str = "";
    has tailor_notes: list[str] = [];
    has tailor_method: str = "";

    # Which resume the extension attaches to applications.
    has app_resume_title: str = "";
    has app_resume_tailored: bool = False;
    has app_resume_for: str = "";
    has choosing: bool = False;
    has choice_message: str = "";
    has choice_error: str = "";

    # Use the saved profile and resume, so the user doesn't retype them here.
    async def load_saved_details {
        try {
            tok = str(localStorage.getItem("jac_token") or "");
            saved: any = await get_applicant_details(token=tok);
            if saved and saved.get("ok") {
                autofill: any = saved.get("autofill") or {};
                contacts: list[any] = autofill.get("contact") or [];
                answers: list[any] = autofill.get("answers") or [];
                contact_rows = contacts;
                answer_rows = answers;
                autofill_resume = str(autofill.get("resume_title") or "");
                saved_resume_title = str(saved.get("resume_title") or "");
                set_app_resume(saved.get("application_resume"));
            } else {
                autofill_error = str(saved.get("error") if saved else "") or "Couldn't load your profile.";
            }
        } except Exception {
            autofill_error = "Couldn't load your profile.";
        }
        autofill_loaded = True;
    }

    def set_app_resume(info: any) {
        if not info {
            return;
        }
        app_resume_title = str(info.get("title") or "");
        app_resume_tailored = bool(info.get("tailored"));
        app_resume_for = str(info.get("tailored_for") or "");
        autofill_resume = app_resume_title + ((" (tailored for " + app_resume_for + ")") if app_resume_tailored and app_resume_for else "");
    }

    # Job descriptions can hold HTML. DOMParser reads it without running any of it.
    def plain_text(raw: str) -> str {
        parser: any = Reflect.construct(DOMParser, []);
        parsed: any = parser.parseFromString(raw, "text/html");
        return str(parsed.body.textContent or "").strip();
    }

    def use_job(title: str, desc: str, tags: str) {
        role = title;
        job_from_feed = True;
        job_description = (plain_text(desc) + ("\n\nSkills: " + tags if tags else ""))[:12000];
    }

    def use_application_job(job: any) {
        title = str(job.get("title") or "");
        desc = str(job.get("desc") or job.get("description") or "");
        tags = str(job.get("tags") or "");
        application_role = title;
        application_company = str(job.get("company") or "");
        application_pay = str(job.get("salary") or job.get("salary_text") or "");
        application_description = plain_text(desc);
        use_job(title, desc, tags);
    }

    # The jobs page passes the selected job along, which covers external listings.
    # A reloaded or shared link may not have it, so fall back to the built-in jobs.
    async can with entry {
        if did_init_tools {
            return;
        }
        did_init_tools = True;
        await load_saved_details();
        selected_job_raw = localStorage.getItem("jaccit_selected_job");
        has_selected_job = False;
        if selected_job_raw {
            try {
                selected_job: any = JSON.parse(selected_job_raw);
                use_application_job(selected_job);
                localStorage.removeItem("jaccit_selected_job");
                has_selected_job = True;
            } except Exception {
                job_notice = "We couldn't load that job. Paste its description below.";
            }
        }
        passed: any = location.state.get("job") if location.state else None;
        if passed {
            use_application_job(passed);
            return;
        }
        if job_id {
            available_jobs = await list_jobs();
            for j in available_jobs {
                if str(j["id"]) == job_id {
                    use_application_job(j);
                    return;
                }
            }
        }
        if not passed and not has_selected_job {
            job_notice = "We couldn't load that job. Paste its description below.";
        }
        if not job_from_feed {
            editing_job = True;
        }
    }

    def handle_upload(e: ChangeEvent) {
        target: any = e.target;
        files: any = target.files;
        if not files or not files[0] {
            return;
        }
        file_obj: any = files[0];
        if not str(file_obj.name).lower().endswith(".pdf") {
            tailor_error = "Choose a PDF resume.";
            return;
        }
        tailor_error = "";
        upload_name = str(file_obj.name);
        reader: any = Reflect.construct(FileReader, []);
        reader.onload = lambda (load_ev: any) { upload_content = str(load_ev.target.result); };
        reader.readAsDataURL(file_obj);
    }

    # A blob URL lets the browser's PDF viewer show the result on the page.
    async def show_preview(data_url: str) {
        # jac check has no stub for the URL global; it exists in every browser.
        if preview_url {
            URL.revokeObjectURL(preview_url);  # jac:ignore[E1032]
        }
        preview_url = "";
        try {
            response: any = await fetch(data_url);
            blob: any = await response.blob();
            preview_url = str(URL.createObjectURL(blob));  # jac:ignore[E1032]
        } except Exception {}
    }

    async def make_tailored_pdf {
        tailor_error = "";
        choice_message = "";
        choice_error = "";
        tailored_pdf = "";
        tailor_changes = [];
        tailor_notes = [];
        ai_status = "";
        matched_keywords = [];
        missing_keywords = [];
        if not job_description.strip() {
            tailor_error = "Add the job description first.";
            editing_job = True;
            return;
        }
        tailoring = True;
        try {
            tok = str(localStorage.getItem("jac_token") or "");
            res: any = await tailor_resume_pdf(token=tok, job_text=job_description, role=role, resume_content=upload_content, add_skills=", ".join(confirmed_skills), use_ai=use_ai);
            if res and res.get("ok") {
                tailored_pdf = str(res.get("pdf"));
                tailored_name = str(res.get("filename"));
                tailored_role = role.strip();
                changed: list[str] = res.get("changes") or [];
                tailor_changes = changed;
                notes: list[str] = res.get("notes") or [];
                tailor_notes = notes;
                ai_status = str(res.get("ai") or "");
                tailor_method = str(res.get("method") or "");
                words: any = res.get("keywords") or {};
                matched: list[str] = words.get("matched") or [];
                missing: list[str] = words.get("missing") or [];
                matched_keywords = matched;
                missing_keywords = missing;
                await show_preview(tailored_pdf);
            } else {
                tailor_error = str(res.get("error") if res else "Couldn't create the PDF.");
            }
        } except Exception {
            tailor_error = "Couldn't reach the tailoring service.";
        }
        tailoring = False;
    }

    def toggle_skill(word: str) {
        if word in confirmed_skills {
            confirmed_skills = [item for item in confirmed_skills if item != word];
        } else {
            confirmed_skills = confirmed_skills + [word];
        }
    }

    def ai_message -> str {
        if ai_status == "used" {
            return "AI reworded some bullets to use the job's terms. Read each one in the list below.";
        }
        if ai_status == "none" {
            return "AI suggested no rewording that passed the checks, so no bullets were reworded.";
        }
        if ai_status == "no_key" {
            return "AI rewording is off on this server: add DEEPSEEK_API_KEY to .env to turn it on.";
        }
        if ai_status == "failed" {
            return "The AI service didn't respond, so bullets were only reordered.";
        }
        if ai_status == "skipped" {
            return "Your resume's fonts can't be reused for new text, so bullets were only reordered.";
        }
        return "";
    }

    async def use_tailored {
        choice_message = "";
        choice_error = "";
        choosing = True;
        try {
            tok = str(localStorage.getItem("jac_token") or "");
            res: any = await use_tailored_resume(token=tok, pdf=tailored_pdf, filename=tailored_name, job_title=tailored_role);
            if res and res.get("ok") {
                set_app_resume(res.get("application_resume"));
                choice_message = "Applications will attach this tailored resume.";
            } else {
                choice_error = str(res.get("error") if res else "Couldn't save your choice.");
            }
        } except Exception {
            choice_error = "Couldn't save your choice.";
        }
        choosing = False;
    }

    async def use_default {
        choice_message = "";
        choice_error = "";
        choosing = True;
        try {
            tok = str(localStorage.getItem("jac_token") or "");
            res: any = await use_default_resume(token=tok);
            if res and res.get("ok") {
                set_app_resume(res.get("application_resume"));
                choice_message = "Applications will attach your default resume.";
            } else {
                choice_error = str(res.get("error") if res else "Couldn't save your choice.");
            }
        } except Exception {
            choice_error = "Couldn't save your choice.";
        }
        choosing = False;
    }

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-8 px-6 py-10">
            <header className="flex flex-col gap-3">
                <p className="text-sm font-semibold text-primary">LAUNCHPAD EXPERIMENTAL WORKSPACE</p>
                <h1 className="text-3xl font-semibold tracking-tight">Application tools</h1>
                <p className="max-w-3xl text-muted-foreground">Check what the Launchpad extension will fill on a job application, and tailor your resume for the job. Nothing here submits an application or changes your original resume.</p>
            </header>

            <section aria-labelledby="autofill-heading" className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                    <div className="flex flex-col gap-1">
                        <h2 id="autofill-heading" className="text-2xl font-semibold">1. Your autofill profile</h2>
                        <p className="max-w-3xl text-sm text-muted-foreground">This is what the Launchpad extension fills on a real application. Your saved profile comes first. Details read from your resume fill only what the profile leaves blank, so check those.</p>
                    </div>
                    <Link to="/me" className="inline-flex h-9 shrink-0 items-center self-start rounded-lg border border-primary px-4 text-sm font-medium text-primary hover:bg-primary/10">Edit profile</Link>
                </div>
                {(not autofill_loaded) and <p role="status" className="text-sm text-muted-foreground">Loading your profile...</p>}
                {bool(autofill_error) and <p role="alert" className="text-sm text-red-600">{autofill_error}</p>}
                {(autofill_loaded and not autofill_error) and <div className="flex flex-col gap-6">
                    <div className="grid gap-6 md:grid-cols-2">
                        <div className="rounded-xl border bg-primary/5 p-5">
                            <h3 className="mb-2 font-semibold">Contact details</h3>
                            <dl>
                                {for row in contact_rows {
                                    <div key={row["key"]} className="flex items-start justify-between gap-4 border-b border-primary/10 py-2 last:border-0">
                                        <dt className="text-sm text-muted-foreground">{row["label"]}</dt>
                                        <dd className="flex min-w-0 flex-col items-end gap-1 text-right text-sm">
                                            <span className={"break-all font-medium" if row["value"] else "text-muted-foreground"}>{row["value"] or "Not set"}</span>
                                            {row["source"] == "resume" and <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">From resume, please check</span>}
                                        </dd>
                                    </div>
                                }}
                            </dl>
                        </div>
                        <div className="rounded-xl border bg-primary/5 p-5">
                            <h3 className="mb-2 font-semibold">Application answers</h3>
                            <dl>
                                {for row in answer_rows {
                                    <div key={row["key"]} className="flex items-start justify-between gap-4 border-b border-primary/10 py-2 last:border-0">
                                        <dt className="text-sm text-muted-foreground">{row["label"]}</dt>
                                        <dd className="flex min-w-0 flex-col items-end gap-1 text-right text-sm">
                                            <span className={"break-words font-medium" if row["value"] else "text-muted-foreground"}>{row["value"] or "Not set"}</span>
                                            {row["source"] == "resume" and <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">From resume, please check</span>}
                                        </dd>
                                    </div>
                                }}
                            </dl>
                        </div>
                    </div>
                    <p className="text-sm">{("Resume attached to applications: " + autofill_resume) if autofill_resume else "No resume saved. Add one in your profile so it can be attached."}</p>
                    <div className="rounded-xl border p-5 text-sm">
                        <h3 className="mb-2 font-semibold">Fill a real application</h3>
                        <ol className="list-decimal space-y-1 pl-5">
                            <li>Open the job application in Chrome, with the Launchpad extension connected.</li>
                            <li>Click Autofill this application in the Launchpad panel, or Fill this page in the extension menu.</li>
                            <li>Review every field and answer the questions it leaves for you. You submit the application yourself.</li>
                        </ol>
                        <p className="mt-3 text-muted-foreground">Fields marked Not set stay blank. Demographic answers are kept in the extension's Saved answers and never sent to Launchpad. Date of birth and Social Security number are never filled.</p>
                    </div>
                </div>}
            </section>

            <section aria-labelledby="tailor-heading" className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-1">
                    <h2 id="tailor-heading" className="text-2xl font-semibold">2. Tailor your resume</h2>
                    <p className="max-w-3xl text-sm text-muted-foreground">Launchpad edits a copy of your resume PDF for the job and keeps its fonts and layout. Bullets and skills that match the job move up, and AI can reword bullets in the job's terms. It never adds a skill, number, or claim your resume doesn't already show, unless you choose a skill below. Review the new PDF, then choose which resume to send.</p>
                </div>

                <div className="mb-6 flex flex-col gap-3 rounded-xl border bg-primary/5 p-4 text-sm md:flex-row md:items-center md:justify-between">
                    <p>
                        <span className="text-muted-foreground">Applications attach: </span>
                        <span className="font-medium">{app_resume_title or "No resume saved yet"}</span>
                        {(app_resume_tailored and bool(app_resume_for)) and <span className="text-muted-foreground">{" (tailored for " + app_resume_for + ")"}</span>}
                    </p>
                    {app_resume_tailored and <Button variant="outline" disabled={choosing} onClick={use_default}>Switch back to my default resume</Button>}
                </div>

                {bool(job_notice) and <p role="status" className="mb-4 text-sm text-amber-700">{job_notice}</p>}
                <div className="grid gap-6 md:grid-cols-2">
                    <div className="flex flex-col gap-3">
                        <h3 className="font-semibold">Job</h3>
                        {(not editing_job) and <div className="flex flex-col gap-2 text-sm">
                            <p className="font-medium">{role or "Selected job"}</p>
                            <button type="button" className="self-start text-primary underline-offset-4 hover:underline" onClick={lambda { editing_job = True; }}>Edit the job description</button>
                        </div>}
                        {editing_job and <div className="flex flex-col gap-3">
                            <label className="flex flex-col gap-1 text-sm font-medium">Job title
                                <input className="rounded-lg border bg-background p-3 font-normal" placeholder="Data Analyst" value={role} onChange={lambda (e: ChangeEvent) { role = e.target.value; }} />
                            </label>
                            <label className="flex flex-col gap-1 text-sm font-medium">Job description
                                <textarea className="min-h-40 rounded-lg border bg-background p-3 text-sm font-normal" placeholder="Paste the job description from the posting." value={job_description} onChange={lambda (e: ChangeEvent) { job_description = e.target.value; }} />
                            </label>
                        </div>}
                    </div>
                    <div className="flex flex-col gap-3">
                        <h3 className="font-semibold">Resume</h3>
                        <p className="text-sm">{upload_name if upload_name else (("Your default resume: " + saved_resume_title) if saved_resume_title else "No saved resume. Choose a PDF below.")}</p>
                        <label className="flex flex-col gap-1 text-sm font-medium">Use a different PDF (optional)
                            <input type="file" accept=".pdf,application/pdf" onChange={handle_upload} className="text-sm font-normal" />
                        </label>
                    </div>
                </div>

                <div className="mt-6 flex flex-wrap items-center gap-3">
                    <Button type="button" disabled={tailoring} onClick={make_tailored_pdf}>{"Tailoring..." if tailoring else "Tailor my resume"}</Button>
                    <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={use_ai} onChange={lambda (e: ChangeEvent) { use_ai = bool(e.target.checked); }} />
                        Reword bullets with AI
                    </label>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">{("With AI on, your resume's bullets and the job description are sent to DeepSeek to suggest wording. Reordering runs on the Launchpad server only." if use_ai else "Runs on the Launchpad server only. Nothing is sent to an AI service.")}</p>
                {bool(tailor_error) and <p role="alert" className="mt-3 text-sm text-red-600">{tailor_error}</p>}

                {bool(tailored_pdf) and <div className="mt-6 flex flex-col gap-5">
                    <div className="grid gap-4 md:grid-cols-2">
                        <div className="rounded-xl border p-4 text-sm">
                            <h3 className="mb-2 font-semibold">Job keywords your resume has</h3>
                            {(not matched_keywords) and <p className="text-muted-foreground">None of the job's main keywords appear in your resume.</p>}
                            <ul className="flex flex-wrap gap-2">
                                {for word in matched_keywords {
                                    <li key={word} className="rounded-full bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary">{word}</li>
                                }}
                            </ul>
                        </div>
                        <div className="rounded-xl border p-4 text-sm">
                            <h3 className="mb-2 font-semibold">Job keywords your resume doesn't mention</h3>
                            {(not missing_keywords) and <p className="text-muted-foreground">None. Your resume covers the job's main keywords.</p>}
                            <ul className="flex flex-wrap gap-2">
                                {for word in missing_keywords {
                                    <li key={word}>
                                        <button type="button" aria-pressed={word in confirmed_skills} onClick={lambda { toggle_skill(word); }} className={("rounded-full px-2.5 py-1 text-xs font-medium " + ("bg-primary text-primary-foreground" if word in confirmed_skills else "bg-muted text-muted-foreground hover:bg-primary/10"))}>{(("✓ " if word in confirmed_skills else "+ ") + word)}</button>
                                    </li>
                                }}
                            </ul>
                            <p className="mt-2 text-xs text-muted-foreground">Launchpad doesn't add these on its own. Select only skills you really have, then tailor again to add them to your skills line.</p>
                            {bool(confirmed_skills) and <Button type="button" variant="outline" className="mt-3" disabled={tailoring} onClick={make_tailored_pdf}>{"Add " + str(len(confirmed_skills)) + (" skill" if len(confirmed_skills) == 1 else " skills") + " and tailor again"}</Button>}
                        </div>
                    </div>
                    <div className="rounded-xl border bg-primary/5 p-4 text-sm">
                        <p className="font-medium">{("What changed" if tailor_changes else "Your resume was already in the best order for this job.")}</p>
                        {bool(ai_message()) and <p className="mt-1 text-muted-foreground">{ai_message()}</p>}
                        <ul className="mt-2 list-disc pl-5">
                            {for change in tailor_changes {
                                <li key={change}>{change}</li>
                            }}
                        </ul>
                        {bool(tailor_notes) and <div className="mt-3">
                            <p className="font-medium">Left as it was</p>
                            <ul className="mt-1 list-disc pl-5 text-muted-foreground">
                                {for note in tailor_notes {
                                    <li key={note}>{note}</li>
                                }}
                            </ul>
                        </div>}
                    </div>
                    {bool(preview_url) and <iframe src={preview_url} title="Tailored resume preview" className="h-[75vh] min-h-96 w-full rounded-xl border bg-white" />}
                    <div className="flex flex-wrap items-center gap-3">
                        <Button type="button" disabled={choosing} onClick={use_tailored}>{"Saving..." if choosing else "Use this resume for applications"}</Button>
                        <a href={tailored_pdf} download={tailored_name} className="inline-flex h-9 items-center rounded-lg border border-primary px-4 text-sm font-medium text-primary hover:bg-primary/10">{"Download " + tailored_name}</a>
                    </div>
                </div>}
                {bool(choice_message) and <p role="status" className="mt-3 text-sm text-primary">{choice_message}</p>}
                {bool(choice_error) and <p role="alert" className="mt-3 text-sm text-red-600">{choice_error}</p>}
            </section>
        </main>
        <SiteFooter />
    </div>;
}

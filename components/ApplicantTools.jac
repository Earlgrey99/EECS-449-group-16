import from "@jac/runtime" { jacIsLoggedIn, Link, Navigate, useLocation }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .ui.button { Button }
import from ..services.applicant_demo { review_resume_text, get_applicant_details, tailor_resume_pdf }
import from ..services.jobs { list_jobs }

def:pub ApplicantTools() -> JsxElement {
    location = useLocation();
    job_id = decodeURIComponent(location.search.replace("?job=", "").split("&")[0]);
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }

    # What the extension will fill, from the server, with where each value comes from.
    has contact_rows: list[any] = [];
    has answer_rows: list[any] = [];
    has autofill_resume: str = "";
    has autofill_loaded: bool = False;
    has autofill_error: str = "";

    # Resume review is computed server-side using the existing tailoring module.
    has role: str = "Data Analyst";
    has resume_text: str = "Data science student\n- Built Python data pipelines to process incoming files.\n- Created dashboards for analytics and reporting.";
    has job_description: str = "Seeking a Data Analyst with Python, SQL, Excel, data pipelines, and dashboard experience.";
    has review: str = "";
    has reviewing: bool = False;
    has review_error: str = "";
    has did_init_tools: bool = False;

    has job_notice: str = "";
    has saved_resume_title: str = "";
    has upload_name: str = "";
    has upload_content: str = "";
    has tailoring: bool = False;
    has tailor_error: str = "";
    has tailored_pdf: str = "";
    has tailored_name: str = "";
    has tailor_changes: list[str] = [];

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
                if saved.get("resume_text") {
                    resume_text = str(saved.get("resume_text"));
                    saved_resume_title = str(saved.get("resume_title") or "");
                }
            } else {
                autofill_error = str(saved.get("error") if saved else "") or "Couldn't load your profile.";
            }
        } except Exception {
            autofill_error = "Couldn't load your profile.";
        }
        autofill_loaded = True;
    }

    # Job descriptions can hold HTML. DOMParser reads it without running any of it.
    def plain_text(raw: str) -> str {
        parser: any = Reflect.construct(DOMParser, []);
        parsed: any = parser.parseFromString(raw, "text/html");
        return str(parsed.body.textContent or "").strip();
    }

    def use_job(title: str, desc: str, tags: str) {
        role = title;
        job_description = (plain_text(desc) + ("\n\nSkills: " + tags if tags else ""))[:12000];
    }

    # The jobs page passes the selected job along, which covers external listings.
    # A reloaded or shared link may not have it, so fall back to the built-in jobs.
    async can with entry {
        if did_init_tools {
            return;
        }
        did_init_tools = True;
        await load_saved_details();
        passed: any = location.state.get("job") if location.state else None;
        if passed {
            use_job(str(passed.get("title") or ""), str(passed.get("desc") or ""), str(passed.get("tags") or ""));
            return;
        }
        if job_id {
            available_jobs = await list_jobs();
            for j in available_jobs {
                if str(j["id"]) == job_id {
                    use_job(str(j["title"]), str(j["desc"]), str(j["tags"]));
                    return;
                }
            }
            job_notice = "We couldn't load that job. Paste its description below.";
        }
    }

    def handle_upload(e: ChangeEvent) {
        target: any = e.target;
        files: any = target.files;
        if not files or not files[0] {
            return;
        }
        file_obj: any = files[0];
        upload_name = str(file_obj.name);
        reader: any = Reflect.construct(FileReader, []);
        reader.onload = lambda (load_ev: any) { upload_content = str(load_ev.target.result); };
        reader.readAsDataURL(file_obj);
    }

    async def make_tailored_pdf {
        tailor_error = "";
        tailored_pdf = "";
        tailor_changes = [];
        if not job_description.strip() {
            tailor_error = "Paste the job description above first.";
            return;
        }
        tailoring = True;
        try {
            tok = str(localStorage.getItem("jac_token") or "");
            res: any = await tailor_resume_pdf(token=tok, job_text=job_description, role=role, resume_content=upload_content);
            if res and res.get("ok") {
                tailored_pdf = str(res.get("pdf"));
                tailored_name = str(res.get("filename"));
                changed: list[str] = res.get("changes") or [];
                tailor_changes = changed;
            } else {
                tailor_error = str(res.get("error") if res else "Couldn't create the PDF.");
            }
        } except Exception {
            tailor_error = "Couldn't reach the tailoring service.";
        }
        tailoring = False;
    }

    async def generate_review(e: FormEvent) {
        e.preventDefault();
        review_error = "";
        if not resume_text.strip() or not job_description.strip() {
            review_error = "Paste both resume text and a job description.";
            return;
        }
        reviewing = True;
        try {
            review = await review_resume_text(resume_text, job_description, role);
        } except Exception {
            review_error = "Could not reach the Jac resume review service.";
        }
        reviewing = False;
    }

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-8 px-6 py-10">
            <header className="flex flex-col gap-3">
                <p className="text-sm font-semibold text-primary">LAUNCHPAD EXPERIMENTAL WORKSPACE</p>
                <h1 className="text-3xl font-semibold tracking-tight">Application tools</h1>
                <p className="max-w-3xl text-muted-foreground">Check what the Launchpad extension will fill on a job application, then review and tailor your resume for the job. Nothing here submits an application or changes your original resume.</p>
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

            <section className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-1">
                    <h2 className="text-2xl font-semibold">2. Resume tailoring</h2>
                    <p className="text-sm text-muted-foreground">Paste resume text and a job description. The Jac backend runs the existing evidence-based tailoring algorithm and returns a review.</p>
                </div>
                {bool(job_notice) and <p role="status" className="mb-4 text-sm text-amber-700">{job_notice}</p>}
                <form onSubmit={generate_review} className="flex flex-col gap-4">
                    <label className="flex flex-col gap-1 text-sm font-medium">Target role
                        <input className="rounded-lg border bg-background p-3 font-normal" value={role} onChange={lambda (e: ChangeEvent) { role = e.target.value; }} />
                    </label>
                    <div className="grid gap-5 md:grid-cols-2">
                        <label className="flex flex-col gap-1 text-sm font-medium">Resume text
                            <textarea className="min-h-52 rounded-lg border bg-background p-3 font-mono text-sm font-normal" value={resume_text} onChange={lambda (e: ChangeEvent) { resume_text = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">Job description
                            <textarea className="min-h-52 rounded-lg border bg-background p-3 font-mono text-sm font-normal" value={job_description} onChange={lambda (e: ChangeEvent) { job_description = e.target.value; }} />
                        </label>
                    </div>
                    {bool(saved_resume_title) and <p className="text-sm text-muted-foreground">{"Using your saved resume: " + saved_resume_title}</p>}
                    <div className="flex flex-wrap items-center gap-3">
                        <Button type="submit" disabled={reviewing}>{"Generating review..." if reviewing else "Generate resume review"}</Button>
                        <p className="text-xs text-muted-foreground">Text is sent to your local Jac backend, not a third-party AI service.</p>
                    </div>
                    {review_error and <p className="text-sm text-red-600">{review_error}</p>}
                </form>
                {review and <div className="mt-7 rounded-xl border bg-primary/5 p-5">
                    <h3 className="mb-3 font-semibold">Job-specific review</h3>
                    <pre className="whitespace-pre-wrap break-words font-mono text-sm leading-relaxed">{review}</pre>
                </div>}
            </section>
            <section className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-1">
                    <h2 className="text-2xl font-semibold">3. Tailored resume PDF</h2>
                    <p className="text-sm text-muted-foreground">Creates a copy of your resume for the job above. Within each job and project, the most relevant bullets move to the top, and matching skills come first. Nothing is added, removed, or reworded.</p>
                </div>
                <div className="flex flex-col gap-4">
                    <p className="text-sm">{("Resume: " + upload_name) if upload_name else (("Resume: your saved " + saved_resume_title) if saved_resume_title else "No saved resume. Upload one below.")}</p>
                    <label className="flex flex-col gap-1 text-sm font-medium">Use a different resume (optional)
                        <input type="file" accept=".pdf,.txt" onChange={handle_upload} className="text-sm font-normal" />
                    </label>
                    <div className="flex flex-wrap items-center gap-3">
                        <Button type="button" disabled={tailoring} onClick={make_tailored_pdf}>{"Creating PDF..." if tailoring else "Create tailored PDF"}</Button>
                        {bool(tailored_pdf) and <a href={tailored_pdf} download={tailored_name} className="inline-flex h-9 items-center rounded-lg border border-primary px-4 text-sm font-medium text-primary hover:bg-primary/10">{"Download " + tailored_name}</a>}
                    </div>
                    {bool(tailor_error) and <p role="alert" className="text-sm text-red-600">{tailor_error}</p>}
                    {bool(tailored_pdf) and <div className="rounded-xl border bg-primary/5 p-4 text-sm">
                        <p className="font-medium">{("What changed" if tailor_changes else "Your resume was already in the best order for this job.")}</p>
                        <ul className="mt-2 list-disc pl-5">
                            {for change in tailor_changes {
                                <li key={change}>{change}</li>
                            }}
                        </ul>
                        <p className="mt-3 text-muted-foreground">Review the PDF before you send it.</p>
                    </div>}
                </div>
            </section>
        </main>
        <SiteFooter />
    </div>;
}

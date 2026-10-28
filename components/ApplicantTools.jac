import from "@jac/runtime" { jacIsLoggedIn, Navigate, useLocation }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .ui.button { Button }
import from ..services.applicant_demo { review_resume_text }
import from ..services.jobs { list_jobs }

def:pub ApplicantTools() -> JsxElement {
    location = useLocation();
    job_id = location.search.replace("?job=", "").split("&")[0];
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }

    # Session-only profile fields (never saved to the server).
    has full_name: str = "";
    has email: str = "";
    has phone: str = "";
    has linkedin: str = "";
    has filled_name: str = "";
    has filled_email: str = "";
    has filled_phone: str = "";
    has filled_linkedin: str = "";
    has autofill_message: str = "Enter test applicant details, then preview the autofill.";

    # Resume review is computed server-side using the existing tailoring module.
    has role: str = "Data Analyst";
    has resume_text: str = "Data science student\n- Built Python data pipelines to process incoming files.\n- Created dashboards for analytics and reporting.";
    has job_description: str = "Seeking a Data Analyst with Python, SQL, Excel, data pipelines, and dashboard experience.";
    has review: str = "";
    has reviewing: bool = False;
    has review_error: str = "";

    # Load the job clicked in the existing feed, if provided.
    async can with entry {
        if job_id {
            available_jobs = await list_jobs();
            for j in available_jobs {
                if str(j["id"]) == job_id {
                    role = str(j["title"]);
                    job_description = str(j["desc"]) + " Relevant technologies: " + str(j["tags"]);
                }
            }
        }
    }

    def fill_demo() {
        if not full_name.strip() or not email.strip() {
            autofill_message = "Name and email are required.";
            return;
        }
        if "@" not in email or "." not in email {
            autofill_message = "Enter a valid email address before filling.";
            return;
        }
        filled_name = full_name.strip();
        filled_email = email.strip();
        filled_phone = phone.strip();
        filled_linkedin = linkedin.strip();
        autofill_message = "Demo form populated. Review or edit the fields below; submission is disabled.";
    }

    def clear_demo() {
        filled_name = "";
        filled_email = "";
        filled_phone = "";
        filled_linkedin = "";
        autofill_message = "Demo form cleared. Your profile inputs remain above.";
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
                <p className="text-sm font-semibold text-primary">JACCIT EXPERIMENTAL WORKSPACE</p>
                <h1 className="text-3xl font-semibold tracking-tight">Application tools</h1>
                <p className="max-w-3xl text-muted-foreground">Try two local prototypes: a sample application autofill and a job-specific resume review. Neither submits a job application or modifies your original resume.</p>
                <p className="text-sm text-amber-700">Prototype only. Profile fields exist in this page session, not in Turso. Refreshing clears them. Use sample information for testing.</p>
            </header>

            <section className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-1">
                    <h2 className="text-2xl font-semibold">1. Applicant autofill</h2>
                    <p className="text-sm text-muted-foreground">Enter details and populate the simulated job application below. Your existing CLI can test browser autofill on supported external forms separately.</p>
                </div>
                <div className="grid gap-6 md:grid-cols-2">
                    <div className="flex flex-col gap-4">
                        <h3 className="font-semibold">Applicant profile</h3>
                        <label className="flex flex-col gap-1 text-sm font-medium">Full name
                            <input className="rounded-lg border bg-background p-3 font-normal" placeholder="Test Applicant" value={full_name} onChange={lambda (e: ChangeEvent) { full_name = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">Email
                            <input type="email" className="rounded-lg border bg-background p-3 font-normal" placeholder="test@example.com" value={email} onChange={lambda (e: ChangeEvent) { email = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">Phone
                            <input className="rounded-lg border bg-background p-3 font-normal" placeholder="5551234567" value={phone} onChange={lambda (e: ChangeEvent) { phone = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">LinkedIn URL
                            <input className="rounded-lg border bg-background p-3 font-normal" placeholder="https://linkedin.com/in/example" value={linkedin} onChange={lambda (e: ChangeEvent) { linkedin = e.target.value; }} />
                        </label>
                        <div className="flex flex-wrap gap-2">
                            <Button onClick={fill_demo}>Autofill demo form</Button>
                            <Button variant="outline" onClick={clear_demo}>Clear form</Button>
                        </div>
                    </div>
                    <div className="flex flex-col gap-4 rounded-xl border bg-primary/5 p-5">
                        <h3 className="font-semibold">Sample application form</h3>
                        <p className="text-xs text-muted-foreground">Example field mappings: full_name, candidate[email], phone, linkedin.</p>
                        <label className="flex flex-col gap-1 text-sm font-medium">Candidate name
                            <input className="rounded-lg border bg-background p-3 font-normal" value={filled_name} onChange={lambda (e: ChangeEvent) { filled_name = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">Candidate email
                            <input className="rounded-lg border bg-background p-3 font-normal" value={filled_email} onChange={lambda (e: ChangeEvent) { filled_email = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">Phone
                            <input className="rounded-lg border bg-background p-3 font-normal" value={filled_phone} onChange={lambda (e: ChangeEvent) { filled_phone = e.target.value; }} />
                        </label>
                        <label className="flex flex-col gap-1 text-sm font-medium">LinkedIn
                            <input className="rounded-lg border bg-background p-3 font-normal" value={filled_linkedin} onChange={lambda (e: ChangeEvent) { filled_linkedin = e.target.value; }} />
                        </label>
                        <p className="text-sm text-primary">{autofill_message}</p>
                        <button type="button" disabled={True} className="cursor-not-allowed rounded-full border border-muted-foreground/30 px-4 py-3 text-sm text-muted-foreground">Submit application (disabled)</button>
                    </div>
                </div>
            </section>

            <section className="rounded-2xl border bg-card p-6 shadow-sm">
                <div className="mb-6 flex flex-col gap-1">
                    <h2 className="text-2xl font-semibold">2. Resume tailoring</h2>
                    <p className="text-sm text-muted-foreground">Paste resume text and a job description. The Jac backend runs the existing evidence-based tailoring algorithm and returns a review.</p>
                </div>
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
        </main>
        <SiteFooter />
    </div>;
}

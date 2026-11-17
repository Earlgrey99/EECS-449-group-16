"""Profile card: what we read from the user's resume, which they can edit.

Shows four parts: Work Experience, Education, Skills and Links.
It loads them from the server when the page opens and saves them when the
user clicks "Save resume details".

GitHub, LinkedIn and Portfolio belong to the profile page (they also show
in step 1, Personal Information). The page passes their current values in,
and this card tells the page about changes through on_link_change. Keeping
one copy in the page is called "lifting state up": both places always show
the same link.

new_resume_content is the file the user just picked in the upload step
(still unsaved). When it is set, a banner offers to fill the sections from it.
"""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { File01Icon, CheckmarkCircle02Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.card { Card, CardContent }
import from .ui.spinner { Spinner }
import from ..services.resume_profile { get_resume_profile, parse_resume_upload, save_resume_profile }

# Shared look for the small section titles inside the card.
glob SECTION_TITLE: str = "text-sm font-semibold text-foreground";
glob FIELD_LABEL: str = "text-xs font-medium text-foreground";
glob REMOVE_BTN: str = "text-xs font-medium text-muted-foreground hover:text-destructive px-1";

def:pub ResumeProfileEditor(
    on_link_change: Callable[[str, str], None],
    github: str = "",
    linkedin: str = "",
    portfolio: str = "",
    new_resume_content: str = ""
) -> JsxElement {
    # The four sections. Each job / school is a dictionary of text fields.
    has experience: list[dict[str, str]] = [];
    has education: list[dict[str, str]] = [];
    has skills: list[str] = [];
    has other_links: list[str] = [];

    has new_skill: str = "";             # text in the "add a skill" box
    has source: str = "";                # "saved", "resume" or "empty"
    has filled_from: str = "";           # the new file we last filled from
    has loading: bool = True;
    has saving: bool = False;
    has unsaved: bool = False;           # True after any edit, until saved
    has confirm_refill: bool = False;    # asking "replace your edits?"
    has notice: str = "";
    has error: str = "";
    has did_init: bool = False;

    def get_token() -> str {
        try {
            return str(localStorage.getItem("jac_token") or "");
        } except Exception {
            return "";
        }
    }

    # The link the page currently holds for "github", "linkedin" or "portfolio".
    def link_value(key: str) -> str {
        if key == "github" {
            return github;
        }
        if key == "linkedin" {
            return linkedin;
        }
        return portfolio;
    }

    # Copy a profile from the server into the boxes on screen.
    # A main link found in the resume only fills a box that is still empty,
    # so links the user typed are never replaced.
    def show_profile(profile: dict[str, any]) {
        experience = profile.get("experience") or [];
        education = profile.get("education") or [];
        skills = profile.get("skills") or [];
        links: dict[str, any] = profile.get("links") or {};
        other_links = links.get("other") or [];
        for key in ["github", "linkedin", "portfolio"] {
            found_url = str(links.get(key) or "");
            if found_url and not link_value(key).strip() {
                on_link_change(key, found_url);
            }
        }
    }

    async can with entry {
        if did_init {
            return;
        }
        did_init = True;
        try {
            res = await get_resume_profile(token=get_token());
            if res and res.get("ok") {
                show_profile(res.get("profile") or {});
                source = str(res.get("source") or "empty");
                # Read fresh from the resume = not saved yet.
                unsaved = source == "resume";
            }
        } except Exception {
            error = "Couldn't load your resume details. Try refreshing the page.";
        }
        loading = False;
    }

    # ----- Editing a job or school -----
    # React only redraws when a "has" value is given a NEW list, so each
    # change builds a new list instead of changing the old one in place.

    def set_job(index: int, field_name: str, value: str) {
        updated: list[dict[str, str]] = [];
        for (i, job) in enumerate(experience) {
            if i == index {
                row = {**job};
                row[field_name] = value;
                updated.append(row);
            } else {
                updated.append(job);
            }
        }
        experience = updated;
        unsaved = True;
    }

    def add_job() {
        experience = experience + [{"title": "", "company": "", "dates": "", "description": ""}];
        unsaved = True;
    }

    def remove_job(index: int) {
        experience = [job for (i, job) in enumerate(experience) if i != index];
        unsaved = True;
    }

    def set_school(index: int, field_name: str, value: str) {
        updated: list[dict[str, str]] = [];
        for (i, school) in enumerate(education) {
            if i == index {
                row = {**school};
                row[field_name] = value;
                updated.append(row);
            } else {
                updated.append(school);
            }
        }
        education = updated;
        unsaved = True;
    }

    def add_school() {
        education = education + [{"school": "", "degree": "", "dates": "", "gpa": ""}];
        unsaved = True;
    }

    def remove_school(index: int) {
        education = [school for (i, school) in enumerate(education) if i != index];
        unsaved = True;
    }

    # ----- Skills -----

    def add_skill() {
        name = new_skill.strip();
        if name and name.lower() not in [s.lower() for s in skills] {
            skills = skills + [name];
            unsaved = True;
        }
        new_skill = "";
    }

    # Pressing Enter in the skill box adds the skill.
    def skill_key(e: any) {
        if e.key == "Enter" {
            e.preventDefault();
            add_skill();
        }
    }

    def remove_skill(name: str) {
        skills = [s for s in skills if s != name];
        unsaved = True;
    }

    # ----- Links -----

    def set_github(e: ChangeEvent) { on_link_change("github", e.target.value); unsaved = True; }
    def set_linkedin(e: ChangeEvent) { on_link_change("linkedin", e.target.value); unsaved = True; }
    def set_portfolio(e: ChangeEvent) { on_link_change("portfolio", e.target.value); unsaved = True; }

    def set_other_link(index: int, value: str) {
        other_links = [(value if i == index else url) for (i, url) in enumerate(other_links)];
        unsaved = True;
    }

    def add_other_link() {
        other_links = other_links + [""];
        unsaved = True;
    }

    def remove_other_link(index: int) {
        other_links = [url for (i, url) in enumerate(other_links) if i != index];
        unsaved = True;
    }

    # True when a link box has text that doesn't start with http.
    # (The server adds "https://" for you, so this is just a hint.)
    def looks_off(url: str) -> bool {
        clean = url.strip().lower();
        return bool(clean) and ("." not in clean or " " in clean);
    }

    # ----- Filling from a resume -----

    async def fill_from_new_file() {
        if (source == "saved" or unsaved) and not confirm_refill {
            confirm_refill = True;   # ask first, so edits aren't lost by accident
            return;
        }
        confirm_refill = False;
        error = "";
        notice = "";
        try {
            res = await parse_resume_upload(token=get_token(), resume_content=new_resume_content);
            if res and res.get("ok") {
                show_profile(res.get("profile") or {});
                filled_from = new_resume_content;
                unsaved = True;
                notice = "Filled in from your new resume. Check it over, then click Save resume details.";
            } else {
                error = str(res.get("error") if res else "Couldn't read that file.");
            }
        } except Exception as err {
            error = f"Couldn't read that file: {str(err)}";
        }
    }

    async def refill_from_saved_resume() {
        if not confirm_refill {
            confirm_refill = True;
            return;
        }
        confirm_refill = False;
        error = "";
        try {
            res = await get_resume_profile(token=get_token(), from_resume=True);
            if res and res.get("ok") {
                show_profile(res.get("profile") or {});
                unsaved = True;
                notice = "Re-read your saved resume. Click Save resume details to keep it.";
            }
        } except Exception as err {
            error = f"Couldn't re-read your resume: {str(err)}";
        }
    }

    # ----- Saving -----

    async def save() {
        saving = True;
        error = "";
        notice = "";
        profile = {
            "experience": experience,
            "education": education,
            "skills": skills,
            "links": {"github": github, "linkedin": linkedin, "portfolio": portfolio, "other": other_links},
        };
        try {
            res = await save_resume_profile(profile=profile, token=get_token());
            if res and res.get("ok") {
                saved_profile: dict[str, any] = res.get("profile") or {};
                show_profile(saved_profile);
                # Show the tidied links (e.g. with https:// added) on the page too.
                saved_links: dict[str, any] = saved_profile.get("links") or {};
                for key in ["github", "linkedin", "portfolio"] {
                    on_link_change(key, str(saved_links.get(key) or ""));
                }
                source = "saved";
                unsaved = False;
                notice = "Saved!";
            } else {
                error = str(res.get("error") if res else "Couldn't save.");
            }
        } except Exception as err {
            error = f"Couldn't save: {str(err)}";
        }
        saving = False;
    }

    has_new_file = bool(new_resume_content) and new_resume_content != filled_from;

    return <Card className="border border-border/80 shadow-sm overflow-visible relative z-0 pt-1 pb-4">
        <CardContent className="flex flex-col gap-5 pt-1.5 pb-2 px-6">
            <div className="flex items-center justify-between gap-2.5 border-b pb-3">
                <div className="flex items-center gap-2.5">
                    <span className="flex size-7 items-center justify-center rounded-full bg-primary/10 text-primary">
                        <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-4" />
                    </span>
                    <div className="flex flex-col">
                        <h2 className="text-base font-semibold text-foreground">Your Resume Details</h2>
                        <p className="text-xs text-muted-foreground">What we read from your resume. Fix anything we got wrong.</p>
                    </div>
                </div>
                {unsaved and <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">Unsaved changes</span>}
            </div>

            {loading and <div className="flex justify-center p-6"><Spinner className="size-6 text-primary" /></div>}

            {(not loading) and <div className="flex flex-col gap-6">

                {has_new_file and <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-primary/30 bg-primary/5 p-3 text-sm">
                    <span className="flex items-center gap-2">
                        <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-4 text-primary" />
                        {"Replace the details below with your new resume? Your edits will be lost." if confirm_refill else "You picked a new resume. Fill in these sections from it?"}
                    </span>
                    <div className="flex gap-2">
                        {confirm_refill and <Button type="button" size="sm" variant="outline" onClick={lambda { confirm_refill = False; }}>Cancel</Button>}
                        <Button type="button" size="sm" onClick={fill_from_new_file}>{"Yes, replace" if confirm_refill else "Fill in from new resume"}</Button>
                    </div>
                </div>}

                {source == "empty" and (not has_new_file) and <p className="rounded-xl border border-dashed p-3 text-sm text-muted-foreground">
                    No resume details yet. Upload your resume in step 3, or type your details in below.
                </p>}

                <section className="flex flex-col gap-3">
                    <div className="flex items-center justify-between">
                        <h3 className={SECTION_TITLE}>Work Experience</h3>
                        <Button type="button" size="sm" variant="outline" onClick={add_job}>+ Add job</Button>
                    </div>
                    {len(experience) == 0 and <p className="text-xs text-muted-foreground">No jobs yet.</p>}
                    {for (i, job) in enumerate(experience) {
                        <div key={"job-" + str(i)} className="flex flex-col gap-2 rounded-xl border bg-background/50 p-3">
                            <div className="grid gap-2 sm:grid-cols-2">
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>Job title</label>
                                    <Input value={job.get("title", "")} placeholder="e.g. Software Engineer" onChange={lambda (e: ChangeEvent) { set_job(i, "title", e.target.value); }} />
                                </div>
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>Company</label>
                                    <Input value={job.get("company", "")} placeholder="e.g. Acme Analytics" onChange={lambda (e: ChangeEvent) { set_job(i, "company", e.target.value); }} />
                                </div>
                            </div>
                            <div className="flex flex-col gap-1">
                                <label className={FIELD_LABEL}>Dates</label>
                                <Input value={job.get("dates", "")} placeholder="e.g. May 2025 - Aug 2025" onChange={lambda (e: ChangeEvent) { set_job(i, "dates", e.target.value); }} />
                            </div>
                            <div className="flex flex-col gap-1">
                                <label className={FIELD_LABEL}>What you did (one point per line)</label>
                                <textarea
                                    className="min-h-24 rounded-lg border bg-background p-2 text-sm"
                                    value={job.get("description", "")}
                                    onChange={lambda (e: ChangeEvent) { set_job(i, "description", e.target.value); }}
                                />
                            </div>
                            <div className="flex justify-end">
                                <button type="button" className={REMOVE_BTN} onClick={lambda { remove_job(i); }}>✕ Remove job</button>
                            </div>
                        </div>
                    }}
                </section>

                <section className="flex flex-col gap-3">
                    <div className="flex items-center justify-between">
                        <h3 className={SECTION_TITLE}>Education</h3>
                        <Button type="button" size="sm" variant="outline" onClick={add_school}>+ Add school</Button>
                    </div>
                    {len(education) == 0 and <p className="text-xs text-muted-foreground">No schools yet.</p>}
                    {for (i, school) in enumerate(education) {
                        <div key={"school-" + str(i)} className="flex flex-col gap-2 rounded-xl border bg-background/50 p-3">
                            <div className="grid gap-2 sm:grid-cols-2">
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>School</label>
                                    <Input value={school.get("school", "")} placeholder="e.g. University of Michigan" onChange={lambda (e: ChangeEvent) { set_school(i, "school", e.target.value); }} />
                                </div>
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>Degree and major</label>
                                    <Input value={school.get("degree", "")} placeholder="e.g. B.S. Computer Science" onChange={lambda (e: ChangeEvent) { set_school(i, "degree", e.target.value); }} />
                                </div>
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>Dates or graduation year</label>
                                    <Input value={school.get("dates", "")} placeholder="e.g. 2026" onChange={lambda (e: ChangeEvent) { set_school(i, "dates", e.target.value); }} />
                                </div>
                                <div className="flex flex-col gap-1">
                                    <label className={FIELD_LABEL}>GPA (optional)</label>
                                    <Input value={school.get("gpa", "")} placeholder="e.g. 3.8" onChange={lambda (e: ChangeEvent) { set_school(i, "gpa", e.target.value); }} />
                                </div>
                            </div>
                            <div className="flex justify-end">
                                <button type="button" className={REMOVE_BTN} onClick={lambda { remove_school(i); }}>✕ Remove school</button>
                            </div>
                        </div>
                    }}
                </section>

                <section className="flex flex-col gap-3">
                    <h3 className={SECTION_TITLE}>Skills</h3>
                    <div className="flex flex-wrap gap-1.5">
                        {len(skills) == 0 and <span className="text-xs text-muted-foreground">No skills yet.</span>}
                        {for s in skills {
                            <span key={s} className="flex items-center gap-1 rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-medium text-primary">
                                {s}
                                <button type="button" aria-label={"Remove " + s} className="hover:text-destructive" onClick={lambda { remove_skill(s); }}>✕</button>
                            </span>
                        }}
                    </div>
                    <div className="flex gap-2">
                        <Input
                            value={new_skill}
                            placeholder="Add a skill, e.g. React"
                            onChange={lambda (e: ChangeEvent) { new_skill = e.target.value; }}
                            onKeyDown={skill_key}
                        />
                        <Button type="button" size="sm" variant="outline" onClick={add_skill}>Add</Button>
                    </div>
                </section>

                <section className="flex flex-col gap-3">
                    <h3 className={SECTION_TITLE}>Links</h3>
                    <p className="text-xs text-muted-foreground">GitHub, LinkedIn and Portfolio are the same ones as in step 1. Changing them here changes them there too.</p>
                    <div className="grid gap-2 sm:grid-cols-3">
                        <div className="flex flex-col gap-1">
                            <label className={FIELD_LABEL}>GitHub</label>
                            <Input value={github} placeholder="https://github.com/you" onChange={set_github} />
                            {looks_off(github) and <span className="text-xs text-destructive">This doesn't look like a web address.</span>}
                        </div>
                        <div className="flex flex-col gap-1">
                            <label className={FIELD_LABEL}>LinkedIn</label>
                            <Input value={linkedin} placeholder="https://linkedin.com/in/you" onChange={set_linkedin} />
                            {looks_off(linkedin) and <span className="text-xs text-destructive">This doesn't look like a web address.</span>}
                        </div>
                        <div className="flex flex-col gap-1">
                            <label className={FIELD_LABEL}>Portfolio</label>
                            <Input value={portfolio} placeholder="https://yoursite.com" onChange={set_portfolio} />
                            {looks_off(portfolio) and <span className="text-xs text-destructive">This doesn't look like a web address.</span>}
                        </div>
                    </div>
                    {for (i, url) in enumerate(other_links) {
                        <div key={"link-" + str(i)} className="flex items-center gap-2">
                            <Input value={url} placeholder="https://..." onChange={lambda (e: ChangeEvent) { set_other_link(i, e.target.value); }} />
                            <button type="button" className={REMOVE_BTN} onClick={lambda { remove_other_link(i); }}>✕</button>
                        </div>
                    }}
                    <div>
                        <Button type="button" size="sm" variant="outline" onClick={add_other_link}>+ Add another link</Button>
                    </div>
                </section>

                {error and <div className="rounded-xl border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive font-medium">{error}</div>}
                {notice and <div className="flex items-center gap-2 rounded-xl border border-emerald-600/20 bg-emerald-50 p-3 text-sm text-emerald-800">
                    <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-4" />
                    <span>{notice}</span>
                </div>}

                {confirm_refill and (not has_new_file) and <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                    <span>Replace the details above with what's in your saved resume? Your edits will be lost.</span>
                    <div className="flex gap-2">
                        <Button type="button" size="sm" variant="outline" onClick={lambda { confirm_refill = False; }}>Cancel</Button>
                        <Button type="button" size="sm" onClick={refill_from_saved_resume}>Yes, replace</Button>
                    </div>
                </div>}

                <div className="flex flex-wrap items-center justify-between gap-3">
                    {source != "empty" and <button type="button" className="text-xs font-medium text-muted-foreground hover:text-primary" onClick={refill_from_saved_resume}>
                        Re-read my saved resume
                    </button>}
                    <Button type="button" disabled={saving} onClick={save} className="ml-auto gap-2">
                        {saving and <Spinner className="size-4" />}
                        <span>{"Saving..." if saving else "Save resume details"}</span>
                    </Button>
                </div>
            </div>}
        </CardContent>
    </Card>;
}

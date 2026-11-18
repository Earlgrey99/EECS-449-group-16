import from "@jac/runtime" { jacIsLoggedIn, Navigate }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .ui.button { Button }
import from ..services.tracker {
    list_tracker_applications,
    add_tracker_application,
    get_tracker_status_options,
    save_tracker_status_options,
    set_tracker_status,
    edit_tracker_application,
    remove_tracker_application
}

def:pub TrackerRow(
    role: str,
    company: str,
    job_url: str,
    applied_date: str,
    description: str,
    pay: str,
    resume: str,
    cover_letter: str,
    status: str,
    status_options: list[dict[str, str]],
    status_color: str,
    edit_mode: bool,
    selected_for_edit: bool,
    onSelection: Callable[[ChangeEvent], None],
    onStatusChange: Callable[[str], None],
    onOpenNotes: Callable[[str, str, str], None]
) -> JsxElement {
    def handle_status(e: ChangeEvent) {
        onStatusChange(e.target.value);
    }
    def handle_selection(e: ChangeEvent) {
        onSelection(e);
    }
    def open_notes(e: MouseEvent) {
        onOpenNotes(role, company, description);
    }
    def handle_notes_key(e: KeyboardEvent) {
        if e.key == "Enter" or e.key == " " {
            e.preventDefault();
            onOpenNotes(role, company, description);
        }
    }

    return
    <tr className="border-b last:border-b-0 hover:bg-muted/30">
        {edit_mode and <td className="px-3 py-3.5">
            <input
                type="checkbox"
                checked={selected_for_edit}
                onChange={handle_selection}
                aria-label={"Select " + role + " at " + company + " to edit"}
                className="size-4 accent-primary"
            />
        </td>}
        <td className="whitespace-nowrap px-4 py-3.5 font-medium text-foreground">
            {bool(job_url) and <a href={job_url} target="_blank" rel="noopener noreferrer" className="underline underline-offset-2 hover:text-primary">{company}</a>}
            {(not job_url) and <span>{company}</span>}
        </td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm">{role}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{applied_date}</td>
        <td className="px-4 py-3.5">
            <select
                value={status}
                onChange={handle_status}
                aria-label={"Status for " + company}
                style={{"backgroundColor": status_color, "borderColor": status_color, "color": "#ffffff"}}
                className="rounded-full border px-3 py-1.5 text-xs font-semibold outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
                {for option in status_options {
                    <option key={option["name"]} value={option["name"]}>{option["name"]}</option>
                }}
            </select>
        </td>
        <td className="w-24 px-4 py-3.5 text-sm">
            <button
                type="button"
                onDoubleClick={open_notes}
                onKeyDown={handle_notes_key}
                aria-label={"Open notes for " + role + " at " + company}
                title="Double-click to read the full description"
                className="w-full truncate rounded-md border border-border bg-muted/40 px-2 py-1 text-left text-muted-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
                Notes
            </button>
        </td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm tabular-nums">{pay}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{resume}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{cover_letter}</td>
    </tr>;
}

def:pub TrackerPage() -> JsxElement {
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }

    has applications: list[dict[str, str | int]] = [];
    has loading: bool = True;
    has action_error: str = "";
    has did_load: bool = False;
    has current_view: str = "table";
    has notes_open: bool = False;
    has note_title: str = "";
    has note_description: str = "";
    has show_form: bool = False;
    has edit_mode: bool = False;
    has selected_application_ids: list[int] = [];
    has edit_drafts: list[dict[str, any]] = [];
    has status_options: list[dict[str, str]] = [
        {"name": "Applied", "color": "#64748b"},
        {"name": "Interview", "color": "#2563eb"},
        {"name": "Offer", "color": "#16a34a"},
        {"name": "Rejected", "color": "#dc2626"},
        {"name": "Withdrawn", "color": "#78716c"}
    ];
    has new_role: str = "";
    has new_company: str = "";
    has new_date: str = "";
    has new_description: str = "";
    has new_pay: str = "";
    has new_status: str = "Applied";
    has new_resume_pdf_name: str = "";
    has new_resume_pdf_content: str = "";
    has new_cover_letter_pdf_name: str = "";
    has new_cover_letter_pdf_content: str = "";
    has reading_pdf: str = "";
    has edit_error: str = "";
    has new_status_name: str = "";
    has new_status_color: str = "#0f766e";
    has form_error: str = "";
    has show_widget_manager: bool = False;
    has active_widgets: list[str] = ["total", "progress", "offers", "response", "status", "flow"];
    has status_visualization: str = "pie";

    widget_options: list[dict[str, str]] = [
        {"id": "total", "label": "Total applications", "description": "Count every application"},
        {"id": "progress", "label": "In progress", "description": "Applied and interview stages"},
        {"id": "offers", "label": "Offers", "description": "Count received offers"},
        {"id": "response", "label": "Response rate", "description": "Applications with a response"},
        {"id": "status", "label": "Status breakdown", "description": "Pie, bar, or table view"},
        {"id": "flow", "label": "Application flow", "description": "Sankey diagram by status"}
    ];

    def has_widget(widget_id: str) -> bool {
        return widget_id in active_widgets;
    }

    def toggle_widget(widget_id: str) {
        if has_widget(widget_id) {
            active_widgets = [widget for widget in active_widgets if widget != widget_id];
        } else {
            active_widgets = active_widgets + [widget_id];
        }
    }

    def handle_visualization(e: ChangeEvent) {
        status_visualization = e.target.value;
    }

    def count_status(status: str) -> int {
        return len([app for app in applications if str(app["status"]) == status]);
    }

    def status_color_for(status: str) -> str {
        for option in status_options {
            if option["name"] == status {
                return option["color"];
            }
        }
        return "#64748b";
    }

    def status_in_use(status: str) -> bool {
        return any([str(app["status"]) == status for app in applications]);
    }

    def session_token -> str {
        try {
            return str(localStorage.getItem("jac_token") or "");
        } except Exception {
            return "";
        }
    }

    async can with entry {
        if did_load {
            return;
        }
        did_load = True;
        try {
            options_res: any = await get_tracker_status_options(token=session_token());
            if options_res and options_res.get("ok") {
                status_options = options_res.get("options") or status_options;
                if status_options and new_status not in [option["name"] for option in status_options] {
                    new_status = status_options[0]["name"];
                }
            } else {
                action_error = str(options_res.get("error") if options_res else "Could not load tracker status options.");
            }
            res: any = await list_tracker_applications(token=session_token());
            if res and res.get("ok") {
                loaded: list[dict[str, str | int]] = res.get("applications") or [];
                pending_raw = localStorage.getItem("jaccit_tracker_pending_application");
                if pending_raw {
                    try {
                        pending: any = JSON.parse(pending_raw);
                        applied_date = str(pending.get("applied_date") or pending.get("date") or "");
                        date_parts = applied_date.split("-");
                        if len(date_parts) == 3 and len(date_parts[0]) != 4 {
                            applied_date = date_parts[2] + "-" + date_parts[0] + "-" + date_parts[1];
                        }
                        pending_res: any = await add_tracker_application(
                            token=session_token(),
                            role=str(pending.get("role") or ""),
                            company=str(pending.get("company") or ""),
                            applied_date=applied_date,
                            description=str(pending.get("description") or ""),
                            pay=None,
                            status=str(pending.get("status") or "Applied"),
                            salary_text=str(pending.get("pay") or "")
                        );
                        if pending_res and pending_res.get("ok") {
                            if not pending_res.get("already_tracked") {
                                loaded = [pending_res.get("application")] + loaded;
                            }
                            localStorage.removeItem("jaccit_tracker_pending_application");
                        } else {
                            action_error = str(pending_res.get("error") if pending_res else "Could not save the pending application.");
                        }
                    } except Exception {
                        action_error = "Could not save the pending application.";
                    }
                }
                applications = loaded;
            } else {
                action_error = str(res.get("error") if res else "Could not load your applications.");
            }
        } except Exception {
            action_error = "Could not load your applications.";
        }
        loading = False;
    }

    async def set_status(app_id: int, selected_status: str) {
        action_error = "";
        try {
            res: any = await set_tracker_status(token=session_token(), app_id=app_id, status=selected_status);
            if res and res.get("ok") {
                applications = [{**app, "status": selected_status} if int(app["id"]) == app_id else app for app in applications];
            } else {
                action_error = str(res.get("error") if res else "Could not update the status.");
            }
        } except Exception {
            action_error = "Could not update the status.";
        }
    }

    async def add_application() {
        if not new_role.strip() or not new_company.strip() or not new_date {
            form_error = "Company, job title, and application date are required.";
            return;
        }
        if reading_pdf {
            form_error = "Wait for the selected PDF to finish reading.";
            return;
        }
        if new_pay and not new_pay.isdigit() {
            form_error = "Pay available must be a whole number.";
            return;
        }
        try {
            res: any = await add_tracker_application(
                token=session_token(),
                role=new_role.strip(),
                company=new_company.strip(),
                applied_date=new_date,
                description=new_description.strip(),
                pay=int(new_pay) if new_pay else None,
                status=new_status,
                resume_pdf_name=new_resume_pdf_name,
                resume_pdf_content=new_resume_pdf_content,
                cover_letter_pdf_name=new_cover_letter_pdf_name,
                cover_letter_pdf_content=new_cover_letter_pdf_content
            );
            if not res or not res.get("ok") {
                form_error = str(res.get("error") if res else "Could not save the application.");
                return;
            }
            added: any = res.get("application");
            if not res.get("already_tracked") {
                applications = [added] + applications;
            }
        } except Exception {
            form_error = "Could not save the application.";
            return;
        }
        new_role = "";
        new_company = "";
        new_date = "";
        new_description = "";
        new_pay = "";
        new_status = status_options[0]["name"] if status_options else "Applied";
        new_resume_pdf_name = "";
        new_resume_pdf_content = "";
        new_cover_letter_pdf_name = "";
        new_cover_letter_pdf_content = "";
        form_error = "";
        show_form = False;
    }

    def handle_role(e: ChangeEvent) { new_role = e.target.value; }
    def handle_company(e: ChangeEvent) { new_company = e.target.value; }
    def handle_date(e: ChangeEvent) { new_date = e.target.value; }
    def handle_description(e: ChangeEvent) { new_description = e.target.value; }
    def handle_pay(e: ChangeEvent) { new_pay = e.target.value; }
    def handle_new_status(e: ChangeEvent) { new_status = e.target.value; }
    def handle_new_status_name(e: ChangeEvent) { new_status_name = e.target.value; }
    def handle_new_status_color(e: ChangeEvent) { new_status_color = e.target.value; }
    def open_application_notes(role: str, company: str, description: str) {
        note_title = role + " at " + company;
        note_description = description;
        notes_open = True;
    }
    def close_application_notes(e: MouseEvent) {
        notes_open = False;
    }
    def close_application_notes_on_escape(e: KeyboardEvent) {
        if e.key == "Escape" {
            notes_open = False;
        }
    }

    def update_edit_draft(app_id: int, changes: dict[str, any]) {
        edit_drafts = [
            {**draft, **changes} if int(draft["id"]) == app_id else draft
            for draft in edit_drafts
        ];
    }

    def edit_field_handler(app_id: int, field: str) -> Callable[[ChangeEvent], None] {
        def handle_edit_field(e: ChangeEvent) {
            changes: dict[str, any] = {};
            changes[field] = e.target.value;
            update_edit_draft(app_id, changes);
        }
        return handle_edit_field;
    }

    def edit_resume_handler(app_id: int) -> Callable[[ChangeEvent], None] {
        return lambda (e: ChangeEvent) { handle_edit_resume_pdf(app_id, e); };
    }

    def edit_cover_letter_handler(app_id: int) -> Callable[[ChangeEvent], None] {
        return lambda (e: ChangeEvent) { handle_edit_cover_letter_pdf(app_id, e); };
    }

    def clear_resume_handler(app_id: int) -> Callable[[], None] {
        return lambda { update_edit_draft(app_id, {"resume_name": "", "resume_content": "", "clear_resume": True}); };
    }

    def clear_cover_letter_handler(app_id: int) -> Callable[[], None] {
        return lambda { update_edit_draft(app_id, {"cover_letter_name": "", "cover_letter_content": "", "clear_cover_letter": True}); };
    }

    def handle_selection(app_id: int, e: ChangeEvent) {
        is_checked: bool = e.target.checked;
        if is_checked and app_id not in selected_application_ids {
            selected_application_ids = selected_application_ids + [app_id];
        } elif not is_checked {
            selected_application_ids = [selected_id for selected_id in selected_application_ids if selected_id != app_id];
        }
    }

    def toggle_edit_mode() {
        edit_mode = not edit_mode;
        selected_application_ids = [];
        edit_drafts = [];
        edit_error = "";
    }

    def read_pdf_file(
        e: ChangeEvent,
        on_read: Callable[[str, str], None],
        on_error: Callable[[str], None]
    ) {
        target: any = e.target;
        files: any = target.files;
        if not files or len(files) == 0 {
            return;
        }
        file_obj: any = files[0];
        file_name = str(file_obj.name or "");
        if not file_name.lower().endswith(".pdf") or int(file_obj.size or 0) > 2097152 {
            on_error("Choose a PDF file that is 2 MB or smaller.");
            target.value = "";
            return;
        }
        if file_obj.type and file_obj.type != "application/pdf" {
            on_error("Choose a PDF file.");
            target.value = "";
            return;
        }
        reader: any = None;
        try {
            reader = Reflect.construct(FileReader, []);
        } except Exception {
            on_error("Your browser could not read this PDF.");
            return;
        }
        reading_pdf = file_name;
        reader.onload = lambda (load_ev: any) {
            data_url = str(load_ev.target.result or "");
            if not data_url.startswith("data:application/pdf;base64,") {
                on_error("The selected file could not be read as a PDF.");
                reading_pdf = "";
                return;
            }
            on_read(file_name, data_url);
            reading_pdf = "";
        };
        reader.onerror = lambda (error_ev: any) {
            on_error("Your browser could not read this PDF.");
            reading_pdf = "";
        };
        reader.readAsDataURL(file_obj);
    }

    def handle_new_resume_pdf(e: ChangeEvent) {
        read_pdf_file(
            e,
            lambda (name: str, content: str) {
                new_resume_pdf_name = name;
                new_resume_pdf_content = content;
                form_error = "";
            },
            lambda (message: str) { form_error = message; }
        );
    }

    def handle_new_cover_letter_pdf(e: ChangeEvent) {
        read_pdf_file(
            e,
            lambda (name: str, content: str) {
                new_cover_letter_pdf_name = name;
                new_cover_letter_pdf_content = content;
                form_error = "";
            },
            lambda (message: str) { form_error = message; }
        );
    }

    def handle_edit_resume_pdf(app_id: int, e: ChangeEvent) {
        read_pdf_file(
            e,
            lambda (name: str, content: str) {
                update_edit_draft(app_id, {"resume_name": name, "resume_content": content, "clear_resume": False});
                edit_error = "";
            },
            lambda (message: str) { edit_error = message; }
        );
    }

    def handle_edit_cover_letter_pdf(app_id: int, e: ChangeEvent) {
        read_pdf_file(
            e,
            lambda (name: str, content: str) {
                update_edit_draft(app_id, {"cover_letter_name": name, "cover_letter_content": content, "clear_cover_letter": False});
                edit_error = "";
            },
            lambda (message: str) { edit_error = message; }
        );
    }

    def make_edit_draft(app: dict[str, str | int]) -> dict[str, any] {
        date_parts = str(app["date"]).split("-");
        return {
            "id": int(app["id"]),
            "role": str(app["role"]),
            "company": str(app["company"]),
            "date": date_parts[2] + "-" + date_parts[0] + "-" + date_parts[1] if len(date_parts) == 3 else "",
            "description": "" if str(app["description"]) == "None found" else str(app["description"]),
            "pay": str(app["pay"]),
            "status": str(app["status"]),
            "resume_name": "" if str(app["resume"]) == "None found" else str(app["resume"]),
            "resume_content": "",
            "cover_letter_name": "" if str(app["cover_letter"]) == "None found" else str(app["cover_letter"]),
            "cover_letter_content": "",
            "clear_resume": False,
            "clear_cover_letter": False
        };
    }

    def start_selected_edit() {
        edit_drafts = [make_edit_draft(app) for app in applications if int(app["id"]) in selected_application_ids];
        edit_error = "";
    }

    def update_status_color(status: str, color: str) {
        status_options = [
            {**option, "color": color} if option["name"] == status else option
            for option in status_options
        ];
    }

    def add_status_option() {
        name = new_status_name.strip();
        if not name or len(name) > 40 {
            edit_error = "Status names must be 1 to 40 characters.";
            return;
        }
        if name.lower() in [option["name"].lower() for option in status_options] {
            edit_error = "That status already exists.";
            return;
        }
        if len(status_options) >= 20 {
            edit_error = "You can have up to 20 status options.";
            return;
        }
        status_options = status_options + [{"name": name, "color": new_status_color}];
        new_status_name = "";
        edit_error = "";
    }

    def remove_status_option(status: str) {
        if status_in_use(status) {
            edit_error = "Reassign applications before removing a status option.";
            return;
        }
        if len(status_options) <= 1 {
            edit_error = "Keep at least one status option.";
            return;
        }
        status_options = [option for option in status_options if option["name"] != status];
        edit_error = "";
    }

    async def remove_application(app_id: int, label: str) {
        if not window.confirm("Remove " + label + " from your tracker? This can't be undone.") {
            return;
        }
        edit_error = "";
        try {
            res: any = await remove_tracker_application(token=session_token(), app_id=app_id);
            if res and res.get("ok") {
                applications = [app for app in applications if int(app["id"]) != app_id];
                edit_drafts = [draft for draft in edit_drafts if int(draft["id"]) != app_id];
                selected_application_ids = [selected_id for selected_id in selected_application_ids if selected_id != app_id];
                if not applications {
                    edit_mode = False;
                }
            } else {
                edit_error = str(res.get("error") if res else "Could not remove the application.");
            }
        } except Exception {
            edit_error = "Could not remove the application.";
        }
    }

    async def save_edit() {
        if reading_pdf {
            edit_error = "Wait for the selected PDF to finish reading.";
            return;
        }
        if not edit_drafts {
            edit_error = "Select at least one application to edit.";
            return;
        }
        for draft in edit_drafts {
            if not str(draft["role"]).strip() or not str(draft["company"]).strip() or not str(draft["date"]) {
                edit_error = "Each selected application needs a company, job title, and application date.";
                return;
            }
            if str(draft["pay"]) and not str(draft["pay"]).isdigit() {
                edit_error = "Pay available must be a whole number for each application.";
                return;
            }
            if str(draft["status"]) not in [option["name"] for option in status_options] {
                edit_error = "Choose a valid status for each application.";
                return;
            }
        }
        edit_error = "";
        try {
            options_res: any = await save_tracker_status_options(token=session_token(), options=status_options);
            if not options_res or not options_res.get("ok") {
                edit_error = str(options_res.get("error") if options_res else "Could not save status options.");
                return;
            }
            status_options = options_res.get("options") or status_options;
            for draft in edit_drafts {
                app_id = int(draft["id"]);
                res: any = await edit_tracker_application(
                    token=session_token(),
                    app_id=app_id,
                    role=str(draft["role"]).strip(),
                    company=str(draft["company"]).strip(),
                    applied_date=str(draft["date"]),
                    description=str(draft["description"]).strip(),
                    pay=int(str(draft["pay"])) if str(draft["pay"]) else 0,
                    status=str(draft["status"]),
                    resume_pdf_name=str(draft["resume_name"]) if draft["resume_content"] else "",
                    resume_pdf_content=str(draft["resume_content"]),
                    cover_letter_pdf_name=str(draft["cover_letter_name"]) if draft["cover_letter_content"] else "",
                    cover_letter_pdf_content=str(draft["cover_letter_content"]),
                    clear_resume_pdf=bool(draft["clear_resume"]),
                    clear_cover_letter_pdf=bool(draft["clear_cover_letter"])
                );
                if not res or not res.get("ok") {
                    edit_error = "Could not save " + str(draft["role"]) + " at " + str(draft["company"]) + ": " + str(res.get("error") if res else "Unknown error.");
                    return;
                }
                updated_app: any = res.get("application");
                applications = [updated_app if int(app["id"]) == app_id else app for app in applications];
            }
            edit_drafts = [];
            selected_application_ids = [];
            edit_mode = False;
        } except Exception {
            edit_error = "Could not save your changes.";
        }
    }

    def csv_cell(value: str) -> str {
        # A leading =, +, -, or @ would run as a formula in a spreadsheet.
        safe = "'" + value if value[:1] in ["=", "+", "-", "@"] else value;
        return "\"" + safe.replace("\"", "\"\"") + "\"";
    }

    csv_rows: list[str] = ["Company name,Job title,Date Applied,Description,Pay available,Resume PDF used,Cover letter,Status"];
    for app in applications {
        csv_rows.append(
            csv_cell(str(app["company"])) + "," +
            csv_cell(str(app["role"])) + "," +
            csv_cell(str(app["date"])) + "," +
            csv_cell(str(app["description"])) + "," +
            csv_cell(str(app["pay"])) + "," +
            csv_cell(str(app["resume"])) + "," +
            csv_cell(str(app["cover_letter"])) + "," +
            csv_cell(str(app["status"]))
        );
    }
    csv_data = "\n".join(csv_rows);

    total = len(applications);
    response_count = total - count_status("Applied");
    response_rate = int((response_count / total) * 100) if total > 0 else 0;
    pie_segments: list[str] = [];
    pie_offset = 0.0;
    for option in status_options {
        status = option["name"];
        status_count = count_status(status);
        if status_count > 0 {
            segment_end = pie_offset + ((status_count / total) * 100);
            pie_segments.append(option["color"] + " " + str(pie_offset) + "% " + str(segment_end) + "%");
            pie_offset = segment_end;
        }
    }
    pie_background = "conic-gradient(" + ", ".join(pie_segments) + ")" if total > 0 else "#e7e8e5";

    sankey_scale = 200.0 / total if total > 0 else 0.0;
    flow_offset = 0.0;

    return <div className="flex min-h-svh flex-col bg-background text-foreground">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-7 px-6 py-10" onKeyDown={close_application_notes_on_escape}>
            <header className="flex flex-col gap-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                    <div className="flex flex-col gap-2">
                        <p className="text-sm font-semibold tracking-wide text-primary">YOUR WORKSPACE / CAREER</p>
                        <h1 className="text-3xl font-semibold tracking-tight">Application tracker</h1>
                        <p className="max-w-2xl text-sm text-muted-foreground">Keep every opportunity in one place. Update a status to see your application insights change instantly.</p>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                        <a
                            href={"data:text/csv;charset=utf-8," + encodeURIComponent(csv_data)}
                            download="application-tracker.csv"
                            className="inline-flex h-9 items-center rounded-lg border border-border bg-background px-3 text-sm font-medium text-foreground shadow-sm transition-colors hover:bg-muted"
                        >
                            Export CSV
                        </a>
                        <Button variant="outline" onClick={toggle_edit_mode} disabled={len(applications) == 0}>
                            {("Cancel edit" if edit_mode else "Edit")}
                        </Button>
                        {edit_mode and <Button onClick={start_selected_edit} disabled={len(selected_application_ids) == 0}>
                            {"Edit selected (" + str(len(selected_application_ids)) + ")"}
                        </Button>}
                        <Button onClick={lambda { show_form = not show_form; form_error = ""; }}>
                            <span className="mr-1 text-base">+</span> Add application
                        </Button>
                    </div>
                </div>
                {bool(action_error) and <p role="alert" className="text-sm text-destructive">{action_error}</p>}
            </header>

            <div className="flex w-fit items-center gap-1 rounded-xl border bg-card p-1 shadow-sm" role="tablist" aria-label="Tracker views">
                <button
                    role="tab"
                    aria-selected={current_view == "table"}
                    onClick={lambda { current_view = "table"; }}
                    className={"rounded-lg px-4 py-2 text-sm font-medium transition-colors " + ("bg-primary text-primary-foreground shadow-sm" if current_view == "table" else "text-muted-foreground hover:text-foreground")}
                >
                    Table
                </button>
                <button
                    role="tab"
                    aria-selected={current_view == "insights"}
                    onClick={lambda { current_view = "insights"; }}
                    className={"rounded-lg px-4 py-2 text-sm font-medium transition-colors " + ("bg-primary text-primary-foreground shadow-sm" if current_view == "insights" else "text-muted-foreground hover:text-foreground")}
                >
                    Insights
                </button>
            </div>

            {show_form and <section className="rounded-2xl border bg-card p-5 shadow-sm">
                <div className="mb-4">
                    <h2 className="font-semibold">New application</h2>
                    <p className="text-sm text-muted-foreground">Add an opportunity to your tracker.</p>
                </div>
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <input value={new_role} onChange={handle_role} placeholder="Job title" aria-label="Job title" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                    <input value={new_company} onChange={handle_company} placeholder="Company" aria-label="Company" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                    <input type="date" value={new_date} onChange={handle_date} aria-label="Applied date" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                    <input value={new_description} onChange={handle_description} placeholder="Description" aria-label="Job description" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                    <input type="number" min="0" step="1" value={new_pay} onChange={handle_pay} placeholder="Pay available" aria-label="Pay available" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                    <select value={new_status} onChange={handle_new_status} aria-label="Initial status" className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring">
                        {for option in status_options {
                            <option key={option["name"]} value={option["name"]}>{option["name"]}</option>
                        }}
                    </select>
                </div>
                <div className="mt-4 grid gap-3 sm:grid-cols-2">
                    <label className="flex flex-col gap-1 text-sm font-medium">
                        Resume PDF (optional, max 2 MB)
                        <input type="file" accept="application/pdf,.pdf" onChange={handle_new_resume_pdf} aria-label="Resume PDF" className="rounded-lg border bg-background px-3 py-2 text-sm font-normal file:mr-3 file:rounded-md file:border-0 file:bg-muted file:px-3 file:py-1.5 file:font-medium" />
                        {bool(new_resume_pdf_name) and <span className="text-xs text-muted-foreground">Selected: {new_resume_pdf_name}</span>}
                    </label>
                    <label className="flex flex-col gap-1 text-sm font-medium">
                        Cover letter PDF (optional, max 2 MB)
                        <input type="file" accept="application/pdf,.pdf" onChange={handle_new_cover_letter_pdf} aria-label="Cover letter PDF" className="rounded-lg border bg-background px-3 py-2 text-sm font-normal file:mr-3 file:rounded-md file:border-0 file:bg-muted file:px-3 file:py-1.5 file:font-medium" />
                        {bool(new_cover_letter_pdf_name) and <span className="text-xs text-muted-foreground">Selected: {new_cover_letter_pdf_name}</span>}
                    </label>
                </div>
                <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
                    <p role="alert" className="text-sm text-destructive">{form_error or ("Reading " + reading_pdf if reading_pdf else "")}</p>
                    <div className="flex gap-2">
                        <Button variant="ghost" onClick={lambda { show_form = False; form_error = ""; }}>Cancel</Button>
                        <Button onClick={add_application}>Save application</Button>
                    </div>
                </div>
            </section>}

            {edit_drafts and <section className="rounded-2xl border border-primary/30 bg-card p-5 shadow-sm">
                <div className="mb-4">
                    <h2 className="font-semibold">Edit selected applications</h2>
                    <p className="text-sm text-muted-foreground">Edit each selected application independently, then save them together.</p>
                </div>
                <div className="grid gap-4">
                    {for draft in edit_drafts {
                        draft_id = int(draft["id"]);
                        <article key={str(draft_id)} className="rounded-xl border p-4">
                            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                                <h3 className="font-medium">{str(draft["role"]) + " at " + str(draft["company"])}</h3>
                                <Button
                                    variant="outline"
                                    className="border-destructive/40 text-destructive hover:bg-destructive/10"
                                    aria-label={"Remove " + str(draft["role"]) + " at " + str(draft["company"])}
                                    onClick={lambda { remove_application(draft_id, str(draft["role"]) + " at " + str(draft["company"])); }}
                                >Remove application</Button>
                            </div>
                            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                                <input value={str(draft["role"])} onChange={edit_field_handler(draft_id, "role")} placeholder="Job title" aria-label={"Edit job title for " + str(draft["company"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                                <input value={str(draft["company"])} onChange={edit_field_handler(draft_id, "company")} placeholder="Company" aria-label={"Edit company for " + str(draft["role"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                                <input type="date" value={str(draft["date"])} onChange={edit_field_handler(draft_id, "date")} aria-label={"Edit applied date for " + str(draft["company"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                                <input value={str(draft["description"])} onChange={edit_field_handler(draft_id, "description")} placeholder="Description" aria-label={"Edit job description for " + str(draft["company"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                                <input type="number" min="0" step="1" value={str(draft["pay"])} onChange={edit_field_handler(draft_id, "pay")} placeholder="Pay available" aria-label={"Edit pay for " + str(draft["company"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                                <select value={str(draft["status"])} onChange={edit_field_handler(draft_id, "status")} aria-label={"Edit status for " + str(draft["company"])} className="h-10 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring">
                                    {for option in status_options {
                                        <option key={option["name"]} value={option["name"]}>{option["name"]}</option>
                                    }}
                                </select>
                            </div>
                            <div className="mt-3 grid gap-3 sm:grid-cols-2">
                                <label className="flex flex-col gap-1 text-sm font-medium">
                                    Resume PDF
                                    <input type="file" accept="application/pdf,.pdf" onChange={edit_resume_handler(draft_id)} aria-label={"Replace resume PDF for " + str(draft["company"])} className="rounded-lg border bg-background px-3 py-2 text-sm font-normal file:mr-3 file:rounded-md file:border-0 file:bg-muted file:px-3 file:py-1.5 file:font-medium" />
                                    <span className="text-xs text-muted-foreground">{str(draft["resume_name"]) if draft["resume_name"] else "No resume PDF attached"}</span>
                                    {bool(draft["resume_name"]) and <button type="button" onClick={clear_resume_handler(draft_id)} className="w-fit text-xs text-destructive underline">Remove attached resume</button>}
                                </label>
                                <label className="flex flex-col gap-1 text-sm font-medium">
                                    Cover letter PDF
                                    <input type="file" accept="application/pdf,.pdf" onChange={edit_cover_letter_handler(draft_id)} aria-label={"Replace cover letter PDF for " + str(draft["company"])} className="rounded-lg border bg-background px-3 py-2 text-sm font-normal file:mr-3 file:rounded-md file:border-0 file:bg-muted file:px-3 file:py-1.5 file:font-medium" />
                                    <span className="text-xs text-muted-foreground">{str(draft["cover_letter_name"]) if draft["cover_letter_name"] else "No cover letter PDF attached"}</span>
                                    {bool(draft["cover_letter_name"]) and <button type="button" onClick={clear_cover_letter_handler(draft_id)} className="w-fit text-xs text-destructive underline">Remove attached cover letter</button>}
                                </label>
                            </div>
                        </article>
                    }}
                </div>
                <div className="mt-5 border-t pt-4">
                    <h3 className="font-medium">Status dropdown options</h3>
                    <p className="mb-3 text-xs text-muted-foreground">Choose a color for each status or add and remove choices. Reassign applications before removing a status in use.</p>
                    <div className="grid gap-2 sm:grid-cols-2">
                        {for option in status_options {
                            <div key={option["name"]} className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2">
                                <span className="flex min-w-0 items-center gap-2 text-sm font-medium">
                                    <span className="size-3 shrink-0 rounded-full" style={{"backgroundColor": option["color"]}} />
                                    <span className="truncate">{option["name"]}</span>
                                </span>
                                <div className="flex items-center gap-2">
                                    <input
                                        type="color"
                                        value={option["color"]}
                                        aria-label={"Color for " + option["name"]}
                                        onChange={lambda (e: ChangeEvent) { update_status_color(option["name"], e.target.value); }}
                                        className="h-8 w-10 cursor-pointer rounded border bg-background p-1"
                                    />
                                    <button
                                        type="button"
                                        disabled={status_in_use(option["name"]) or len(status_options) <= 1}
                                        aria-label={"Remove status " + option["name"]}
                                        onClick={lambda { remove_status_option(option["name"]); }}
                                        className="rounded px-2 py-1 text-xs text-muted-foreground hover:bg-destructive/10 hover:text-destructive disabled:cursor-not-allowed disabled:opacity-40"
                                    >Remove</button>
                                </div>
                            </div>
                        }}
                    </div>
                    <div className="mt-3 flex flex-wrap items-center gap-2">
                        <input value={new_status_name} onChange={handle_new_status_name} placeholder="New status name" aria-label="New status name" maxLength={40} className="h-9 min-w-44 flex-1 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
                        <input type="color" value={new_status_color} onChange={handle_new_status_color} aria-label="New status color" className="h-9 w-12 cursor-pointer rounded border bg-background p-1" />
                        <Button variant="outline" onClick={add_status_option}>Add status</Button>
                    </div>
                </div>
                <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
                    <p role="alert" className="text-sm text-destructive">{edit_error or ("Reading " + reading_pdf if reading_pdf else "")}</p>
                    <div className="flex gap-2">
                        <Button variant="ghost" onClick={lambda { edit_drafts = []; edit_error = ""; }}>Cancel</Button>
                        <Button onClick={save_edit}>Save all changes</Button>
                    </div>
                </div>
            </section>}

            {current_view == "table" and <section className="overflow-hidden rounded-2xl border bg-card shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-2 border-b px-5 py-4">
                    <div>
                        <h2 className="font-semibold">All applications</h2>
                        <p className="text-sm text-muted-foreground">{str(total)} opportunities in your tracker</p>
                    </div>
                    <span className="rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary">Saved to your account</span>
                </div>
                <div className="overflow-x-auto">
                    <table className="w-full min-w-[640px] border-collapse text-left">
                        <thead>
                            <tr className="border-b bg-muted/30 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                                {edit_mode and <th className="px-3 py-3"><span className="sr-only">Select</span></th>}
                                <th className="px-4 py-3">Company name</th>
                                <th className="px-4 py-3">Job title</th>
                                <th className="px-4 py-3">Date applied</th>
                                <th className="px-4 py-3">Status</th>
                                <th className="px-4 py-3">Notes</th>
                                <th className="px-4 py-3">Pay available</th>
                                <th className="px-4 py-3">Resume PDF used</th>
                                <th className="px-4 py-3">Cover letter</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for app in applications {
                                <TrackerRow
                                    key={str(app["id"])}
                                    role={str(app["role"])}
                                    company={str(app["company"])}
                                    job_url={str(app.get("job_url") or "")}
                                    applied_date={str(app["date"])}
                                    description={str(app["description"])}
                                    pay={str(app["pay"])}
                                    resume={str(app["resume"])}
                                    cover_letter={str(app["cover_letter"])}
                                    status={str(app["status"])}
                                    status_options={status_options}
                                    status_color={status_color_for(str(app["status"]))}
                                    edit_mode={edit_mode}
                                    selected_for_edit={int(app["id"]) in selected_application_ids}
                                    onSelection={lambda (e: ChangeEvent) { handle_selection(int(app["id"]), e); }}
                                    onStatusChange={lambda (selected: str) { set_status(int(app["id"]), selected); }}
                                    onOpenNotes={open_application_notes}
                                />
                            }}
                            {total == 0 and <tr><td colSpan={9 if edit_mode else 8} className="px-4 py-12 text-center text-sm text-muted-foreground">{("Loading your applications..." if loading else "No applications yet. Add one to start building your tracker.")}</td></tr>}
                        </tbody>
                    </table>
                </div>
            </section>}

            {notes_open and <div className="fixed inset-0 z-50 flex justify-end bg-black/40">
                <aside
                    role="dialog"
                    aria-modal="true"
                    aria-label={"Notes for " + note_title}
                    tabIndex={-1}
                    autoFocus={True}
                    className="flex h-full w-full max-w-xl flex-col border-l border-border bg-background text-foreground shadow-2xl"
                >
                    <div className="flex items-start justify-between gap-4 border-b border-border px-6 py-5">
                        <div>
                            <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Application notes</p>
                            <h2 className="mt-1 text-lg font-semibold">{note_title}</h2>
                        </div>
                        <button
                            type="button"
                            onClick={close_application_notes}
                            aria-label="Close notes"
                            className="rounded-md px-3 py-1.5 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            Close
                        </button>
                    </div>
                    <div className="overflow-y-auto px-6 py-5">
                        <p className="whitespace-pre-wrap break-words text-sm leading-6">{note_description}</p>
                    </div>
                </aside>
            </div>}

            {current_view == "insights" and <div className="flex flex-col gap-5">
                <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                        <h2 className="font-semibold">Your statistics</h2>
                        <p className="text-sm text-muted-foreground">Choose which insights to show and how to visualize application status.</p>
                    </div>
                    <Button variant="outline" onClick={lambda { show_widget_manager = not show_widget_manager; }}>
                        {("Hide widgets" if show_widget_manager else "Manage widgets")}
                    </Button>
                </div>

                {show_widget_manager and <section className="rounded-2xl border bg-card p-5 shadow-sm">
                    <div className="mb-4">
                        <h3 className="font-semibold">Dashboard widgets</h3>
                        <p className="text-sm text-muted-foreground">Add or remove statistics from your dashboard.</p>
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        {for widget in widget_options {
                            widget_id = widget["id"];
                            enabled = has_widget(widget_id);
                            <div key={widget_id} className="flex items-center justify-between gap-3 rounded-xl border p-3">
                                <div>
                                    <p className="text-sm font-medium">{widget["label"]}</p>
                                    <p className="text-xs text-muted-foreground">{widget["description"]}</p>
                                </div>
                                <button
                                    type="button"
                                    aria-pressed={enabled}
                                    onClick={lambda { toggle_widget(widget_id); }}
                                    className={"rounded-lg px-3 py-1.5 text-xs font-semibold transition-colors " + ("bg-muted text-foreground hover:bg-destructive/10 hover:text-destructive" if enabled else "bg-primary text-primary-foreground hover:bg-primary/85")}
                                >
                                    {("Remove" if enabled else "Add")}
                                </button>
                            </div>
                        }}
                    </div>
                </section>}

                <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    {has_widget("total") and <div className="rounded-2xl border bg-card p-5 shadow-sm">
                        <p className="text-sm text-muted-foreground">Total applications</p>
                        <p className="mt-2 text-3xl font-semibold tabular-nums">{total}</p>
                    </div>}
                    {has_widget("progress") and <div className="rounded-2xl border bg-card p-5 shadow-sm">
                        <p className="text-sm text-muted-foreground">In progress</p>
                        <p className="mt-2 text-3xl font-semibold tabular-nums">{count_status("Applied") + count_status("Interview")}</p>
                    </div>}
                    {has_widget("offers") and <div className="rounded-2xl border bg-card p-5 shadow-sm">
                        <p className="text-sm text-muted-foreground">Offers</p>
                        <p className="mt-2 text-3xl font-semibold tabular-nums">{count_status("Offer")}</p>
                    </div>}
                    {has_widget("response") and <div className="rounded-2xl border bg-card p-5 shadow-sm">
                        <p className="text-sm text-muted-foreground">Response rate</p>
                        <p className="mt-2 text-3xl font-semibold tabular-nums">{response_rate}%</p>
                    </div>}
                </section>

                <section className="grid gap-5 lg:grid-cols-2">
                    {has_widget("status") and <div className="rounded-2xl border bg-card p-6 shadow-sm">
                        <div className="mb-6 flex flex-wrap items-start justify-between gap-3">
                            <div>
                                <h2 className="font-semibold">Application status</h2>
                                <p className="text-sm text-muted-foreground">A live view of where each opportunity stands.</p>
                            </div>
                            <select
                                value={status_visualization}
                                onChange={handle_visualization}
                                aria-label="Status visualization type"
                                className="h-9 rounded-lg border bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                <option value="pie">Pie chart</option>
                                <option value="bar">Bar chart</option>
                                <option value="table">Data table</option>
                            </select>
                        </div>
                        {status_visualization == "pie" and <div className="flex flex-wrap items-center justify-center gap-8">
                            <div className="relative size-44 shrink-0 rounded-full" style={{"background": pie_background}} role="img" aria-label={"Application status pie chart for " + str(total) + " applications"}>
                                <div className="absolute inset-5 flex flex-col items-center justify-center rounded-full bg-card">
                                    <span className="text-3xl font-semibold tabular-nums">{total}</span>
                                    <span className="text-xs text-muted-foreground">applications</span>
                                </div>
                            </div>
                            <div className="flex flex-col gap-3">
                                {for option in status_options {
                                    status = option["name"];
                                    <div key={status} className="flex min-w-32 items-center justify-between gap-5 text-sm">
                                        <span className="flex items-center gap-2"><span className="size-2.5 rounded-full" style={{"background": option["color"]}} />{status}</span>
                                        <span className="font-medium tabular-nums">{count_status(status)}</span>
                                    </div>
                                }}
                            </div>
                        </div>}
                        {status_visualization == "bar" and <div className="flex flex-col gap-4">
                            {for option in status_options {
                                status = option["name"];
                                status_count = count_status(status);
                                bar_width = (status_count / total) * 100 if total > 0 else 0;
                                <div key={status} className="flex items-center gap-3">
                                    <span className="w-24 shrink-0 text-sm text-muted-foreground">{status}</span>
                                    <div className="h-3 flex-1 overflow-hidden rounded-full bg-muted">
                                        <div className="h-full rounded-full transition-all" style={{"width": str(bar_width) + "%", "background": option["color"]}} />
                                    </div>
                                    <span className="w-8 text-right text-sm font-medium tabular-nums">{status_count}</span>
                                </div>
                            }}
                        </div>}
                        {status_visualization == "table" and <div className="overflow-x-auto">
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="border-b text-xs uppercase tracking-wide text-muted-foreground">
                                        <th className="py-2 font-medium">Status</th>
                                        <th className="py-2 text-right font-medium">Applications</th>
                                        <th className="py-2 text-right font-medium">Share</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {for option in status_options {
                                        status = option["name"];
                                        status_count = count_status(status);
                                        status_share = int((status_count / total) * 100) if total > 0 else 0;
                                        <tr key={status} className="border-b last:border-b-0">
                                            <td className="py-3"><span className="inline-flex items-center gap-2"><span className="size-2.5 rounded-full" style={{"background": option["color"]}} />{status}</span></td>
                                            <td className="py-3 text-right tabular-nums">{status_count}</td>
                                            <td className="py-3 text-right tabular-nums">{status_share}%</td>
                                        </tr>
                                    }}
                                </tbody>
                            </table>
                        </div>}

                    </div>}
                    {has_widget("flow") and <div className="rounded-2xl border bg-card p-6 shadow-sm">
                        <div className="mb-6">
                            <h2 className="font-semibold">Application flow</h2>
                            <p className="text-sm text-muted-foreground">Sankey view of submissions flowing into their current status.</p>
                        </div>
                        <div className="overflow-x-auto">
                            <svg viewBox="0 0 540 260" className="min-w-[480px] w-full" role="img" aria-label="Sankey diagram from submitted applications to their current status">
                                <text x="26" y="16" className="fill-muted-foreground" fontSize="11">SUBMITTED</text>
                                <text x="436" y="16" className="fill-muted-foreground" fontSize="11">CURRENT STATUS</text>
                                {for option in status_options {
                                    status = option["name"];
                                    status_count = count_status(status);
                                    flow_width = status_count * sankey_scale;
                                    destination_y = 30.0 + flow_offset;
                                    ribbon_start = 30.0 + flow_offset + (flow_width / 2);
                                    ribbon_end = destination_y + (flow_width / 2);
                                    color = option["color"];
                                    if status_count > 0 {
                                        <path
                                            key={status + "-flow"}
                                            d={"M 84 " + str(ribbon_start) + " C 185 " + str(ribbon_start) + ", 310 " + str(ribbon_end) + ", 420 " + str(ribbon_end)}
                                            fill="none"
                                            stroke={color}
                                            strokeWidth={max(flow_width, 2.0)}
                                            strokeOpacity="0.48"
                                        />
                                        <rect key={status + "-node"} x="420" y={destination_y} width="12" height={flow_width} rx="4" fill={color} />
                                        <text key={status + "-label"} x="442" y={ribbon_end + 4} className="fill-foreground" fontSize="12">{status + " · " + str(status_count)}</text>
                                    }
                                    flow_offset = flow_offset + flow_width;
                                }}
                                {total > 0 and <rect x="26" y="30" width="58" height="200" rx="8" fill="#46695d" />}
                                {total == 0 and <text x="28" y="112" className="fill-muted-foreground" fontSize="12">Add applications to see flows</text>}
                            </svg>
                        </div>
                    </div>}
                </section>
            </div>}
        </main>
        <SiteFooter />
    </div>;
}

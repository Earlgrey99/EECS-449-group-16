import from "@jac/runtime" { jacIsLoggedIn, Navigate }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .ui.button { Button }
import from ..services.tracker {
    list_tracker_applications,
    add_tracker_application,
    set_tracker_status,
    remove_tracker_application
}

glob TRACKER_STATUSES: list[str] = ["Applied", "Interview", "Offer", "Rejected", "Withdrawn"];

def:pub TrackerRow(
    role: str,
    company: str,
    applied_date: str,
    description: str,
    pay: str,
    resume: str,
    cover_letter: str,
    status: str,
    onStatusChange: Callable[[str], None],
    onRemove: Callable[[], None]
) -> JsxElement {
    def handle_status(e: ChangeEvent) {
        onStatusChange(e.target.value);
    }

    return <tr className="border-b last:border-b-0 hover:bg-muted/30">
        <td className="whitespace-nowrap px-4 py-3.5 font-medium text-foreground">{company}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm">{role}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{applied_date}</td>
        <td className="max-w-56 truncate px-4 py-3.5 text-sm text-muted-foreground" title={description}>{description}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm tabular-nums">{pay}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{resume}</td>
        <td className="whitespace-nowrap px-4 py-3.5 text-sm text-muted-foreground">{cover_letter}</td>
        <td className="px-4 py-3.5">
            <select
                value={status}
                onChange={handle_status}
                aria-label={"Status for " + company}
                className="rounded-full border border-border bg-background px-3 py-1.5 text-xs font-medium text-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
                {for option in TRACKER_STATUSES {
                    <option key={option} value={option}>{option}</option>
                }}
            </select>
        </td>
        <td className="px-4 py-3.5 text-right">
            <button
                onClick={onRemove}
                aria-label={"Remove " + role + " at " + company}
                className="rounded-md px-2 py-1 text-sm text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
            >
                Remove
            </button>
        </td>
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
    has show_form: bool = False;
    has new_role: str = "";
    has new_company: str = "";
    has new_date: str = "";
    has new_description: str = "";
    has new_pay: str = "";
    has new_status: str = "Applied";
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
            res: any = await list_tracker_applications(token=session_token());
            if res and res.get("ok") {
                loaded: any = res.get("applications");
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

    async def remove_application(app_id: int) {
        action_error = "";
        try {
            res: any = await remove_tracker_application(token=session_token(), app_id=app_id);
            if res and res.get("ok") {
                applications = [app for app in applications if int(app["id"]) != app_id];
            } else {
                action_error = str(res.get("error") if res else "Could not remove the application.");
            }
        } except Exception {
            action_error = "Could not remove the application.";
        }
    }

    async def add_application() {
        if not new_role.strip() or not new_company.strip() or not new_date {
            form_error = "Company, job title, and application date are required.";
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
                status=new_status
            );
            if not res or not res.get("ok") {
                form_error = str(res.get("error") if res else "Could not save the application.");
                return;
            }
            added: any = res.get("application");
            applications = [added] + applications;
        } except Exception {
            form_error = "Could not save the application.";
            return;
        }
        new_role = "";
        new_company = "";
        new_date = "";
        new_description = "";
        new_pay = "";
        new_status = "Applied";
        form_error = "";
        show_form = False;
    }

    def handle_role(e: ChangeEvent) { new_role = e.target.value; }
    def handle_company(e: ChangeEvent) { new_company = e.target.value; }
    def handle_date(e: ChangeEvent) { new_date = e.target.value; }
    def handle_description(e: ChangeEvent) { new_description = e.target.value; }
    def handle_pay(e: ChangeEvent) { new_pay = e.target.value; }
    def handle_new_status(e: ChangeEvent) { new_status = e.target.value; }

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
    for status in TRACKER_STATUSES {
        status_count = count_status(status);
        if status_count > 0 {
            segment_end = pie_offset + ((status_count / total) * 100);
            color = "#7c9a92" if status == "Applied" else "#6c8ba1" if status == "Interview" else "#4f806b" if status == "Offer" else "#c77d72" if status == "Rejected" else "#a5a29b";
            pie_segments.append(color + " " + str(pie_offset) + "% " + str(segment_end) + "%");
            pie_offset = segment_end;
        }
    }
    pie_background = "conic-gradient(" + ", ".join(pie_segments) + ")" if total > 0 else "#e7e8e5";

    sankey_scale = 200.0 / total if total > 0 else 0.0;
    flow_offset = 0.0;

    return <div className="flex min-h-svh flex-col bg-[#f7f8f6]">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-7 px-6 py-10">
            <header className="flex flex-col gap-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                    <div className="flex flex-col gap-2">
                        <p className="text-sm font-semibold tracking-wide text-primary">YOUR WORKSPACE / CAREER</p>
                        <h1 className="text-3xl font-semibold tracking-tight">Application tracker</h1>
                        <p className="max-w-2xl text-sm text-muted-foreground">Keep every opportunity in one place. Update a status to see your application insights change instantly.</p>
                    </div>
                    <div className="flex items-center gap-2">
                        <a
                            href={"data:text/csv;charset=utf-8," + encodeURIComponent(csv_data)}
                            download="application-tracker.csv"
                            className="inline-flex h-9 items-center rounded-lg border border-border bg-background px-3 text-sm font-medium text-foreground shadow-sm transition-colors hover:bg-muted"
                        >
                            Export CSV
                        </a>
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
                        {for option in TRACKER_STATUSES {
                            <option key={option} value={option}>{option}</option>
                        }}
                    </select>
                </div>
                <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
                    <p className="text-sm text-destructive">{form_error}</p>
                    <div className="flex gap-2">
                        <Button variant="ghost" onClick={lambda { show_form = False; form_error = ""; }}>Cancel</Button>
                        <Button onClick={add_application}>Save application</Button>
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
                                <th className="px-4 py-3">Company name</th>
                                <th className="px-4 py-3">Job title</th>
                                <th className="px-4 py-3">Date applied</th>
                                <th className="px-4 py-3">Description</th>
                                <th className="px-4 py-3">Pay available</th>
                                <th className="px-4 py-3">Resume PDF used</th>
                                <th className="px-4 py-3">Cover letter</th>
                                <th className="px-4 py-3">Status</th>
                                <th className="px-4 py-3 text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for app in applications {
                                <TrackerRow
                                    key={str(app["id"])}
                                    role={str(app["role"])}
                                    company={str(app["company"])}
                                    applied_date={str(app["date"])}
                                    description={str(app["description"])}
                                    pay={str(app["pay"])}
                                    resume={str(app["resume"])}
                                    cover_letter={str(app["cover_letter"])}
                                    status={str(app["status"])}
                                    onStatusChange={lambda (selected: str) { set_status(int(app["id"]), selected); }}
                                    onRemove={lambda { remove_application(int(app["id"])); }}
                                />
                            }}
                            {total == 0 and <tr><td colSpan={9} className="px-4 py-12 text-center text-sm text-muted-foreground">{("Loading your applications..." if loading else "No applications yet. Add one to start building your tracker.")}</td></tr>}
                        </tbody>
                    </table>
                </div>
            </section>}

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
                                {for status in TRACKER_STATUSES {
                                    color = "#7c9a92" if status == "Applied" else "#6c8ba1" if status == "Interview" else "#4f806b" if status == "Offer" else "#c77d72" if status == "Rejected" else "#a5a29b";
                                    <div key={status} className="flex min-w-32 items-center justify-between gap-5 text-sm">
                                        <span className="flex items-center gap-2"><span className="size-2.5 rounded-full" style={{"background": color}} />{status}</span>
                                        <span className="font-medium tabular-nums">{count_status(status)}</span>
                                    </div>
                                }}
                            </div>
                        </div>}
                        {status_visualization == "bar" and <div className="flex flex-col gap-4">
                            {for status in TRACKER_STATUSES {
                                status_count = count_status(status);
                                bar_width = (status_count / total) * 100 if total > 0 else 0;
                                color = "#7c9a92" if status == "Applied" else "#6c8ba1" if status == "Interview" else "#4f806b" if status == "Offer" else "#c77d72" if status == "Rejected" else "#a5a29b";
                                <div key={status} className="flex items-center gap-3">
                                    <span className="w-24 shrink-0 text-sm text-muted-foreground">{status}</span>
                                    <div className="h-3 flex-1 overflow-hidden rounded-full bg-muted">
                                        <div className="h-full rounded-full transition-all" style={{"width": str(bar_width) + "%", "background": color}} />
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
                                    {for status in TRACKER_STATUSES {
                                        status_count = count_status(status);
                                        status_share = int((status_count / total) * 100) if total > 0 else 0;
                                        <tr key={status} className="border-b last:border-b-0">
                                            <td className="py-3">{status}</td>
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
                                <text x="26" y="16" className="fill-muted-foreground" font-size="11">SUBMITTED</text>
                                <text x="436" y="16" className="fill-muted-foreground" font-size="11">CURRENT STATUS</text>
                                {for status in TRACKER_STATUSES {
                                    status_count = count_status(status);
                                    flow_width = status_count * sankey_scale;
                                    destination_y = 30.0 + flow_offset;
                                    ribbon_start = 30.0 + flow_offset + (flow_width / 2);
                                    ribbon_end = destination_y + (flow_width / 2);
                                    color = "#7c9a92" if status == "Applied" else "#6c8ba1" if status == "Interview" else "#4f806b" if status == "Offer" else "#c77d72" if status == "Rejected" else "#a5a29b";
                                    if status_count > 0 {
                                        <path
                                            key={status + "-flow"}
                                            d={"M 84 " + str(ribbon_start) + " C 185 " + str(ribbon_start) + ", 310 " + str(ribbon_end) + ", 420 " + str(ribbon_end)}
                                            fill="none"
                                            stroke={color}
                                            stroke-width={max(flow_width, 2.0)}
                                            stroke-opacity="0.48"
                                        />
                                        <rect key={status + "-node"} x="420" y={destination_y} width="12" height={flow_width} rx="4" fill={color} />
                                        <text key={status + "-label"} x="442" y={ribbon_end + 4} className="fill-foreground" font-size="12">{status + " · " + str(status_count)}</text>
                                    }
                                    flow_offset = flow_offset + flow_width;
                                }}
                                {total > 0 and <rect x="26" y="30" width="58" height="200" rx="8" fill="#46695d" />}
                                {total == 0 and <text x="28" y="112" className="fill-muted-foreground" font-size="12">Add applications to see flows</text>}
                            </svg>
                        </div>
                    </div>}
                </section>
            </div>}
        </main>
        <SiteFooter />
    </div>;
}

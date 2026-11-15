import from "@jac/runtime" { Link }
import from "@heyputer/puter.js" { puter }
import from "react-markdown" { default as ReactMarkdown }
import from ..services.career_navigator {
    get_career_chat_details,
    list_career_chats,
    remove_career_chat,
    send_career_message
}

glob MAX_CONTEXT_MESSAGES: int = 16;
glob CAREER_ASSISTANT_MODEL: str = "openai/gpt-5.3-codex";

def:pub CareerAssistant(compact: bool = False) -> JsxElement {
    has panel_open: bool = not compact;
    has threads: list[dict[str, any]] = [];
    has messages: list[dict[str, any]] = [];
    has selected_chat_id: int | None = None;
    has major: str = "";
    has career_goal: str = "";
    has message_input: str = "";
    has loading: bool = False;
    has sending: bool = False;
    has error_message: str = "";
    has did_load_threads: bool = False;
    has history_open: bool = False;

    def session_token -> str {
        try {
            return str(localStorage.getItem("jac_token") or "");
        } except Exception {
            return "";
        }
    }

    async def load_threads {
        error_message = "";
        try {
            res: any = await list_career_chats(token=session_token());
            if res and res.get("ok") {
                threads = res.get("chats") or [];
                did_load_threads = True;
            } else {
                error_message = str(res.get("error") if res else "Could not load saved conversations.");
            }
        } except Exception {
            error_message = "Could not load saved conversations.";
        }
    }

    async can with entry {
        if not compact {
            await load_threads();
        }
    }

    async def open_panel {
        panel_open = True;
        if not did_load_threads {
            await load_threads();
        }
    }

    def start_new_chat {
        selected_chat_id = None;
        messages = [];
        major = "";
        career_goal = "";
        message_input = "";
        error_message = "";
        history_open = False;
    }

    async def select_chat(chat_id: int) {
        loading = True;
        error_message = "";
        try {
            res: any = await get_career_chat_details(token=session_token(), chat_id=chat_id);
            if res and res.get("ok") {
                selected_chat_id = chat_id;
                messages = res.get("messages") or [];
                selected_chat: any = res.get("chat") or {};
                major = str(selected_chat.get("major") or "");
                career_goal = str(selected_chat.get("career_goal") or "");
                message_input = "";
                history_open = False;
            } else {
                error_message = str(res.get("error") if res else "Could not open this conversation.");
            }
        } except Exception {
            error_message = "Could not open this conversation.";
        }
        loading = False;
    }

    async def delete_chat(chat_id: int) {
        error_message = "";
        try {
            res: any = await remove_career_chat(token=session_token(), chat_id=chat_id);
            if res and res.get("ok") {
                threads = [chat for chat in threads if int(chat["id"]) != chat_id];
                if selected_chat_id == chat_id {
                    start_new_chat();
                }
            } else {
                error_message = str(res.get("error") if res else "Could not delete this conversation.");
            }
        } except Exception {
            error_message = "Could not delete this conversation.";
        }
    }

    async def send_message(e: FormEvent) {
        e.preventDefault();
        if sending or not message_input.strip() {
            return;
        }
        if selected_chat_id is None and (not major.strip() or not career_goal.strip()) {
            error_message = "Add your major and career goal to start a new conversation.";
            return;
        }
        sending = True;
        error_message = "";
        sent_text = message_input.strip();
        try {
            ai_messages: list[dict[str, str]] = [{
                "role": "system",
                "content": (
                    "You are Launchpad's Career Navigator, a supportive, practical career coach for college students. "
                    + "Help students explore career paths related to their major, identify majors and coursework that fit a career goal, "
                    + "find realistic entry-level job titles, plan internships and projects, build job-search strategies, and improve "
                    + "resumes and interview preparation. Personalize advice to the student's stated major and goal, explain tradeoffs "
                    + "without pushing one path, and end with clear next steps. Ask focused follow-up questions when important details "
                    + "are missing. You may also answer questions about using Launchpad; point users to Jobs for listings, Tracker for "
                    + "applications, Profile for preferences, and Applicant tools for resume help. Do not invent current job listings, "
                    + "guarantee employment or salaries, or invent current market facts. Be encouraging, concise, inclusive, and honest "
                    + "about uncertainty. Format replies for a chat: use short paragraphs and bullet lists for multiple items, "
                    + "bold key phrases (shown in emerald), italicize sparingly (shown in teal), and use short headings "
                    + "(shown in green) only when they help. Use standard Markdown formatting without printing raw formatting "
                    + "markers or HTML. Student major: " + major + ". Career goal: " + career_goal + "."
                )
            }];
            for item in messages[-MAX_CONTEXT_MESSAGES:] {
                role = str(item.get("role") or "");
                content = str(item.get("content") or "");
                if role in ["user", "assistant"] and content {
                    ai_messages.append({"role": role, "content": content});
                }
            }
            ai_messages.append({"role": "user", "content": sent_text});
            ai_response: any = await puter.ai.chat(ai_messages, False, {
                "model": CAREER_ASSISTANT_MODEL,
                "max_tokens": 1200,
                "temperature": 0.4,
                "normalize": True
            });
            ai_message: any = ai_response.message;
            assistant_reply = str(ai_message.content or "").strip();
            if not assistant_reply {
                error_message = "Puter returned an empty response. Please try again.";
            } else {
                res: any = await send_career_message(
                    token=session_token(),
                    message=sent_text,
                    reply=assistant_reply,
                    chat_id=selected_chat_id,
                    major=major,
                    career_goal=career_goal
                );
                if res and res.get("ok") {
                    selected_chat_id = int(res.get("chat_id"));
                    major = str(res.get("major") or major);
                    career_goal = str(res.get("career_goal") or career_goal);
                    messages = messages + [
                        {"role": "user", "content": sent_text},
                        {
                            "role": "assistant",
                            "content": assistant_reply,
                            "jobs": res.get("job_results") or []
                        }
                    ];
                    message_input = "";
                    error_message = str(res.get("warning") or "");
                    await load_threads();
                } else {
                    error_message = str(res.get("error") if res else "Could not save this response.");
                }
            }
        } except Exception as error {
            error_message = "Puter AI could not respond. Sign in to Puter if prompted, then try again. "
                + str(error);
        }
        sending = False;
    }

    def handle_major(e: ChangeEvent) { major = e.target.value; }
    def handle_goal(e: ChangeEvent) { career_goal = e.target.value; }
    def handle_message(e: ChangeEvent) { message_input = e.target.value; }

    return <>
        {compact and not panel_open and <button
            type="button"
            onClick={open_panel}
            className="fixed bottom-5 right-5 z-50 rounded-full bg-primary px-5 py-3 text-sm font-semibold text-primary-foreground shadow-xl transition hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            aria-label="Open Career Navigator assistant"
        >Career assistant</button>}
        {(not compact or panel_open) and <section className={("fixed bottom-4 right-4 z-50 flex h-[min(760px,calc(100vh-2rem))] w-[min(900px,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl border bg-background shadow-2xl " if compact else "flex h-[680px] min-h-[520px] w-full flex-col overflow-hidden rounded-2xl border bg-background shadow-sm")}>
            <header className="flex items-center justify-between gap-3 border-b bg-card px-4 py-3">
                <div>
                    <h2 className="font-semibold">Career Navigator</h2>
                    <p className="text-xs text-muted-foreground">Career guidance and Launchpad help</p>
                </div>
                <div className="flex items-center gap-2">
                    {compact and <Link to="/explore" className="rounded-lg border px-3 py-1.5 text-xs font-medium hover:bg-muted">Full page</Link>}
                    {compact and <button type="button" onClick={lambda { history_open = not history_open; }} className="rounded-lg border px-3 py-1.5 text-xs font-medium hover:bg-muted" aria-expanded={history_open}>Chats</button>}
                    <button type="button" onClick={start_new_chat} className="rounded-lg border px-3 py-1.5 text-xs font-medium hover:bg-muted">New chat</button>
                    {compact and <button type="button" onClick={lambda { panel_open = False; }} className="rounded-lg px-3 py-1.5 text-xs font-medium hover:bg-muted" aria-label="Close assistant">Close</button>}
                </div>
            </header>
            <div className="flex min-h-0 flex-1">
                <aside className={("flex w-44 shrink-0 flex-col gap-2 overflow-y-auto border-r bg-muted/20 p-2 sm:w-56 " if not compact else ("flex w-28 shrink-0 flex-col gap-2 overflow-y-auto border-r bg-muted/20 p-2 " if history_open else "hidden"))}>
                    <p className="px-2 pt-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Saved chats</p>
                    {for chat in threads {
                        <div key={str(chat["id"])} className={"group flex items-start gap-1 rounded-lg border p-2 " + ("border-primary/30 bg-primary/5" if selected_chat_id == int(chat["id"]) else "border-transparent hover:bg-muted")}>
                            <button type="button" onClick={lambda { select_chat(int(chat["id"])); }} className="min-w-0 flex-1 text-left">
                                <span className="block truncate text-xs font-medium">{str(chat.get("title") or "Career chat")}</span>
                                <span className="mt-1 block truncate text-[10px] text-muted-foreground">{str(chat.get("major") or "") + " · " + str(chat.get("career_goal") or "")}</span>
                            </button>
                            <button type="button" onClick={lambda { delete_chat(int(chat["id"])); }} className="shrink-0 rounded px-1 text-xs text-muted-foreground hover:bg-destructive/10 hover:text-destructive" aria-label={"Delete " + str(chat.get("title") or "conversation")}>×</button>
                        </div>
                    }}
                    {len(threads) == 0 and <p className="px-2 text-xs text-muted-foreground">Your saved conversations will appear here.</p>}
                </aside>
                <div className="flex min-w-0 flex-1 flex-col">
                    {selected_chat_id is None and <div className="grid gap-3 border-b bg-primary/5 p-3 sm:grid-cols-2 sm:p-4">
                        <label className="flex flex-col gap-1 text-xs font-medium">
                            Your major
                            <input value={major} onChange={handle_major} maxLength={160} placeholder="e.g. Biology" className="rounded-lg border bg-background px-3 py-2 text-sm font-normal" />
                        </label>
                        <label className="flex flex-col gap-1 text-xs font-medium">
                            Career goal
                            <input value={career_goal} onChange={handle_goal} maxLength={200} placeholder="e.g. Become a physician assistant" className="rounded-lg border bg-background px-3 py-2 text-sm font-normal" />
                        </label>
                    </div>}
                    {selected_chat_id is not None and <div className="border-b px-4 py-2 text-xs text-muted-foreground">{"Guidance for " + major + " → " + career_goal}</div>}
                    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-3 sm:p-4">
                        {loading and <p role="status" className="text-sm text-muted-foreground">Loading conversation…</p>}
                        {len(messages) == 0 and not loading and <div className="my-auto flex flex-col items-center gap-2 px-4 py-8 text-center">
                            <p className="text-base font-semibold">What would you like to explore?</p>
                            <p className="max-w-sm text-sm text-muted-foreground">Ask which roles fit your major, what to study for a career goal, how to find internships, or how to use Launchpad.</p>
                        </div>}
                        {for (index, item) in enumerate(messages) {
                            item_jobs: list[dict[str, any]] = item.get("jobs") or [];
                            is_user_message: bool = item.get("role") == "user";
                            <div key={str(index)} className={"max-w-[90%] rounded-2xl px-3 py-2.5 text-sm " + ("self-end rounded-tr-md bg-primary text-primary-foreground" if is_user_message else "self-start rounded-tl-md border border-emerald-200 bg-emerald-50 text-emerald-950 shadow-sm")}>
                                {is_user_message and <p className="whitespace-pre-wrap">{str(item.get("content") or "")}</p>}
                                {not is_user_message and <div className="break-words [&_a]:font-medium [&_a]:text-emerald-700 [&_a]:underline [&_blockquote]:border-l-2 [&_blockquote]:border-emerald-300 [&_blockquote]:pl-3 [&_code]:rounded [&_code]:bg-emerald-100 [&_code]:px-1 [&_em]:text-teal-800 [&_h1]:mb-2 [&_h1]:mt-3 [&_h1]:text-lg [&_h1]:font-semibold [&_h1]:text-emerald-900 [&_h2]:mb-2 [&_h2]:mt-3 [&_h2]:text-base [&_h2]:font-semibold [&_h2]:text-emerald-800 [&_h3]:mb-1 [&_h3]:mt-2 [&_h3]:font-semibold [&_h3]:text-teal-800 [&_li]:pl-1 [&_ol]:my-2 [&_ol]:list-decimal [&_ol]:space-y-1 [&_ol]:pl-5 [&_p]:my-1 [&_p:first-child]:mt-0 [&_p:last-child]:mb-0 [&_strong]:font-semibold [&_strong]:text-emerald-900 [&_ul]:my-2 [&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-5">
                                    <ReactMarkdown>{str(item.get("content") or "")}</ReactMarkdown>
                                </div>}
                                {item_jobs and <div className="mt-3 grid gap-2">
                                    {for job in item_jobs {
                                        job_link: str = str(job.get("link") or "");
                                        <article key={str(job.get("id") or job.get("title") or "") + str(job.get("company") or "")} className="rounded-xl border bg-background p-3 text-foreground">
                                            <h3 className="font-semibold">{str(job.get("title") or "Untitled role")}</h3>
                                            <p className="mt-1 text-xs text-muted-foreground">
                                                {str(job.get("company") or "Company not listed")}
                                                {" · " + str(job.get("location") or "Location not listed")}
                                            </p>
                                            {(job.get("salary") or job.get("type")) and <p className="mt-1 text-xs text-muted-foreground">
                                                {str(job.get("salary") or "")}
                                                {job.get("salary") and job.get("type") and " · "}
                                                {str(job.get("type") or "")}
                                            </p>}
                                            {(job_link.startswith("https://") or job_link.startswith("http://")) and <a
                                                href={job_link}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="mt-2 inline-block text-xs font-semibold text-primary underline"
                                            >View listing</a>}
                                        </article>
                                    }}
                                </div>}
                            </div>
                        }}
                        {sending and <p role="status" className="self-start rounded-2xl border bg-card px-3 py-2 text-sm text-muted-foreground">Thinking…</p>}
                    </div>
                    <div className="border-t bg-card p-3 sm:p-4">
                        {bool(error_message) and <p role="alert" className="mb-2 text-sm text-destructive">{error_message}</p>}
                        <form onSubmit={send_message} className="flex items-end gap-2">
                            <textarea
                                value={message_input}
                                onChange={handle_message}
                                placeholder="Ask a career or Launchpad question…"
                                aria-label="Message Career Navigator"
                                rows={2}
                                maxLength={4000}
                                className="min-h-12 flex-1 resize-y rounded-xl border bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            />
                            <button type="submit" disabled={sending or not message_input.strip()} className="rounded-xl bg-primary px-4 py-3 text-sm font-semibold text-primary-foreground disabled:cursor-not-allowed disabled:opacity-50">Send</button>
                        </form>
                        <p className="mt-2 text-[10px] text-muted-foreground">Chats are saved to your account. AI runs through Puter.js; sign in to Puter if prompted. Usage follows Puter’s user-pays model. Verify important education and career decisions.</p>
                    </div>
                </div>
            </div>
        </section>}
    </>;
}

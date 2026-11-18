import from "@jac/runtime" { Link, useLocation, useNavigate, jacIsLoggedIn, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Logout01Icon, UserAccountIcon, ArrowDown01Icon, Sun03Icon, Moon02Icon }
import from .ui.button { Button }
import from .BrandMark { BrandMark }
import from .CareerAssistant { CareerAssistant }

def:pub TopNav -> JsxElement {
    loc = useLocation();
    nav = useNavigate();
    path = loc.pathname;
    has logged_in: bool = False;
    has dropdown_open: bool = False;
    has did_init_nav: bool = False;
    has dark_mode: bool = False;

    async can with entry {
        if did_init_nav {
            return;
        }
        did_init_nav = True;
        logged_in = jacIsLoggedIn();
        dark_mode = localStorage.getItem("launchpad-theme") == "dark";
        document.documentElement.classList.toggle("dark", dark_mode);
    }

    def toggle_theme {
        next_dark_mode = not dark_mode;
        dark_mode = next_dark_mode;
        document.documentElement.classList.toggle("dark", next_dark_mode);
        localStorage.setItem("launchpad-theme", "dark" if next_dark_mode else "light");
    }

    def handle_signout {
        dropdown_open = False;
        try {
            localStorage.setItem("dev_logged_out", "true");
            localStorage.removeItem("user_email");
            localStorage.removeItem("user_resume_title");
        } except Exception {}
        jacLogout();
        logged_in = False;
        nav("/login");
    }

    def link_class(to: str) -> str {
        base = "text-sm font-medium transition-colors px-3 py-1.5 rounded-md";
        return base + (" bg-primary/10 text-primary" if path == to or (to != "/" and path.startswith(to)) else " text-muted-foreground hover:text-foreground");
    }

    def handle_navigate_profile {
        dropdown_open = False;
        nav("/me");
    }

    return <>
    <nav className="sticky top-0 z-30 border-b bg-background">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-6 pl-6 pr-6">
            <Link to="/"><BrandMark name="Launchpad" /></Link>
            <div className="hidden flex-1 items-center justify-end gap-2 md:flex">
                <Link to="/"><span className={link_class("/")}>Home</span></Link>
                <Link to="/jobs"><span className={link_class("/jobs")}>Jobs</span></Link>
                <Link to="/tracker"><span className={link_class("/tracker")}>Tracker</span></Link>
                <Link to="/tools"><span className={link_class("/tools")}>Applicant tools</span></Link>
                {logged_in and <div className="relative flex items-center gap-2 pl-3">
                    <button
                        onClick={lambda { dropdown_open = not dropdown_open; }}
                        className={"flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition-colors " + ("bg-primary text-primary-foreground shadow-sm" if (dropdown_open or path == "/me") else "bg-primary/10 text-primary hover:bg-primary/20")}
                        aria-label="Account menu"
                        aria-expanded={dropdown_open}
                    >
                        <HugeiconsIcon icon={UserAccountIcon} strokeWidth={2} className="size-3.5" />
                        <span>Account</span>
                        <HugeiconsIcon icon={ArrowDown01Icon} strokeWidth={2} className={"size-3 transition-transform " + ("rotate-180" if dropdown_open else "")} />
                    </button>
                    {dropdown_open and <div className="absolute right-0 top-full mt-2 w-48 rounded-xl border border-border bg-card p-1.5 shadow-lg animate-in fade-in zoom-in-95 duration-150 z-50">
                        <button
                            onClick={handle_navigate_profile}
                            className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-foreground transition-colors hover:bg-muted text-left"
                        >
                            <HugeiconsIcon icon={UserAccountIcon} strokeWidth={2} className="size-4 text-primary" />
                            <span>Profile</span>
                        </button>
                        <div className="my-1 h-px bg-border/60" />
                        <button
                            onClick={handle_signout}
                            className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-destructive transition-colors hover:bg-destructive/10 text-left"
                        >
                            <HugeiconsIcon icon={Logout01Icon} strokeWidth={2} className="size-4" />
                            <span>Sign Out</span>
                        </button>
                    </div>}
                </div>}
                {(not logged_in) and <div className="flex items-center gap-2 pl-3">
                    <Link to="/login">
                        <Button variant="outline" size="sm" className="h-8">Sign In</Button>
                    </Link>
                </div>}
            </div>
            <button className="flex size-9 items-center justify-center rounded-md text-foreground md:hidden" aria-label="Account" onClick={lambda { if logged_in { nav("/me"); } else { nav("/login"); } }}>
                <HugeiconsIcon icon={UserAccountIcon} strokeWidth={2} className="size-5" />
            </button>
            <button
                type="button"
                onClick={toggle_theme}
                aria-label={"Switch to " + ("light" if dark_mode else "dark") + " mode"}
                title={"Switch to " + ("light" if dark_mode else "dark") + " mode"}
                aria-pressed={dark_mode}
                className="flex size-9 items-center justify-center rounded-md text-foreground transition-colors hover:bg-muted"
            >
                <HugeiconsIcon icon={Sun03Icon if dark_mode else Moon02Icon} strokeWidth={2} className="size-5" />
            </button>
        </div>
    </nav>
    {logged_in and path != "/explore" and <CareerAssistant compact={True} />}
    </>;
}

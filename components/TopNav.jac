import from "@jac/runtime" { Link, useLocation, useNavigate, jacIsLoggedIn, jacLogout, jacSetToken }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Menu01Icon, Logout01Icon, UserAccountIcon, ArrowDown01Icon }
import from .ui.button { Button }
import from .BrandMark { BrandMark }
import from ..services.auth_sync { get_test_user_session }

def:pub TopNav -> JsxElement {
    loc = useLocation();
    nav = useNavigate();
    path = loc.pathname;
    has logged_in: bool = False;
    has dropdown_open: bool = False;

    async can with entry {
        is_auth = jacIsLoggedIn();
        logged_in = is_auth;
        if not is_auth {
            try {
                if localStorage.getItem("dev_logged_out") != "true" {
                    session = await get_test_user_session();
                    if session and session.get("ok") and session.get("token") {
                        jacSetToken(session["token"]);
                        logged_in = True;
                    }
                }
            } except Exception {
                # Normal unauthenticated state
            }
        }
    }

    def handle_signout {
        dropdown_open = False;
        try {
            localStorage.setItem("dev_logged_out", "true");
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

    return <nav className="sticky top-0 z-30 border-b bg-background">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-6 pl-6 pr-6">
            <Link to="/"><BrandMark name="Jaccit" /></Link>
            <div className="hidden flex-1 items-center justify-end gap-2 md:flex">
                <Link to="/"><span className={link_class("/")}>Home</span></Link>
                <Link to="/jobs"><span className={link_class("/jobs")}>Jobs</span></Link>
                <Link to="/jobs"><span className={link_class("/explore")}>Explore</span></Link>
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
            <button className="flex size-9 items-center justify-center rounded-md text-foreground md:hidden" aria-label="Menu" onClick={lambda { if logged_in { nav("/me"); } else { nav("/login"); } }}>
                <HugeiconsIcon icon={Menu01Icon} strokeWidth={2} className="size-5" />
            </button>
            <button className="hidden md:flex size-9 items-center justify-center rounded-md text-foreground" aria-label="Menu">
                <HugeiconsIcon icon={Menu01Icon} strokeWidth={2} className="size-5" />
            </button>
        </div>
    </nav>;
}

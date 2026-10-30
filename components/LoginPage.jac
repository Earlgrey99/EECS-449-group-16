import from "@jac/runtime" {
    Link,
    useNavigate,
    useLocation,
    jacLogin,
    jacSignup,
    jacSsoLogin,
    jacSetToken,
    jacIsLoggedIn
}
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Tick02Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.spinner { Spinner }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.auth_sync { sync_user_session }

def GoogleIcon -> JsxElement {
    return <svg className="mr-2 size-4" viewBox="0 0 24 24" aria-hidden="true">
        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" />
        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" />
    </svg>;
}

def:pub LoginPage -> JsxElement {
    nav = useNavigate();
    loc = useLocation();
    has email: str = "";
    has password: str = "";
    has mode: str = "signin";
    has message: str = "";
    has busy: bool = False;
    has busy_google: bool = False;
    has keep_signed_in: bool = False;

    async can with entry {
        search = loc.search or "";
        if not search {
            if jacIsLoggedIn() {
                nav("/jobs");
            }
            return;
        }

        query_str = search[1:] if search.startswith("?") else search;
        token_val: str = "";
        error_val: str = "";
        msg_val: str = "";

        for part in query_str.split("&") {
            if "=" in part {
                kv = part.split("=", 1);
                k = kv[0];
                v = kv[1];
                if k == "token" {
                    token_val = v;
                } elif k == "error" {
                    error_val = v;
                } elif k == "message" {
                    msg_val = v;
                }
            }
        }

        if error_val {
            clean_msg = msg_val.replace("+", " ").replace("%20", " ") if msg_val else "Google authentication was cancelled or failed.";
            message = f"Sign-in failed: {clean_msg}";
            busy_google = False;
            return;
        }

        if token_val {
            busy_google = True;
            jacSetToken(token_val);
            try {
                await sync_user_session(token=token_val, auth_provider="google");
            } except Exception {
                # Session is established
            }
            busy_google = False;
            nav("/jobs");
        }
    }

    def handle_email(e: ChangeEvent) { email = e.target.value; }
    def handle_password(e: ChangeEvent) { password = e.target.value; }

    async def handle_google_signin {
        message = "";
        busy_google = True;
        try {
            await jacSsoLogin("google");
        } except Exception {
            message = "Unable to start Google sign-in. Please try again.";
            busy_google = False;
        }
    }

    async def handle_submit(e: FormEvent) {
        e.preventDefault();
        message = "";
        if not email.strip() or not password.strip() {
            message = "Enter your email and password.";
            return;
        }
        busy = True;
        ok: bool = False;
        signup_result: any = None;
        try {
            if mode == "signin" {
                ok = await jacLogin(email.strip(), password);
                if not ok {
                    message = "Invalid email or password.";
                    busy = False;
                    return;
                }
            } else {
                signup_result = await jacSignup(email.strip(), password);
                if not signup_result.success {
                    message = signup_result.error or "Could not create the account (email may already be in use).";
                    busy = False;
                    return;
                }
                ok = await jacLogin(email.strip(), password);
                if not ok {
                    message = "Account created, but sign-in failed. Try signing in.";
                    busy = False;
                    return;
                }
            }
            try {
                await sync_user_session(email=email.strip(), name=email.strip().split("@")[0], auth_provider="local");
            } except Exception {}
            nav("/jobs");
        } except Exception {
            message = "Something went wrong. Please try again.";
            busy = False;
        }
    }

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="flex flex-1 items-center justify-center px-6 pt-10 pb-16">
            <form onSubmit={handle_submit} className="flex w-full max-w-md flex-col gap-4 rounded-2xl bg-primary p-8 text-primary-foreground shadow-lg animate-in fade-in slide-in-from-bottom-2 duration-500">
                <h1 className="text-3xl font-semibold tracking-tight">{"Sign in" if mode == "signin" else "Sign up"}</h1>
                <p className="text-sm text-primary-foreground/75">
                    {"New? "}
                    <button type="button" onClick={lambda { mode = "signup" if mode == "signin" else "signin"; message = ""; }} className="font-medium text-primary-foreground underline underline-offset-4">
                        {"Sign up here." if mode == "signin" else "Sign in here."}
                    </button>
                </p>
                <Button
                    type="button"
                    variant="outline"
                    disabled={busy or busy_google}
                    className="h-11 bg-background text-foreground hover:bg-background/90"
                    onClick={handle_google_signin}
                >
                    {busy_google and <Spinner className="mr-2 size-4" />}
                    {(not busy_google) and <GoogleIcon />}
                    {("Connecting to Google..." if busy_google else "Continue with Google")}
                </Button>
                <div className="h-0.5 rounded bg-primary-foreground/30" />
                <Input placeholder="Enter Username" type="email" value={email} onChange={handle_email} className="h-11 border-transparent bg-background text-foreground placeholder:text-muted-foreground" />
                <Input placeholder="Enter Password" type="password" value={password} onChange={handle_password} className="h-11 border-transparent bg-background text-foreground placeholder:text-muted-foreground" />
                <button type="button" onClick={lambda { keep_signed_in = not keep_signed_in; }} className="flex items-center gap-2 self-start text-sm text-primary-foreground/85">
                    <span className={"flex size-4 items-center justify-center rounded border border-primary-foreground/40 " + ("bg-primary-foreground/90 text-primary" if keep_signed_in else "")}>
                        {keep_signed_in and <HugeiconsIcon icon={Tick02Icon} strokeWidth={2.5} className="size-3" />}
                    </span>
                    Keep me signed in
                </button>
                {message and <p className="text-sm font-medium text-amber-200">{message}</p>}
                <Button type="submit" disabled={busy or busy_google} className="h-12 w-3/4 self-center rounded-full bg-emerald-500 text-white shadow-md hover:bg-emerald-500/90">
                    {"Signing in..." if busy else ("Sign in" if mode == "signin" else "Create account")}
                </Button>
                <Link to="/" className="self-center text-xs text-primary-foreground/60 underline-offset-4 hover:underline">Back to home</Link>
            </form>
        </main>
        <SiteFooter />
    </div>;
}

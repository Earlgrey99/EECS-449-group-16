import from "@jac/runtime" { Link, useNavigate, jacLogin, jacSignup }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Tick02Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }

def:pub LoginPage() -> JsxElement {
    nav = useNavigate();
    has email: str = "";
    has password: str = "";
    has mode: str = "signin";
    has message: str = "";
    has busy: bool = False;
    has keep_signed_in: bool = False;

    def handle_email(e: ChangeEvent) { email = e.target.value; }
    def handle_password(e: ChangeEvent) { password = e.target.value; }

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
                <Button type="button" variant="outline" className="h-11 bg-background text-foreground" onClick={lambda { message = "Google sign-in is coming soon - use your email for now."; }}>
                    Continue with Google
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
                <Button type="submit" disabled={busy} className="h-12 w-3/4 self-center rounded-full bg-emerald-500 text-white shadow-md hover:bg-emerald-500/90">
                    {"Signing in..." if busy else ("Sign in" if mode == "signin" else "Create account")}
                </Button>
                <Link to="/" className="self-center text-xs text-primary-foreground/60 underline-offset-4 hover:underline">Back to home</Link>
            </form>
        </main>
        <SiteFooter />
    </div>;
}
import from "@jac/runtime" { Link, useNavigate, jacLogin, jacSignup }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Task01Icon, File01Icon, Search01Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.field { Field, FieldLabel, FieldGroup }
import from .BrandMark { BrandMark }

def:pub LoginPage() -> JsxElement {
    nav = useNavigate();
    has email: str = "";
    has password: str = "";
    has mode: str = "signin";
    has message: str = "";
    has busy: bool = False;

    def handle_email(e: ChangeEvent) { email = e.target.value; }
    def handle_password(e: ChangeEvent) { password = e.target.value; }

    async def handle_submit {
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

    return <div className="grid min-h-svh lg:grid-cols-2">
        <div className="relative hidden overflow-hidden bg-primary text-primary-foreground lg:flex lg:flex-col lg:justify-between pt-10 pb-10 pl-10 pr-10">
            <div className="pointer-events-none absolute -right-24 -top-24 size-96 rounded-full bg-primary-foreground/10 blur-3xl" />
            <div className="pointer-events-none absolute -bottom-32 -left-16 size-96 rounded-full bg-primary-foreground/10 blur-3xl" />
            <div className="relative"><BrandMark name="Jaccit" inverted={True} /></div>
            <div className="relative flex max-w-md flex-col gap-8">
                <h1 className="text-balance text-4xl font-semibold leading-tight tracking-tight">{"Find the role. Track every application."}</h1>
                <div className="flex flex-col gap-4">
                    <div className="flex items-start gap-3">
                        <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary-foreground/15">
                            <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="size-4" />
                        </div>
                        <div>
                            <p className="font-medium">Search the feed</p>
                            <p className="text-sm text-primary-foreground/75">Filter by role, location, and pay.</p>
                        </div>
                    </div>
                    <div className="flex items-start gap-3">
                        <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary-foreground/15">
                            <HugeiconsIcon icon={Task01Icon} strokeWidth={2} className="size-4" />
                        </div>
                        <div>
                            <p className="font-medium">Track applications</p>
                            <p className="text-sm text-primary-foreground/75">Know where every submission stands.</p>
                        </div>
                    </div>
                    <div className="flex items-start gap-3">
                        <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary-foreground/15">
                            <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-4" />
                        </div>
                        <div>
                            <p className="font-medium">Attach your work</p>
                            <p className="text-sm text-primary-foreground/75">Keep the resume and letter you sent.</p>
                        </div>
                    </div>
                </div>
            </div>
            <p className="relative text-sm text-primary-foreground/80">Jaccit, the job application platform.</p>
        </div>
        <div className="flex flex-col bg-background pt-8 pb-8 pl-6 pr-6 sm:pl-10 sm:pr-10">
            <div className="lg:hidden"><BrandMark name="Jaccit" /></div>
            <div className="flex flex-1 items-center justify-center">
                <form onSubmit={handle_submit} className="flex w-full max-w-sm flex-col gap-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
                    <div className="flex flex-col gap-1.5">
                        <h2 className="text-2xl font-semibold tracking-tight">{"Welcome back" if mode == "signin" else "Create your account"}</h2>
                        <p className="text-sm text-muted-foreground">{"Sign in to continue your job search." if mode == "signin" else "Sign up with an email and a password."}</p>
                    </div>
                    <FieldGroup>
                        <Field>
                            <FieldLabel htmlFor="email">Email</FieldLabel>
                            <Input id="email" type="email" placeholder="you@example.com" value={email} onChange={handle_email} className="h-10" />
                        </Field>
                        <Field>
                            <FieldLabel htmlFor="password">Password</FieldLabel>
                            <Input id="password" type="password" placeholder="Your password" value={password} onChange={handle_password} className="h-10" />
                        </Field>
                    </FieldGroup>
                    {message and <p className="text-sm text-destructive">{message}</p>}
                    <Button type="submit" disabled={busy} className="h-10 w-full">{"Signing in..." if busy else ("Sign in" if mode == "signin" else "Create account")}</Button>
                    <p className="text-center text-sm text-muted-foreground">
                        {"New here? " if mode == "signin" else "Already have an account? "}
                        <button type="button" onClick={lambda { mode = "signup" if mode == "signin" else "signin"; message = ""; }} className="font-medium text-foreground underline-offset-4 hover:underline">
                            {"Create an account" if mode == "signin" else "Sign in"}
                        </button>
                    </p>
                    <p className="text-center text-xs text-muted-foreground"><Link to="/" className="underline-offset-4 hover:underline">Back to home</Link></p>
                </form>
            </div>
        </div>
    </div>;
}
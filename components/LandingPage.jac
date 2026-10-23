import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, Task01Icon, File01Icon, ArrowRight01Icon, CheckmarkCircle02Icon, UserGroupIcon }
import from .ui.button { Button }
import from .ui.badge { Badge }
import from .ui.card { Card, CardHeader, CardTitle, CardContent }
import from .BrandMark { BrandMark }

def:pub LandingPage() -> JsxElement {
    return <div className="min-h-svh bg-muted/40">
        <nav className="sticky top-0 z-20 border-b bg-background/80 backdrop-blur">
            <div className="mx-auto flex h-16 max-w-6xl items-center gap-8 pl-6 pr-6">
                <BrandMark name="Jaccit" />
                <div className="hidden flex-1 items-center gap-6 text-sm text-muted-foreground md:flex">
                    <a href="#features" className="transition-colors hover:text-foreground">Features</a>
                    <a href="#how" className="transition-colors hover:text-foreground">How it works</a>
                </div>
                <div className="flex items-center gap-2">
                    <Link to="/login"><Button variant="ghost" size="sm">Sign in</Button></Link>
                    <Link to="/login"><Button size="sm">Get started</Button></Link>
                </div>
            </div>
        </nav>

        <section className="relative overflow-hidden">
            <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_80%_20%,color-mix(in_oklch,var(--primary)_18%,transparent),transparent)]" />
            <div className="mx-auto grid max-w-6xl items-center gap-12 pt-20 pb-20 pl-6 pr-6 lg:grid-cols-2">
                <div className="flex flex-col gap-6">
                    <Badge variant="secondary" className="w-fit">Built for job seekers</Badge>
                    <h1 className="text-balance text-4xl font-semibold leading-[1.1] tracking-tight md:text-5xl">{"Find the role. Track every application."}</h1>
                    <p className="text-balance text-lg text-muted-foreground">Jaccit puts job search, resume tracking, and application history in one place, so you always know where you stand.</p>
                    <div className="flex flex-wrap items-center gap-3">
                        <Link to="/login"><Button className="shadow-sm">Start searching <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4" /></Button></Link>
                        <a href="#how"><Button variant="outline">How it works</Button></a>
                    </div>
                </div>
                <div className="relative">
                    <div className="absolute -inset-4 rounded-3xl bg-primary/10 blur-2xl" />
                    <Card className="relative shadow-xl">
                        <CardHeader className="flex flex-row items-start justify-between gap-4">
                            <div className="flex flex-col gap-1">
                                <CardTitle>Applications this week</CardTitle>
                                <p className="text-sm text-muted-foreground">Your pipeline at a glance</p>
                            </div>
                            <Badge>{8}</Badge>
                        </CardHeader>
                        <CardContent className="flex flex-col gap-3">
                            {for row in [
                                {"role": "Frontend Engineer", "company": "Lumen Labs", "status": "Interviewing"},
                                {"role": "Backend Engineer", "company": "Northwind Data", "status": "Applied"},
                                {"role": "Product Designer", "company": "Marigold Studio", "status": "Saved"},
                            ] {
                                <div key={row["company"]} className="flex items-center justify-between rounded-lg border bg-background p-3">
                                    <div className="flex items-center gap-3">
                                        <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                                            <HugeiconsIcon icon={UserGroupIcon} strokeWidth={2} className="size-4" />
                                        </div>
                                        <div>
                                            <p className="text-sm font-medium">{row["role"]}</p>
                                            <p className="text-xs text-muted-foreground">{row["company"]}</p>
                                        </div>
                                    </div>
                                    <Badge variant="outline">{row["status"]}</Badge>
                                </div>
                            }}
                        </CardContent>
                    </Card>
                </div>
            </div>
        </section>

        <section id="features" className="pt-16 pb-16">
            <div className="mx-auto max-w-6xl pl-6 pr-6">
                <h2 className="text-balance text-3xl font-semibold tracking-tight">Everything the search needs</h2>
                <p className="mt-2 max-w-2xl text-muted-foreground">One tool from the first listing to the offer letter.</p>
                <div className="mt-8 grid gap-4 md:grid-cols-3">
                    <div className="rounded-2xl bg-primary p-8 text-primary-foreground md:col-span-2 md:row-span-2">
                        <div className="flex size-10 items-center justify-center rounded-xl bg-primary-foreground/15">
                            <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="size-5" />
                        </div>
                        <h3 className="mt-6 text-2xl font-semibold">Search that fits you</h3>
                        <p className="mt-2 max-w-md text-primary-foreground/80">Filter the feed by role, location, and pay, then apply with the resume and cover letter already on file.</p>
                    </div>
                    <div className="flex flex-col gap-3 rounded-2xl border bg-card p-6 shadow-sm">
                        <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                            <HugeiconsIcon icon={Task01Icon} strokeWidth={2} className="size-4" />
                        </div>
                        <h3 className="font-semibold">Track applications</h3>
                        <p className="text-sm text-muted-foreground">Every submission logged with its date and status.</p>
                    </div>
                    <div className="flex flex-col gap-3 rounded-2xl bg-muted/60 p-6">
                        <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                            <HugeiconsIcon icon={File01Icon} strokeWidth={2} className="size-4" />
                        </div>
                        <h3 className="font-semibold">Resume and cover letter</h3>
                        <p className="text-sm text-muted-foreground">Attach the exact version you sent, per role.</p>
                    </div>
                </div>
            </div>
        </section>

        <section id="how" className="pt-16 pb-16">
            <div className="mx-auto max-w-6xl pl-6 pr-6">
                <h2 className="text-balance text-3xl font-semibold tracking-tight">How it works</h2>
                <div className="mt-8 grid gap-4 md:grid-cols-3">
                    {for step in [
                        {"n": "1", "title": "Create an account", "body": "Sign up with your email in under a minute."},
                        {"n": "2", "title": "Browse the feed", "body": "Search live listings and save the roles that fit."},
                        {"n": "3", "title": "Apply and track", "body": "Log every application and follow it to the offer."},
                    ] {
                        <div key={step["n"]} className="rounded-2xl border bg-card p-6 shadow-sm">
                            <div className="flex items-center gap-3">
                                <span className="flex size-8 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary tabular-nums">{step["n"]}</span>
                                <h3 className="font-semibold">{step["title"]}</h3>
                            </div>
                            <p className="mt-3 text-sm text-muted-foreground">{step["body"]}</p>
                        </div>
                    }}
                </div>
                <div className="mt-12 rounded-2xl border bg-card p-8 text-center shadow-sm">
                    <h3 className="text-2xl font-semibold tracking-tight">Ready to start?</h3>
                    <p className="mt-2 text-muted-foreground">Create your free account and open the job feed.</p>
                    <Link to="/login" className="mt-6 inline-block"><Button className="shadow-sm">Get started <HugeiconsIcon icon={CheckmarkCircle02Icon} strokeWidth={2} className="size-4" /></Button></Link>
                </div>
            </div>
        </section>

        <footer className="border-t bg-background pt-8 pb-8">
            <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 pl-6 pr-6">
                <BrandMark name="Jaccit" />
                <p className="text-sm text-muted-foreground">{"© " + str(new(Date).getFullYear()) + " Jaccit"}</p>
            </div>
        </footer>
    </div>;
}
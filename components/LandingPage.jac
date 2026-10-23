import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon }
import from .ui.button { Button }
import from .ui.card { Card, CardContent }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from ..services.jobs { list_jobs }

def:pub LandingPage() -> JsxElement {
    has jobs: list[dict[str, str | int]] = [];

    async can with entry {
        jobs = await list_jobs();
    }

    preview: list[dict[str, str | int]] = jobs[:5] if len(jobs) > 5 else jobs;

    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="flex flex-1 flex-col gap-14 pt-14 pb-20">
            <section className="mx-auto grid w-full max-w-6xl gap-10 pl-6 pr-6">
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
                    {for j in preview {
                        <Card key={str(j["id"])} className="shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md">
                            <CardContent className="flex flex-col gap-2 pt-5">
                                <h3 className="font-semibold leading-tight">{str(j["title"])}</h3>
                                <p className="text-sm text-muted-foreground">{str(j["location"])}</p>
                                <p className="text-sm font-medium tabular-nums text-primary">{"$" + str(j["salary"])}</p>
                            </CardContent>
                        </Card>
                    }}
                </div>
                <div className="flex flex-col items-center gap-8 text-center">
                    <h1 className="text-balance text-4xl font-semibold tracking-tight md:text-5xl">{"Launch your career. Today. For free."}</h1>
                    <div className="flex flex-col items-center gap-3">
                        <Link to="/login"><Button className="h-11 px-8 shadow-sm">Sign in with Google</Button></Link>
                        <Link to="/login"><Button variant="outline" className="h-11 bg-background px-8">Sign in with email</Button></Link>
                        <p className="text-sm text-muted-foreground">{"New? "}
                            <Link to="/login" className="font-medium text-primary underline-offset-4 hover:underline">Sign up here.</Link>
                        </p>
                    </div>
                </div>
            </section>
            <section className="mx-auto w-full max-w-6xl pl-6 pr-6">
                <div className="rounded-2xl border bg-card p-8 shadow-sm md:p-10">
                    <h2 className="text-balance text-2xl font-semibold tracking-tight">How Jaccit works</h2>
                    <p className="mt-2 max-w-2xl text-muted-foreground">Jaccit pulls jobs near you, and the feed scrolls right to left so the first results are the closest match. Save roles, apply with the resume on file, and track every application in one place.</p>
                    <div className="mt-8 grid gap-4 md:grid-cols-3">
                        {for step in [
                            {"n": "1", "title": "Create an account", "body": "Sign up with your email in under a minute."},
                            {"n": "2", "title": "Browse the feed", "body": "Search live listings by role, location, and pay."},
                            {"n": "3", "title": "Apply and track", "body": "Log every application and follow it to the offer."},
                        ] {
                            <div key={step["n"]} className="rounded-xl border bg-background p-6">
                                <div className="flex items-center gap-3">
                                    <span className="flex size-8 items-center justify-center rounded-full bg-primary/10 text-sm font-semibold text-primary tabular-nums">{step["n"]}</span>
                                    <h3 className="font-semibold">{step["title"]}</h3>
                                </div>
                                <p className="mt-3 text-sm text-muted-foreground">{step["body"]}</p>
                            </div>
                        }}
                    </div>
                    <div className="mt-8 flex justify-center">
                        <Link to="/login"><Button className="shadow-sm">Start searching <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4" /></Button></Link>
                    </div>
                </div>
            </section>
        </main>
        <SiteFooter />
    </div>;
}
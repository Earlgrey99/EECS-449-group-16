import from "@jac/runtime" { Link }
import from ..components.TopNav { TopNav }
import from ..components.SiteFooter { SiteFooter }

"""Shown for any address that isn't a page, instead of a blank screen."""
def:pub Page() -> JsxPage {
    return <div className="flex min-h-screen flex-col bg-background">
        <TopNav />
        <main className="mx-auto flex w-full max-w-xl flex-1 flex-col items-center justify-center gap-4 px-6 py-16 text-center">
            <p className="text-sm font-semibold text-primary">404</p>
            <h1 className="text-3xl font-semibold">We couldn't find that page</h1>
            <p className="text-muted-foreground">The link may be old or mistyped. Head back to your job feed or the home page.</p>
            <div className="flex flex-wrap justify-center gap-3">
                <Link to="/jobs" className="inline-flex h-10 items-center rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground hover:bg-primary/90">Go to jobs</Link>
                <Link to="/" className="inline-flex h-10 items-center rounded-lg border px-4 text-sm font-medium hover:bg-muted">Home</Link>
            </div>
        </main>
        <SiteFooter />
    </div>;
}

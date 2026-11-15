import from "@jac/runtime" { jacIsLoggedIn, Navigate }
import from .TopNav { TopNav }
import from .SiteFooter { SiteFooter }
import from .CareerAssistant { CareerAssistant }

def:pub CareerNavigator() -> JsxElement {
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }
    return <div className="flex min-h-svh flex-col bg-primary/5">
        <TopNav />
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-6 px-4 py-8 md:px-6 md:py-10">
            <header className="flex flex-col gap-3">
                <p className="text-sm font-semibold text-primary">CAREER NAVIGATOR</p>
                <h1 className="text-3xl font-semibold tracking-tight md:text-4xl">Find your next step.</h1>
                <p className="max-w-3xl text-muted-foreground">Explore careers connected to your major, discover majors that can lead to your career goal, and get practical job-search guidance. Your conversations are saved to your account.</p>
            </header>
            <CareerAssistant />
        </main>
        <SiteFooter />
    </div>;
}

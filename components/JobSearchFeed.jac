import from "@jac/runtime" { Link, jacIsLoggedIn, Navigate, jacLogout }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Search01Icon, KanbanIcon, Logout01Icon }
import from .ui.button { Button }
import from .ui.input { Input }
import from .ui.badge { Badge }
import from .ui.card { Card, CardHeader, CardTitle, CardContent }
import from .ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from .ui.spinner { Spinner }
import from .BrandMark { BrandMark }
import from ..services.jobs { list_jobs }

def:pub JobSearchFeed() -> JsxElement {
    if not jacIsLoggedIn() {
        return <Navigate to="/login" replace={True} />;
    }
    has jobs: list[dict[str, str | int]] = [];
    has loading: bool = True;
    has query: str = "";

    async can with entry {
        jobs = await list_jobs();
        loading = False;
    }

    filtered = [j for j in jobs if query.strip().lower() in (str(j["title"]) + " " + str(j["company"]) + " " + str(j["location"]) + " " + str(j["tags"])).lower()];

    def handle_query(e: ChangeEvent) { query = e.target.value; }

    return <div className="min-h-svh bg-muted/40">
        <nav className="sticky top-0 z-20 border-b bg-background/80 backdrop-blur">
            <div className="mx-auto flex h-16 max-w-6xl items-center gap-8 pl-6 pr-6">
                <Link to="/"><BrandMark name="Jaccit" /></Link>
                <div className="hidden flex-1 items-center gap-6 text-sm text-muted-foreground md:flex">
                    <span className="font-medium text-foreground">Job search</span>
                </div>
                <Button variant="outline" size="sm" onClick={lambda { jacLogout(); }}>
                    <HugeiconsIcon icon={Logout01Icon} strokeWidth={2} className="size-4" /> Sign out
                </Button>
            </div>
        </nav>

        <main className="mx-auto flex w-full max-w-6xl flex-col gap-6 pt-8 pb-16 pl-6 pr-6 animate-in fade-in slide-in-from-bottom-2 duration-500">
            <div className="flex flex-wrap items-end justify-between gap-4">
                <div className="flex flex-col gap-1">
                    <h1 className="text-2xl font-semibold tracking-tight">Job search</h1>
                    <p className="text-sm text-muted-foreground">Open roles from companies hiring now.</p>
                </div>
            </div>

            {if loading {
                <div className="flex items-center justify-center p-12"><Spinner /></div>
            } else {
                <Card className="shadow-sm">
                    <CardContent className="flex flex-col gap-4 pt-6">
                        <div className="flex flex-wrap items-center justify-between gap-3">
                            <div className="relative w-full max-w-xs">
                                <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                                <Input value={query} onChange={handle_query} placeholder="Search roles, companies, skills" className="pl-8" />
                            </div>
                            <span className="text-sm text-muted-foreground tabular-nums">{str(len(filtered)) + (" jobs" if len(filtered) == 1 else " jobs")}</span>
                        </div>

                        {if len(filtered) == 0 {
                            <Empty className="border border-dashed pt-12 pb-12">
                                <EmptyHeader>
                                    <EmptyMedia variant="icon"><HugeiconsIcon icon={KanbanIcon} strokeWidth={2} /></EmptyMedia>
                                    <EmptyTitle>No matching jobs</EmptyTitle>
                                    <EmptyDescription>Try a different role, company, or skill.</EmptyDescription>
                                </EmptyHeader>
                                <EmptyContent><Button variant="outline" onClick={lambda { query = ""; }}>Clear search</Button></EmptyContent>
                            </Empty>
                            skip;
                        }}

                        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                            {for j in filtered {
                                <Card key={str(j["id"])} className="shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md">
                                    <CardHeader>
                                        <div className="flex items-start justify-between gap-3">
                                            <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                                                <HugeiconsIcon icon={KanbanIcon} strokeWidth={2} className="size-4" />
                                            </div>
                                            <Badge variant="outline">{str(j["type"])}</Badge>
                                        </div>
                                        <CardTitle className="text-base">{str(j["title"])}</CardTitle>
                                        <p className="text-sm text-muted-foreground">{str(j["company"])}</p>
                                    </CardHeader>
                                    <CardContent className="flex flex-col gap-3">
                                        <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
                                            <span>{str(j["location"])}</span>
                                            <span aria-hidden="true">·</span>
                                            <span className="tabular-nums">{"$" + str(j["salary"])}</span>
                                        </div>
                                        <div className="flex flex-wrap gap-1.5">
                                            {for tag in str(j["tags"]).split(", ") {
                                                <Badge key={tag} variant="secondary" className="font-normal">{tag}</Badge>
                                            }}
                                        </div>
                                    </CardContent>
                                </Card>
                            }}
                        </div>
                    </CardContent>
                </Card>
            }}
        </main>
    </div>;
}
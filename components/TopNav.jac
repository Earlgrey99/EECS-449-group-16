import from "@jac/runtime" { Link, useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Menu01Icon }
import from .BrandMark { BrandMark }

def:pub TopNav() -> JsxElement {
    path = useLocation().pathname;
    def link_class(to: str) -> str {
        base = "text-sm font-medium transition-colors px-3 py-1.5 rounded-md";
        return base + (" bg-primary/10 text-primary" if path == to or (to != "/" and path.startswith(to)) else " text-muted-foreground hover:text-foreground");
    }
    return <nav className="sticky top-0 z-20 border-b bg-background">
        <div className="mx-auto flex h-16 max-w-6xl items-center gap-6 pl-6 pr-6">
            <Link to="/"><BrandMark name="Jaccit" /></Link>
            <div className="hidden flex-1 items-center justify-end gap-2 md:flex">
                <Link to="/"><span className={link_class("/")}>Home</span></Link>
                <Link to="/jobs"><span className={link_class("/jobs")}>Jobs</span></Link>
                <Link to="/jobs"><span className={link_class("/explore")}>Explore</span></Link>
            </div>
            <button className="flex size-9 items-center justify-center rounded-md text-foreground md:hidden" aria-label="Menu">
                <HugeiconsIcon icon={Menu01Icon} strokeWidth={2} className="size-5" />
            </button>
            <button className="hidden md:flex size-9 items-center justify-center rounded-md text-foreground" aria-label="Menu">
                <HugeiconsIcon icon={Menu01Icon} strokeWidth={2} className="size-5" />
            </button>
        </div>
    </nav>;
}
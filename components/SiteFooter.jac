import from .BrandMark { BrandMark }

def:pub SiteFooter() -> JsxElement {
    return <footer className="border-t bg-muted/60 pt-6 pb-6">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 pl-6 pr-6">
            <BrandMark name="Jaccit" />
            <p className="text-sm text-muted-foreground">{"© " + str(new(Date).getFullYear()) + " Jaccit"}</p>
        </div>
    </footer>;
}
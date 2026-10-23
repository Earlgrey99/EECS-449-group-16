def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    tile = "bg-primary-foreground/15 text-primary-foreground ring-1 ring-primary-foreground/20" if inverted else "bg-primary/10 text-primary ring-1 ring-primary/20";
    return <div className="flex items-center gap-2.5">
        <div className={"flex size-10 items-center justify-center rounded-full " + tile}>
            <span className="text-sm font-bold">{name[0]}</span>
        </div>
        <span className="text-base font-bold tracking-tight">{name}</span>
    </div>;
}
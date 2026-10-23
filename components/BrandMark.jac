import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { KanbanIcon }

def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    tile = "bg-primary-foreground/15 text-primary-foreground ring-1 ring-primary-foreground/20" if inverted else "bg-primary text-primary-foreground shadow-sm";
    return <div className="flex items-center gap-2.5">
        <div className={"flex size-8 items-center justify-center rounded-lg " + tile}>
            <HugeiconsIcon icon={KanbanIcon} strokeWidth={2} className="size-4" />
        </div>
        <span className="text-base font-semibold tracking-tight">{name}</span>
    </div>;
}
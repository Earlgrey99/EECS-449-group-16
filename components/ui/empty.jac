import from "class-variance-authority" { cva }
import from ...lib.utils { cn }

glob _emptyMediaVariants: any = cva(
         "mb-2 flex shrink-0 items-center justify-center [&_svg]:pointer-events-none [&_svg]:shrink-0",
         {
             "variants": {
                 "variant": {
                     "default": "bg-transparent",
                     "icon": "bg-muted text-foreground flex size-10 shrink-0 items-center justify-center rounded-lg [&_svg:not([class*='size-'])]:size-6"
                 }
             },
             "defaultVariants": {"variant": "default"}
         }
     );

def:pub Empty(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    return
        <div
            {**attrs}
            data-slot="empty"
            className={cn(
                "gap-4 rounded-lg border border-dashed p-12 flex w-full min-w-0 flex-1 flex-col items-center justify-center text-center text-balance",
                props["className"]
            )}
        >
            {props["children"]}
        </div>;
}

def:pub EmptyHeader(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    return
        <div
            {**attrs}
            data-slot="empty-header"
            className={cn(
                "gap-2 flex w-full max-w-sm flex-col items-center justify-center text-center mx-auto",
                props["className"]
            )}
        >
            {props["children"]}
        </div>;
}

def:pub EmptyMedia(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    variant = props["variant"] or "default";
    computedClass = cn(
        _emptyMediaVariants.call(
            None, {"variant": variant, "className": props["className"]}
        )
    );
    return
        <div
            {**attrs}
            data-slot="empty-icon"
            data-variant={variant}
            className={computedClass}
        >
            {props["children"]}
        </div>;
}

def:pub EmptyTitle(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    return
        <div
            {**attrs}
            data-slot="empty-title"
            className={cn("text-lg font-medium tracking-tight text-center", props["className"])}
        >
            {props["children"]}
        </div>;
}

def:pub EmptyDescription(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    return
        <div
            {**attrs}
            data-slot="empty-description"
            className={cn(
                "text-sm/relaxed text-muted-foreground text-center [&>a:hover]:text-primary [&>a]:underline [&>a]:underline-offset-4",
                props["className"]
            )}
        >
            {props["children"]}
        </div>;
}

def:pub EmptyContent(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    attrs.pop("className", None);
    return
        <div
            {**attrs}
            data-slot="empty-content"
            className={cn(
                "gap-4 text-sm flex w-full max-w-sm min-w-0 flex-col items-center justify-center text-center text-balance mx-auto",
                props["className"]
            )}
        >
            {props["children"]}
        </div>;
}

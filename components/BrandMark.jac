def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    fg = "var(--primary-foreground)" if inverted else "var(--primary)";
    return <div className="flex items-center gap-2">
        <svg width="30" height="30" viewBox="0 0 32 32" fill="none" aria-hidden="true">
            <path
                d="M21.5 3.5 C23.5 9 21 15 16.5 19.5 C12.5 23.5 7.5 24.5 6 21 C5.2 19.2 6.5 17.5 8.5 17.2"
                stroke={fg}
                strokeWidth="5.5"
                strokeLinecap="round"
                strokeLinejoin="round"
            />
            <circle cx="7" cy="22.5" r="3.4" fill={fg} />
        </svg>
        <span className="text-lg font-extrabold italic tracking-tight">{name}</span>
    </div>;
}
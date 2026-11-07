glob LOGO_URL: str = "/static/assets/launchpad-logo.png";

def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    return <div className="flex items-center gap-2">
        <img src={LOGO_URL} alt={name} className="h-9 w-auto" />
        <span className="sr-only">{name}</span>
    </div>;
}
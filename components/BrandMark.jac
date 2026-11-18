"""The Launchpad brand: the frog-and-wordmark logo, as a PNG.

The file lives in public/ (Vite serves it at /launchpad-logo.png in dev and
copies it into the build), so it is referenced by URL - not imported as a
module, which previously caused a runtime error.
"""
def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    return <img
        src="/launchpad-logo.png"
        alt={name}
        className="h-9 w-auto select-none"
    />;
}

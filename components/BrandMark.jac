"""The Launchpad brand: the frog-and-wordmark logo, as a PNG.

The png lives in assets/, which the build copies to the served client root,
so it is referenced by the plain URL /assets/launchpad-logo.png - not
imported as a module, which previously caused a runtime error. (Note:
a top-level /launchpad-logo.png URL is intercepted by the server and
returns the app HTML instead, so the /assets/ path is required.)
"""
def:pub BrandMark(name: str, inverted: bool = False) -> JsxElement {
    return <img
        src="/assets/launchpad-logo.png"
        alt={name}
        className="h-9 w-auto select-none"
    />;
}

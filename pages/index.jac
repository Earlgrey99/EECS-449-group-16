import "..styles.global.css";
import "..components.LandingPage.css";
import from ..components.LandingPage { LandingPage }

def:pub Page() -> JsxPage {
    return <LandingPage/>;
}
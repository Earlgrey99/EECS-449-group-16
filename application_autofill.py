"""User-reviewed browser form filling; never submits forms."""
import json, re
from pathlib import Path
from urllib.parse import urlparse
ALIASES={
"name":("full name","fullname","applicant name","candidate name"),
"first_name":("first name","firstname","given name","givenname","fname"),
"last_name":("last name","lastname","surname","family name","lname"),
"email":("email","email address","e-mail"),
"phone":("phone","phone number","mobile","telephone"),
"location":("location","city","current city"),
"address":("address","street address"),
"linkedin":("linkedin","linkedin url","linkedin profile"),
"github":("github","github url"),
"portfolio":("portfolio","website","personal website"),
"resume_path":("resume","cv","upload resume","attach resume"),
}
SENSITIVE=("password","ssn","social security","passport","credit card","bank","date of birth","dob","gender","race","ethnicity","disability","veteran","salary expectation","work authorization","visa","citizenship")
def normalize(value):
    value=re.sub(r"([a-z])([A-Z])",r"\1 \2",str(value))
    return re.sub(r"[^a-z0-9]+"," ",value.lower()).strip()
def read_mapping(path=None):
    if not path:return {}
    obj=json.loads(Path(path).expanduser().read_text(encoding="utf8"))
    if not isinstance(obj,dict) or any(not isinstance(k,str) or not isinstance(v,str) for k,v in obj.items()):raise ValueError("Mapping must be an object of field names")
    return obj
def resolve_field(attrs,profile,mapping=None):
    mapping=mapping or {}
    values=[str(v) for v in attrs.values() if v]
    words=[normalize(v) for v in values]
    if any(any(s in w for s in SENSITIVE) for w in words):return None
    for raw in values:
        if raw in mapping and mapping[raw] in profile:return mapping[raw]
    for w in words:
        for raw,key in mapping.items():
            if normalize(raw)==w and key in profile:return key
    for key,aliases in ALIASES.items():
        if key not in profile or not profile[key]:continue
        labels=(key.replace("_"," "),)+aliases
        for word in words:
            if any(normalize(a)==word or (word.endswith(" "+normalize(a))) for a in labels):
                return key
    return None
def browser_autofill(target,profile,mapping=None,apply=False,headless=False,hold_seconds=0):
    from playwright.sync_api import sync_playwright
    target=str(target); u=urlparse(target)
    if u.scheme not in ("http","https","file"):raise ValueError("Target must be an HTTP(S) or local file URL")
    if u.scheme=="file" and not Path(u.path).exists():raise ValueError("Local form file missing")
    if hold_seconds<0:raise ValueError("hold-seconds cannot be negative")
    plan=[]
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=headless)
        try:
            page=browser.new_page()
            page.goto(target,wait_until="domcontentloaded",timeout=30000)
            inputs=page.locator("input, textarea, select")
            for index in range(inputs.count()):
                field=inputs.nth(index)
                try:
                    tag=field.evaluate("(e)=>e.tagName.toLowerCase()")
                    kind=(field.get_attribute("type") or "text").lower()
                    if kind in ("hidden","password","submit","button","reset","checkbox","radio") or not field.is_visible() or not field.is_enabled() or field.get_attribute("readonly") is not None:continue
                    attrs={"name":field.get_attribute("name"),"id":field.get_attribute("id"),"placeholder":field.get_attribute("placeholder"),"aria-label":field.get_attribute("aria-label")}
                    fid=field.get_attribute("id")
                    if fid:
                        labels=page.locator("label[for]").filter(has=page.locator("xpath=.")).count() if False else page.locator("label[for='"+fid.replace("'","\\'")+"']")
                        if labels.count():attrs["label"]=labels.first.inner_text()
                    key=resolve_field(attrs,profile,mapping)
                    if not key:continue
                    value=profile[key]
                    if kind=="file":
                        if key!="resume_path" or not Path(value).is_file():continue
                        if apply:field.set_input_files(str(Path(value).expanduser().resolve()))
                    elif tag=="select":
                        if apply:
                            try:field.select_option(label=value)
                            except Exception:continue
                    else:
                        if apply:field.fill(str(value))
                    plan.append({"field":attrs.get("name") or attrs.get("id") or attrs.get("label"),"profile_key":key,"status":"filled" if apply else "preview"})
                except Exception as exc:
                    plan.append({"field":str(index),"status":"skipped","reason":str(exc)[:120]})
            if apply and not headless:
                if hold_seconds:page.wait_for_timeout(hold_seconds*1000)
                else:
                    try:input("Review form in browser; press Enter to close (nothing submitted).")
                    except EOFError:pass
            elif apply and hold_seconds:page.wait_for_timeout(hold_seconds*1000)
        finally:browser.close()
    return plan

import from "clsx" { clsx }
import from "tailwind-merge" { twMerge }

def:pub cn(*inputs: any) -> str {
    return twMerge(clsx(inputs));
}

def:pub format_salary(sal: str | None = None) -> str {
    s = str(sal or "").strip();
    if not s {
        return "";
    }
    while s.startswith("$$") {
        s = s[1:];
    }
    if s.startswith("$") {
        return s;
    }
    return "$" + s;
}

def:pub format_desc(raw_desc: str) -> str {
    d = str(raw_desc or "").strip();
    if not d {
        return "";
    }
    d = d.replace("&amp;nbsp;", " ").replace("&nbsp;", " ").replace("&#160;", " ").replace("&#xA0;", " ").replace("\xa0", " ");
    while "  " in d {
        d = d.replace("  ", " ");
    }
    low = d.lower();
    if "<p" not in low and "<br" not in low and "<div" not in low and "\n" in d {
        return d.replace("\r\n", "<br />").replace("\n", "<br />");
    }
    return d;
}

def:pub is_jooble_job(j: dict[str, any] | None = None) -> bool {
    if not j {
        return False;
    }
    src = str(j.get("source") or j.get("site") or "").strip().lower();
    if src == "jooble" {
        return True;
    }
    link = str(j.get("link") or "").strip().lower();
    if "jooble.org" in link or "jooble." in link {
        return True;
    }
    return False;
}

def:pub get_jooble_link(j: dict[str, any] | None = None) -> str {
    if not j {
        return "https://jooble.org";
    }
    link = str(j.get("link") or "").strip();
    if link {
        return link;
    }
    jid = str(j.get("id") or "").strip();
    if jid {
        return f"https://jooble.org/desc/{jid}";
    }
    return "https://jooble.org";
}

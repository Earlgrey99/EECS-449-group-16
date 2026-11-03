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
    low = d.lower();
    if "<p" not in low and "<br" not in low and "<div" not in low and "\n" in d {
        return d.replace("\r\n", "<br />").replace("\n", "<br />");
    }
    return d;
}

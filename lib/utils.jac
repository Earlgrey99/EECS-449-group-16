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

"""Return True when a job description uses common Markdown syntax."""
def:pub is_markdown(raw_desc: str | None = None) -> bool {
    text = str(raw_desc or "").strip();
    if not text {
        return False;
    }
    if "**" in text or "__" in text or "`" in text {
        return True;
    }
    if "[" in text and "](" in text and ")" in text {
        return True;
    }
    for line in text.splitlines() {
        stripped = line.strip();
        if not stripped {
            continue;
        }
        if stripped.startswith("# ") or stripped.startswith("## ") or stripped.startswith("### ") {
            return True;
        }
        if stripped.startswith("- ") or stripped.startswith("* ") or stripped.startswith("+ ") or stripped.startswith("> ") {
            return True;
        }
        first_dot = stripped.find(".");
        if first_dot > 0 and first_dot < 4 and stripped[:first_dot].isdigit() and len(stripped) > first_dot + 1 and stripped[first_dot + 1] == " " {
            return True;
        }
    }
    return False;
}

def _escape_html(text: str) -> str {
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&#x27;");
}

def _render_delimited(text: str, marker: str, tag: str) -> str {
    parts: list[str] = text.split(marker);
    if len(parts) < 3 {
        return text;
    }
    rebuilt: str = "";
    for (idx, part) in enumerate(parts) {
        if idx % 2 == 1 and idx < len(parts) - 1 {
            rebuilt += "<" + tag + ">" + part + "</" + tag + ">";
        } else {
            rebuilt += part;
        }
    }
    return rebuilt;
}

def _render_markdown_inline(text: str) -> str {
    rendered = _escape_html(text);
    # Render the inline styles most commonly used by job boards. Splitting on a
    # delimiter leaves unmatched markers untouched instead of producing invalid HTML.
    rendered = _render_delimited(rendered, "**", "strong");
    rendered = _render_delimited(rendered, "__", "strong");
    rendered = _render_delimited(rendered, "`", "code");
    return rendered;
}

def _markdown_heading(line: str) -> str | None {
    if line.startswith("### ") {
        return "<h3>" + _render_markdown_inline(line[4:]) + "</h3>";
    }
    if line.startswith("## ") {
        return "<h2>" + _render_markdown_inline(line[3:]) + "</h2>";
    }
    if line.startswith("# ") {
        return "<h1>" + _render_markdown_inline(line[2:]) + "</h1>";
    }
    return None;
}

def _markdown_list_item(line: str) -> tuple[str, str] | None {
    for prefix in ["- ", "* ", "+ "] {
        if line.startswith(prefix) {
            return ("ul", line[len(prefix):]);
        }
    }
    first_dot = line.find(".");
    if first_dot > 0 and first_dot < 4 and line[:first_dot].isdigit() and len(line) > first_dot + 1 and line[first_dot + 1] == " " {
        return ("ol", line[first_dot + 2:]);
    }
    return None;
}

def _render_markdown(text: str) -> str {
    html = "";
    open_list = "";
    for raw_line in text.splitlines() {
        line = raw_line.strip();
        heading = _markdown_heading(line);
        item = _markdown_list_item(line);
        if heading is not None {
            if open_list {
                html += "</" + open_list + ">";
                open_list = "";
            }
            html += heading;
        } elif item is not None {
            (list_type, content) = item;
            if open_list and open_list != list_type {
                html += "</" + open_list + ">";
                open_list = "";
            }
            if not open_list {
                html += "<" + list_type + ">";
                open_list = list_type;
            }
            html += "<li>" + _render_markdown_inline(content) + "</li>";
        } elif line.startswith("> ") {
            if open_list {
                html += "</" + open_list + ">";
                open_list = "";
            }
            html += "<blockquote>" + _render_markdown_inline(line[2:]) + "</blockquote>";
        } elif line {
            if open_list {
                html += "</" + open_list + ">";
                open_list = "";
            }
            html += "<p>" + _render_markdown_inline(line) + "</p>";
        } elif open_list {
            html += "</" + open_list + ">";
            open_list = "";
        }
    }
    if open_list {
        html += "</" + open_list + ">";
    }
    return html;
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
    # Providers that return HTML already supply the markup expected by the UI.
    # Only parse Markdown for text descriptions so existing listings keep their
    # current formatting.
    has_provider_html = "<p" in low or "<br" in low or "<div" in low or "<ul" in low or "<ol" in low or "<li" in low or "<strong" in low or "<b" in low or "<a " in low or "<h" in low;
    if not has_provider_html and is_markdown(d) {
        return _render_markdown(d);
    }
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

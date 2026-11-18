"""Tailor a resume by editing the original PDF, so its fonts and layout stay the same.

What it can change:
  - bullet order: within each job or project, the bullets that match the posting move up
  - skills order: in each "Label: a, b, c" skills line, matching skills move first
  - added skills: skills the applicant confirmed they have, added to a skills line
  - reworded bullets: rewrites proposed by an AI model (see resume_ai.py), each checked
    so it adds no new facts, numbers, or skills the resume doesn't already show

How: each changed page is rebuilt from layers of the original page. One layer holds the
page's lines and shapes; then every band of text (a heading, a job title line, a bullet)
is copied from the original in reading order, at its new position. Copies are exact, so
moved text looks the same. New text is drawn with the resume's own embedded font, and
only when that font has every letter needed and fits the bullet's original lines.
Anything that can't be done exactly is skipped and left as it was.
"""
from __future__ import annotations

import re
import statistics
from dataclasses import dataclass, field

from resume_pdf import BULLET, SECTION_NAMES, SKILL_LINE, _job_weights, _score, _section_title

MARKS = set("•●▪◦‣⁃∙·■►➢❖–—*-\x7f\x95\x88")


@dataclass
class Row:
    """One printed line: every span on the same baseline, left to right."""
    page: int
    chars: list  # (char, bbox, origin, span) in reading order
    baseline: float
    size: float
    x0: float
    x1: float
    y0: float
    y1: float
    text_x0: float = 0.0  # where the words start, after any bullet mark
    mark: tuple | None = None  # bbox of the bullet mark
    kind: str = "text"  # heading, bullet, cont, text

    @property
    def text(self) -> str:
        return _join(self.chars, self.size)

    @property
    def first_column(self) -> str:
        """The text before a wide gap, such as a job title without its right-aligned dates."""
        return _join(self.chars, self.size, stop_gap=1.5 * self.size)

    def words_text(self) -> str:
        """The row's words, without its bullet mark."""
        return _join([ch for ch in self.chars if ch[1][0] >= self.text_x0 - 0.5], self.size)


def _join(chars: list, size: float, stop_gap: float | None = None) -> str:
    """Text of chars, with a space wherever the PDF leaves a gap instead of a space."""
    out = []
    previous = None
    for ch in chars:
        if previous is not None:
            gap = ch[1][0] - previous[1][2]
            if stop_gap is not None and gap > stop_gap:
                break
            if gap > 0.2 * size and ch[0] != " " and previous[0] != " ":
                out.append(" ")
        out.append(ch[0])
        previous = ch
    return re.sub(r"\s+", " ", "".join(out)).strip()


@dataclass
class Unit:
    """A bullet (one or more rows), or a skills line."""
    rows: list[Row]
    section: str
    entry: str = ""

    @property
    def page(self) -> int:
        return self.rows[0].page

    @property
    def top(self) -> float:
        return min(row.y0 for row in self.rows)

    @property
    def bottom(self) -> float:
        return max(row.y1 for row in self.rows)

    @property
    def text(self) -> str:
        return " ".join(row.words_text() for row in self.rows).strip()


@dataclass
class Rewrite:
    """New words for a unit, drawn after its kept prefix (the bullet mark or skills label)."""
    text: str
    start_x: float  # where the new words start on the first row


@dataclass
class Plan:
    moves: dict = field(default_factory=dict)  # id(unit) -> dy
    rewrites: dict = field(default_factory=dict)  # id(unit) -> Rewrite
    changes: list[str] = field(default_factory=list)


def short(text: str, limit: int) -> str:
    """text cut at a word boundary, with an ellipsis when cut."""
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0].rstrip(",;:") + "…"


# ---------------------------------------------------------------- reading the page


def _rows(page, index: int) -> list[Row]:
    raw = page.get_text("rawdict", flags=0)
    pieces = []
    for block in raw["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block["lines"]:
            chars = []
            for span in line["spans"]:
                for ch in span["chars"]:
                    chars.append((ch["c"], ch["bbox"], ch["origin"], span))
            if chars:
                pieces.append((line, chars))
    pieces.sort(key=lambda piece: (piece[1][0][2][1], piece[1][0][1][0]))
    rows: list[Row] = []
    for line, chars in pieces:
        baseline = chars[0][2][1]
        size = max(span["size"] for span in line["spans"])
        straight = abs(line["dir"][1]) < 0.01
        if straight and rows and rows[-1].page == index and abs(rows[-1].baseline - baseline) <= 0.35 * min(size, rows[-1].size):
            row = rows[-1]
            row.chars = sorted(row.chars + chars, key=lambda ch: ch[1][0])
            row.size = max(row.size, size)
        else:
            row = Row(page=index, chars=list(chars), baseline=baseline, size=size, x0=0, x1=0, y0=0, y1=0)
            rows.append(row)
        if not straight:
            row.kind = "other"
    for row in rows:
        boxes = [bbox for _, bbox, *_ in row.chars]
        row.x0 = min(box[0] for box in boxes)
        row.x1 = max(box[2] for box in boxes)
        row.y0 = min(box[1] for box in boxes)
        row.y1 = max(box[3] for box in boxes)
        row.text_x0 = row.x0
    return rows


def _find_mark(row: Row, drawings: list) -> None:
    """Set row.mark if the row starts with a bullet glyph or a small drawn dot."""
    visible = [ch for ch in row.chars if ch[0].strip()]
    if not visible:
        return
    first = visible[0]
    rest = [ch for ch in visible[1:]]
    if rest:
        gap = rest[0][1][0] - first[1][2]
        other_font = first[3]["font"] != rest[0][3]["font"]
        if (first[0] in MARKS or (other_font and not first[0].isalnum() and first[0] not in "([\"'$")) and gap > 0.12 * row.size:
            row.mark = tuple(first[1])
            row.text_x0 = rest[0][1][0]
            return
    for box in drawings:
        width, height = box[2] - box[0], box[3] - box[1]
        middle = (box[1] + box[3]) / 2
        if 0.5 < width <= 0.6 * row.size and 0.5 < height <= 0.6 * row.size and row.y0 <= middle <= row.y1 and box[2] <= row.x0 and row.x0 - box[2] < 2 * row.size:
            row.mark = tuple(box)
            row.x0 = box[0]
            row.text_x0 = visible[0][1][0]
            return


def _units(doc) -> tuple[list[Row], list[list[Unit]], list[Unit]]:
    """All rows, the bullet groups (bullets listed one after another), and skills lines."""
    all_rows: list[Row] = []
    groups: list[list[Unit]] = []
    skills: list[Unit] = []
    section = ""
    # Headings that use a section name ("Experience") show the heading style; other rows
    # in exactly that style are headings too, whatever they say.
    heading_styles = set()
    for index, page in enumerate(doc):
        for row in _rows(page, index):
            if _section_title(row.text) and row.text.lower().rstrip(":") in SECTION_NAMES:
                heading_styles.add(_style_of(row))
    for index, page in enumerate(doc):
        drawings = [tuple(d["rect"]) for d in page.get_drawings() if d.get("fill") is not None]
        rows = _rows(page, index)
        all_rows.extend(rows)
        group: list[Unit] = []
        entry = ""
        fresh = True  # the next text row starts a new job or project
        current: Unit | None = None
        for row in rows:
            if row.kind == "other":
                current = None
                group = _close(group, groups)
                continue
            title = _section_title(row.text)
            if not title and _style_of(row) in heading_styles and len(row.text) <= 40 and len({ch[3]["font"] for ch in row.chars if ch[0].strip()}) == 1:
                title = row.text
            if title and not BULLET.match(row.text):
                row.kind = "heading"
                section = title
                fresh = True
                current = None
                group = _close(group, groups)
                continue
            _find_mark(row, drawings)
            if row.mark:
                row.kind = "bullet"
                if group and abs(group[-1].rows[0].text_x0 - row.text_x0) > 1.5:
                    group = _close(group, groups)
                current = Unit(rows=[row], section=section, entry=entry)
                group.append(current)
                fresh = True
                continue
            previous = current.rows[-1] if current else None
            if previous and abs(row.x0 - previous.text_x0) <= 1.5 and row.baseline - previous.baseline <= 1.6 * row.size:
                row.kind = "cont"
                current.rows.append(row)
                continue
            current = None
            group = _close(group, groups)
            if _is_skills_line(row.text, section) or (skills and skills[-1].section == section and SKILL_LINE.match(row.text) and section):
                skills.append(Unit(rows=[row], section=section))
            elif skills and skills[-1].section == section and _continues_skills(row, skills[-1]):
                row.kind = "cont"
                skills[-1].rows.append(row)
            elif fresh:
                entry = row.first_column
                fresh = False
        _close(group, groups)
    return all_rows, groups, skills


def _continues_skills(row: Row, unit: Unit) -> bool:
    """A wrapped skills line: the next line, close below, near the same left edge."""
    last = unit.rows[-1]
    return (row.page == last.page and 0 < row.baseline - last.baseline <= 1.6 * row.size
            and not SKILL_LINE.match(row.text) and abs(row.x0 - unit.rows[0].x0) <= 2 * row.size)


def _is_skills_line(text: str, section: str) -> bool:
    """"Label: a, b, c" in a skills section, or a list of short items anywhere."""
    match = SKILL_LINE.match(text)
    if not match:
        return False
    if "skill" in section.lower():
        return True
    items = [item.strip() for item in match.group(2).split(",")]
    return len(items) >= 3 and all(0 < len(item.split()) <= 3 for item in items)


def _style_of(row: Row) -> tuple:
    counts: dict = {}
    for c, _, _, span in row.chars:
        if c.strip():
            key = (span["font"], round(span["size"], 1))
            counts[key] = counts.get(key, 0) + 1
    return max(counts, key=counts.get) if counts else ()


def _close(group: list[Unit], groups: list[list[Unit]]) -> list[Unit]:
    if len(group) > 1:
        groups.append(group)
    return []


# ---------------------------------------------------------------- fonts


BASE_FONTS = {
    ("sans", False, False): "helv", ("sans", True, False): "hebo", ("sans", False, True): "heit", ("sans", True, True): "hebi",
    ("serif", False, False): "tiro", ("serif", True, False): "tibo", ("serif", False, True): "tiit", ("serif", True, True): "tibi",
    ("mono", False, False): "cour", ("mono", True, False): "cobo", ("mono", False, True): "coit", ("mono", True, True): "cobi",
}


class Fonts:
    """Loads the PDF's own fonts by name, so new text matches the original."""

    def __init__(self, doc):
        self.doc = doc
        self.cache: dict = {}
        self.used: dict = {}  # (page, font name) -> {unicode: glyph id} as the PDF draws them

    def _used(self, page_index: int, name: str) -> dict[int, int]:
        if page_index not in {key[0] for key in self.used}:
            for span in self.doc[page_index].get_texttrace():
                mapping = self.used.setdefault((page_index, span["font"].split("+")[-1]), {})
                for code, glyph, *_ in span["chars"]:
                    if glyph > 0 and 32 <= code < 0xFFFD:
                        mapping.setdefault(code, glyph)
            self.used.setdefault((page_index, ""), {})
        return self.used.get((page_index, name), {})

    def get(self, page_index: int, name: str):
        key = (page_index, name)
        if key in self.cache:
            return self.cache[key]
        import pymupdf

        font = None
        for xref, ext, kind, basefont, *_ in self.doc[page_index].get_fonts():
            if basefont.split("+")[-1] != name:
                continue
            if ext == "n/a" and kind in ("Type1", "TrueType"):
                lower = name.lower()
                family = "mono" if "courier" in lower else "serif" if "times" in lower else "sans" if ("helvetica" in lower or "arial" in lower) else ""
                if family:
                    font = pymupdf.Font(BASE_FONTS[(family, "bold" in lower, "italic" in lower or "oblique" in lower)])
            elif ext in ("ttf", "otf", "cff", "pfa", "pfb", "cid"):
                try:
                    buffer = self.doc.extract_font(xref)[3]
                    font = pymupdf.Font(fontbuffer=buffer) if buffer else None
                    used = self._used(page_index, name)
                    if font is not None and ext == "ttf" and used and not all(font.has_glyph(code) for code in used):
                        # Subset fonts often drop their letter map. Rebuild it from the
                        # letters this PDF draws with the font.
                        font = pymupdf.Font(fontbuffer=with_cmap(buffer, used))
                except Exception:
                    font = None
            break
        self.cache[key] = font
        return font


def with_cmap(font_data: bytes, mapping: dict[int, int]) -> bytes:
    """Return a TrueType font with its 'cmap' table replaced by mapping {unicode: glyph id}."""
    import struct

    count = struct.unpack(">H", font_data[4:6])[0]
    tables = {}
    for index in range(count):
        tag, _, offset, length = struct.unpack(">4sIII", font_data[12 + 16 * index: 28 + 16 * index])
        tables[tag] = font_data[offset: offset + length]
    codes = sorted(code for code in mapping if code <= 0xFFFF)
    segments = [(code, code, (mapping[code] - code) % 65536) for code in codes] + [(0xFFFF, 0xFFFF, 1)]
    seg_count = len(segments)
    search = 2 ** (seg_count.bit_length() - 1)
    body = struct.pack(">HHHH", seg_count * 2, search * 2, search.bit_length() - 1, seg_count * 2 - search * 2)
    body += b"".join(struct.pack(">H", end) for _, end, _ in segments) + b"\0\0"
    body += b"".join(struct.pack(">H", start) for start, _, _ in segments)
    body += b"".join(struct.pack(">H", delta) for _, _, delta in segments)
    body += b"\0\0" * seg_count
    subtable = struct.pack(">HHH", 4, 6 + len(body), 0) + body
    tables[b"cmap"] = struct.pack(">HHHHI", 0, 1, 3, 1, 12) + subtable
    tags = sorted(tables)
    header = font_data[:4] + struct.pack(">HHHH", len(tags), *_search_fields(len(tags)))
    directory, data = b"", b""
    offset = 12 + 16 * len(tags)
    for tag in tags:
        table = tables[tag]
        padded = table + b"\0" * (-len(table) % 4)
        checksum = sum(struct.unpack(">%dI" % (len(padded) // 4), padded)) & 0xFFFFFFFF
        directory += struct.pack(">4sIII", tag, checksum, offset + len(data), len(table))
        data += padded
    return header + directory + data


def _search_fields(count: int) -> tuple[int, int, int]:
    power = 2 ** (count.bit_length() - 1)
    return power * 16, power.bit_length() - 1, count * 16 - power * 16


def _style(unit: Unit, start_x: float):
    """(font name, size, color) of the unit's words, or None if they mix styles."""
    styles = {(span["font"], round(span["size"], 2), span["color"]) for row in unit.rows for c, bbox, _, span in row.chars if c.strip() and bbox[0] >= (start_x if row is unit.rows[0] else row.x0) - 0.5}
    return styles.pop() if len(styles) == 1 else None


def _faithful(font, unit: Unit, start_x: float, size: float) -> bool:
    """True if the font draws the unit's own letters at the widths the PDF shows."""
    checked = 0
    for row in unit.rows:
        chars = row.chars
        for index, (c, bbox, *_) in enumerate(chars):
            if not c.strip() or bbox[0] < (start_x if row is unit.rows[0] else row.x0) - 0.5:
                continue
            if not font.has_glyph(ord(c)):
                return False
            # Letters drawn as one ligature ("fi") share a box; their widths can't be compared.
            following = chars[index + 1] if index + 1 < len(chars) else None
            if following is not None and (following[1][0] < bbox[2] - 0.3 or following[1][2] - following[1][0] < 0.3 or (c == "f" and following[0] in "fil")):
                continue
            if index and (bbox[2] - bbox[0] < 0.3 or (chars[index - 1][0] == "f" and c in "fil")):
                continue
            width = bbox[2] - bbox[0]
            if abs(font.glyph_advance(ord(c)) * size - width) > max(0.08 * width, 0.25):
                return False
            checked += 1
    return checked > 0


def body_start(unit: Unit) -> float:
    """Where a bullet's plain words start: after a bold or italic lead-in such as "Skills:"."""
    first = unit.rows[0]
    chars = [ch for ch in first.chars if ch[0].strip() and ch[1][0] >= first.text_x0 - 0.5]
    if not chars:
        return first.text_x0
    styles = [(ch[3]["font"], round(ch[3]["size"], 1)) for ch in chars]
    rest = {(ch[3]["font"], round(ch[3]["size"], 1)) for row in unit.rows[1:] for ch in row.chars if ch[0].strip()}
    change = next((index for index, style in enumerate(styles) if style != styles[0]), None)
    if change is None:
        return first.text_x0
    body = styles[change]
    if any(style != body for style in styles[change:]) or (rest and rest != {body}) or change > 0.6 * len(chars):
        return first.text_x0
    return chars[change][1][0]


def text_from(unit: Unit, start_x: float) -> str:
    first = unit.rows[0]
    words = _join([ch for ch in first.chars if ch[1][0] >= start_x - 0.5], first.size)
    return " ".join([words] + [row.words_text() for row in unit.rows[1:]]).strip()


def _space_width(unit: Unit, start_x: float, font, size: float) -> float:
    gaps = []
    for row in unit.rows:
        chars = [ch for ch in row.chars if ch[1][0] >= (start_x if row is unit.rows[0] else row.x0) - 0.5]
        for left, right in zip(chars, chars[1:]):
            if left[0].strip() and right[0].strip() and right[1][0] - left[1][2] > 0.15 * size:
                gaps.append(right[1][0] - left[1][2])
            elif left[0] == " " and right[0].strip():
                previous = chars[chars.index(left) - 1] if chars.index(left) else None
                if previous and previous[0].strip():
                    gaps.append(right[1][0] - previous[1][2])
    if gaps:
        return statistics.median(gaps)
    return font.glyph_advance(32) * size if font.has_glyph(32) else 0.3 * size


# ---------------------------------------------------------------- layout of new text


def _lines_for(text: str, font, size: float, space: float, widths: list[float]) -> list[list[str]] | None:
    """Wrap words into at most len(widths) lines; None if they don't fit."""
    lines: list[list[str]] = [[]]
    used = 0.0
    for word in text.split():
        length = font.text_length(word, fontsize=size)
        needed = length if not lines[-1] else used + space + length
        if needed <= widths[len(lines) - 1] + 0.5:
            lines[-1].append(word)
            used = needed
            continue
        if not lines[-1] or len(lines) == len(widths):
            return None
        lines.append([word])
        used = length
    return lines


def _right_edge(unit: "Unit", rows: list[Row]) -> float:
    """How far right new text may go: the page's text margin, or the start of anything
    beside the unit, such as a second column."""
    page_rows = [row for row in rows if row.page == unit.page and row.kind != "other"]
    edge = max(row.x1 for row in page_rows)
    own = {id(row) for row in unit.rows}
    for row in page_rows:
        if id(row) in own or row.x0 <= unit.rows[0].text_x0:
            continue
        if row.y1 > unit.top + 0.5 and row.y0 < unit.bottom - 0.5:
            edge = min(edge, row.x0 - 0.5 * row.size)
    return edge


def fit(unit: Unit, text: str, start_x: float, fonts: Fonts, right: float):
    """How to draw text in the unit's rows, or a reason it can't be drawn exactly."""
    style = _style(unit, start_x)
    if not style:
        return None, "it mixes fonts"
    name, size, color = style
    font = fonts.get(unit.page, name)
    if font is None:
        return None, "its font can't be reused"
    if not _faithful(font, unit, start_x, size):
        return None, "its font can't be reused"
    missing = sorted({c for c in text if c.strip() and not font.has_glyph(ord(c))})
    if missing:
        return None, "the resume's font doesn't include " + " ".join(missing)
    space = _space_width(unit, start_x, font, size)
    starts = [start_x] + [row.x0 for row in unit.rows[1:]]
    widths = [right - x for x in starts]
    lines = _lines_for(text, font, size, space, widths)
    if lines is None:
        return None, "it's too long for the space"
    return {"font": font, "size": size, "color": color, "space": space, "starts": starts, "lines": lines}, ""


# ---------------------------------------------------------------- planning changes


def plan_reorder(groups: list[list[Unit]], skills: list[Unit], job_text: str, fonts: Fonts, rows: list[Row], plan: Plan) -> None:
    weights = _job_weights(job_text)
    for group in groups:
        ordered = sorted(group, key=lambda unit: -_score(unit.text, weights))
        if [id(u) for u in ordered] == [id(u) for u in group]:
            continue
        # Keep the group's spacing: line spacing inside a bullet, and the space between
        # bullets, stay as they were, measured baseline to baseline.
        gaps = [after.rows[0].baseline - before.rows[-1].baseline for before, after in zip(group, group[1:])]
        baseline = group[0].rows[0].baseline
        for index, unit in enumerate(ordered):
            dy = baseline - unit.rows[0].baseline
            if abs(dy) > 0.01:
                plan.moves[id(unit)] = dy
            baseline += unit.rows[-1].baseline - unit.rows[0].baseline + (gaps[index] if index < len(gaps) else 0)
        plan.changes.append(f"{short(group[0].entry or group[0].section, 60)}: moved \"{short(ordered[0].text, 70)}\" to the top")
    for unit in skills:
        line = unit.text
        match = SKILL_LINE.match(line)
        if not match:
            continue
        parts = [part.strip() for part in match.group(2).split(",")]
        if len(parts) < 2 or not all(parts):
            continue
        ordered = sorted(parts, key=lambda part: -_score(part, weights))
        if ordered == parts:
            continue
        start = _list_start(unit)
        if start is None:
            continue
        drawn, reason = fit(unit, ", ".join(ordered), start, fonts, _right_edge(unit, rows))
        if drawn:
            plan.rewrites[id(unit)] = Rewrite(", ".join(ordered), start)
            plan.changes.append(f"{match.group(1)}: put matching skills first")


def _list_start(unit: Unit) -> float | None:
    """x where a skills line's list starts, after "Label:"."""
    chars = unit.rows[0].chars
    for index, ch in enumerate(chars):
        if ch[0] == ":":
            for after in chars[index + 1:]:
                if after[0].strip():
                    return after[1][0]
    return None


def add_skills(skills: list[Unit], extra: list[str], job_text: str, fonts: Fonts, rows: list[Row], plan: Plan) -> list[str]:
    """Add skills the applicant confirmed to the best-matching skills line. Returns notes."""
    notes = []
    weights = _job_weights(job_text)
    wanted = [skill.strip() for skill in extra if skill.strip()]
    if not wanted:
        return notes
    if not skills:
        return ["Couldn't add skills: no \"Label: a, b, c\" skills line was found."]
    def preference(unit: Unit) -> tuple:
        label = SKILL_LINE.match(unit.text).group(1).lower()
        if re.search(r"tool|technolog|framework|software|platform|librar|skill|technical", label):
            return (0, -_score(unit.text, weights))
        return (2 if "language" in label else 1, -_score(unit.text, weights))

    ranked = sorted(skills, key=preference)
    last_reason = "no skills line has room"
    for skill in wanted:
        placed = False
        for unit in ranked:
            start = _list_start(unit)
            if start is None:
                continue
            current = plan.rewrites[id(unit)].text if id(unit) in plan.rewrites else SKILL_LINE.match(unit.text).group(2)
            if skill.lower() in [part.strip().lower() for part in current.split(",")]:
                placed = True
                break
            text = current.rstrip() + ", " + skill
            drawn, reason = fit(unit, text, start, fonts, _right_edge(unit, rows))
            if drawn:
                plan.rewrites[id(unit)] = Rewrite(text, start)
                plan.changes.append(f"Added {skill} to {SKILL_LINE.match(unit.text).group(1)}")
                placed = True
                break
            last_reason = reason
        if not placed:
            notes.append(f"Couldn't add {skill}: {last_reason if ranked else 'no skills line'}.")
    return notes


# ---------------------------------------------------------------- drawing


def _strip_copy(work, source_index: int, keep: list[Row], rows: list[Row], shapes: bool = False) -> int:
    """Copy a page with only the given rows' text left on it. Returns the copy's page number.

    Shapes (lines, dots) stay only when asked: the bottom layer already draws the ones
    that don't move, and drawing them twice would darken them.
    """
    import pymupdf

    work.fullcopy_page(source_index)
    page = work[-1]
    kept = {id(row) for row in keep}
    for row in rows:
        if row.page == source_index and id(row) not in kept:
            _strip_rect(page, pymupdf.Rect(row.x0 - 1, 0, row.x1 + 1, 0), row)
    if page.first_annot:
        page.apply_redactions(images=0, graphics=0)
    if not shapes:
        page.add_redact_annot(page.rect, fill=False)
        page.apply_redactions(images=1, graphics=1, text=1)
    return page.number


def _strip_rect(page, rect, row: Row) -> None:
    import pymupdf

    # A thin strip through the middle of the letters touches this row only.
    top = row.baseline - 0.45 * row.size
    bottom = row.baseline - 0.15 * row.size
    page.add_redact_annot(pymupdf.Rect(rect.x0, top, rect.x1, bottom), fill=False)


def _band(rows_in: list[Row], page_rect) -> "Rect":
    import pymupdf

    top = min(row.y0 for row in rows_in) - 1
    bottom = max(row.y1 for row in rows_in) + 1
    return pymupdf.Rect(page_rect.x0, top, page_rect.x1, bottom)


def render(doc, rows: list[Row], units: list[Unit], plan: Plan, fonts: Fonts) -> bytes:
    import pymupdf

    by_row = {id(row): unit for unit in units for row in unit.rows}
    changed_pages = sorted({unit.page for unit in units if id(unit) in plan.moves or id(unit) in plan.rewrites})
    out = pymupdf.open()
    work = pymupdf.open()
    work.insert_pdf(doc)
    for index, page in enumerate(doc):
        if index not in changed_pages:
            out.insert_pdf(doc, from_page=index, to_page=index)
            continue
        page_rows = [row for row in rows if row.page == index]
        target = out.new_page(width=page.rect.width, height=page.rect.height)
        # Layer 1: the page's lines, shapes, and images, without text. Shapes that belong
        # to a moved or reworded bullet (a drawn dot, an underline) move with it instead.
        work.fullcopy_page(index)
        base = work[-1]
        for unit in units:
            if unit.page == index and (id(unit) in plan.moves or id(unit) in plan.rewrites):
                base.add_redact_annot(pymupdf.Rect(unit.rows[0].x0 - 1, unit.top, max(r.x1 for r in unit.rows) + 1, unit.bottom), fill=False)
        if base.first_annot:
            base.apply_redactions(images=0, graphics=1, text=0)
        base.add_redact_annot(base.rect, fill=False)
        base.apply_redactions(images=0, graphics=0, text=0)
        target.show_pdf_page(target.rect, work, base.number)
        # Layer 2: text, band by band in reading order.
        # Draw bands in their new top-to-bottom order, so text extraction (and
        # applicant tracking systems) read the bullets in the new order too.
        bands: list = []
        seen: set = set()
        for row in page_rows:
            unit = by_row.get(id(row))
            if unit is None:
                bands.append((row.y0, row, None))
            elif id(unit) not in seen:
                seen.add(id(unit))
                bands.append((unit.top + plan.moves.get(id(unit), 0.0), None, unit))
        bands.sort(key=lambda band: band[0])
        for _, row, unit in bands:
            if unit is None or (id(unit) not in plan.moves and id(unit) not in plan.rewrites):
                band_rows = [row] if unit is None else unit.rows
                copy = _strip_copy(work, index, band_rows, rows)
                clip = _band(band_rows, page.rect)
                target.show_pdf_page(clip, work, copy, clip=clip)
                continue
            dy = plan.moves.get(id(unit), 0.0)
            rewrite = plan.rewrites.get(id(unit))
            if rewrite is None:
                copy = _strip_copy(work, index, unit.rows, rows, shapes=True)
                clip = _band(unit.rows, page.rect)
                target.show_pdf_page(clip + (0, dy, 0, dy), work, copy, clip=clip)
                continue
            first = unit.rows[0]
            # Keep what comes before the new words (the bullet mark or "Label:") exactly.
            copy = _strip_copy(work, index, [first], rows, shapes=True)
            prefix = pymupdf.Rect(page.rect.x0, first.y0 - 1, rewrite.start_x - 0.2, first.y1 + 1)
            _strip_prefix_copy(work, copy, first, rewrite.start_x)
            target.show_pdf_page(prefix + (0, dy, 0, dy), work, copy, clip=prefix)
            drawn, _ = fit(unit, rewrite.text, rewrite.start_x, fonts, _right_edge(unit, rows))
            writer = pymupdf.TextWriter(target.rect)
            font, size = drawn["font"], drawn["size"]
            # Real spaces keep the words apart for text readers; fonts without a space
            # (TeX's) place each word at the original spacing instead.
            real_spaces = font.has_glyph(32) and abs(font.glyph_advance(32) * size - drawn["space"]) <= 0.15 * drawn["space"]
            for line_index, words in enumerate(drawn["lines"]):
                x = drawn["starts"][line_index]
                baseline = unit.rows[line_index].baseline + dy
                if real_spaces:
                    writer.append((x, baseline), " ".join(words), font=font, fontsize=size)
                    continue
                for word in words:
                    writer.append((x, baseline), word, font=font, fontsize=size)
                    x += font.text_length(word, fontsize=size) + drawn["space"]
            writer.write_text(target, color=pymupdf.sRGB_to_pdf(drawn["color"]))
        # Links keep working: unchanged ones stay, moved ones move, reworded ones go.
        for link in page.get_links():
            rect = pymupdf.Rect(link["from"])
            owner = next((u for u in units if u.page == index and u.top - 1 <= rect.y0 and rect.y1 <= u.bottom + 1), None)
            if owner is not None and id(owner) in plan.rewrites:
                continue
            if owner is not None and id(owner) in plan.moves:
                link["from"] = rect + (0, plan.moves[id(owner)], 0, plan.moves[id(owner)])
            link.pop("xref", None)
            link.pop("id", None)
            try:
                target.insert_link(link)
            except Exception:
                pass
    out.set_metadata(doc.metadata or {})
    return out.tobytes(garbage=3, deflate=True)


def _strip_prefix_copy(work, page_number: int, row: Row, start_x: float) -> None:
    """On a copy holding one row, remove the words after start_x, keeping the mark or label."""
    import pymupdf

    page = work[page_number]
    _strip_rect(page, pymupdf.Rect(start_x - 0.2, 0, row.x1 + 1, 0), row)
    page.apply_redactions(images=0, graphics=0)


# ---------------------------------------------------------------- entry point


def tailor_pdf(data: bytes, job_text: str, extra_skills: list[str] | None = None, rewriter=None) -> dict:
    """Edit the resume PDF for a job. Returns {"pdf", "changes", "notes", "ai"} or raises ValueError.

    rewriter(candidates) returns {id: new text} for some of the candidates, each
    {"id", "text", "max_chars"}; resume_ai.suggest_rewrites is the real one.
    """
    import pymupdf

    try:
        doc = pymupdf.open(stream=data, filetype="pdf")
    except Exception as error:
        raise ValueError("Couldn't open that PDF.") from error
    if doc.needs_pass or doc.is_encrypted:
        raise ValueError("That PDF is password-protected.")
    rows, groups, skills = _units(doc)
    if not rows:
        raise ValueError("That PDF has no text to edit. It may be a scan.")
    if not any(row.kind == "heading" for row in rows):
        raise ValueError("Couldn't find resume sections such as Experience or Education. Try a PDF exported from a document, not a scan.")
    fonts = Fonts(doc)
    plan = Plan()
    notes: list[str] = []
    plan_reorder(groups, skills, job_text, fonts, rows, plan)
    notes.extend(add_skills(skills, list(extra_skills or []), job_text, fonts, rows, plan))
    bullets = [unit for group in groups for unit in group]
    ai = "off"
    if rewriter is not None and bullets:
        ai, ai_notes = _reword(bullets, job_text, fonts, rows, plan, rewriter)
        notes.extend(ai_notes)
    if not plan.moves and not plan.rewrites:
        return {"pdf": data, "changes": [], "notes": notes, "ai": ai}
    pdf = render(doc, rows, bullets + skills, plan, fonts)
    return {"pdf": pdf, "changes": plan.changes, "notes": notes, "ai": ai}


def _reword(bullets: list[Unit], job_text: str, fonts: Fonts, rows: list[Row], plan: Plan, rewriter) -> tuple[str, list[str]]:
    from resume_pdf import load_sibling

    check_rewrite = load_sibling("resume_ai").check_rewrite

    weights = _job_weights(job_text)
    resume_text = " ".join(row.text for row in rows)
    candidates = []
    for index, unit in enumerate(sorted(bullets, key=lambda unit: -_score(unit.text, weights))[:8]):
        start = body_start(unit)
        style = _style(unit, start)
        if not style:
            continue
        font = fonts.get(unit.page, style[0])
        if font is None or not _faithful(font, unit, start, style[1]):
            continue
        right = _right_edge(unit, rows)
        room = sum(right - x for x in [start] + [row.x0 for row in unit.rows[1:]])
        body = text_from(unit, start)
        used = font.text_length(body, fontsize=style[1])
        max_chars = int(len(body) * min(room / max(used, 1), 1.3))
        candidates.append({"id": str(index), "text": body, "max_chars": max_chars, "unit": unit, "start": start})
    if not candidates:
        return "skipped", ["Reworded bullets were skipped: the resume's fonts can't be reused for new text."]
    try:
        proposals = rewriter([{key: c[key] for key in ("id", "text", "max_chars")} for c in candidates]) or {}
    except Exception:
        return "failed", ["The AI rewording didn't respond, so only the reordering was done."]
    notes = []
    used_count = 0
    for candidate in candidates:
        new = str(proposals.get(candidate["id"]) or "").strip()
        if not new or new == candidate["text"]:
            continue
        problem = check_rewrite(candidate["text"], new, resume_text, job_text)
        if problem:
            notes.append(f"Skipped a rewording of \"{short(candidate['text'], 50)}\": {problem}.")
            continue
        drawn, reason = fit(candidate["unit"], new, candidate["start"], fonts, _right_edge(candidate["unit"], rows))
        if not drawn:
            notes.append(f"Skipped a rewording of \"{short(candidate['text'], 50)}\": {reason}.")
            continue
        plan.rewrites[id(candidate["unit"])] = Rewrite(new, candidate["start"])
        plan.changes.append(f"Reworded \"{short(candidate['text'], 80)}\" to \"{new}\"")
        used_count += 1
    return ("used" if used_count else "none"), notes

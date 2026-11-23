#!/usr/bin/env python3
"""Build a clean JSON corpus of A Course in Miracles (1975 first edition) from English Wikisource."""
import hashlib, html, json, re, ssl, sys, time, urllib.parse, urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".cache" / "wikisource"
OUT = ROOT / "ACIMAudio" / "Resources" / "acim.json"
API = "https://en.wikisource.org/w/api.php"
UA = "ACIMReaderCorpusBuilder/1.0 (offline corpus build; public-domain text)"
PREFIX = "A Course in Miracles"
DELAY = 1.0


def ssl_ctx():
    # python.org builds on macOS ship without CA roots; fall back to the system bundle.
    ctx = ssl.create_default_context()
    if not ctx.get_ca_certs():
        for c in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
            if Path(c).exists():
                return ssl.create_default_context(cafile=c)
    return ctx


def api_get(params):
    q = urllib.parse.urlencode(params)
    key = hashlib.sha1(q.encode()).hexdigest()
    f = CACHE / (key + ".json")
    if f.exists():
        return json.loads(f.read_text("utf-8"))
    CACHE.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(API + "?" + q, headers={"User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60, context=ssl_ctx()) as r:
                data = r.read().decode("utf-8")
            break
        except Exception as e:
            print("retry", attempt, e, file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit("fetch failed")
    f.write_text(data, "utf-8")
    time.sleep(DELAY)
    return json.loads(data)


def fetch_all():
    pages = {}
    params = {"action": "query", "generator": "allpages", "gapprefix": PREFIX, "gaplimit": 50,
              "prop": "revisions", "rvprop": "content", "rvslots": "main", "format": "json"}
    cont = {}
    while True:
        d = api_get({**params, **cont})
        for p in d.get("query", {}).get("pages", {}).values():
            rev = p.get("revisions")
            if rev:
                pages[p["title"]] = rev[0]["slots"]["main"]["*"]
        if "continue" in d:
            cont = d["continue"]
        else:
            break
    return pages

# ---------------------------------------------------------------- cleanup

def norm_title(t):
    return re.sub(r"\s+", " ", t.replace("_", " ")).strip().lower()


def parse_header(text):
    """Read the {{header|...}} template (before it is discarded) into a dict."""
    m = re.search(r"\{\{\s*header\b(.*?)\n\}\}", text, re.S | re.I)
    out = {}
    if m:
        for line in m.group(1).split("\n"):
            mm = re.match(r"\s*\|\s*(\w+)\s*=(.*)$", line)
            if mm:
                out[mm.group(1).lower()] = clean_inline(mm.group(2)).strip()
    return out


def strip_templates(t):
    prev = None
    while prev != t:
        prev = t
        t = re.sub(r"\{\{[^{}]*\}\}", "", t)
    return t


def clean_inline(t):
    t = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", t)  # [[a|b]] -> b, [[a]] -> a
    t = re.sub(r"'{2,}", "", t)  # bold/italic markup
    t = re.sub(r"<[^>\n]*>", "", t)
    t = html.unescape(t).replace(" ", " ")
    return re.sub(r"[ \t]+", " ", t).strip()


def clean_page(text):
    """Return (sections, paragraphs) for one page's wikitext.

    sections: list of {"roman","title","paragraphs"} in reading order; text before the first
    heading goes into a leading section with empty roman/title (only if non-empty).
    paragraphs: the same paragraphs flattened."""
    t = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    t = strip_templates(t)
    t = re.sub(r"<table\b.*?</table>", "", t, flags=re.S | re.I)
    t = re.sub(r"__[A-Z]+__", "", t)
    t = re.sub(r"<br\s*/?>", "\n", t, flags=re.I)
    t = re.sub(r"</?blockquote[^>]*>", "\n", t, flags=re.I)
    t = re.sub(r"<[^>\n]*>", "", t)
    t = t.replace("\r", "")
    sections, paras, block, indented = [], [], [], False
    cur = {"roman": "", "title": "", "paragraphs": []}

    def emit(txt):
        paras.append(txt)
        cur["paragraphs"].append(txt)

    def flush():
        nonlocal block, indented
        if block:
            txt = ("\n" if indented else " ").join(block)
            txt = re.sub(r"[ \t]+", " ", txt).strip()
            if len(txt) >= 2:
                emit(txt)
        block, indented = [], False

    for raw in t.split("\n"):
        line = raw.strip()
        if not line or re.fullmatch(r"-{4,}", line):
            flush()
            continue
        hm = re.fullmatch(r"(={2,6})\s*(.*?)\s*\1", line)
        if hm:
            flush()
            sec = clean_inline(hm.group(2))
            if len(hm.group(1)) >= 4 and not re.match(r"^[IVXLC]+\.\s", sec):
                continue  # unnumbered sub-subheading (e.g. "A. Special Principles..."): stays inside its section
            if sec:
                if cur["paragraphs"]:
                    sections.append(cur)
                rm = re.match(r"^([IVXLC]+)\.\s*(.*)$", sec)
                cur = {"roman": rm.group(1) if rm else "", "title": rm.group(2).strip() if rm else sec,
                       "paragraphs": []}
            continue
        if line.startswith("#"):
            flush()
            body = clean_inline(line.lstrip("#"))
            if len(body) >= 2:
                emit(body)
            continue
        m = re.match(r"^([:*;]+)\s*(.*)$", line)
        if m:
            indented = True
            line = m.group(2)
        line = clean_inline(line)
        if line:
            block.append(line)
    flush()
    if cur["paragraphs"]:
        sections.append(cur)
    return sections, paras


# ---------------------------------------------------------------- index parsing

INDEX_HEAD = re.compile(r"^=+\s*\[\[(.+?)\]\]\s*=+\s*$")
INDEX_ITEM = re.compile(r"^[:*]+\s*(?:(\d+(?:\s*-\s*\d+)?)\.?\s+)?\[\[(.+?)\]\]\s*$")


def link_parts(inner):
    inner = inner.strip()
    target, label = inner.split("|", 1) if "|" in inner else (inner, inner)
    target = target.strip().strip("/").strip()
    label = label.strip().strip("/").strip()
    return target, (label or target)


def parse_index(text):
    """Ordered list of (number, target, title) from an index page."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = strip_templates(text)
    entries = []
    for raw in text.split("\n"):
        line = raw.strip()
        m = INDEX_HEAD.match(line)
        if m:
            target, label = link_parts(m.group(1))
            entries.append((0, target, label))
            continue
        m = INDEX_ITEM.match(line)
        if not m:
            continue
        num, inner = m.group(1), m.group(2)
        target, label = link_parts(inner)
        n = int(re.match(r"\d+", num).group(0)) if num else 0
        entries.append((n, target, label))
    return entries


def build():
    pages = fetch_all()
    lookup = {norm_title(t): t for t in pages}
    used = set()
    chapters, notes, seclog = [], [], []

    def get(title):
        key = norm_title(title)
        if key not in lookup:
            notes.append("MISSING PAGE: " + title)
            return None
        used.add(lookup[key])
        return pages[lookup[key]]

    def add(part, number, title, text):
        secs, paras = clean_page(text)
        seclog.append(len(secs))
        if part != "text" and part != "manual" or len(secs) <= 1 and not any(x["roman"] or x["title"] for x in secs):
            secs = [{"roman": "", "title": "", "paragraphs": paras}] if paras else []
        if not paras:
            notes.append("EMPTY: %s %s" % (part, title))
            return
        chapters.append({"part": part, "number": number, "title": title,
                         "sections": [{"number": i + 1, **x} for i, x in enumerate(secs)]})

    for t in (PREFIX, PREFIX + "/Text", PREFIX + "/Workbook for Students", PREFIX + "/Manual for Teachers",
              PREFIX + "/Text/Table of Contents"):
        get(t)

    # Text: Introduction, then Chapters 1-31; chapter titles come from the header template
    text_titles = {}
    for _, tgt, lab in parse_index(pages[PREFIX + "/Text"]):
        mm = re.search(r"(\d+)$", tgt)
        if mm:
            text_titles[int(mm.group(1))] = lab
    add("text", 0, "Introduction", get(PREFIX + "/Text/Introduction"))
    for n in range(1, 32):
        src = get("%s/Text/Chapter %d" % (PREFIX, n))
        if src is None:
            continue
        add("text", n, parse_header(src).get("section") or text_titles.get(n, "Chapter %d" % n), src)

    # Workbook and Manual: ordering and titles from the index pages
    for part, base in (("workbook", PREFIX + "/Workbook for Students"), ("manual", PREFIX + "/Manual for Teachers")):
        for num, target, title in parse_index(pages[base]):
            src = get(base + "/" + target)
            if src is not None:
                add(part, num, title, src)

    unused = sorted(set(pages) - used)
    return chapters, unused, notes, sum(1 for x in seclog if x > 1)


def main():
    chapters, unused, notes, with_sections = build()
    doc = {
        "edition": "A Course in Miracles — first edition (1975)",
        "source": "English Wikisource, https://en.wikisource.org/wiki/A_Course_in_Miracles",
        "license": "Public domain in the US (published without copyright notice; Penguin Books USA v. New Christian "
                   "Church of Full Endeavor, 288 F. Supp. 2d 544, S.D.N.Y. 2003)",
        "retrieved": date.today().isoformat(),
        "chapters": chapters,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")

    # ---- verification
    data = json.loads(OUT.read_text("utf-8"))
    bad = ["{{", "}}", "[[", "]]", "<!--", "__NOTOC__", "''"]
    npar = nchar = 0
    per, secs = {}, {}
    for c in data["chapters"]:
        assert c["part"] in ("text", "workbook", "manual") and c["title"].strip() and c["sections"]
        per[c["part"]] = per.get(c["part"], 0) + 1
        secs[c["part"]] = secs.get(c["part"], 0) + len(c["sections"])
        for i, sec in enumerate(c["sections"]):
            assert sec["number"] == i + 1 and sec["paragraphs"]
            for p in sec["paragraphs"]:
                assert len(p) >= 2 and p.strip() == p, repr(p[:40])
                for b in bad:
                    assert b not in p, (c["title"], b, p[:80])
                assert not re.search(r"<[a-zA-Z/!]|&\w+;", p), (c["title"], p[:80])
                npar += 1
                nchar += len(p)
    print("chapters per part:", per)
    print("sections per part:", secs)
    print("paragraphs:", npar, "characters:", nchar)
    for c in data["chapters"]:
        if c["part"] == "text":
            print("text", c["number"], len(c["sections"]), ",".join(x["roman"] or "-" for x in c["sections"]))
    print("manual chapters with >1 section:", [(c["title"][:30], len(c["sections"])) for c in data["chapters"]
                                              if c["part"] == "manual" and len(c["sections"]) > 1])
    print("file size:", OUT.stat().st_size, "bytes")
    print("notes:", notes)
    print("unused pages:", unused)


if __name__ == "__main__":
    main()

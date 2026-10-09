"""TCVN3 / ABC (TCVN 5712:1993, fonts .VnTime, .VnArial...) -> Unicode for texts drawn with TCVN3 fonts.

TCVN3 fonts are 8-bit: Vietnamese letters sit at codes 0xA1-0xFE, so a DWG stores them as the ANSI
characters of those codes ("®\xadêng ®Êt" = "đường đất") and AutoCAD shows them right only when the .Vn font
is installed. Decoding is driven by the font, not by guessing: whatever is drawn in a TCVN3 font is shown
through this table. Fonts whose family name ends in "H" (.VnTimeH, .VnArialH) are all-caps fonts.
"""
import codecs
import re

_BYTES = bytes.fromhex(
    "B8B5B6B7B9" "A8" "BEBBBCBDC6" "A9" "CAC7C8C9CB"  # a ă â (acute, grave, hook, tilde, dot)
    "D0CCCECFD1" "AA" "D5D2D3D4D6"                    # e ê
    "DDD7D8DCDE"                                      # i
    "E3DFE1E2E4" "AB" "E8E5E6E7E9" "AC" "EDEAEBECEE"  # o ô ơ
    "F3EFF1F2F4" "AD" "F8F5F6F7F9"                    # u ư
    "FDFAFBFCFE" "AE"                                 # y đ
    "A1A2A7A3A4A5A6")                                 # Ă Â Đ Ê Ô Ơ Ư
_UNI = ("áàảãạ" "ă" "ắằẳẵặ" "â" "ấầẩẫậ"
        "éèẻẽẹ" "ê" "ếềểễệ"
        "íìỉĩị"
        "óòỏõọ" "ô" "ốồổỗộ" "ơ" "ớờởỡợ"
        "úùủũụ" "ư" "ứừửữự"
        "ýỳỷỹỵ" "đ"
        "ĂÂĐÊÔƠƯ")
assert len(_BYTES) == len(_UNI)
BYTE_TO_UNI = dict(zip(_BYTES, _UNI))

# Unicode fonts used instead (installed with Windows); ezdxf matches them by family name.
# Arial Narrow is not used: the copies shipped with Windows/Office lack most Vietnamese letters (ư, ơ, ấ...),
# so narrow fonts become Arial squeezed to 0.82 of its width, the proportion of Arial Narrow.
SUBSTITUTES = (("narrow", "Arial", 0.82), (".vntime", "Times New Roman", 1.0), ("vntime", "Times New Roman", 1.0),
               ("courier", "Courier New", 1.0))


def _base_name(font: str) -> str:
    return (font or "").strip().replace("\\", "/").split("/")[-1]


def is_tcvn3_font(font: str) -> bool:
    """Family names start with ".Vn"; font files are vn*.ttf (VNI files start with "vni" and are not TCVN3)."""
    n = _base_name(font).lower()
    if n.startswith(".vn"):
        return True
    if n.endswith((".ttf", ".otf")):
        stem = n.rsplit(".", 1)[0]
        return stem.startswith("vn") and not stem.startswith(("vni", "vn-", "vn_"))
    return False


def is_caps_font(font: str) -> bool:
    n = _base_name(font)
    if n.lower().endswith((".ttf", ".otf")):
        return n.rsplit(".", 1)[0].lower().endswith("h")
    return n.endswith("H")


def substitute(font: str) -> tuple[str, float]:
    """(Unicode font family, width factor that keeps the original letter width)."""
    n = _base_name(font).lower()
    for key, family, width in SUBSTITUTES:
        if key in n:
            return family, width
    return "Arial", 1.0


def python_codepage(doc) -> str:
    """$DWGCODEPAGE (e.g. ANSI_1252) -> codec that turns the stored characters back into font codes."""
    m = re.match(r"ANSI_(\d+)$", str(doc.header.get("$DWGCODEPAGE", "") or ""), re.I)
    cp = f"cp{m.group(1)}" if m else "cp1252"
    try:
        codecs.lookup(cp)
    except LookupError:
        cp = "cp1252"
    return cp


def _decode_char(ch: str, codepage: str) -> str:
    if ch < "\x80":
        return ch
    try:
        b = ch.encode(codepage)
    except UnicodeEncodeError:
        return ch  # real Unicode (e.g. typed with a Unicode keyboard): leave it
    return BYTE_TO_UNI.get(b[0], ch) if len(b) == 1 else ch


def decode_plain(s: str, caps: bool = False, codepage: str = "cp1252") -> str:
    out = "".join(_decode_char(c, codepage) for c in s)
    return out.upper() if caps else out


# %%nnn = character with font code nnn; %%c %%d %%p %%u %%o %%% are AutoCAD specials and stay as they are
_PCT = re.compile(r"%%(\d{3}|.)", re.S)


def decode_text(s: str, caps: bool = False, codepage: str = "cp1252") -> str:
    """TEXT / ATTRIB / ATTDEF content: decode the letters, keep the %% control codes intact."""
    out, pos = [], 0
    for m in _PCT.finditer(s):
        out.append(decode_plain(s[pos:m.start()], caps, codepage))
        code = m.group(1)
        if code.isdigit() and int(code) in BYTE_TO_UNI:
            u = BYTE_TO_UNI[int(code)]
            out.append(u.upper() if caps else u)
        else:
            out.append(m.group(0))
        pos = m.end()
    out.append(decode_plain(s[pos:], caps, codepage))
    return "".join(out)


_MTEXT_TOKEN = re.compile(
    r"(?P<font>\\[fF](?P<fname>[^|;]*)(?P<fargs>[^;]*);)"  # \fName|b0|i0|c0|p34;  \Ffile.shx;
    r"|(?P<stack>\\S)(?P<scont>[^;]*;)"                    # stacked text: visible, decoded like text
    r"|(?P<code>\\[ACHQTWacp][^;]*;)"                      # codes with arguments up to ';'
    r"|(?P<single>\\.)"                                    # \P \~ \L \\ \{ \} ...
    r"|(?P<brace>[{}])", re.S)


def decode_mtext(s: str, tcvn3: bool, caps: bool, codepage: str = "cp1252") -> str:
    """MTEXT content: follow inline font switches and { } groups; decode only the runs drawn in a TCVN3
    font and point those switches at a Unicode font."""
    out, pos, stack = [], 0, []
    state = (tcvn3, caps)

    def text(chunk):
        return decode_text(chunk, state[1], codepage) if state[0] else chunk

    for m in _MTEXT_TOKEN.finditer(s):
        out.append(text(s[pos:m.start()]))
        pos = m.end()
        if m.group("font") is not None:
            name = m.group("fname")
            if is_tcvn3_font(name):
                state = (True, is_caps_font(name))
                out.append(m.group(0)[:2] + substitute(name)[0] + m.group("fargs") + ";")
            else:
                state = (False, False)
                out.append(m.group(0))
        elif m.group("stack") is not None:
            out.append(m.group("stack") + text(m.group("scont")))
        elif m.group("brace") == "{":
            stack.append(state)
            out.append("{")
        elif m.group("brace") == "}":
            state = stack.pop() if stack else state
            out.append("}")
        else:
            out.append(m.group(0))
    out.append(text(s[pos:]))
    return "".join(out)


def fix_document(doc, log=print):
    """Re-encode TCVN3 texts to Unicode and point TCVN3 styles at Unicode fonts."""
    codepage = python_codepage(doc)
    styles = {}  # style name (lower) -> (caps, width factor)
    for st in doc.styles:
        family, italic, bold = st.get_extended_font_data()
        font = family if is_tcvn3_font(family) else st.dxf.font
        if not is_tcvn3_font(font):
            continue
        new_family, width = substitute(font)
        styles[st.dxf.name.lower()] = (is_caps_font(font), width)
        # an empty font file makes AutoCAD and ezdxf use the family stored in XDATA
        st.dxf.font = ""
        st.set_extended_font_data(new_family, italic=italic, bold=bold)
        st.dxf.width = (st.dxf.get("width", 1.0) or 1.0) * width
    changed = 0

    def fix(e):
        nonlocal changed
        t = e.dxftype()
        if t not in ("TEXT", "ATTRIB", "ATTDEF", "MTEXT"):
            return
        style = (e.dxf.get("style", "Standard") or "Standard").lower()
        caps, width = styles.get(style, (False, 1.0))
        if t == "MTEXT":
            s = e.text
            if style not in styles and not re.search(r"\\[fF]", s):
                return
            s2 = decode_mtext(s, style in styles, caps, codepage)
            if s2 != s:
                e.text = s2
                changed += 1
        elif style in styles:
            # TEXT keeps its own width factor (copied from the style when it was typed); Aligned (3) and
            # Fit (5) texts are sized by their two alignment points instead
            if e.dxf.get("halign", 0) not in (3, 5):
                e.dxf.width = (e.dxf.get("width", 1.0) or 1.0) * width
            s = e.dxf.text
            s2 = decode_text(s, caps, codepage)
            if s2 != s:
                e.dxf.text = s2
                changed += 1

    layouts = [doc.modelspace()] + [l for l in doc.layouts if l.name != "Model"]
    for lay in layouts:
        for e in lay:
            fix(e)
            if e.dxftype() == "INSERT":
                for a in e.attribs:
                    fix(a)
    for blk in doc.blocks:
        if blk.name.lower().startswith(("*model_space", "*paper_space")):
            continue
        for e in blk:
            fix(e)
            if e.dxftype() == "INSERT":
                for a in e.attribs:
                    fix(a)
    log(f"TCVN3: styles={len(styles)} texts converted={changed} (codepage {codepage})")
    return changed


if __name__ == "__main__":
    for s in ["C«ng ty c%%230 phÇn vi%%212n th«ng", "®\xadêng ®Êt", "s©n", "Tê b¶n ®å sè 12",
              "®\xadêng nhùa", "Ø%%c200 %%d %%%230"]:
        print(repr(s), "->", decode_text(s))
    print("caps:", decode_text("b¶n ®å hiÖn tr¹ng", caps=True))
    print("mtext:", decode_mtext("{\\f.VnTime|b0|i0|c0|p18;®\xadêng}\\P{\\fArial|b0;Mái} {\\f.VnArialH;b¶n ®å}", False, False))

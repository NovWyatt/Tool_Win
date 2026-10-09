"""VNI-Windows (legacy Vietnamese 8-bit) -> Unicode for texts drawn with VNI fonts."""
import re

VNI_FONT_PREFIXES = ("vni", "vavo", "vhelv", "vtime", "vari", "vcoop", "vbodo", "vcour", "vbook",
                     "vsouv", "vuniv", "vgara", "vluc", "vtek", "vapt", "vbahn", "vcent", "vgoud",
                     "vpalt", "vmemo", "vbrush", "vcamb", "vhelvc")

def is_vni_font(font: str) -> bool:
    f = (font or "").lower().replace("\\", "/").split("/")[-1]
    return f.startswith(VNI_FONT_PREFIXES)

_T = {}
def _add(seq, uni):
    _T[seq] = uni

# tone marks (lower, upper) -> combining index: sac, huyen, hoi, nga, nang
TONES_L = "ùøûõï"; TONES_U = "ÙØÛÕÏ"
def _tone_forms(base):
    return {
        "a": "áàảãạ", "e": "éèẻẽẹ", "o": "óòỏõọ", "u": "úùủũụ", "y": "ýỳỷỹ",
        "â": "ấầẩẫậ", "ê": "ếềểễệ", "ô": "ốồổỗộ", "ă": "ắằẳẵặ",
        "ơ": "ớờởỡợ", "ư": "ứừửữự",
    }[base]
for base in "aeouy":
    forms = _tone_forms(base)
    for i, (tl, tu) in enumerate(zip(TONES_L, TONES_U)):
        if i < len(forms):
            for b, f in ((base, forms[i]), (base.upper(), forms[i].upper())):
                _add(b + tl, f); _add(b + tu, f)
# circumflex (â) and breve (ă) markers
for b, m_l, m_u, res in (("a", "â", "Â", "â"), ("e", "â", "Â", "ê"), ("o", "â", "Â", "ô"), ("a", "ê", "Ê", "ă")):
    for bb, r in ((b, res), (b.upper(), res.upper())):
        _add(bb + m_l, r); _add(bb + m_u, r)
# circumflex+tone: á à å ã ä ; breve+tone: é è ú ü ë
CIRC_L, CIRC_U = "áàåãä", "ÁÀÅÃÄ"
BREV_L, BREV_U = "éèúüë", "ÉÈÚÜË"
for b, res in (("a", "â"), ("e", "ê"), ("o", "ô")):
    forms = _tone_forms(res)
    for i in range(5):
        for bb, f in ((b, forms[i]), (b.upper(), forms[i].upper())):
            _add(bb + CIRC_L[i], f); _add(bb + CIRC_U[i], f)
forms = _tone_forms("ă")
for i in range(5):
    for bb, f in (("a", forms[i]), ("A", forms[i].upper())):
        _add(bb + BREV_L[i], f); _add(bb + BREV_U[i], f)
# horn vowels ơ (ô) ư (ö) and their tones
for code_l, code_u, res in (("ô", "Ô", "ơ"), ("ö", "Ö", "ư")):
    forms = _tone_forms(res)
    for i in range(5):
        for c, f in ((code_l, forms[i]), (code_u, forms[i].upper())):
            _add(c + TONES_L[i], f); _add(c + TONES_U[i], f)
    _add(code_l, res); _add(code_u, res.upper())
# single-char letters
for k, v in {"í": "í", "ì": "ì", "æ": "ỉ", "ó": "ĩ", "ò": "ị", "î": "ỵ", "ñ": "đ",
             "Í": "Í", "Ì": "Ì", "Æ": "Ỉ", "Ó": "Ĩ", "Ò": "Ị", "Î": "Ỵ", "Ñ": "Đ",
             "Þ": "Ø"}.items():
    _add(k, v)

_KEYS = sorted(_T, key=len, reverse=True)
_RX = re.compile("|".join(re.escape(k) for k in _KEYS))
_UNICODE_VI = re.compile("[ĂăĐđƠơƯưẠ-ỹ]")
_HAS_VNI = re.compile("[À-ÿ]")

def looks_vni(s: str) -> bool:
    return bool(_HAS_VNI.search(s)) and not _UNICODE_VI.search(s)

def decode(s: str) -> str:
    return _RX.sub(lambda m: _T[m.group(0)], s)

def fix_document(doc, log=print):
    """Re-encode VNI texts to Unicode and point VNI styles at Arial."""
    vni_styles = set()
    for st in doc.styles:
        if is_vni_font(st.dxf.font):
            vni_styles.add(st.dxf.name.lower())
            st.dxf.font = "arial.ttf"
    changed = 0
    def fix(e):
        nonlocal changed
        t = e.dxftype()
        if t not in ("TEXT", "ATTRIB", "ATTDEF", "MTEXT"):
            return
        style = (e.dxf.get("style", "Standard") or "Standard").lower()
        if t in ("TEXT", "ATTRIB", "ATTDEF"):
            s = e.dxf.text
            if style in vni_styles and looks_vni(s):
                e.dxf.text = decode(s); changed += 1
        elif t == "MTEXT":
            s = e.text
            inline_vni = re.search(r"\\f(vni|vavo|vhelv|vtime)", s, re.I)
            if (style in vni_styles or inline_vni) and looks_vni(s):
                s = decode(s); changed += 1
            # inline font switches to a VNI font -> Arial (the text is Unicode now)
            s2 = re.sub(r"\\f(vni[^|;]*|vavo[^|;]*|vhelv[^|;]*|vtime[^|;]*)(?=[|;])", r"\\fArial", s, flags=re.I)
            if s2 != e.text:
                e.text = s2
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
    log(f"VNI: styles={len(vni_styles)} texts converted={changed}")
    return changed

if __name__ == "__main__":
    for s in ["KÍNH CÖÔØNG LÖÏC \nDAØY 10 mm", "OÁNG SAÉT Þ 76", "HAÏNG MUÏC", "KÍ HIEÄU", "BEÅ THU GOM",
              "CHOÂN SAÂU VAØO BT", "PAÙT SAÉT DAØY 6 mm", "Ghi chuù: thieát keá", "ÑÔN VÒ THIEÁT KEÁ",
              "Maët baèng taàng ñieån hình", "ĐÁ CHẼ"]:
        print(repr(s), "->", decode(s) if looks_vni(s) else "(skip) " + s)

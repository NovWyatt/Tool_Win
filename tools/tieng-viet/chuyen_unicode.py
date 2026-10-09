"""Chuyển bản sao tài liệu Word, Excel gõ bằng font VNI (VNI-Times...) hoặc TCVN3 (.VnTime...) sang Unicode.

Không đụng file gốc: ghi <tên>_Unicode<đuôi> cạnh file (hoặc vào --ra). Chữ được giải mã theo font của từng đoạn
(không đoán theo nội dung), rồi font cũ được đổi sang font Unicode có sẵn trong Windows (Times New Roman, Arial,
Courier New). Chỉ dùng thư viện chuẩn của Python: sửa thẳng XML trong file .docx/.xlsx, mọi phần khác giữ nguyên.
vni.py, tcvn3.py chép từ tools/dwg2pdf (bài thử giữ hai bản giống hệt nhau).

Word: đoạn chữ (w:t) trong thân, đầu trang, chân trang, chú thích; font lấy theo đúng thứ tự của Word (font đặt
thẳng, kiểu ký tự, kiểu đoạn, mặc định của tài liệu). Excel: ô chữ (bảng chữ dùng chung, chữ trong ô, kết quả công
thức dạng chữ) theo font của ô, chữ nhiều định dạng theo font từng đoạn, ghi chú. Chữ dùng chung vừa ở ô font cũ vừa
ở ô font Unicode thì tách thành hai bản. Chưa chuyển: chữ trong biểu đồ, hình vẽ, tên trang tính, đầu trang Excel,
chuỗi trong công thức.

Mã thoát: 0 xong (kể cả không có file nào cần chuyển), 1 lỗi bất ngờ, 2 không có file nào để làm, 3 có file lỗi.
"""
import argparse
import json
import os
import re
import socket
import sys
import time
import zipfile
from collections import Counter
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tcvn3  # noqa: E402
import vni  # noqa: E402

PHIEN_BAN = "1.0"
DUOI_WORD = {".docx", ".docm"}
DUOI_EXCEL = {".xlsx", ".xlsm"}
DUOI_CU = {".doc", ".xls", ".rtf", ".dot", ".xlt"}
HAU_TO = "_Unicode"

TOKEN = re.compile(r"<[^>]*>|[^<]+")
TAG = re.compile(r"<\s*(/?)\s*([A-Za-z_][\w:.-]*)(.*?)(/?)\s*>\Z", re.S)
ATTR = re.compile(r"([^\s=/<>\"']+)\s*=\s*(\"([^\"]*)\"|'([^']*)')")
_ENT = re.compile(r"&(#x[0-9A-Fa-f]+|#\d+|amp|lt|gt|quot|apos);")
_ENT_TEN = {"amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'"}
_PUA = re.compile("[-]")
_UNICODE_VI = re.compile("[ĂăĐđƠơƯưẠ-ỹ]")


# ---------------------------------------------------------------- XML, font
def the(tok):
    """'<w:r ...>' -> (đóng, tên, {thuộc tính}, tự đóng); None với <?xml ?>, <!-- -->."""
    if tok.startswith(("<?", "<!")):
        return None
    m = TAG.match(tok)
    if not m:
        return None
    attrs = {a.group(1): xml_text(a.group(3) if a.group(3) is not None else a.group(4)) for a in ATTR.finditer(m.group(3))}
    return bool(m.group(1)), m.group(2), attrs, bool(m.group(4))


def xml_text(s):
    def ent(m):
        k = m.group(1)
        if k.startswith("#x"):
            return chr(int(k[2:], 16))
        if k.startswith("#"):
            return chr(int(k[1:]))
        return _ENT_TEN[k]
    return _ENT.sub(ent, s)


def xml_escape(s, attr=False):
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s.replace('"', "&quot;") if attr else s


def ten_dia_phuong(ten):
    return ten.split(":")[-1]


def loai_font(ten):
    """'vni', 'tcvn3' hoặc None."""
    if not ten:
        return None
    if tcvn3.is_tcvn3_font(ten):
        return "tcvn3"
    if vni.is_vni_font(ten):
        return "vni"
    return None


def font_thay(ten):
    """Font Unicode có sẵn trong Windows thay cho font cũ."""
    if loai_font(ten) == "tcvn3":
        return tcvn3.substitute(ten)[0]
    n = ten.lower()
    if "cour" in n:
        return "Courier New"
    if any(k in n for k in ("time", "book", "bodo", "souv", "gara", "cent", "goud", "palt", "memo")):
        return "Times New Roman"
    return "Arial"


def _pua(s):
    # Font kiểu "symbol" làm Word lưu ký tự vào vùng riêng U+F0xx: đưa về ký tự ANSI tương ứng trước khi giải mã.
    def f(m):
        b = ord(m.group(0)) - 0xF000
        return bytes([b]).decode("cp1252", errors="ignore") or chr(b)
    return _PUA.sub(f, s)


def giai_ma(s, font):
    """Chữ hiện bằng font cũ -> Unicode. Đoạn đã có chữ Việt Unicode thì giữ nguyên."""
    if _UNICODE_VI.search(s):
        return s
    s = _pua(s)
    if loai_font(font) == "vni":
        return vni.decode(s)
    return tcvn3.decode_plain(s, caps=tcvn3.is_caps_font(font), codepage="cp1252")


def thay_font_trong_the(tok, ten_thuoc_tinh):
    """Đổi giá trị các thuộc tính (vd w:ascii) đang là font cũ thành font Unicode; trả thẻ mới."""
    def f(m):
        if m.group(1) not in ten_thuoc_tinh:
            return m.group(0)
        v = xml_text(m.group(3) if m.group(3) is not None else m.group(4))
        if not loai_font(v):
            return m.group(0)
        q = m.group(2)[0]
        return "%s=%s%s%s" % (m.group(1), q, xml_escape(font_thay(v), attr=True), q)
    m = TAG.match(tok)
    if not m:
        return tok
    return tok[:m.start(3)] + ATTR.sub(f, m.group(3)) + tok[m.end(3):]


def doc_xml(data):
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8"), b"\xef\xbb\xbf"
    return data.decode("utf-8"), b""


class ThongKe:
    """doan: số đoạn chữ hiện bằng font cũ (kể cả đoạn không dấu, vẫn phải đổi font); doi: số đoạn đổi chữ."""

    def __init__(self):
        self.doan = 0
        self.doi = 0
        self.font = Counter()

    def chuyen(self, toks, i, font):
        s = xml_text(toks[i])
        if not s.strip():
            return
        self.doan += 1
        self.font[font] += 1
        moi = giai_ma(s, font)
        if moi != s:
            toks[i] = xml_escape(moi)
            self.doi += 1


# ---------------------------------------------------------------- Word
RFONTS_ATTR = {"w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"}


def font_rfonts(attrs):
    """Thẻ w:rFonts -> {'hAnsi': tên | 'theme', 'ascii': ...} (chỉ khe có đặt)."""
    out = {}
    for k in ("hAnsi", "ascii"):
        if "w:%sTheme" % k in attrs:
            out[k] = "theme"
        elif "w:" + k in attrs:
            out[k] = attrs["w:" + k]
    return out


class KieuWord:
    """Font của kiểu (styles.xml): mặc định tài liệu, mỗi kiểu (theo basedOn), kiểu đoạn mặc định."""

    def __init__(self, xml):
        self.mac_dinh = {}
        self.kieu = {}
        self.doan_mac_dinh = None
        cur = None
        stack = []
        for tok in TOKEN.findall(xml or ""):
            if not tok.startswith("<"):
                continue
            t = the(tok)
            if not t:
                continue
            dong, ten, attrs, tu_dong = t
            if dong:
                if ten == "w:style" and cur:
                    self.kieu[cur["id"]] = cur
                    cur = None
                while stack and stack.pop() != ten:
                    pass
                continue
            if ten == "w:style":
                cur = {"id": attrs.get("w:styleId", ""), "loai": attrs.get("w:type", ""), "goc": None, "font": {}}
                if attrs.get("w:default") in ("1", "true", "on") and cur["loai"] == "paragraph":
                    self.doan_mac_dinh = cur["id"]
            elif ten == "w:basedOn" and cur is not None and stack[-1:] == ["w:style"]:
                cur["goc"] = attrs.get("w:val")
            elif ten == "w:rFonts":
                if cur is not None and stack[-2:] == ["w:style", "w:rPr"]:
                    cur["font"] = font_rfonts(attrs)
                elif stack[-2:] == ["w:rPrDefault", "w:rPr"]:
                    self.mac_dinh = font_rfonts(attrs)
            if not tu_dong:
                stack.append(ten)

    def tu_kieu(self, sid, khe):
        da = set()
        while sid and sid in self.kieu and sid not in da:
            da.add(sid)
            v = self.kieu[sid]["font"].get(khe)
            if v:
                return v
            sid = self.kieu[sid]["goc"]
        return None

    def font_hieu_luc(self, truc_tiep, rstyle, pstyle):
        """Font cũ (nếu có) mà Word dùng cho đoạn chữ này; None khi là font Unicode hay font theo chủ đề."""
        for khe in ("hAnsi", "ascii"):
            v = truc_tiep.get(khe) or self.tu_kieu(rstyle, khe) or self.tu_kieu(pstyle or self.doan_mac_dinh, khe) \
                or self.mac_dinh.get(khe)
            if v and v != "theme" and loai_font(v):
                return v
        return None


def xu_ly_phan_word(xml, kieu, tk):
    """Một phần XML có đoạn văn (document, header, footer...). Trả XML mới."""
    toks = TOKEN.findall(xml)
    stack, paras, runs = [], [], []
    for i, tok in enumerate(toks):
        if not tok.startswith("<"):
            if runs and stack and stack[-1] in ("w:t", "w:delText") and len(stack) >= 2 and stack[-2] == "w:r":
                runs[-1]["chu"].append(i)
            continue
        t = the(tok)
        if not t:
            continue
        dong, ten, attrs, tu_dong = t
        if dong:
            if ten == "w:r" and runs:
                r = runs.pop()
                font = kieu.font_hieu_luc(r["font"], r["rstyle"], paras[-1] if paras else None)
                if font:
                    for k in r["chu"]:
                        tk.chuyen(toks, k, font)
            elif ten == "w:p" and paras:
                paras.pop()
            while stack and stack.pop() != ten:
                pass
            continue
        cha = stack[-1] if stack else None
        if ten == "w:p" and not tu_dong:
            paras.append(None)
        elif ten == "w:pStyle" and cha == "w:pPr" and paras:
            paras[-1] = attrs.get("w:val")
        elif ten == "w:r" and not tu_dong:
            runs.append({"font": {}, "rstyle": None, "chu": []})
        elif ten == "w:rStyle" and cha == "w:rPr" and stack[-2:-1] == ["w:r"] and runs:
            runs[-1]["rstyle"] = attrs.get("w:val")
        elif ten == "w:rFonts":
            if cha == "w:rPr" and stack[-2:-1] == ["w:r"] and runs:
                runs[-1]["font"] = font_rfonts(attrs)
            toks[i] = thay_font_trong_the(tok, RFONTS_ATTR)
        if not tu_dong:
            stack.append(ten)
    return "".join(toks)


def thay_rfonts(xml):
    """styles.xml, numbering.xml: chỉ đổi tên font cũ trong w:rFonts."""
    return "".join(thay_font_trong_the(t, RFONTS_ATTR) if t.startswith("<w:rFonts") else t for t in TOKEN.findall(xml))


PHAN_WORD = re.compile(r"word/(document|header\d*|footer\d*|footnotes|endnotes|comments)\.xml\Z")


def chuyen_word(zi, tk):
    ten = set(zi.namelist())
    styles = doc_xml(zi.read("word/styles.xml"))[0] if "word/styles.xml" in ten else ""
    kieu = KieuWord(styles)
    thay = {}
    for n in sorted(ten):
        if PHAN_WORD.match(n):
            xml, bom = doc_xml(zi.read(n))
            moi = xu_ly_phan_word(xml, kieu, tk)
            if moi != xml:
                thay[n] = bom + moi.encode("utf-8")
    for n in ("word/styles.xml", "word/numbering.xml"):
        if n in ten:
            xml, bom = doc_xml(zi.read(n))
            moi = thay_rfonts(xml)
            if moi != xml:
                thay[n] = bom + moi.encode("utf-8")
    return thay


# ---------------------------------------------------------------- Excel
def ten_x(tok):
    t = the(tok)
    return (t[0], ten_dia_phuong(t[1]), {ten_dia_phuong(k): v for k, v in t[2].items()}, t[3]) if t else None


class KieuExcel:
    """styles.xml: tên font theo fontId, fontId theo chỉ số kiểu ô (cellXfs)."""

    def __init__(self, xml):
        self.font, self.xf = [], []
        self.toks = TOKEN.findall(xml or "")
        stack = []
        for i, tok in enumerate(self.toks):
            if not tok.startswith("<"):
                continue
            t = ten_x(tok)
            if not t:
                continue
            dong, ten, attrs, tu_dong = t
            if dong:
                while stack and stack.pop() != ten:
                    pass
                continue
            if ten == "font" and stack[-1:] == ["fonts"]:
                self.font.append("")
            elif ten == "name" and stack[-2:] == ["fonts", "font"] and self.font:
                self.font[-1] = attrs.get("val", "")
            elif ten == "xf" and stack[-1:] == ["cellXfs"]:
                try:
                    self.xf.append(int(attrs.get("fontId", "0")))
                except ValueError:
                    self.xf.append(0)
            if ten == "name" and stack[-1:] == ["font"]:
                self.toks[i] = thay_font_trong_the(tok, {"val"})
            if not tu_dong:
                stack.append(ten)

    def font_o(self, s):
        """Font của ô có kiểu s (thuộc tính s của thẻ c; thiếu là 0)."""
        try:
            fid = self.xf[int(s or 0)]
            return self.font[fid]
        except (ValueError, IndexError):
            return ""

    def xml(self):
        return "".join(self.toks)


def doc_chuoi_tu_do(toks, bat_dau, ket_thuc):
    """Các đoạn chữ trong một <si> hay <is>: [(chỉ số token chữ, font của đoạn hoặc None)]."""
    out, stack, font_run = [], [], None
    for i in range(bat_dau, ket_thuc):
        tok = toks[i]
        if not tok.startswith("<"):
            if stack and stack[-1] == "t" and "rPh" not in stack:
                out.append((i, font_run if "r" in stack else None))
            continue
        t = ten_x(tok)
        if not t:
            continue
        dong, ten, attrs, tu_dong = t
        if dong:
            while stack and stack.pop() != ten:
                pass
            if ten == "r":
                font_run = None
            continue
        if ten == "rFont" and "r" in stack:
            font_run = attrs.get("val") or None
            toks[i] = thay_font_trong_the(tok, {"val"})
        if not tu_dong:
            stack.append(ten)
    return out


def chuyen_doan(toks, doan, font_o, tk):
    for i, font_run in doan:
        f = font_run if font_run else font_o
        if loai_font(f):
            tk.chuyen(toks, i, f)


def chuyen_excel(zi, tk):
    ten = set(zi.namelist())
    thay = {}
    kieu = KieuExcel(doc_xml(zi.read("xl/styles.xml"))[0] if "xl/styles.xml" in ten else "")
    # Bảng chữ dùng chung: vị trí từng <si>.
    sst_ten = "xl/sharedStrings.xml"
    sst_toks, sst_bom, si = [], b"", []
    if sst_ten in ten:
        sst_xml, sst_bom = doc_xml(zi.read(sst_ten))
        sst_toks = TOKEN.findall(sst_xml)
        mo = None
        for i, tok in enumerate(sst_toks):
            if tok.startswith("<"):
                t = ten_x(tok)
                if t and t[1] == "si":
                    if t[3]:
                        si.append((i, i + 1))
                    elif not t[0]:
                        mo = i
                    elif mo is not None:
                        si.append((mo, i + 1))
                        mo = None
    dung = {}   # chỉ số si -> [(tên phần, chỉ số token <v>, font ô)]
    trang = {}
    for n in sorted(ten):
        if not re.match(r"xl/worksheets/[^/]+\.xml\Z", n):
            continue
        xml, bom = doc_xml(zi.read(n))
        toks = TOKEN.findall(xml)
        trang[n] = (toks, bom, xml)
        stack, o = [], None
        for i, tok in enumerate(toks):
            if not tok.startswith("<"):
                if o and stack and stack[-1] == "v":
                    o["v"] = i
                continue
            t = ten_x(tok)
            if not t:
                continue
            dong, tn, attrs, tu_dong = t
            if dong:
                while stack and stack.pop() != tn:
                    pass
                if tn == "c" and o:
                    font = kieu.font_o(o["s"])
                    if o["t"] == "s" and o.get("v") is not None:
                        try:
                            dung.setdefault(int(toks[o["v"]].strip()), []).append((n, o["v"], font))
                        except ValueError:
                            pass
                    elif o["t"] == "str" and o.get("v") is not None and loai_font(font):
                        tk.chuyen(toks, o["v"], font)
                    elif o["t"] == "inlineStr" and o.get("is") is not None:
                        chuyen_doan(toks, doc_chuoi_tu_do(toks, o["is"], i), font, tk)
                    o = None
                continue
            if tn == "c" and not tu_dong:
                o = {"s": attrs.get("s"), "t": attrs.get("t", "n"), "v": None, "is": None}
            elif tn == "is" and o is not None:
                o["is"] = i
            if not tu_dong:
                stack.append(tn)
    # Chữ dùng chung: chuyển tại chỗ khi mọi ô dùng nó cùng một font cũ; dùng ở cả ô font khác thì thêm bản đã chuyển.
    them = []
    for k, (a, b) in enumerate(si):
        doan = doc_chuoi_tu_do(sst_toks, a, b)
        cac_o = dung.get(k, [])
        font_cu = sorted({f for _, _, f in cac_o if loai_font(f)})
        khac = any(not loai_font(f) for _, _, f in cac_o)
        # Đoạn có font riêng (chữ nhiều định dạng) luôn theo font của đoạn.
        for i, font_run in doan:
            if font_run and loai_font(font_run):
                tk.chuyen(sst_toks, i, font_run)
        tron = [i for i, font_run in doan if not font_run]
        if not tron or not font_cu:
            continue
        if len(font_cu) == 1 and not khac:
            for i in tron:
                tk.chuyen(sst_toks, i, font_cu[0])
            continue
        for f in font_cu:
            ban = sst_toks[a:b]
            for i in tron:
                tk.chuyen(ban, i - a, f)
            moi = len(si) + len(them)
            them.append("".join(ban))
            for n, vi, ff in cac_o:
                if ff == f:
                    trang[n][0][vi] = str(moi)
    if them:
        for i in range(len(sst_toks) - 1, -1, -1):
            t = ten_x(sst_toks[i]) if sst_toks[i].startswith("<") else None
            if t and t[0] and t[1] == "sst":
                sst_toks[i] = "".join(them) + sst_toks[i]
                break
        for i, tok in enumerate(sst_toks):
            t = ten_x(tok) if tok.startswith("<") else None
            if t and not t[0] and t[1] == "sst":
                if "uniqueCount" in t[2]:
                    sst_toks[i] = re.sub(r'uniqueCount="\d+"', 'uniqueCount="%d"' % (len(si) + len(them)), tok)
                break
    if sst_toks:
        moi = "".join(sst_toks)
        if moi != sst_xml:
            thay[sst_ten] = sst_bom + moi.encode("utf-8")
    for n, (toks, bom, xml) in trang.items():
        moi = "".join(toks)
        if moi != xml:
            thay[n] = bom + moi.encode("utf-8")
    # Ghi chú: chỉ đoạn có font riêng là font cũ.
    for n in sorted(ten):
        if re.match(r"xl/comments\d*\.xml\Z", n):
            xml, bom = doc_xml(zi.read(n))
            toks = TOKEN.findall(xml)
            for i, f in doc_chuoi_tu_do(toks, 0, len(toks)):
                if f and loai_font(f):
                    tk.chuyen(toks, i, f)
            moi = "".join(toks)
            if moi != xml:
                thay[n] = bom + moi.encode("utf-8")
    styles_moi = kieu.xml()
    if "xl/styles.xml" in ten and tk.doan:
        xml, bom = doc_xml(zi.read("xl/styles.xml"))
        if styles_moi != xml:
            thay["xl/styles.xml"] = bom + styles_moi.encode("utf-8")
    return thay


# ---------------------------------------------------------------- file
def ten_ra(nguon, thu_muc_ra):
    d = Path(thu_muc_ra) if thu_muc_ra else nguon.parent
    p = d / (nguon.stem + HAU_TO + nguon.suffix)
    k = 2
    while p.exists():
        p = d / ("%s%s (%d)%s" % (nguon.stem, HAU_TO, k, nguon.suffix))
        k += 1
    return p


def xu_ly_file(nguon, thu_muc_ra, chi_xem):
    kq = {"nguon": str(nguon), "ra": "", "trangThai": "", "soDoan": 0, "font": {}, "lyDo": ""}
    duoi = nguon.suffix.lower()
    if duoi in DUOI_CU:
        kq.update(trangThai="bo-qua", lyDo="Định dạng cũ: mở bằng Word hoặc Excel, Lưu thành .docx hoặc .xlsx rồi chuyển bản đó.")
        return kq
    tk = ThongKe()
    try:
        with zipfile.ZipFile(nguon) as zi:
            thay = chuyen_word(zi, tk) if duoi in DUOI_WORD else chuyen_excel(zi, tk)
            if not tk.doan:
                kq.update(trangThai="khong-co-chu-cu", lyDo="Không có chữ nào dùng font VNI hay TCVN3.")
                return kq
            kq.update(soDoan=tk.doan, font=dict(tk.font.most_common()))
            if chi_xem:
                kq["trangThai"] = "co-chu-cu"
                return kq
            dich = ten_ra(nguon, thu_muc_ra)
            tam = dich.with_name(dich.name + ".tmp")
            with zipfile.ZipFile(tam, "w", zipfile.ZIP_DEFLATED) as zo:
                for info in zi.infolist():
                    data = thay.get(info.filename)
                    zo.writestr(info, data if data is not None else zi.read(info.filename), compress_type=zipfile.ZIP_DEFLATED)
            os.replace(tam, dich)
            kq.update(trangThai="da-chuyen", ra=str(dich))
    except zipfile.BadZipFile:
        kq.update(trangThai="loi", lyDo="Không phải file Office hợp lệ (hỏng, hoặc đang được bảo vệ bằng mật khẩu).")
    except (OSError, UnicodeDecodeError, KeyError) as e:
        kq.update(trangThai="loi", lyDo=str(e))
    return kq


def gom_file(cac_duong_dan, de_quy):
    out, seen = [], set()
    hop_le = DUOI_WORD | DUOI_EXCEL | DUOI_CU
    for p in cac_duong_dan:
        p = Path(p)
        if p.is_dir():
            it = p.rglob("*") if de_quy else p.iterdir()
            ds = sorted(x for x in it if x.is_file())
        elif p.is_file():
            ds = [p]
        else:
            print("  [!] Không thấy: %s" % p)
            continue
        for f in ds:
            if f.suffix.lower() not in hop_le or f.name.startswith("~$"):
                continue
            if re.search(re.escape(HAU_TO) + r"( \(\d+\))?\Z", f.stem):
                continue
            k = str(f.resolve()).lower()
            if k not in seen:
                seen.add(k)
                out.append(f)
    return out


def ghi_tien_do(duong_dan, xong, tong, buoc):
    if not duong_dan:
        return
    d = {"chuan": "tramtool.tiendo/1", "phanTram": round(100.0 * xong / tong, 1) if tong else 100.0,
         "buoc": buoc, "xong": xong, "tong": tong}
    try:
        with open(duong_dan + ".tmp", "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False)
        os.replace(duong_dan + ".tmp", duong_dan)
    except OSError:
        pass


def ghi_ket_qua(ds, bat_dau, ma_thoat, chi_xem, thu_muc):
    """KetQua_TiengViet_ChuyenUnicode_<máy>_<giờ>.json theo chuẩn tramtool.ketqua/1."""
    phat = []
    for k in ds:
        ten = Path(k["nguon"]).name
        fonts = ", ".join(k["font"])
        if k["trangThai"] == "da-chuyen":
            phat.append({"ma": "DA_CHUYEN", "mucDo": "ok", "tieuDe": "%s: chuyển %d đoạn chữ (%s)" % (ten, k["soDoan"], fonts),
                         "chiTiet": "Bản Unicode: " + k["ra"], "cachSua": ""})
        elif k["trangThai"] == "co-chu-cu":
            phat.append({"ma": "CO_CHU_FONT_CU", "mucDo": "canh-bao", "tieuDe": "%s: %d đoạn chữ dùng font cũ (%s)" % (ten, k["soDoan"], fonts),
                         "chiTiet": k["nguon"], "cachSua": "Bỏ chọn Chỉ xem rồi chạy lại để tạo bản Unicode.",
                         "chayTiep": {"congCu": "tieng-viet", "action": "chuyen"}})
        elif k["trangThai"] == "bo-qua":
            phat.append({"ma": "DINH_DANG_CU", "mucDo": "canh-bao", "tieuDe": "%s: chưa chuyển được" % ten, "chiTiet": k["lyDo"], "cachSua": k["lyDo"]})
        elif k["trangThai"] == "loi":
            phat.append({"ma": "LOI_DOC_FILE", "mucDo": "loi", "tieuDe": "%s: không đọc được" % ten, "chiTiet": k["lyDo"], "cachSua": ""})
        else:
            phat.append({"ma": "KHONG_CO_CHU_CU", "mucDo": "thong-tin", "tieuDe": "%s: không có chữ font cũ" % ten, "chiTiet": "", "cachSua": ""})
    rank = {"loi": 0, "canh-bao": 1, "thong-tin": 2, "ok": 3}
    phat.sort(key=lambda f: rank[f["mucDo"]])
    dem = Counter(k["trangThai"] for k in ds)
    n = {m: sum(1 for f in phat if f["mucDo"] == m) for m in ("loi", "canh-bao", "thong-tin")}
    if chi_xem:
        thong = "Chỉ xem: %d trên %d file có chữ font cũ." % (dem["co-chu-cu"], len(ds))
    else:
        thong = "Đã tạo %d bản Unicode, %d file không có chữ font cũ, %d chưa chuyển được, %d lỗi." % (
            dem["da-chuyen"], dem["khong-co-chu-cu"], dem["bo-qua"], dem["loi"])
    r = {"chuan": "tramtool.ketqua/1", "congCu": "tieng-viet", "cheDo": "chuyen", "phienBan": PHIEN_BAN,
         "may": os.environ.get("COMPUTERNAME", socket.gethostname()), "taiKhoan": os.environ.get("USERNAME", ""),
         "batDau": bat_dau.strftime("%Y-%m-%dT%H:%M:%S"), "ketThuc": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
         "maThoat": ma_thoat, "trangThai": {0: "xong", 1: "loi", 2: "thieu-dieu-kien", 3: "mot-phan"}[ma_thoat],
         "chayThu": bool(chi_xem), "ma": "CO_LOI" if n["loi"] else ("CO_CANH_BAO" if n["canh-bao"] else "KHONG_CO_LOI"),
         "thongDiep": thong, "tomTat": {"loi": n["loi"], "canhBao": n["canh-bao"], "thongTin": n["thong-tin"]},
         "phatHien": phat, "tep": [{"nhan": "Bản Unicode", "duongDan": k["ra"]} for k in ds if k["ra"]][:50]}
    try:
        Path(thu_muc).mkdir(parents=True, exist_ok=True)
        p = Path(thu_muc) / ("KetQua_TiengViet_ChuyenUnicode_%s_%s.json" % (r["may"], bat_dau.strftime("%Y%m%d_%H%M%S")))
        tam = str(p) + ".tmp"
        with open(tam, "w", encoding="utf-8") as f:
            json.dump(r, f, ensure_ascii=False, indent=2)
        os.replace(tam, p)
        print("  Kết quả cho Trạm Tool: %s" % p)
    except OSError as e:
        print("  [!] Không ghi được file kết quả: %s" % e)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Chuyển bản sao .docx, .xlsx gõ bằng font VNI, TCVN3 sang Unicode.")
    ap.add_argument("tep", nargs="*", help="file .docx/.xlsx hoặc thư mục")
    ap.add_argument("--thu-muc", action="append", default=[], help="thư mục chứa tài liệu (lặp lại được)")
    ap.add_argument("--ra", default="", help="thư mục ghi bản Unicode (mặc định: cạnh file gốc)")
    ap.add_argument("--de-quy", action="store_true", help="tìm cả trong thư mục con")
    ap.add_argument("--chi-xem", action="store_true", help="chỉ liệt kê file có chữ font cũ, không tạo bản sao")
    ap.add_argument("--tien-do", default="", help="file tiến độ cho Trạm Tool (tramtool.tiendo/1)")
    ap.add_argument("--ket-qua", default=os.environ.get("TV_KET_QUA") or str(Path(__file__).resolve().parent / "ket_qua"),
                    help="thư mục ghi file kết quả JSON")
    a = ap.parse_args(argv)
    bat_dau = datetime.now()
    print("\n  CHUYỂN TÀI LIỆU FONT VNI, TCVN3 SANG UNICODE (bản %s)%s\n" % (PHIEN_BAN, " - chỉ xem" if a.chi_xem else ""))
    if a.ra and not Path(a.ra).is_dir():
        print("  [X] Không thấy thư mục ghi: %s" % a.ra)
        return 2
    ds_file = gom_file(list(a.tep) + list(a.thu_muc), a.de_quy)
    if not ds_file:
        print("  [!] Không có file .docx, .xlsx nào. Kéo thả file hoặc thư mục vào CHUYEN_UNICODE.bat.")
        ghi_ket_qua([], bat_dau, 2, a.chi_xem, a.ket_qua)
        return 2
    ds = []
    t0 = time.time()
    for k, f in enumerate(ds_file):
        ghi_tien_do(a.tien_do, k, len(ds_file), "File %d/%d: %s" % (k + 1, len(ds_file), f.name))
        kq = xu_ly_file(f, a.ra, a.chi_xem)
        ds.append(kq)
        nhan = {"da-chuyen": "[OK]", "co-chu-cu": "[!] ", "khong-co-chu-cu": "[ ] ", "bo-qua": "[!] ", "loi": "[X] "}[kq["trangThai"]]
        dong = "  %s %s" % (nhan, f)
        if kq["soDoan"]:
            dong += "  (%d đoạn: %s)" % (kq["soDoan"], ", ".join(kq["font"]))
        print(dong)
        if kq["ra"]:
            print("        -> %s" % kq["ra"])
        elif kq["lyDo"] and kq["trangThai"] != "khong-co-chu-cu":
            print("        %s" % kq["lyDo"])
    ghi_tien_do(a.tien_do, len(ds_file), len(ds_file), "Xong %d file" % len(ds_file))
    dem = Counter(k["trangThai"] for k in ds)
    print("\n  Tổng: %d file trong %.0f giây; %d đã chuyển, %d có chữ font cũ, %d không có, %d chưa chuyển được, %d lỗi." % (
        len(ds), time.time() - t0, dem["da-chuyen"], dem["co-chu-cu"], dem["khong-co-chu-cu"], dem["bo-qua"], dem["loi"]))
    if dem["da-chuyen"]:
        print("  Mở bản _Unicode để kiểm tra; file gốc không bị đổi.")
    ma = 3 if dem["loi"] else 0
    ghi_ket_qua(ds, bat_dau, ma, a.chi_xem, a.ket_qua)
    return ma


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(1)

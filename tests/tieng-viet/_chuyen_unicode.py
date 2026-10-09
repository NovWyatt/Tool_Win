# -*- coding: utf-8 -*-
"""Phần Python của bài thử 1_ChuyenUnicode.ps1: chuyen_unicode.py của Gói tiếng Việt với file .docx, .xlsx dựng tại chỗ.

Chữ VNI, TCVN3 đặt ở đủ chỗ font được quyết định: font đặt thẳng, kiểu ký tự, kiểu đoạn, kiểu kế thừa (basedOn),
font theo chủ đề, khung chữ lồng trong đoạn, đầu trang; Excel: font của ô, chữ dùng chung ở ô font cũ và ô font
Unicode, chữ nhiều định dạng, chữ trong ô, kết quả công thức, ghi chú. Mọi file trong thư mục tạm (tham số 1); in mỗi
kiểm tra một dòng "KT <1|0> <mô tả>".
"""
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

TAM = Path(sys.argv[1])
CONG_CU = Path(sys.argv[2])
sys.path.insert(0, str(CONG_CU))
sys.stdout.reconfigure(encoding="utf-8")
import chuyen_unicode as c  # noqa: E402


def kt(dk, mo_ta):
    print(f"KT {1 if dk else 0} {mo_ta}", flush=True)


W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
CT_WORD = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
           '<Default Extension="xml" ContentType="application/xml"/></Types>')


def dung_zip(p, phan):
    with zipfile.ZipFile(p, "w", zipfile.ZIP_DEFLATED) as z:
        for ten, noi_dung in phan.items():
            z.writestr(ten, noi_dung)


def doc(p, ten):
    with zipfile.ZipFile(p) as z:
        return z.read(ten).decode("utf-8")


def md5(p):
    return hashlib.md5(Path(p).read_bytes()).hexdigest()


def chu(xml):
    """Nội dung các thẻ w:t theo thứ tự."""
    return [c.xml_text(m) for m in re.findall(r"<w:t(?: [^>]*)?>([^<]*)</w:t>", xml)]


def run(font_xml, text, rstyle=""):
    rpr = ""
    if font_xml or rstyle:
        rpr = "<w:rPr>%s%s</w:rPr>" % ('<w:rStyle w:val="%s"/>' % rstyle if rstyle else "", font_xml)
    return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, text)


def para(runs, pstyle=""):
    ppr = '<w:pPr><w:pStyle w:val="%s"/></w:pPr>' % pstyle if pstyle else ""
    return "<w:p>%s%s</w:p>" % (ppr, "".join(runs))


VNI = '<w:rFonts w:ascii="VNI-Times" w:hAnsi="VNI-Times" w:cs="VNI-Times"/>'
TNR = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>'
THEME = '<w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi"/>'

STYLES = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s>'
          '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/></w:rPr></w:rPrDefault></w:docDefaults>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="Vni"><w:name w:val="Vni"/><w:basedOn w:val="Normal"/>'
          '<w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/></w:rPr></w:pPr>'
          '<w:rPr><w:rFonts w:ascii="VNI-Times" w:hAnsi="VNI-Times"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="VniCon"><w:name w:val="VniCon"/><w:basedOn w:val="Vni"/></w:style>'
          '<w:style w:type="character" w:styleId="Tcvn"><w:name w:val="Tcvn"/><w:rPr><w:rFonts w:ascii=".VnTime" w:hAnsi=".VnTime"/></w:rPr></w:style>'
          '<w:style w:type="character" w:styleId="TcvnHoa"><w:name w:val="TcvnHoa"/><w:rPr><w:rFonts w:ascii=".VnTimeH" w:hAnsi=".VnTimeH"/></w:rPr></w:style>'
          '</w:styles>') % W

# Đoạn chữ và kết quả mong đợi, theo thứ tự xuất hiện trong document.xml.
THAN = [
    (para([run(VNI, "Vieät Nam")]), "Việt Nam", "font VNI đặt thẳng"),
    (para([run("", "Haø Noäi")], "Vni"), "Hà Nội", "font VNI từ kiểu đoạn"),
    (para([run("", "Ñaø Naüng")], "VniCon"), "Đà Nẵng", "kiểu đoạn kế thừa kiểu VNI (basedOn)"),
    (para([run("", "®­êng ®Êt", "Tcvn")]), "đường đất", "font TCVN3 từ kiểu ký tự"),
    (para([run("", "hµ néi", "TcvnHoa")]), "HÀ NỘI", "font TCVN3 chữ hoa (.VnTimeH)"),
    (para([run(TNR, "Vieät")], "Vni"), "Vieät", "font Unicode đặt thẳng trong đoạn kiểu VNI: giữ nguyên"),
    (para([run(THEME, "Vieät")], "Vni"), "Vieät", "font theo chủ đề: giữ nguyên"),
    (para([run(VNI, "Việt Nam")]), "Việt Nam", "đoạn font VNI đã là Unicode: giữ nguyên"),
    (para([run(VNI, "A &amp; B &lt;Vieät&gt;")]), "A & B <Việt>", "ký tự XML (&, <, >) giữ đúng"),
    (para([run("", "Saøi Goøn")]), "Saøi Goøn", "đoạn kiểu mặc định (Normal, Times New Roman): giữ nguyên"),
    (para([run(VNI, "")]), "Ä", "ký tự vùng riêng U+F0xx (font kiểu symbol)"),
]
LONG = ('<w:p><w:r><w:t>Ngoaøi</w:t><w:drawing><w:txbxContent>%s</w:txbxContent></w:drawing></w:r></w:p>'
        % para([run("", "Khung chöõ")], "Vni"))
DOCUMENT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>'
            % (W, "".join(p for p, _, _ in THAN), LONG))
HEADER = '<?xml version="1.0" encoding="UTF-8"?><w:hdr %s>%s</w:hdr>' % (W, para([run("", "Coâng ty")], "Vni"))
APP = '<?xml version="1.0"?><Properties><Company>Thu</Company></Properties>'

# ---------------------------------------------------------------- Word
docx = TAM / "Bao cao.docx"
dung_zip(docx, {"[Content_Types].xml": CT_WORD, "word/document.xml": DOCUMENT, "word/styles.xml": STYLES,
                "word/header1.xml": HEADER, "docProps/app.xml": APP})
goc = md5(docx)
kq = c.xu_ly_file(docx, "", False)
ra = Path(kq["ra"]) if kq["ra"] else None
kt(kq["trangThai"] == "da-chuyen" and ra and ra.name == "Bao cao_Unicode.docx", "docx: tạo bản Bao cao_Unicode.docx (%s)" % kq["trangThai"])
kt(md5(docx) == goc, "file gốc không bị đổi")
if ra:
    xml = doc(ra, "word/document.xml")
    t = chu(xml)
    for k, (_, mong, mo_ta) in enumerate(THAN):
        kt(t[k] == mong, "%s: %r" % (mo_ta, t[k]))
    kt(t[len(THAN)] == "Ngoaøi" and t[len(THAN) + 1] == "Khung chữ", "khung chữ lồng trong đoạn: chữ trong khung đổi, chữ của đoạn ngoài (font mặc định) giữ (%r, %r)" % tuple(t[len(THAN):len(THAN) + 2]))
    kt("VNI-Times" not in xml and 'w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"' in xml, "font VNI đặt thẳng đổi thành Times New Roman (cả w:cs)")
    st = doc(ra, "word/styles.xml")
    kt("VNI-Times" not in st and ".VnTime" not in st and st.count('"Times New Roman"') >= 6, "styles.xml: font VNI, .VnTime trong kiểu đổi thành Times New Roman")
    kt(chu(doc(ra, "word/header1.xml")) == ["Công ty"], "đầu trang cũng được chuyển")
    kt(doc(ra, "docProps/app.xml") == APP, "phần khác của file giữ nguyên từng byte")
    kt(kq["font"].get("VNI-Times", 0) >= 4 and kq["font"].get(".VnTime") == 1 and kq["font"].get(".VnTimeH") == 1, "thống kê theo font: %s" % kq["font"])
    kq2 = c.xu_ly_file(docx, "", False)
    kt(Path(kq2["ra"]).name == "Bao cao_Unicode (2).docx" and ra.exists(), "chạy lại không ghi đè bản trước: %s" % Path(kq2["ra"]).name)

# ---------------------------------------------------------------- Excel
X = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
XSTYLES = ('<?xml version="1.0" encoding="UTF-8"?><styleSheet %s><fonts count="3">'
           '<font><sz val="11"/><name val="Calibri"/></font><font><sz val="11"/><name val="VNI-Times"/></font>'
           '<font><b/><name val=".VnArial"/></font></fonts>'
           '<cellXfs count="3"><xf fontId="0"/><xf fontId="1" applyFont="1"/><xf fontId="2" applyFont="1"/></cellXfs>'
           '<dxfs count="1"><dxf><font><name val="VNI-Helve"/></font></dxf></dxfs></styleSheet>') % X
SST = ('<?xml version="1.0" encoding="UTF-8"?><sst %s count="6" uniqueCount="4">'
       '<si><t>Vieät Nam</t></si>'
       '<si><t>Haø Noäi</t></si>'
       '<si><r><rPr><rFont val="VNI-Times"/></rPr><t>Vieät</t></r><r><t xml:space="preserve"> Nam</t></r></si>'
       '<si><t>®­</t></si></sst>') % X
SHEET = ('<?xml version="1.0" encoding="UTF-8"?><worksheet %s><sheetData><row r="1">'
         '<c r="A1" s="1" t="s"><v>0</v></c><c r="C1" s="2" t="s"><v>3</v></c>'
         '<c r="D1" s="1" t="inlineStr"><is><t>Ñaø Naüng</t></is></c>'
         '<c r="E1" s="1" t="str"><f>A1</f><v>Vieät</v></c><c r="F1" s="1"><v>12.5</v></c>'
         '<c r="G1" t="s"><v>2</v></c></row>'
         '<row r="2"><c r="A2" s="1" t="s"><v>1</v></c><c r="B2" t="s"><v>1</v></c></row></sheetData></worksheet>') % X
COMMENTS = ('<?xml version="1.0" encoding="UTF-8"?><comments %s><commentList><comment ref="A1"><text>'
            '<r><rPr><rFont val="VNI-Times"/></rPr><t>Ghi chuù</t></r><r><rPr><rFont val="Tahoma"/></rPr><t>Vieät</t></r>'
            '</text></comment></commentList></comments>') % X
xlsx = TAM / "So lieu.xlsx"
dung_zip(xlsx, {"[Content_Types].xml": CT_WORD, "xl/styles.xml": XSTYLES, "xl/sharedStrings.xml": SST,
                "xl/worksheets/sheet1.xml": SHEET, "xl/comments1.xml": COMMENTS})
kq = c.xu_ly_file(xlsx, "", False)
kt(kq["trangThai"] == "da-chuyen", "xlsx: tạo bản Unicode (%s %s)" % (kq["trangThai"], kq["lyDo"]))
if kq["ra"]:
    ra = Path(kq["ra"])
    sst = doc(ra, "xl/sharedStrings.xml")
    si = re.findall(r"<si>(.*?)</si>", sst)
    txt = [c.xml_text("".join(re.findall(r"<t(?: [^>]*)?>([^<]*)</t>", s))) for s in si]
    kt(txt[0] == "Việt Nam", "chữ dùng chung ở ô font VNI: %r" % txt[0])
    kt(txt[1] == "Haø Noäi" and len(txt) == 5 and txt[4] == "Hà Nội", "chữ dùng ở cả ô VNI và ô Calibri: giữ bản cũ cho ô Calibri, thêm bản đã chuyển (%r)" % txt)
    kt('uniqueCount="5"' in sst and 'count="6"' in sst, "uniqueCount tăng theo bản thêm, count giữ")
    kt(txt[2] == "Việt Nam" and "VNI-Times" not in sst, "chữ nhiều định dạng: đoạn có font VNI đổi, đoạn theo font ô (Calibri) giữ; rFont đổi tên (%r)" % txt[2])
    kt(txt[3] == "đư", "ô font .VnArial (TCVN3): %r" % txt[3])
    sh = doc(ra, "xl/worksheets/sheet1.xml")
    kt('<c r="A2" s="1" t="s"><v>4</v></c>' in sh and '<c r="B2" t="s"><v>1</v></c>' in sh, "ô A2 (VNI) trỏ sang bản đã chuyển, ô B2 (Calibri) giữ bản cũ")
    kt("<t>Đà Nẵng</t>" in sh and "<v>Việt</v>" in sh and "<f>A1</f>" in sh and "<v>12.5</v>" in sh, "chữ trong ô, kết quả công thức dạng chữ đổi; công thức, số giữ")
    xs = doc(ra, "xl/styles.xml")
    kt('<name val="Times New Roman"/>' in xs and '<name val="Arial"/>' in xs and "VNI-" not in xs and ".VnArial" not in xs, "styles.xml: font VNI, .VnArial (cả trong định dạng có điều kiện) đổi sang font Unicode")
    cm = doc(ra, "xl/comments1.xml")
    kt("<t>Ghi chú</t>" in cm and "<t>Vieät</t>" in cm, "ghi chú: đoạn font VNI đổi, đoạn font Tahoma giữ")

# ---------------------------------------------------------------- trường hợp khác
khong = TAM / "Unicode san.docx"
dung_zip(khong, {"[Content_Types].xml": CT_WORD, "word/document.xml": DOCUMENT.replace("VNI-Times", "Arial").replace('w:pStyle w:val="Vni', 'w:pStyle w:val="X').replace('w:rStyle w:val="Tcvn', 'w:rStyle w:val="X'), "word/styles.xml": STYLES.replace("VNI-Times", "Arial").replace(".VnTime", "Arial")})
kq = c.xu_ly_file(khong, "", False)
kt(kq["trangThai"] == "khong-co-chu-cu" and not kq["ra"] and not (TAM / "Unicode san_Unicode.docx").exists(), "tài liệu đã là Unicode: báo không có chữ font cũ, không tạo bản sao")
cu = TAM / "Cu.doc"
cu.write_bytes(b"\xd0\xcf\x11\xe0 doc cu")
kt(c.xu_ly_file(cu, "", False)["trangThai"] == "bo-qua", ".doc: bỏ qua, chỉ cách lưu thành .docx")
hong = TAM / "Hong.xlsx"
hong.write_bytes(b"khong phai zip")
kt(c.xu_ly_file(hong, "", False)["trangThai"] == "loi", "file hỏng: lỗi, không dừng cả lô")

# ---------------------------------------------------------------- dòng lệnh, kết quả cho trạm
lo = TAM / "lo"
lo.mkdir()
dung_zip(lo / "A.docx", {"[Content_Types].xml": CT_WORD, "word/document.xml": DOCUMENT, "word/styles.xml": STYLES})
(lo / "~$A.docx").write_bytes(b"tam")
(lo / "ghi chu.txt").write_text("x", encoding="utf-8")
ket_qua = TAM / "ket_qua"
tien_do = TAM / "tien_do.json"
ma = c.main([str(lo), "--chi-xem", "--ket-qua", str(ket_qua), "--tien-do", str(tien_do)])
kt(ma == 0 and not list(lo.glob("*_Unicode*")), "--chi-xem: mã 0, không tạo bản sao")
js = list(ket_qua.glob("KetQua_TiengViet_ChuyenUnicode_*.json"))
r = json.loads(js[0].read_text(encoding="utf-8")) if js else {}
kt(r.get("chuan") == "tramtool.ketqua/1" and r.get("congCu") == "tieng-viet" and r.get("cheDo") == "chuyen" and r.get("chayThu") is True,
   "JSON kết quả theo chuẩn của trạm (chế độ chuyen, chỉ xem là chạy thử)")
kt([f["ma"] for f in r.get("phatHien", [])] == ["CO_CHU_FONT_CU"], "chỉ A.docx được xét (bỏ file tạm ~$, file khác đuôi): %s" % [f["ma"] for f in r.get("phatHien", [])])
td = json.loads(tien_do.read_text(encoding="utf-8")) if tien_do.exists() else {}
kt(td.get("chuan") == "tramtool.tiendo/1" and td.get("phanTram") == 100.0 and td.get("tong") == 1, "file tiến độ: %s" % td)
for f in js:
    f.unlink()
ra_dir = TAM / "ra"
ra_dir.mkdir()
ma = c.main([str(lo / "A.docx"), str(hong), "--ra", str(ra_dir), "--ket-qua", str(ket_qua)])
r = json.loads(next(ket_qua.glob("*.json")).read_text(encoding="utf-8"))
kt(ma == 3 and (ra_dir / "A_Unicode.docx").exists() and r["maThoat"] == 3 and r["trangThai"] == "mot-phan",
   "--ra: bản Unicode vào thư mục chọn; có file lỗi thì mã 3, trạng thái một phần")
kt([f["ma"] for f in r["phatHien"]] == ["LOI_DOC_FILE", "DA_CHUYEN"], "phát hiện: lỗi lên đầu (%s)" % [f["ma"] for f in r["phatHien"]])
kt(c.main([str(TAM / "khong co"), "--ket-qua", str(ket_qua)]) == 2, "không có file nào: mã 2")
print("XONG")

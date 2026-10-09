# -*- coding: utf-8 -*-
"""Phần Python của bài thử 1_TienDo.ps1: tiến độ của DWG sang PDF cho Trạm Tool (chuẩn tramtool.tiendo/1).

Chạy bằng Python của máy (chuyen_dwg_sang_pdf.py chỉ dùng thư viện chuẩn). Không cần LibreDWG, ezdxf: bước đổi DXF
được thay, convert.py được thay bằng script giả in đúng các dòng nhật ký của convert.py thật rồi ghi một file PDF giả.
Mọi file nằm trong thư mục tạm (tham số 1); in mỗi kiểm tra một dòng "KT <1|0> <mô tả>".
"""

import json
import sys
import time
from pathlib import Path

TAM = Path(sys.argv[1])
CONG_CU = Path(sys.argv[2])
sys.path.insert(0, str(CONG_CU))
sys.stdout.reconfigure(encoding="utf-8")
import chuyen_dwg_sang_pdf as c  # noqa: E402


def kt(dk, mo_ta):
    print(f"KT {1 if dk else 0} {mo_ta}", flush=True)


# ---- đọc bước từ nhật ký của convert.py
mau = {
    "[10:00:01] read C:\\x\\ban_ve.dxf (12s) entities=5000 audit_errors=0": 0.30,
    "[10:00:02] frames found: 3 via blocks (13s)": 0.35,
    "[10:05:00] drawn (280s) mtext_fallback=0": 0.80,
    "[10:05:10]   sheet 1/4 'KT-01' 841x594 -> 420x297mm (290s)": 0.80 + 0.19 / 4,
    "[10:05:40]   sheet 4/4 'KT-04' 841x594 -> 420x297mm (320s)": 0.99,
    "[10:05:41] DONE C:\\x\\ket_qua.pdf pages=4 total=321s": 0.99,
    "[10:05:41]   NO FRAME FOUND -> single page of whole model": 0.99,
    "[10:00:03] sheet order: KT01-02, KT01-03": None,
    "[10:00:03] OLE pictures: 0": None,
}
sai = [t for t, v in mau.items() if c.phan_tu_dong(t) != v]
kt(not sai, f"đọc bước từ nhật ký convert.py ({sai})")

# ---- gộp tiến độ cả lô
p = TAM / "tien_do.json"
td = c.TienDo(str(p), 4)
td.bao("a", 0.5, "Bản vẽ 1/4 a.dwg: đang vẽ", ep=True)
d = json.loads(p.read_text(encoding="utf-8"))
kt(d["chuan"] == "tramtool.tiendo/1" and d["phanTram"] == 12.5 and d["xong"] == 0 and d["tong"] == 4, f"một bản vẽ làm được nửa trong 4 bản: 12,5% ({d})")
td.bao("a", 0.3, "lùi", ep=True)
kt(json.loads(p.read_text(encoding="utf-8"))["phanTram"] == 12.5, "phần đã làm không lùi lại")
td.bao("b", 1.0, "Bản vẽ 2/4 b.dwg: xong", ep=True, xong_file=True)
td.bao("c", 0.2, "Bản vẽ 3/4 c.dwg: đang đổi sang DXF")
d = json.loads(p.read_text(encoding="utf-8"))
kt(d["phanTram"] == 37.5 and d["xong"] == 1 and d["buoc"].startswith("Bản vẽ 2/4"), f"trong 1 giây không ghi lại trừ lúc đổi bước ({d['phanTram']}, {d['buoc']})")
kt(not p.with_name(p.name + ".tmp").exists(), "không để lại file tạm")
c.KHONG_TIEN_DO.bao("x", 1.0, "không có file", ep=True)
kt(True, "không có --tien-do: không ghi gì, không lỗi")

# ---- xu_ly với convert.py giả
gia = TAM / "convert_gia.py"
gia.write_text(
    "import sys, time\n"
    "for t in ['read ban_ve.dxf (1s) entities=10', 'frames found: 2 via blocks (1s)', 'drawn (2s) mtext_fallback=0',\n"
    "          \"  sheet 1/2 'A' 10x10 -> 420x297mm (3s)\", \"  sheet 2/2 'B' 10x10 -> 420x297mm (3s)\", 'DONE x pages=2 total=3s']:\n"
    "    print('[10:00:00] ' + t, flush=True)\n"
    "open(sys.argv[2], 'wb').write(b'%PDF-gia')\n",
    encoding="utf-8")
c.CONVERT = gia


def dxf_gia(src, work):
    dxf = work / "ban_ve.dxf"
    dxf.write_text("dxf gia", encoding="utf-8")
    return dxf


c.dwg_sang_dxf = dxf_gia
ve = TAM / "ban_ve"
ve.mkdir(exist_ok=True)
(ve / "KT-01.dwg").write_bytes(b"dwg gia")
(ve / "KT-02.dwg").write_bytes(b"dwg gia")
nhat_ky = []
goc = c.TienDo.bao


def ghi_lai(self, key, phan, buoc, ep=False, xong_file=False):
    nhat_ky.append((round(phan, 3), buoc))
    return goc(self, key, phan, buoc, ep, xong_file)


c.TienDo.bao = ghi_lai
p2 = TAM / "tien_do_lo.json"
sys.argv = ["chuyen_dwg_sang_pdf.py", str(ve), "--tien-do", str(p2)]
c.DWG2DXF = gia   # main() kiểm có LibreDWG: trỏ vào một file có thật
code = c.main()
d = json.loads(p2.read_text(encoding="utf-8"))
kt(code == 0 and (ve / "PDF" / "KT-01.pdf").read_bytes() == b"%PDF-gia" and (ve / "PDF" / "KT-02.pdf").exists(), f"chuyển 2 bản vẽ (mã {code})")
kt(d["phanTram"] == 100 and d["xong"] == 2 and d["tong"] == 2 and d["buoc"] == "Xong 2/2 bản vẽ", f"tiến độ cuối: 100%, 2/2 ({d})")
buoc_kt01 = [b for _, b in nhat_ky if "KT-01" in b]
can = ["đang đổi sang DXF", "đang đọc bản vẽ", "đã đọc xong, đang vẽ", "đang vẽ trang 1/2", "đang vẽ trang 2/2", "xong"]
kt(all(any(b.endswith(x) for b in buoc_kt01) for x in can), f"đủ các bước của một bản vẽ ({sorted(set(buoc_kt01))})")
phan_kt01 = [ph for ph, b in nhat_ky if "KT-01" in b]
kt(phan_kt01 == sorted(phan_kt01) and phan_kt01[-1] == 1.0, f"phần đã làm tăng dần tới 1 ({phan_kt01})")
kt(all(b.startswith("Bản vẽ 1/2 KT-01.dwg") for b in buoc_kt01), "mô tả có số thứ tự và tên bản vẽ")

nhat_ky.clear()
p3 = TAM / "tien_do_bo_qua.json"
sys.argv = ["chuyen_dwg_sang_pdf.py", str(ve), "--tien-do", str(p3)]
code = c.main()
d = json.loads(p3.read_text(encoding="utf-8"))
kt(code == 0 and d["phanTram"] == 100 and d["xong"] == 2 and any("đã có PDF, bỏ qua" in b for _, b in nhat_ky), "bản vẽ đã có PDF: bỏ qua, vẫn tính là xong")
print("XONG", flush=True)

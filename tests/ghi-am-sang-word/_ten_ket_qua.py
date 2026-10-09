# -*- coding: utf-8 -*-
"""Phần Python của bài thử 1_TenKetQua.ps1: đặt tên kết quả, nhận kết quả bản cũ, --ra.

Chạy bằng Python của máy (không cần .venv, faster-whisper hay python-docx): chuyen_doi.py chỉ nạp thư viện nặng
bên trong hàm. Mọi file nằm trong thư mục tạm (tham số 1); in mỗi kiểm tra một dòng "KT <1|0> <mô tả>".
"""

import json
import sys
from pathlib import Path

TAM = Path(sys.argv[1])
CONG_CU = Path(sys.argv[2])
sys.path.insert(0, str(CONG_CU))
sys.stdout.reconfigure(encoding="utf-8")
import chuyen_doi as cd  # noqa: E402


def kt(dk, mo_ta):
    print(f"KT {1 if dk else 0} {mo_ta}", flush=True)


def lam_sach(thu_muc):
    for p in sorted(thu_muc.rglob("*"), reverse=True):
        p.unlink() if p.is_file() else p.rmdir()


# Không bao giờ đụng thư mục công cụ thật: THU_MUC, KET_QUA trỏ vào thư mục tạm
cd.THU_MUC = TAM / "cong_cu"
cd.THU_MUC.mkdir(parents=True, exist_ok=True)
cd.dat_thu_muc_ket_qua(TAM / "ket_qua")
kt(cd.KET_QUA == (TAM / "ket_qua").resolve() and cd.DU_LIEU == cd.KET_QUA / "_du_lieu", "dat_thu_muc_ket_qua đổi cả ket_qua và _du_lieu")

# ---- tên kết quả
m4a, mp4 = Path("hop.m4a"), Path("hop.mp4")
kt(cd.file_ket_qua(m4a, ".docx").name == "hop.m4a - ban tho.docx", f"tên giữ đuôi: {cd.file_ket_qua(m4a, '.docx').name}")
kt(cd.file_ket_qua(m4a, ".docx") != cd.file_ket_qua(mp4, ".docx"), "hop.m4a và hop.mp4 ra hai file khác nhau")
kt(cd.file_du_lieu(m4a).name == "hop.m4a.json", f"dữ liệu chi tiết: {cd.file_du_lieu(m4a).name}")
cd.NHAN_MO_HINH = " (phowhisper-large-ct2)"
kt(cd.file_ket_qua(m4a, ".txt").name == "hop.m4a - ban tho (phowhisper-large-ct2).txt", "nhãn mô hình đứng sau phần ban tho")
cd.NHAN_MO_HINH = ""

# ---- chọn file cần làm
thu = TAM / "ghi_am"
thu.mkdir(parents=True, exist_ok=True)
for ten in ("hop.m4a", "hop.mp4", "ghi chu.txt"):
    (thu / ten).write_bytes(b"")


def con_lai(lam_lai=False):
    return sorted(p.name for p in cd.tim_file_dau_vao([str(thu)], lam_lai))


kt(con_lai() == ["hop.m4a", "hop.mp4"], f"chưa có kết quả: làm cả hai ({con_lai()})")
cd.KET_QUA.mkdir(parents=True, exist_ok=True)
cd.DU_LIEU.mkdir(parents=True, exist_ok=True)
cd.file_ket_qua(thu / "hop.m4a", ".docx").write_bytes(b"")
kt(con_lai() == ["hop.mp4"], f"hop.m4a xong thì hop.mp4 vẫn phải làm ({con_lai()})")
kt(con_lai(True) == ["hop.m4a", "hop.mp4"], "--lam-lai: làm cả hai")

# Kết quả bản 2026.10 (tên bỏ đuôi)
lam_sach(cd.KET_QUA)
cd.DU_LIEU.mkdir(parents=True, exist_ok=True)
(cd.KET_QUA / "hop - ban tho.docx").write_bytes(b"")
kt(con_lai() == ["hop.m4a", "hop.mp4"], "bản cũ không có dữ liệu kèm theo: không đoán, làm lại cả hai")
(cd.DU_LIEU / "hop.json").write_text(json.dumps({"tep": "hop.m4a"}), encoding="utf-8")
kt(con_lai() == ["hop.mp4"], f"bản cũ ghi tep=hop.m4a: chỉ bỏ qua hop.m4a ({con_lai()})")
(cd.DU_LIEU / "hop.json").write_text(json.dumps({"tep": "hop.mp4"}), encoding="utf-8")
kt(con_lai() == ["hop.m4a"], f"bản cũ ghi tep=hop.mp4: chỉ bỏ qua hop.mp4 ({con_lai()})")
(cd.DU_LIEU / "hop.json").write_text("{hỏng", encoding="utf-8")
kt(con_lai() == ["hop.m4a", "hop.mp4"], "dữ liệu kèm theo hỏng: làm lại, không văng lỗi")
cd.NHAN_MO_HINH = " (phowhisper-large-ct2)"
(cd.DU_LIEU / "hop.json").write_text(json.dumps({"tep": "hop.m4a"}), encoding="utf-8")
kt(con_lai() == ["hop.m4a", "hop.mp4"], "kết quả bản cũ của mô hình mặc định không tính cho mô hình khác")
cd.NHAN_MO_HINH = ""

# ---- xử lý một file: ghi đúng tên, không ghi đè file cùng tên khác đuôi (bỏ phần nhận dạng và Word)
lam_sach(cd.KET_QUA)
cd.doc_am_thanh = lambda f: f.name
cd.chuyen_thanh_chu = lambda model, am_thanh, goi_y, *a, **k: (
    [{"bat_dau": 0.0, "ket_thuc": 2.0, "van_ban": f"nội dung của {am_thanh}"}], 2.0, [{"trang_thai": "tot"}])
cd.ghi_docx = lambda duong_dan, ten_file, thoi_luong, ds: duong_dan.write_text(ten_file, encoding="utf-8")
for ten in ("hop.m4a", "hop.mp4"):
    cd.xu_ly_mot_file(thu / ten, None, "CPU", "", Path("models/gia"))
ten_ra = sorted(p.name for p in cd.KET_QUA.iterdir() if p.is_file())
kt(ten_ra == ["hop.m4a - ban tho.docx", "hop.m4a - ban tho.txt", "hop.mp4 - ban tho.docx", "hop.mp4 - ban tho.txt"],
   f"hai file ra bốn kết quả riêng ({ten_ra})")
kt("nội dung của hop.m4a" in (cd.KET_QUA / "hop.m4a - ban tho.txt").read_text(encoding="utf-8-sig"), "bản thô của hop.m4a không bị hop.mp4 ghi đè")
du_lieu = json.loads((cd.DU_LIEU / "hop.mp4.json").read_text(encoding="utf-8"))
kt(du_lieu.get("tep") == "hop.mp4", "_du_lieu\\hop.mp4.json ghi tep=hop.mp4")
kt(sorted(p.name for p in cd.DU_LIEU.iterdir()) == ["hop.m4a.json", "hop.mp4.json"], "mỗi file một dữ liệu chi tiết")

# ---- --ra: thư mục kết quả mới (kể cả thư mục cha chưa có) được dùng cho cả _du_lieu
ra = TAM / "noi khac" / "ket qua 'moi'"
sys.argv = ["chuyen_doi.py", str(thu / "hop.m4a"), "--ra", str(ra), "--mo-hinh", "khong-co-mo-hinh-nay"]
ma = cd.main()
kt(ma == 1, f"thiếu mô hình: dừng với mã 1 trước khi nhận dạng ({ma})")
kt(cd.KET_QUA == ra.resolve() and cd.DU_LIEU == ra.resolve() / "_du_lieu", f"--ra đổi thư mục kết quả ({cd.KET_QUA})")
cd.NHAN_MO_HINH = ""
cd.xu_ly_mot_file(thu / "hop.m4a", None, "CPU", "", Path("models/gia"))
kt((ra / "hop.m4a - ban tho.txt").is_file() and (ra / "_du_lieu" / "hop.m4a.json").is_file(), "--ra: tạo thư mục (cả cha) rồi ghi kết quả vào đó")

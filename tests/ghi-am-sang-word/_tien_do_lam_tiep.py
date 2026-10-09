# -*- coding: utf-8 -*-
"""Phần Python của bài thử 2_TienDoLamTiep.ps1: tiến độ cho Trạm Tool, lưu từng khúc để làm tiếp, thử lại khúc khi
card đồ hoạ hết bộ nhớ, chuyển CPU làm tiếp chứ không làm lại.

Chạy bằng Python của máy (không cần .venv): mô hình giả, âm thanh là danh sách số 0, không gọi bộ dò tiếng nói thật.
Mọi file nằm trong thư mục tạm (tham số 1); in mỗi kiểm tra một dòng "KT <1|0> <mô tả>".
"""

import json
import os
import sys
import time
from pathlib import Path

TAM = Path(sys.argv[1])
CONG_CU = Path(sys.argv[2])
sys.path.insert(0, str(CONG_CU))
sys.stdout.reconfigure(encoding="utf-8")
import chuyen_doi as cd  # noqa: E402

cd.time.sleep = lambda s: None   # thử lại khi hết bộ nhớ card không chờ thật


def kt(dk, mo_ta):
    print(f"KT {1 if dk else 0} {mo_ta}", flush=True)


# Không bao giờ đụng thư mục công cụ thật
cd.THU_MUC = TAM / "cong_cu"
cd.THU_MUC.mkdir(parents=True, exist_ok=True)
cd.dat_thu_muc_ket_qua(TAM / "ket_qua")

# ---- TienDo
p = TAM / "tien_do.json"
td = cd.TienDo(str(p))
td.ghi(12.345, "Khúc 1/8", 0, 2, ep=True)
d = json.loads(p.read_text(encoding="utf-8"))
kt(d["chuan"] == "tramtool.tiendo/1" and d["phanTram"] == 12.3 and d["buoc"] == "Khúc 1/8" and d["tong"] == 2, f"ghi đúng chuẩn: {d}")
kt(not p.with_name(p.name + ".tmp").exists(), "không để lại file tạm")
td.ghi(50, "Khúc 4/8")
kt(json.loads(p.read_text(encoding="utf-8"))["phanTram"] == 12.3, "trong 1 giây không ghi lại (trừ ep)")
td.ghi(150, "x" * 500, ep=True)
d = json.loads(p.read_text(encoding="utf-8"))
kt(d["phanTram"] == 100 and len(d["buoc"]) == 200 and d["conLaiGiay"] is None, "kẹp 100%, cắt 200 ký tự, 100% thì không ước thời gian còn lại")
td.t0 -= 100
td.ghi(25, "Khúc 2/8", ep=True)
kt(json.loads(p.read_text(encoding="utf-8"))["conLaiGiay"] == 300, "chạy 100 giây được 25%: còn khoảng 300 giây")
cd.TienDo(None).ghi(10, "không có file", ep=True)
kt(True, "không có --tien-do: không làm gì, không lỗi")


# ---- mô hình giả
class Doan:
    def __init__(self, text, start=0.0, end=1.0):
        self.text, self.start, self.end = text, start, end
        self.avg_logprob, self.no_speech_prob, self.compression_ratio = -0.2, 0.01, 1.2


class MoHinhGia:
    """Khúc thứ k (theo giây bắt đầu) trả câu "câu k". loi: {k: [lỗi lần 1, lỗi lần 2, ...]} ném ra theo lượt gọi."""

    def __init__(self, loi=None, ten="gpu"):
        self.loi = {k: list(v) for k, v in (loi or {}).items()}
        self.goi = []
        self.ten = ten

    def transcribe(self, doan_am, beam_size=5, initial_prompt=None, **kw):
        k = self.dang_lam
        self.goi.append((k, beam_size))
        ds = self.loi.get(k)
        if ds:
            e = ds.pop(0)
            if e is not None:
                raise e
        return [Doan(f"câu số {k} của {self.ten}")], None


KHUC = [{"bd": float(i * 10), "kt": float(i * 10 + 5), "noi": 5.0} for i in range(8)]
cd.tim_khuc_tieng_noi = lambda am: json.loads(json.dumps(KHUC))
goc_nhan_dang = cd.nhan_dang_khuc


def nhan_dang_ghi_lai(model, am_thanh, bd, kt_, giay_noi, ngu_canh, goi_y, do_sau=0, so_chum=cd.SO_CHUM):
    model.dang_lam = int(bd // 10)
    return goc_nhan_dang(model, am_thanh, bd, kt_, giay_noi, ngu_canh, goi_y, do_sau, so_chum)


cd.nhan_dang_khuc = nhan_dang_ghi_lai
AM = [0.0] * (cd.TAN_SO * 80)
f = TAM / "hop.m4a"
f.write_bytes(b"ghi am gia")
vt = cd.dau_van_tay(f, "Nguyễn Văn A", "faster-whisper-large-v3")
dang_lam = cd.file_dang_lam(f)

# ---- Ctrl+C giữa chừng: lưu phần đã xong
m = MoHinhGia({3: [KeyboardInterrupt()]})
try:
    cd.chuyen_thanh_chu(m, AM, "Nguyễn Văn A", f, vt)
    kt(False, "Ctrl+C phải dừng việc nhận dạng")
except KeyboardInterrupt:
    pass
d = json.loads(dang_lam.read_text(encoding="utf-8"))
kt(d["so_khuc_xong"] == 3 and len(d["cau"]) == 3 and d["van_tay"] == vt, f"dừng ở khúc 4: lưu 3 khúc đã xong ({d['so_khuc_xong']}, {len(d['cau'])} câu)")

# ---- chạy lại: làm tiếp từ khúc 4
m2 = MoHinhGia()
moc = []
ds, thoi_luong, cac_khuc = cd.chuyen_thanh_chu(m2, AM, "Nguyễn Văn A", f, vt, bao=lambda pt, buoc: moc.append((pt, buoc)))
kt([k for k, _ in m2.goi] == [3, 4, 5, 6, 7], f"chỉ nhận dạng khúc chưa xong ({[k for k, _ in m2.goi]})")
kt([c["van_ban"] for c in ds] == [f"câu số {k} của gpu" for k in range(8)], "câu đủ 8 khúc, đúng thứ tự, không lặp")
kt(all(k.get("trang_thai") == "tot" for k in cac_khuc), "mọi khúc có trạng thái")
kt(moc and moc[-1][0] == 75 / 80 * 100 and moc[-1][1] == "Khúc 8/8, tới 00:01:15" and all(a[0] <= b[0] for a, b in zip(moc, moc[1:])), f"báo tiến độ tăng dần theo vị trí khúc ({moc[-1] if moc else None})")
kt(json.loads(dang_lam.read_text(encoding="utf-8"))["so_khuc_xong"] == 8, "xong hết thì file làm dở ghi đủ 8 khúc (xu_ly_mot_file xoá sau khi ghi Word)")

# ---- gợi ý khác: không dùng phần cũ
m3 = MoHinhGia()
cd.chuyen_thanh_chu(m3, AM, "gợi ý khác", f, cd.dau_van_tay(f, "gợi ý khác", "faster-whisper-large-v3"))
kt(len(m3.goi) == 8, "đổi gợi ý thì làm lại từ đầu")
f.write_bytes(b"ghi am gia da sua")
kt(cd.doc_dang_lam(f, cd.dau_van_tay(f, "Nguyễn Văn A", "faster-whisper-large-v3")) is None, "file ghi âm đổi thì không làm tiếp")
cd.xoa_dang_lam(f)
kt(not dang_lam.exists(), "xoa_dang_lam xoá file làm dở")

# ---- card đồ hoạ hết bộ nhớ ở một khúc
oom = RuntimeError("CUDA failed with error out of memory")
m4 = MoHinhGia({2: [oom, None]})
ds, _, _ = cd.chuyen_thanh_chu(m4, AM, "", f, cd.dau_van_tay(f, "", "m"))
kt(len(ds) == 8 and [b for k, b in m4.goi if k == 2] == [5, 5], "hết bộ nhớ một lần: thử lại khúc đó, vẫn beam 5")
m5 = MoHinhGia({2: [oom, oom, None]})
cd.chuyen_thanh_chu(m5, AM, "", f, cd.dau_van_tay(f, "", "m5"))
kt([b for k, b in m5.goi if k == 2] == [5, 5, 1], "hết bộ nhớ hai lần: lần ba dùng beam 1")
m6 = MoHinhGia({5: [oom, oom, oom]})
vt6 = cd.dau_van_tay(f, "", "m6")
try:
    cd.chuyen_thanh_chu(m6, AM, "", f, vt6)
    kt(False, "hết bộ nhớ ba lần phải báo lỗi")
except RuntimeError as e:
    kt(cd.la_het_bo_nho(e), "hết bộ nhớ ba lần: báo lỗi để chuyển CPU")
kt(cd.doc_dang_lam(f, vt6)["so_khuc_xong"] == 5, "lỗi ở khúc 6: đã lưu 5 khúc")
m7 = MoHinhGia({1: [RuntimeError("cuDNN lỗi khác")]})
try:
    cd.chuyen_thanh_chu(m7, AM, "", f, cd.dau_van_tay(f, "", "m7"))
    kt(False, "lỗi khác phải báo ngay")
except RuntimeError:
    kt(len([k for k, _ in m7.goi if k == 1]) == 1, "lỗi không phải hết bộ nhớ: không thử lại")

# ---- xu_ly_mot_file: card lỗi thì CPU làm tiếp; xong thì xoá file làm dở; --lam-lai
cd.doc_am_thanh = lambda duong_dan: AM
cd.ghi_docx = lambda duong_dan, *a: Path(duong_dan).write_bytes(b"docx gia")
cpu = MoHinhGia(ten="cpu")
cd.nap_mo_hinh = lambda dung_cpu, thu_muc=None: (cpu, "CPU")
mo_hinh = TAM / "models" / "faster-whisper-large-v3"
gpu = MoHinhGia({4: [RuntimeError("CUDA error: an illegal memory access")]})
cd.xu_ly_mot_file(f, gpu, "card đồ họa NVIDIA", "", mo_hinh)
kt([k for k, _ in cpu.goi] == [4, 5, 6, 7], f"card lỗi ở khúc 5: CPU làm tiếp từ khúc 5 ({[k for k, _ in cpu.goi]})")
du_lieu = json.loads(cd.file_du_lieu(f).read_text(encoding="utf-8"))
kt([c["van_ban"].split(" của ")[1] for c in du_lieu["cau"]] == ["gpu"] * 4 + ["cpu"] * 4, "kết quả ghép phần GPU và phần CPU")
kt(not cd.file_dang_lam(f).exists() and cd.file_ket_qua(f, ".docx").exists(), "xong thì xoá file làm dở, có file Word")

vt8 = cd.dau_van_tay(f, "", mo_hinh.name)
KHUC_XONG6 = [dict(k, trang_thai="tot") if i < 6 else dict(k) for i, k in enumerate(KHUC)]
cd.ghi_dang_lam(f, vt8, KHUC_XONG6, 6, [{"van_ban": f"cũ {k}", "bat_dau": k * 10.0, "ket_thuc": k * 10 + 5.0} for k in range(6)], "")
m8 = MoHinhGia()
cd.xu_ly_mot_file(f, m8, "CPU", "", mo_hinh, lam_lai=True)
kt(len(m8.goi) == 8, "--lam-lai: bỏ phần làm dở, làm từ đầu")
cd.ghi_dang_lam(f, vt8, KHUC_XONG6, 6, [{"van_ban": f"cũ {k}", "bat_dau": k * 10.0, "ket_thuc": k * 10 + 5.0} for k in range(6)], "")
os.environ["GHI_AM_CHAY_TIEP"] = "1"
m9 = MoHinhGia()
cd.xu_ly_mot_file(f, m9, "CPU", "", mo_hinh, lam_lai=True)
del os.environ["GHI_AM_CHAY_TIEP"]
kt([k for k, _ in m9.goi] == [6, 7], "chạy lại bằng CPU sau khi card làm sập (GHI_AM_CHAY_TIEP): giữ phần đã xong dù có --lam-lai")
print("XONG", flush=True)

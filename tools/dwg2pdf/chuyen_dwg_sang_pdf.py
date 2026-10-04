"""Chuyển bản vẽ AutoCAD (.dwg) sang PDF, mỗi khung tên (khung bản vẽ) thành một trang.

Cách dùng:
  Kéo thả thư mục bản vẽ (hoặc các file .dwg) vào CHUYEN_DWG_SANG_PDF.bat
  hoặc: .venv\\Scripts\\python.exe chuyen_dwg_sang_pdf.py <thư mục|file.dwg>... [tùy chọn]

Tùy chọn:
  --ra THU_MUC     nơi lưu PDF (mặc định: thư mục PDF nằm cạnh bản vẽ)
  --lam-lai        làm lại cả bản vẽ đã có PDF mới hơn file .dwg
  --song-song N    số bản vẽ xử lý cùng lúc (mặc định 1; mỗi bản vẽ lớn tốn vài GB RAM)

Các bước cho mỗi file:
  1. Chép .dwg ra thư mục tạm với tên ngắn (LibreDWG không đọc được đường dẫn có dấu tiếng Việt).
  2. LibreDWG dwg2dxf đổi sang DXF. Nếu LibreDWG từ chối nhầm ("Invalid System Section",
     gặp ở một số file AutoCAD 2007), đệm 2 MB số 0 vào BẢN SAO rồi thử lại. File gốc không bị đụng.
  3. convert.py vẽ DXF thành PDF đen trắng (giống monochrome.ctb), chạy trong tiến trình riêng.

Mã thoát: 0 = xong hết, 1 = có file lỗi, 2 = không có gì để làm hoặc thiếu công cụ.
"""
import argparse
import concurrent.futures as cf
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DWG2DXF = HERE / "bin" / "libredwg" / "dwg2dxf.exe"
CONVERT = HERE / "convert.py"
PRINT_LOCK = threading.Lock()


def say(msg: str) -> None:
    with PRINT_LOCK:
        print(msg, flush=True)


def tim_ban_ve(inputs):
    seen = set()
    for raw in inputs:
        p = Path(raw)
        files = sorted(p.glob("*.dwg")) + sorted(p.glob("*.DWG")) if p.is_dir() else [p]
        for f in files:
            key = str(f.resolve()).lower()
            if f.is_file() and f.suffix.lower() == ".dwg" and key not in seen:
                seen.add(key)
                yield f


def dwg_sang_dxf(src: Path, work: Path) -> Path:
    tmp = work / "ban_ve.dwg"
    dxf = work / "ban_ve.dxf"
    shutil.copy2(src, tmp)

    def chay() -> str:
        if dxf.exists():
            dxf.unlink()
        r = subprocess.run([str(DWG2DXF), "-y", "-o", str(dxf), str(tmp)], capture_output=True, timeout=900)
        return (r.stdout + r.stderr).decode("utf-8", "replace")

    log = chay()
    if "Invalid System Section" in log or not dxf.exists() or dxf.stat().st_size < 20_000:
        with open(tmp, "ab") as f:
            f.write(b"\0" * 2_000_000)
        log = chay()
    if not dxf.exists() or dxf.stat().st_size < 20_000:
        loi = [l for l in log.splitlines() if "ERROR" in l.upper()][-3:]
        raise RuntimeError("LibreDWG không đọc được bản vẽ. " + " | ".join(loi))
    return dxf


def dxf_sang_pdf(dxf: Path, pdf_tmp: Path, ten: str) -> None:
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    p = subprocess.Popen(
        [sys.executable, "-u", str(CONVERT), str(dxf), str(pdf_tmp), "mono"],
        cwd=str(HERE), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    cuoi = []
    for line in p.stdout:
        text = line.decode("utf-8", "replace").rstrip()
        cuoi = (cuoi + [text])[-8:]
        if "sheet" in text or "DONE" in text or "NO FRAME" in text:
            say(f"    {ten}: {text}")
    if p.wait() != 0 or not pdf_tmp.exists():
        raise RuntimeError("convert.py lỗi:\n      " + "\n      ".join(cuoi))


def xu_ly(src: Path, out_dir: Path, lam_lai: bool, so_thu_tu: str) -> str:
    pdf = out_dir / (src.stem + ".pdf")
    if pdf.exists() and not lam_lai and pdf.stat().st_mtime >= src.stat().st_mtime:
        say(f"{so_thu_tu} {src.name}: đã có PDF, bỏ qua (thêm --lam-lai để làm lại)")
        return "bo-qua"
    t0 = time.time()
    say(f"{so_thu_tu} {src.name}: đang đổi sang DXF...")
    with tempfile.TemporaryDirectory(prefix="dwg2pdf_") as tmp:
        work = Path(tmp)
        dxf = dwg_sang_dxf(src, work)
        say(f"{so_thu_tu} {src.name}: đang vẽ PDF (bản vẽ lớn có thể mất 5 đến 35 phút)...")
        pdf_tmp = work / "ket_qua.pdf"
        dxf_sang_pdf(dxf, pdf_tmp, src.stem)
        out_dir.mkdir(parents=True, exist_ok=True)
        shutil.move(str(pdf_tmp), str(pdf))
    say(f"{so_thu_tu} {src.name}: XONG -> {pdf} ({time.time() - t0:.0f} giây)")
    return "xong"


def main() -> int:
    # Khi đầu ra bị chuyển hướng (ghi ra file, chạy từ công cụ khác), Windows mặc định cp1252 không in được tiếng Việt.
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description="Chuyển bản vẽ .dwg sang PDF")
    ap.add_argument("dau_vao", nargs="*", help="thư mục chứa .dwg hoặc file .dwg")
    ap.add_argument("--ra", help="thư mục lưu PDF")
    ap.add_argument("--lam-lai", action="store_true")
    ap.add_argument("--song-song", type=int, default=1)
    a = ap.parse_args()

    if not DWG2DXF.exists():
        say(f"Thiếu LibreDWG ({DWG2DXF}). Chạy CAI_DAT.ps1 (hoặc nút Cài trong Trạm Tool) trước.")
        return 2
    if not a.dau_vao:
        say("Chưa chọn bản vẽ. Kéo thả thư mục chứa file .dwg vào CHUYEN_DWG_SANG_PDF.bat.")
        return 2
    files = list(tim_ban_ve(a.dau_vao))
    if not files:
        say("Không tìm thấy file .dwg nào trong: " + ", ".join(a.dau_vao))
        return 2

    say(f"Có {len(files)} bản vẽ. Kết quả lưu vào {a.ra if a.ra else 'thư mục PDF nằm cạnh bản vẽ'}.\n")
    t0 = time.time()
    kq = {}
    n = len(files)
    workers = max(1, min(a.song_song, 4))
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {}
        for i, f in enumerate(files, 1):
            out_dir = Path(a.ra) if a.ra else f.parent / "PDF"
            futs[ex.submit(xu_ly, f, out_dir, a.lam_lai, f"[{i}/{n}]")] = f
        for fut in cf.as_completed(futs):
            f = futs[fut]
            try:
                kq[f] = fut.result()
            except Exception as e:  # noqa: BLE001 - báo lỗi từng file, không dừng cả lô
                kq[f] = "loi"
                say(f"  LỖI {f.name}: {e}")

    loi = [f.name for f, v in kq.items() if v == "loi"]
    say(f"\nTổng: {sum(v == 'xong' for v in kq.values())} xong, {sum(v == 'bo-qua' for v in kq.values())} bỏ qua, "
        f"{len(loi)} lỗi, {time.time() - t0:.0f} giây.")
    if loi:
        say("File lỗi: " + "; ".join(loi))
    return 1 if loi else 0


if __name__ == "__main__":
    sys.exit(main())

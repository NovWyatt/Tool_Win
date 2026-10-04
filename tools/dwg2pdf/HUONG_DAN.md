# Bản vẽ DWG sang PDF

Chuyển bản vẽ AutoCAD (`.dwg`) sang PDF đen trắng, **mỗi khung bản vẽ thành một trang**, không cần cài
AutoCAD. Chạy hoàn toàn trên máy, không gửi bản vẽ đi đâu.

## Cách dùng

- **Trong Trạm Tool:** bấm **Chuyển cả thư mục bản vẽ**, chọn thư mục chứa các file `.dwg`, bấm Chạy.
- **Không có Trạm Tool:** kéo thả thư mục bản vẽ (hoặc vài file `.dwg`) vào `CHUYEN_DWG_SANG_PDF.bat`.
- **Dòng lệnh:**
  ```
  .venv\Scripts\python.exe chuyen_dwg_sang_pdf.py "D:\Ban ve" [--ra THU_MUC] [--lam-lai] [--song-song N]
  ```

Kết quả: thư mục `PDF` nằm cạnh bản vẽ, mỗi file `.dwg` ra một file `.pdf` cùng tên. Bản vẽ đã có PDF mới
hơn file `.dwg` thì bỏ qua (thêm `--lam-lai` để làm lại).

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `--ra THU_MUC` | lưu PDF vào thư mục khác thay vì `PDF` cạnh bản vẽ |
| `--lam-lai` | làm lại cả bản vẽ đã có PDF |
| `--song-song N` | xử lý N bản vẽ cùng lúc (tối đa 4). Mỗi bản vẽ lớn tốn vài GB RAM: máy 8 GB để 1 |

Thời gian: bản vẽ nhỏ khoảng 1–2 phút, bản vẽ lớn nhiều chi tiết 5–35 phút.

## Cài đặt (máy mới)

`CHUYEN_DWG_SANG_PDF.bat` tự hỏi cài khi thiếu. Hoặc chạy:

```
powershell -ExecutionPolicy Bypass -File CAI_DAT.ps1          (thêm -LamLai để dựng lại từ đầu)
```

Không cần quyền Admin. Script sẽ:

1. Tìm Python 3.12, thiếu thì cài bản cho riêng tài khoản bằng winget.
2. Tạo `.venv` và cài thư viện đúng phiên bản trong `requirements.txt` / `requirements-lock.txt`.
3. Tải LibreDWG 0.14 từ GitHub, **kiểm tra mã SHA256** trước khi giải nén vào `bin\libredwg`.
4. Tự kiểm tra.

Cần mạng Internet lần đầu, tải khoảng 100 MB.

## Cách hoạt động

1. Chép `.dwg` ra thư mục tạm với tên ngắn (LibreDWG không mở được đường dẫn có dấu tiếng Việt).
2. LibreDWG `dwg2dxf` đổi sang DXF. Một số file AutoCAD 2007 bị LibreDWG từ chối nhầm
   ("Invalid System Section"): công cụ đệm 2 MB số 0 vào **bản sao** rồi thử lại. File gốc không bị đụng.
3. `convert.py` đọc DXF bằng ezdxf, tìm các khung bản vẽ, sắp theo mã bản vẽ, vẽ từng khung thành một
   trang PDF bằng PyMuPDF với nét in đen trắng giống `monochrome.ctb`. Chữ VNI-Windows được đổi sang
   Unicode (`vni.py`), bảng Excel nhúng (OLE) được chèn vào dưới dạng ảnh.

## Giới hạn đã biết

- Chữ dùng font **TCVN3** (`.VnTime`, `.VnArial`...) chưa giải mã được, sẽ ra ký tự lạ. Chữ VNI thì đã xử lý.
- `convert.py` vá thẳng vào bên trong ezdxf 1.4.4 và PyMuPDF 1.28.2. **Không tự nâng phiên bản thư viện**;
  muốn nâng thì chạy lại một bộ bản vẽ mẫu và so sánh PDF trước.
- Bản vẽ không có khung nào nhận ra được thì cả model space ra một trang.
- Chưa có thanh phần trăm; cửa sổ chỉ báo khi xong từng trang ("sheet 1/2 ...").

## Giấy phép thành phần bên thứ ba

| Thành phần | Giấy phép | Ghi chú |
|---|---|---|
| LibreDWG 0.14 | GPL-3.0 | tải về khi cài, không đi kèm repo |
| ezdxf | MIT | |
| PyMuPDF | AGPL-3.0 | dùng nội bộ trên máy; muốn phân phối phần mềm đóng thì cần giấy phép thương mại |
| Pillow, olefile, numpy, fonttools | giấy phép mở kiểu MIT/BSD | |

Ghi chú khôi phục mã nguồn và quá trình làm bộ bản vẽ SAMSORA: [docs/GHI-CHU-KHOI-PHUC.md](docs/GHI-CHU-KHOI-PHUC.md).

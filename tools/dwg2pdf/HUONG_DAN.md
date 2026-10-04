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
   trang PDF bằng PyMuPDF với nét in đen trắng giống `monochrome.ctb`. Bảng Excel nhúng (OLE) được chèn vào
   dưới dạng ảnh.

## Chữ tiếng Việt font cũ

Máy không cần cài font VNI hay TCVN3: công cụ đổi chữ sang Unicode theo font của từng kiểu chữ rồi vẽ bằng
font Unicode có sẵn trong Windows.

| Bảng mã | Font trong bản vẽ | Xử lý |
|---|---|---|
| VNI-Windows | `VNI-Times`, `VNI-Avo`, `VNI-Helve`... | `vni.py`, vẽ bằng Arial |
| TCVN3 (ABC) | `.VnTime`, `.VnArial`, `.VnArial Narrow`... | `tcvn3.py`: `.VnTime` → Times New Roman, `.VnArial` → Arial, `.VnArial Narrow` → Arial co ngang 0,82 (Arial Narrow của Windows thiếu phần lớn chữ có dấu); font đuôi `H` (`.VnTimeH`) là font chữ hoa nên chữ được viết hoa |

Chỉ chữ thực sự vẽ bằng font TCVN3 mới được đổi (theo kiểu chữ và mã đổi font `\f` trong MTEXT), kể cả mã
`%%nnn` của AutoCAD (vd `c%%230 phÇn` → "cổ phần"). Chữ Unicode gõ bằng font thường giữ nguyên.

## Giới hạn đã biết

- Chữ TCVN3 nằm trong đổi font giữa dòng của MTEXT đổi sang Arial nhưng không co ngang; chữ trong MULTILEADER và
  bảng (TABLE) chưa được đổi bảng mã.
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

# CheckWinFix — bộ script chẩn đoán máy Windows bị chậm

| File | Dùng khi nào |
|---|---|
| `ThuThapThongTin.bat` | **Luôn chạy đầu tiên** trên máy bị chậm. Chỉ đọc, xuất `LagReport_*.txt` |
| `1-CUU-DU-LIEU.bat` | Khi đã xác định ổ đĩa hỏng — copy dữ liệu ra khỏi ổ đó trước khi mất |
| `2-CHAN-DOAN-PHAN-CUNG.bat` | Khi có lỗi WHEA / màn hình xanh — bản đồ ổ đĩa, SMART có ngưỡng, minidump |
| `3-GIAI-MA-WHEA.bat` | Giải mã bản ghi WHEA (chuẩn UEFI CPER) → chỉ đích danh CPU / RAM / PCIe / ổ đĩa |
| `4-XUAT-BANG-CHUNG.bat` | Xuất hồ sơ bằng chứng (.evtx gốc + CSV + SMART) để nộp lên công ty |
| `5-CHAN-DOAN-SUP-NGUON.bat` | Máy **sụp nguồn / tự tắt / tự khởi động lại** — phân loại từng lần sập (mất điện thật, màn hình xanh ẩn, giữ nút nguồn, lỗi khi ngủ), nhiệt độ, pin/nguồn, có chế độ **theo dõi liên tục** đến lúc sập. Xuất `SupNguon_*.txt` |

Tất cả đều tự nâng quyền Admin và chỉ đọc. Riêng script 1 có dừng/bật lại dịch vụ SQL (có hỏi trước), script 4 có tuỳ chọn tạo Custom View trong Event Viewer (có hỏi trước), script 5 có tuỳ chọn bật minidump + tắt AutoReboot để lần sau thấy mã lỗi (có hỏi trước).

Kiểm tra quyền Admin bằng `fltmc` (không cần dịch vụ Server như `net session`), tự mở lại bằng quyền Admin đúng một lần. Mã thoát: 0 xong, 1 lỗi (kể cả không ghi được báo cáo), 2 không có quyền Admin hoặc đã huỷ, 3 xong một phần (chỉ script 1).

## Cứu dữ liệu (script 1, bản 2.0)

- Nơi lưu phải nằm trên **ổ vật lý khác** với ổ đang hỏng: script liệt kê các ổ khác (ưu tiên USB) và từ chối nơi lưu cùng ổ vật lý (C: và D: thường là hai phân vùng của cùng một ổ).
- Dừng **mọi** dịch vụ SQL Server (mọi instance `MSSQL$...`, Agent, Full-text, SSIS, SQLWriter...), đóng ITS-Pro, SSMS.
- Chép bằng robocopy vào một **thư mục mới** `CUU_DU_LIEU_ITS_<ngày giờ>` (không bao giờ chép chồng lên lần trước).
- Đối chiếu MD5 file `.mdf/.ldf/.ndf/.bak` **trong lúc SQL Server còn dừng** (bản cũ đối chiếu sau khi bật lại nên file bị khoá, luôn báo "không khớp").
- Luôn bật lại đúng các dịch vụ đã dừng, kể cả khi lỗi giữa chừng. Cửa sổ bị đóng khi SQL đang dừng thì lần chạy sau script nhắc và bật lại (danh sách ghi tạm ở `HKLM\SOFTWARE\TramTool\CuuDuLieu`).
- Kết quả `KET_QUA_CUU_DU_LIEU.txt` và `robocopy_log.txt` nằm trong thư mục cứu.

**Ca thực tế đã xử lý:** [du-lieu/ca-DESKTOP-2VQE588/CHAN-DOAN-DESKTOP-2VQE588.md](du-lieu/ca-DESKTOP-2VQE588/CHAN-DOAN-DESKTOP-2VQE588.md) (dữ liệu khách, chỉ lưu trên máy, không đưa lên git) — biên bản trình bày: https://claude.ai/artifact/VCqBxCGexui2ZpVXerB9up

---

# Bước 1: Thu thập thông tin

## Chạy thế nào

1. Copy **`ThuThapThongTin.bat`** sang máy đang bị chậm (USB / Zalo / email đều được).
   - ⚠️ **Đừng mở bằng Notepad rồi lưu lại** — sẽ hỏng bảng mã và script không chạy.
2. Chuột phải → **Run as administrator** (nếu bấm đúp, script tự xin quyền Admin, bấm **Yes**).
3. Script hỏi 3 câu (có thể Enter bỏ qua):
   - Máy bắt đầu chậm từ khi nào?
   - Chậm kiểu gì?
   - Có kiểm tra sâu không (ảnh Windows bằng DISM, lỗi hệ thống file từng ổ, thêm 5–20 phút)?
   Chạy từ Trạm Tool thì hai câu đầu và ô *Kiểm tra sâu* nằm trong form, cửa sổ không hỏi gì.
4. Chờ **~1,5–3 phút**. Xong sẽ tự mở Notepad hiện báo cáo.
5. File kết quả nằm **ngay cạnh file .bat**, tên `LagReport_<TênMáy>_<ngày giờ>.txt` (~70–150 KB), kèm
   `KetQua_CheckWinFix_ThuThap_<TênMáy>_<ngày giờ>.json` cho Trạm Tool.
6. Gửi file .txt đó lại cho tôi → tôi phân tích và viết `.bat` sửa đúng bệnh của máy đó.

**Script chỉ ĐỌC. Không xoá, không sửa registry, không cài gì, không gửi dữ liệu đi đâu.**

## Nó thu thập gì (24 mục)

| # | Mục | Bắt bệnh gì |
|---|-----|-------------|
| 1 | Thông tin máy, OS, BIOS, uptime, Fast Startup | Máy quá cũ, không restart lâu ngày |
| 2 | CPU + tần số thực / % tần số tối đa, Interrupt & DPC | **Bóp xung do nóng/pin**, driver lỗi gây giật |
| 3 | RAM, pagefile, pool non-paged | Thiếu RAM, **rò rỉ bộ nhớ do driver** |
| 4 | Ổ đĩa vật lý + **SMART chi tiết** (bad sector, lỗi đọc/ghi, độ hao mòn) | **Ổ cứng sắp hỏng** — nguyên nhân số 1 |
| 5 | Dung lượng trống, dirty bit, thư mục rác, file chỉ mục | Đầy ổ C, NTFS hỏng, index phình |
| 6 | Đo hiệu năng 3 lần: CPU/đĩa/bộ nhớ/hàng đợi | **"100% disk"**, CPU quá tải, swap liên tục |
| 7 | Top tiến trình theo CPU/RAM/IO + **svchost chứa dịch vụ gì** + chữ ký số | Phần mềm ăn CPU, **đào tiền ảo / mã độc** |
| 8 | Khởi động cùng Windows, Winlogon, AppInit_DLLs, IFEO | Khởi động chậm, mã độc cắm vào mọi app |
| 9 | Dịch vụ bên thứ ba đang chạy / Auto mà lỗi | Dịch vụ rác, dịch vụ crash |
| 10 | Tác vụ hẹn giờ không phải của Microsoft | Tác vụ nền chạy ngầm |
| 11 | Power plan (**giới hạn % CPU**), sức khoẻ pin | **CPU bị khoá ở 30–50%** — lỗi rất hay gặp |
| 12 | Defender + **các AV khác đang cài** | **Xung đột 2 phần mềm diệt virus** |
| 13 | VBS / Memory Integrity / Hyper-V | Mất 5–15% hiệu năng sau khi update Windows |
| 14 | Card màn hình + driver | Mất driver GPU → giao diện giật |
| 15 | Thiết bị lỗi trong Device Manager + driver mới cài | Driver hỏng |
| 16 | Mạng, **proxy**, file hosts, ổ mạng | Adware đổi proxy, hosts bị crack sửa |
| 17 | **Nhật ký hiệu năng của Windows** | Windows *tự khai* cái gì làm chậm boot |
| 18 | Log System 14 ngày + đối chiếu 25 lỗi đã biết theo **nguồn + mã**, gồm cả mức Warning (disk 153/154/51, Display 4101, WHEA 1/17/18/19/47...), tách theo từng ổ | Reset ổ đĩa, ổ hỏng, NTFS hỏng, driver màn hình treo, dịch vụ treo |
| 19 | Log Application + cảnh báo **hết bộ nhớ** | App crash liên tục |
| 20 | Lịch sử bật/tắt máy + **file minidump** | Màn hình xanh, tắt đột ngột |
| 21 | **Dòng thời gian 90 ngày**: update, phần mềm mới cài, restore point | **Đối chiếu đúng ngày máy bắt đầu chậm** |
| 22 | Phần mềm đã cài + tiện ích trình duyệt | Phần mềm "tối ưu"/adware, quá nhiều extension |
| 23 | Chờ khởi động lại, CBS log, System Restore | Update kẹt, file hệ thống hỏng |
| 24 | Nhiệt độ, quạt | Quá nhiệt |

Đầu báo cáo có mục **“CẢNH BÁO TỰ ĐỘNG”** — script tự chấm khoảng 60 điều kiện và liệt kê nghi phạm, mục nghiêm trọng lên đầu (`[NGHIEM TRONG]`), đọc mục này trước. Mỗi cảnh báo có mã cố định trong ngoặc cuối dòng (vd `SMART_SAP_HONG`, `O_DIA_IO_THAT_BAI`, `FILE_HE_THONG_HONG`): mã không đổi khi sửa câu chữ.

Lỗi của nguồn `disk` trên ổ USB hoặc ổ đã rút ra (không còn trong danh sách ổ) chỉ là cảnh báo: rút ổ khi đang ghi cũng sinh các lỗi này.

## Kiểm tra sâu (tuỳ chọn)

Thay cho *Báo cáo sức khoẻ máy* cũ (đã gộp vào CheckWinFix). Chỉ đọc, cần quyền Admin:

- Ảnh Windows: `Repair-WindowsImage -Online -ScanHealth` (như `DISM /ScanHealth`, 5–15 phút). Hỏng mà sửa được thì báo `ANH_WINDOWS_HONG` và gợi ý *Sửa lỗi Windows > DISM rồi SFC*.
- Lỗi hệ thống file từng ổ NTFS: `Repair-Volume -Scan` (như `chkdsk /scan`, không sửa). Có lỗi thì báo `O_DIA_LOI_HE_THONG_FILE` và gợi ý *Sửa lỗi ổ đĩa*.

Cả hai đọc kết quả có cấu trúc nên đúng trên Windows mọi ngôn ngữ (bản cũ in nguyên chữ của `sfc /verifyonly`).

## Kết quả cho Trạm Tool

`KetQua_CheckWinFix_ThuThap_*.json` theo chuẩn `tramtool.ketqua/1` (xem `docs\THEM-CONG-CU.md`): mỗi cảnh báo là một phát hiện có mã, mức (`loi`, `canh-bao`, `thong-tin`) và gợi ý script chạy tiếp khi có (ổ đĩa, màn hình xanh → *Chẩn đoán phần cứng*; WHEA → *Giải mã WHEA*; tắt đột ngột → *Sụp nguồn*; file hệ thống hỏng → *Sửa lỗi Windows*; ổ C đầy → *Dọn ổ C*). Trạm hiện các mục này ở Lịch sử, bấm là chạy tiếp. Mã thoát 0 khi đã ghi báo cáo, kể cả khi có cảnh báo.

Các script chuyên sâu (bản 1.1) cũng ghi file kết quả cạnh báo cáo, cùng chuẩn:

| Script | File kết quả | Ví dụ mã |
|---|---|---|
| 2 Chẩn đoán phần cứng | `KetQua_CheckWinFix_PhanCung_*.json` | `O_DIA_LOI_IO_NHIEU`, `O_VAT_LY_KHONG_KHOE`, `SMART_BAO_HONG`, `LOI_WHEA`, `MAN_HINH_XANH`, `RAM_CO_LOI` |
| 3 Giải mã WHEA | `KetQua_CheckWinFix_GiaiMaWhea_*.json` | `WHEA_RAM`, `WHEA_CPU`, `WHEA_PCIE`, `WHEA_LUC_KHOI_DONG`, `KHONG_CO_LOI_WHEA` |
| 4 Xuất bằng chứng | `KetQua_CheckWinFix_BangChung_*.json` | `EVTX_KHONG_XUAT_DUOC`, `HO_SO_CO_LOI_O_DIA`, `DA_TAO_CUSTOM_VIEW` (kèm đường dẫn thư mục hồ sơ) |
| 5 Sụp nguồn | `KetQua_CheckWinFix_SupNguon_*.json` | `MAT_NGUON_DOT_NGOT`, `MAN_HINH_XANH`, `QUA_NHIET`, `PIN_CHAI`, `KHONG_GHI_DUMP` |

Mỗi kết luận trong báo cáo `.txt` in kèm mã trong ngoặc. Gợi ý chạy tiếp: lỗi ổ đĩa → *Xuất hồ sơ bằng chứng*; WHEA →
*Giải mã WHEA*; WHEA chỉ ra RAM, chưa từng test RAM → *Kiểm tra RAM* (Sửa lỗi Windows); WHEA chỉ ra CPU, màn hình
xanh → *Sụp nguồn*. Không có quyền Admin thì có `THIEU_QUYEN_ADMIN` và không kết luận máy ổn. Script 5 ghi file kết
quả trước khi hỏi bật minidump hay theo dõi. Script 4, 5 nhận `-KhongHoi` để không hỏi gì (bài thử dùng).

## Kiểm chứng

Đã chạy thử thật trên máy này (Windows 11 25H2, build 26200): chạy hết 24/24 mục trong **85 giây**, không mục nào lỗi, báo cáo 76 KB, tự bắt được 16 cảnh báo.

## Bước tiếp theo

Có báo cáo → tôi viết `SuaLoi.bat` **đúng bệnh** của máy đó, có xác nhận từng bước và có thể hoàn tác. Không đoán mò vì mỗi máy chậm một nguyên nhân khác nhau.

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

**Ca thực tế đã xử lý:** [du-lieu/ca-DESKTOP-2VQE588/CHAN-DOAN-DESKTOP-2VQE588.md](du-lieu/ca-DESKTOP-2VQE588/CHAN-DOAN-DESKTOP-2VQE588.md) (dữ liệu khách, chỉ lưu trên máy, không đưa lên git) — biên bản trình bày: https://claude.ai/artifact/VCqBxCGexui2ZpVXerB9up

---

# Bước 1: Thu thập thông tin

## Chạy thế nào

1. Copy **`ThuThapThongTin.bat`** sang máy đang bị chậm (USB / Zalo / email đều được).
   - ⚠️ **Đừng mở bằng Notepad rồi lưu lại** — sẽ hỏng bảng mã và script không chạy.
2. Chuột phải → **Run as administrator** (nếu bấm đúp, script tự xin quyền Admin, bấm **Yes**).
3. Script hỏi 2 câu (có thể Enter bỏ qua):
   - Máy bắt đầu chậm từ khi nào?
   - Chậm kiểu gì?
4. Chờ **~1,5–3 phút**. Xong sẽ tự mở Notepad hiện báo cáo.
5. File kết quả nằm **ngay cạnh file .bat**, tên `LagReport_<TênMáy>_<ngày giờ>.txt` (~70–150 KB).
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
| 18 | Log System (Error/Critical 14 ngày) + đối chiếu 24 mã lỗi đã biết | Reset ổ đĩa, NTFS hỏng, dịch vụ treo |
| 19 | Log Application + cảnh báo **hết bộ nhớ** | App crash liên tục |
| 20 | Lịch sử bật/tắt máy + **file minidump** | Màn hình xanh, tắt đột ngột |
| 21 | **Dòng thời gian 90 ngày**: update, phần mềm mới cài, restore point | **Đối chiếu đúng ngày máy bắt đầu chậm** |
| 22 | Phần mềm đã cài + tiện ích trình duyệt | Phần mềm "tối ưu"/adware, quá nhiều extension |
| 23 | Chờ khởi động lại, CBS log, System Restore | Update kẹt, file hệ thống hỏng |
| 24 | Nhiệt độ, quạt | Quá nhiệt |

Đầu báo cáo có mục **“CẢNH BÁO TỰ ĐỘNG”** — script tự chấm ~45 điều kiện và liệt kê nghi phạm, đọc mục này trước.

## Kiểm chứng

Đã chạy thử thật trên máy này (Windows 11 25H2, build 26200): chạy hết 24/24 mục trong **85 giây**, không mục nào lỗi, báo cáo 76 KB, tự bắt được 16 cảnh báo.

## Bước tiếp theo

Có báo cáo → tôi viết `SuaLoi.bat` **đúng bệnh** của máy đó, có xác nhận từng bước và có thể hoàn tác. Không đoán mò vì mỗi máy chậm một nguyên nhân khác nhau.

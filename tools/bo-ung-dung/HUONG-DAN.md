# Bộ ứng dụng văn phòng (winget)

Máy mới hoặc vừa cài lại Windows: chọn ứng dụng rồi cài một lượt từ nguồn **winget** của Microsoft, không phải tìm bộ
cài trên mạng (các trang tải lậu hay gói kèm quảng cáo, mã độc). Bấm đúp `BO_UNG_DUNG.bat` để mở menu, hoặc chạy từ
Trạm Tool.

## Các nút

| Nút | Làm gì |
|---|---|
| Kiểm tra | Chỉ đọc, không cần quyền Admin. Winget chạy được không; ứng dụng nào trong danh sách đã cài, chưa cài. Đọc bằng `winget export` nên nhận cả ứng dụng không cài bằng winget. |
| Cài ứng dụng | Cần quyền Admin. Cài các ứng dụng đánh dấu (`winget install --id <mã> -e --silent`), bỏ qua ứng dụng đã có, rồi đọc lại danh sách đã cài để chắc cài xong (không tin riêng mã thoát của bộ cài). Không đánh dấu ô nào thì cài các ứng dụng mặc định. |
| Cập nhật ứng dụng | Cần quyền Admin. `winget upgrade` từng ứng dụng trong danh sách đã cài; đóng ứng dụng đang mở trước khi cập nhật. |

Menu (bấm đúp) cho chọn ứng dụng bằng số: `1 3 5`, Enter là các mục có dấu `*` (mặc định); mục đã cài có ghi
`[đã cài]`. Ô *Chạy thử* (hoặc `-ChayThu`) chỉ in việc sẽ làm.

Công cụ không gỡ ứng dụng: gỡ trong Cài đặt > Ứng dụng như thường.

## Danh sách

| Ứng dụng | Mã winget | Mặc định |
|---|---|---|
| Zalo | `VNGCorp.Zalo` | có |
| UniKey | `UniKey.UniKey` | có |
| EVKey | `lamquangminh.EVKey` | |
| 7-Zip | `7zip.7zip` | có |
| Foxit PDF Reader | `Foxit.FoxitReader` | có |
| UltraViewer | `DucFabulous.UltraViewer` | có |
| Google Chrome | `Google.Chrome` | có |
| Cốc Cốc | `CocCoc.CocCoc` | (bản trên winget cũ, v120; Cốc Cốc tự cập nhật sau khi cài) |
| Firefox | `Mozilla.Firefox` | |
| Adobe Acrobat Reader | `Adobe.Acrobat.Reader.64-bit` | |
| VLC | `VideoLAN.VLC` | |
| Notepad++ | `Notepad++.Notepad++` | |
| TeamViewer | `TeamViewer.TeamViewer` | |
| Telegram | `Telegram.TelegramDesktop` | |

UniKey và EVKey cùng nhóm *bộ gõ*: chỉ cài một (hai bộ gõ chạy cùng lúc hay làm gõ sai dấu); Kiểm tra cảnh báo khi máy
đã có cả hai.

**Thêm ứng dụng**: tìm mã bằng `winget search <tên>`, kiểm bằng `winget show --id <mã> -e`, thêm một dòng vào
`DanhSach.json` (`khoa` là tên cờ, chỉ chữ và số, không trùng tiền tố với tham số của script như `Mode`, `ChayThu`,
`KhongDung`) và một ô chọn cùng `id`, `flag` trong action `cai` của `tool.json`. Bài thử `tests\bo-ung-dung` kiểm hai
nơi khớp nhau.

## Lưu ý

- Cần winget (App Installer). Windows 10 bản cũ, Windows LTSC thường thiếu: cài App Installer từ Microsoft Store, hoặc
  trong Trạm Tool mở Máy này > Sửa winget.
- Ứng dụng cài cho riêng tài khoản (như Zalo) vào tài khoản đang chạy cửa sổ Admin. Máy có tài khoản thường riêng thì
  đăng nhập tài khoản đó rồi cài.
- Cài là đồng ý điều khoản của từng gói và của nguồn winget (`--accept-package-agreements`,
  `--accept-source-agreements`).

## Kết quả cho Trạm Tool

Mỗi lần chạy ghi `ket_qua\KetQua_BoUngDung_<tên máy>_<giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): ứng dụng đã cài, chưa cài (kèm nút *Cài ứng dụng*), cài lỗi, cập nhật xong.

Chạy thẳng: `BO_UNG_DUNG.bat -Mode kiem-tra|cai|cap-nhat [-Zalo -UniKey -SevenZip ...] [-ChayThu] [-KhongDung]`.
Mã thoát: 0 xong, 1 lỗi, 2 thiếu winget, thiếu quyền Admin hoặc đã huỷ, 3 làm được một phần.

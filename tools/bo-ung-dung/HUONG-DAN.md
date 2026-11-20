# Bộ ứng dụng văn phòng (winget)

Máy mới hoặc vừa cài lại Windows: chọn ứng dụng rồi cài một lượt từ nguồn **winget** của Microsoft, không phải tìm bộ
cài trên mạng (các trang tải lậu hay gói kèm quảng cáo, mã độc). Bản portable có thể mang sẵn bộ cài để cài không cần
mạng (xem *Cài không cần mạng*). Bấm đúp `BO_UNG_DUNG.bat` để mở menu, hoặc chạy từ Trạm Tool.

## Các nút

| Nút | Làm gì |
|---|---|
| Kiểm tra | Chỉ đọc, không cần quyền Admin. Winget chạy được không; ứng dụng nào trong danh sách đã cài, chưa cài. Đọc bằng `winget export` nên nhận cả ứng dụng không cài bằng winget; bản portable có bộ cài sẵn thì đọc thêm Programs and Features. |
| Cài ứng dụng | Cần quyền Admin. Cài các ứng dụng đánh dấu (từ bộ cài có sẵn trong bản portable, không thì `winget install --id <mã> -e --silent`), bỏ qua ứng dụng đã có, rồi đọc lại danh sách đã cài để chắc cài xong (không tin riêng mã thoát của bộ cài). Không đánh dấu ô nào thì cài các ứng dụng mặc định. |
| Cập nhật ứng dụng | Cần quyền Admin và winget. `winget upgrade` từng ứng dụng trong danh sách đã cài (trừ ứng dụng ghim bản); đóng ứng dụng đang mở trước khi cập nhật. |

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

## Cài không cần mạng (bản portable)

Bản portable có gói `TramTool-UngDung-*.zip` (giải nén chồng vào thư mục `TramTool`), hoặc bản đầy đủ dựng bằng
`hub\dev\DongGoi.ps1 -DayDu`, mang sẵn bộ cài của các ứng dụng trong `runtime\bo-cai`. Lúc đó:

- Kế hoạch cài ghi nguồn từng ứng dụng: *bộ cài có sẵn trong bản này (bản X, không cần mạng)*, lệnh winget, hoặc bỏ qua.
- Bộ cài lấy bằng `winget download` lúc dựng gói. Trước khi chạy, công cụ kiểm lại mã SHA-256; sai mã thì không chạy
  và cài lại bằng winget (nếu có).
- Máy không có winget, hoặc winget hỏng, vẫn cài được các ứng dụng có gói (chỉ cảnh báo). Ứng dụng không có gói thì
  báo `CAI_KHONG_CO_NGUON`. *Cập nhật ứng dụng* vẫn cần winget.
- Ứng dụng đã cài nhận cả qua Programs and Features. UniKey (gói dạng nén chạy ngay) được chép vào
  `Program Files\UniKey`, có lối tắt ở Start menu và một mục trong Programs and Features để gỡ.

Ứng dụng có thể thiếu gói: EVKey (từ 11/2026 file của EVKey khác mã SHA-256 ghi trong winget, winget từ chối tải;
không bỏ qua kiểm tra này). Cốc Cốc trên winget là bộ cài mồi 1 MB, lúc cài vẫn tải từ mạng.

**Ghim bản**: trường `phienBan` trong `DanhSach.json` ghim một bản (winget `--version`, gói portable cũng tải bản này)
khi bản mới nhất không cài được. UniKey ghim 4.6.230919 vì bản 4.6.250531 trên winget chỉ có cho máy ARM64.

## Lưu ý

- Cần winget (App Installer) khi không có bộ cài sẵn. Windows 10 bản cũ, Windows LTSC thường thiếu: cài App Installer
  từ Microsoft Store, hoặc trong Trạm Tool mở Máy này > Sửa winget.
- Ứng dụng cài cho riêng tài khoản (như Zalo) vào tài khoản đang chạy cửa sổ Admin. Máy có tài khoản thường riêng thì
  đăng nhập tài khoản đó rồi cài.
- Cài là đồng ý điều khoản của từng gói và của nguồn winget (`--accept-package-agreements`,
  `--accept-source-agreements`).

## Kết quả cho Trạm Tool

Mỗi lần chạy ghi `ket_qua\KetQua_BoUngDung_<tên máy>_<giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): ứng dụng đã cài, chưa cài (kèm nút *Cài ứng dụng*), cài lỗi, cập nhật xong.

Chạy thẳng: `BO_UNG_DUNG.bat -Mode kiem-tra|cai|cap-nhat [-Zalo -UniKey -SevenZip ...] [-ChayThu] [-KhongDung]`.
Mã thoát: 0 xong, 1 lỗi, 2 thiếu winget, thiếu quyền Admin hoặc đã huỷ, 3 làm được một phần.

# Đồng bộ phiên Claude giữa các tài khoản

Đăng nhập Claude Desktop bằng tài khoản khác thì thanh bên tab Code trống, dù các cuộc hội thoại cũ vẫn nằm trên máy. Công cụ này đưa các phiên đó sang tài khoản đang đăng nhập để mở lại và làm tiếp.

## Vì sao đổi tài khoản là mất phiên

Claude Desktop lưu hai thứ ở hai nơi:

| Thứ | Nơi lưu | Theo tài khoản? |
|---|---|---|
| Danh sách phiên ở thanh bên (tiêu đề, thư mục dự án, chế độ quyền, lần cuối dùng) | `%APPDATA%\Claude\claude-code-sessions\<mã tài khoản>\<mã tổ chức>\local_<mã>.json` | Có |
| Nội dung hội thoại | `~\.claude\projects\<thư mục dự án>\<mã phiên>.jsonl` | Không, dùng chung |

Đổi tài khoản thì Claude đọc thư mục danh sách của tài khoản mới, còn trống. Nội dung vẫn còn nên chỉ cần chép các mục danh sách sang là mở lại được.

Cuộc trò chuyện ở tab Chat và Projects trên claude.ai nằm trên máy chủ của từng tài khoản, công cụ không chuyển được.

## Cùng một máy

1. Đăng nhập tài khoản mới (B) trong Claude Desktop, mở tab Code một lần.
2. Thoát hẳn Claude: chuột phải biểu tượng Claude ở khay đồng hồ, chọn Quit. Hoặc đánh dấu *Tự đóng Claude* khi chạy.
3. Bấm **Đồng bộ phiên vào tài khoản đang đăng nhập**. Công cụ đọc danh sách của mọi tài khoản khác từng đăng nhập trên máy (A, ...) và thêm các phiên B chưa có.
4. Mở lại Claude: các phiên hiện ở thanh bên, mở ra là làm tiếp được.

Không cần Sao lưu trước. Muốn có bản dự phòng thì vẫn Sao lưu được; Đồng bộ đọc cả gói, phiên nào có ở cả hai nơi thì lấy bản mới hơn.

Đổi lại sang A rồi Đồng bộ thì A nhận các phiên B đã tạo thêm, và bản mới hơn của các phiên đã làm tiếp ở B. Nội dung dùng chung nên mở ở tài khoản nào cũng thấy đủ các lượt đã trao đổi.

## Sang máy khác

1. Máy cũ, đăng nhập tài khoản có phiên: bấm **Sao lưu**, chọn nơi lưu (USB). Công cụ tạo thư mục `Goi_<mã tài khoản>_<giờ>` gồm danh sách phiên (`phien\`) và nội dung hội thoại (`noi-dung\`), kèm `goi.json`.
2. Máy mới: cài Claude Desktop, đăng nhập (tài khoản nào cũng được), mở tab Code một lần, thoát Claude.
3. Bấm **Đồng bộ**, chọn thư mục gói ở ô *Gói sao lưu* (hoặc chép gói vào `du-lieu` của công cụ rồi để trống).
4. Chép các thư mục dự án về đúng đường dẫn cũ trước khi mở các phiên đó. Tên tài khoản Windows khác máy cũ thì công cụ tự sửa đường dẫn nằm trong thư mục người dùng (`C:\Users\<tên>\...`).

Gói chứa toàn bộ nội dung hội thoại, có thể có mật khẩu, khoá, dữ liệu khách từng dán vào Claude. Cất USB cẩn thận, xoá gói khi đã đồng bộ xong.

## Đồng bộ làm gì với từng phiên

- Tài khoản đang dùng chưa có phiên: thêm.
- Đã có, giống hệt: bỏ qua.
- Đã có nhưng khác bản ở nơi khác: bản có lần dùng cuối mới hơn thắng (`Test-NenThay` trong `DongBoClaude.ps1`); bằng nhau thì giữ bản đang có. Thay thì bản đang có được cất vào `du-lieu\HoanTac`.
- Nhiều nơi cùng có một phiên (tài khoản khác, các gói): lấy bản mới nhất; bằng nhau thì ưu tiên bản trên máy vì nội dung đã nằm sẵn.
- Đã xoá ở tài khoản đang dùng: không thêm lại.
- Không có nội dung hội thoại trên máy (và không có trong gói): bỏ qua, có báo.

Khi chép mục danh sách sang tài khoản mới, công cụ bỏ hai thứ gắn với tài khoản cũ: cấu hình kết nối claude.ai (connector) và mã phiên Remote Control. Tài khoản mới chưa tự bật chế độ không hỏi quyền (bypass permissions) thì phiên đang ở chế độ đó mở lại ở chế độ hỏi trước.

## Hoàn tác

**Hoàn tác lần đồng bộ gần nhất** bỏ các mục lần đó đã thêm và trả lại các mục đã thay. Mục nào đã dùng tiếp sau khi đồng bộ (file khác lúc đồng bộ xong) thì giữ, có báo. Nhật ký và bản cũ nằm trong `du-lieu\HoanTac\DongBo_<giờ>`.

## Tham số

```
DongBoClaude.ps1 -Mode kiem-tra|sao-luu|dong-bo|hoan-tac [-Tu <gói>] [-Den <thư mục>] [-DongClaude] [-ChayThu] [-KhongDung]
```

- `-Tu`: gói (thư mục có `goi.json`) hoặc thư mục chứa các gói. Bỏ trống: `du-lieu` của công cụ.
- `-Den`: nơi tạo gói khi Sao lưu. Bỏ trống: `du-lieu`.
- `-DongClaude`: Claude Desktop đang mở thì tự đóng (mọi cửa sổ, phiên đang chạy). Không có thì hỏi, chạy tự động thì dừng với mã 2.
- `-ChayThu`: chỉ in việc sẽ làm.
- `-KhongDung`: không chờ Enter khi xong.

Mỗi lần chạy ghi `ket_qua\KetQua_ClaudeDongBo_<máy>_<giờ>.json` (chuẩn `tramtool.ketqua/1`). `du-lieu\tai-khoan.json` nhớ email của từng mã tài khoản (lấy từ `~\.claude.json`) để hiện tên dễ hiểu.

## Mã thoát

0 xong (kể cả khi không có gì để làm), 1 lỗi, 2 chưa làm (chưa cài Claude Desktop, chưa đăng nhập, chưa mở tab Code lần nào, Claude đang mở, đã huỷ, thiếu chỗ trống, không thấy gói), 3 làm được một phần.

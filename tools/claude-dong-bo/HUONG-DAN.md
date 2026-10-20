# Đồng bộ phiên Claude giữa các tài khoản

Đăng nhập Claude Desktop bằng tài khoản khác thì thanh bên tab Code trống, dù các cuộc hội thoại cũ vẫn nằm trên máy. Công cụ này đưa các phiên đó sang tài khoản đang đăng nhập để mở lại và làm tiếp, kèm tác vụ hẹn giờ, mẫu phiên và các mục ở thanh bên của tài khoản cũ.

## Vì sao đổi tài khoản là mất phiên

Claude Desktop lưu mỗi thứ một nơi:

| Thứ | Nơi lưu | Theo tài khoản? |
|---|---|---|
| Danh sách phiên ở thanh bên (tiêu đề, thư mục dự án, chế độ quyền, lần cuối dùng) | `%APPDATA%\Claude\claude-code-sessions\<mã tài khoản>\<mã tổ chức>\local_<mã>.json` | Có |
| Tác vụ hẹn giờ tab Code | `scheduled-tasks.json` trong cùng thư mục trên | Có |
| Mẫu phiên (preset ở ô tạo phiên mới) | `%APPDATA%\Claude\ccd-session-presets.json`, phần `byAccount` | Có |
| Mục ở thanh bên tab Code (Đã ghim, Tác vụ, Phiên, mục tự tạo) | `claude_desktop_config.json`, khoá `dframe-code-sections` | Có |
| Ghim phiên (starred) | `claude_desktop_config.json` | Không, chung cho cả máy |
| Nội dung hội thoại | `~\.claude\projects\<thư mục dự án>\<mã phiên>.jsonl` | Không, dùng chung |
| Trí nhớ dự án, file nhắc việc của tác vụ hẹn giờ | `~\.claude\projects\<thư mục dự án>\memory\`, `~\.claude\scheduled-tasks\` | Không, dùng chung |

Đổi tài khoản thì Claude đọc phần của tài khoản mới, còn trống. Nội dung vẫn còn nên chỉ cần chép các mục sang là mở lại được.

Cuộc trò chuyện ở tab Chat và Projects trên claude.ai nằm trên máy chủ của từng tài khoản, công cụ không chuyển được.

## Cùng một máy

1. Đăng nhập tài khoản mới (B) trong Claude Desktop, mở tab Code một lần.
2. Thoát hẳn Claude: chuột phải biểu tượng Claude ở khay đồng hồ, chọn Quit. Hoặc đánh dấu *Tự đóng Claude* khi chạy.
3. Bấm **Đồng bộ phiên vào tài khoản đang đăng nhập**. Công cụ đọc phần của mọi tài khoản khác từng đăng nhập trên máy (A, ...) và thêm những gì B chưa có. Đánh dấu *Xong thì mở lại Claude* để công cụ mở Claude luôn.
4. Mở lại Claude: các phiên hiện ở thanh bên, mở ra là làm tiếp được.

Không cần Sao lưu trước. Đổi lại sang A rồi Đồng bộ thì A nhận các phiên B đã tạo thêm, và bản mới hơn của các phiên đã làm tiếp ở B.

### Lối tắt Mở Claude: không phải nhớ bấm Đồng bộ

Bấm **Tạo lối tắt Mở Claude trên màn hình** một lần. Từ đó mở Claude bằng lối tắt *Mở Claude (đồng bộ phiên)* thay cho lối tắt thường:

- Claude đang tắt: công cụ đồng bộ (không hỏi lại) rồi mở Claude. Claude đọc danh sách lúc mở nên thấy ngay các phiên vừa thêm.
- Claude đang mở: công cụ không đồng bộ được (Claude giữ danh sách trong bộ nhớ), chỉ đưa cửa sổ Claude lên.
- Cửa sổ công cụ tự đóng khi xong; có lỗi thì ở lại để đọc.

Chuyển thư mục Trạm Tool đi nơi khác thì tạo lại lối tắt.

## Sang máy khác

1. Máy cũ, đăng nhập tài khoản có phiên: bấm **Sao lưu**, chọn nơi lưu (USB). Công cụ tạo (hoặc cập nhật) thư mục `Goi_<8 ký tự đầu mã tài khoản>`:
   - `phien\`: danh sách phiên, tác vụ hẹn giờ, mẫu phiên, mục thanh bên;
   - `noi-dung\`: nội dung hội thoại;
   - `nguoi-dung\`: trí nhớ của các dự án có phiên, file nhắc việc của tác vụ hẹn giờ;
   - `cowork\`: khi đánh dấu *Kèm phiên Cowork*;
   - `goi.json`: mô tả gói.
2. Máy mới: cài Claude Desktop, đăng nhập (tài khoản nào cũng được), mở tab Code một lần, thoát Claude.
3. Bấm **Đồng bộ**, chọn gói ở ô *Gói sao lưu*: `goi.json` trong thư mục gói, hoặc file `.zip`/`.aes`. Cách khác: chép gói vào `du-lieu` của công cụ rồi để trống ô này.
4. Chép các thư mục dự án về đúng đường dẫn cũ trước khi mở các phiên đó. Tên tài khoản Windows khác máy cũ thì công cụ tự sửa đường dẫn nằm trong thư mục người dùng (`C:\Users\<tên>\...`). Đường dẫn được sửa ở: mục danh sách phiên, tác vụ hẹn giờ, mẫu phiên, trí nhớ dự án, file nhắc việc.

Sao lưu lại vào cùng chỗ chỉ chép phần đổi (file mới, file khác cỡ hoặc khác giờ sửa) và bỏ phiên đã xoá ở tài khoản, nên các lần sau chạy nhanh. Trong lúc ghi, `goi.json` mang dấu `dangGhi`: Sao lưu bị ngắt giữa chừng thì Đồng bộ bỏ qua gói đó cho tới khi Sao lưu lại xong.

### Nén, mã hoá

- *Nén thành một file .zip* (`-Nen`): gói vẫn cập nhật dần trong `du-lieu`, rồi nén thành `Goi_<tài khoản>_<giờ>.zip` ở nơi lưu. Một file thì chép qua USB, mạng nhanh hơn hàng nghìn file nhỏ.
- *Nén và mã hoá bằng mật khẩu* (`-MaHoa`): như trên rồi mã hoá thành `.aes` (AES-256, khoá dẫn từ mật khẩu bằng PBKDF2-SHA256 200.000 vòng, kiểm toàn vẹn HMAC-SHA256; cùng định dạng `BiMat.aes` của công cụ chuyển dữ liệu new-windows).
  - Mật khẩu chỉ gõ trong cửa sổ công cụ (ít nhất 8 ký tự, gõ hai lần). Mật khẩu không nhận qua tham số và không lưu ở đâu, quên là không mở được gói.
  - Đồng bộ từ file `.aes` thì công cụ hỏi mật khẩu. Sai mật khẩu hoặc file bị sửa thì dừng, không ghi gì.

Gói chứa toàn bộ nội dung hội thoại, có thể có mật khẩu, khoá, dữ liệu khách từng dán vào Claude. Mang qua USB thì nên mã hoá; xoá gói khi đã đồng bộ xong.

## Đồng bộ làm gì

Với từng phiên:

- Tài khoản đang dùng chưa có phiên: thêm.
- Đã có, giống hệt: bỏ qua.
- Đã có nhưng khác bản ở nơi khác: bản có lần dùng cuối mới hơn thắng (`Test-NenThay` trong `DongBoClaude.ps1`); bằng nhau thì giữ bản đang có. Thay thì bản đang có được cất vào `du-lieu\HoanTac`.
- Nhiều nơi cùng có một phiên (tài khoản khác, các gói): lấy bản mới nhất; bằng nhau thì ưu tiên bản trên máy vì nội dung đã nằm sẵn.
- Đã xoá ở tài khoản đang dùng: không thêm lại.
- Không có nội dung hội thoại trên máy (và không có trong gói): bỏ qua, có báo.

Khi chép mục danh sách sang tài khoản mới, công cụ bỏ hai thứ gắn với tài khoản cũ: cấu hình kết nối claude.ai (connector) và mã phiên Remote Control. Tài khoản mới chưa tự bật chế độ không hỏi quyền (bypass permissions) thì phiên đang ở chế độ đó mở lại ở chế độ hỏi trước. Chế độ quyền đặt riêng cho từng thư mục không được đồng bộ.

Phần ngoài danh sách phiên:

- **Tác vụ hẹn giờ** (tab Code; Cowork khi có `-KemCowork`): thêm tác vụ tài khoản đang dùng chưa có. Trùng mã hoặc trùng file nhắc việc thì bỏ qua. File nhắc việc chưa có trên máy (và gói không mang theo) thì không thêm, có báo `HEN_GIO_THIEU_TEP`. Tác vụ thêm vào giữ nguyên trạng thái bật, tắt.
- **Mẫu phiên**: thêm mẫu còn thiếu.
- **Thanh bên tab Code**: tài khoản chưa có cách sắp xếp riêng thì lấy của tài khoản kia; đã có thì chỉ thêm mục tự tạo còn thiếu vào cuối. Công cụ chưa thấy nơi Claude lưu phiên nào thuộc nhóm nào, nên nhóm tự tạo chỉ có tên, chưa có phiên bên trong.
- **Trí nhớ dự án, file nhắc việc** (chỉ từ gói làm ở máy khác, vì cùng máy thì `~\.claude` đã dùng chung): file chưa có thì chép; đã có mà bản trong gói sửa sau thì thay (bản cũ cất để Hoàn tác).
- **Cowork** (`-KemCowork`, thử nghiệm): chép các mục Cowork tài khoản đang dùng chưa có. Phiên làm việc từ xa (`remote-session-spaces.json`) nằm trên máy chủ, không chép.

Những phần này không có dấu đã xoá như danh sách phiên. Vì vậy công cụ nhớ trong `du-lieu\da-them.json` những gì đã thêm vào từng tài khoản trên từng máy: mục đã thêm một lần mà bạn xoá đi thì lần đồng bộ sau không thêm lại.

`claude_desktop_config.json` có thể chứa khoá bí mật của máy chủ MCP. Công cụ chỉ đổi đúng khoá thanh bên của tài khoản đang dùng. Nhật ký hoàn tác chỉ giữ giá trị cũ, mới của khoá đó, không chép cả file; gói sao lưu cũng không có file này.

## Claude đổi cách lưu thì sao

Công cụ viết theo cách lưu của Claude Desktop bản 2.42304 (10/2026). Mỗi lần chạy:

- Bản Claude (`updaterLastSeenVersion` trong `config.json`) được ghi vào kết quả, nhật ký và gói. Bản khác bản đã thử thì Kiểm tra báo `BAN_CLAUDE_MOI`, chỉ để biết.
- Mỗi mục danh sách phiên được kiểm cấu trúc: tên file khớp `sessionId`, có `cwd`, `lastActivityAt` là số, `cliSessionId` đúng dạng mã.
  - Mục sai ở tài khoản khác hay trong gói thì bỏ qua, có báo `MUC_KHONG_HOP_LE`.
  - Quá nửa số mục của tài khoản đang dùng (hoặc của các tài khoản trên máy) sai thì coi như Claude đã đổi cách lưu: Đồng bộ, Sao lưu dừng với `CACH_LUU_DA_DOI`, mã 2, không ghi gì.

### Kiểm lại sau lần đồng bộ thật đầu tiên

Sau lần đồng bộ thật đầu tiên sang một tài khoản, mở Claude, xem thanh bên, thoát Claude rồi chạy **Kiểm tra**. Mục `LAN_DONG_BO_GAN_NHAT` cho biết bao nhiêu phiên đã đồng bộ được Claude mở hoặc ghi lại, chưa đụng tới, hay đã xoá. Phiên biến mất mà không có dấu đã xoá thì có cảnh báo `PHIEN_DONG_BO_MAT`: có thể bản Claude đó không nhận mục chép sang.

## Hoàn tác

**Hoàn tác lần đồng bộ gần nhất** bỏ các mục lần đó đã thêm và trả lại các mục đã thay: mục danh sách phiên, nội dung, file trí nhớ, file tác vụ hẹn giờ, mẫu phiên, Cowork, khoá thanh bên. Mục nào đã dùng tiếp sau khi đồng bộ (file khác lúc đồng bộ xong) thì giữ, có báo. Những mục đã bỏ cũng được xoá khỏi `da-them.json`, lần đồng bộ sau lại thêm được. Nhật ký và bản cũ nằm trong `du-lieu\HoanTac\DongBo_<giờ>`.

## Tham số

```
DongBoClaude.ps1 -Mode kiem-tra|sao-luu|dong-bo|hoan-tac|mo-claude|loi-tat [-Tu <gói>] [-Den <thư mục>]
                 [-Nen] [-MaHoa] [-KemCowork] [-DongClaude] [-MoClaude] [-ChayThu] [-KhongDung]
```

- `-Tu`: gói (thư mục có `goi.json`, hoặc chính `goi.json`), thư mục chứa các gói, hoặc file `.zip`/`.aes` do Sao lưu tạo (giải ra thư mục tạm trong `du-lieu`, xoá khi xong). Bỏ trống: `du-lieu` của công cụ.
- `-Den`: nơi tạo gói (hoặc file nén) khi Sao lưu. Bỏ trống: `du-lieu`.
- `-Nen`, `-MaHoa`: xem mục Nén, mã hoá.
- `-KemCowork`: kèm phiên, tác vụ hẹn giờ Cowork (thử nghiệm).
- `-DongClaude`: Claude Desktop đang mở thì tự đóng (mọi cửa sổ, phiên đang chạy). Không có thì hỏi, chạy tự động thì dừng với mã 2.
- `-MoClaude`: Đồng bộ xong thì mở Claude Desktop.
- `-ChayThu`: chỉ in việc sẽ làm.
- `-KhongDung`: không chờ Enter khi xong.

Mỗi lần chạy ghi `ket_qua\KetQua_ClaudeDongBo_<máy>_<giờ>.json` (chuẩn `tramtool.ketqua/1`). `du-lieu\tai-khoan.json` nhớ email của từng mã tài khoản (lấy từ `~\.claude.json`) để hiện tên dễ hiểu. `du-lieu\claude.ico` là biểu tượng của lối tắt.

Công cụ chuyển dữ liệu khi cài lại Windows (new-windows) khôi phục Claude xong sẽ gợi ý chạy Đồng bộ (nút chạy tiếp trong Trạm), và cảnh báo khi Claude trên máy mới đang đăng nhập tài khoản khác tài khoản có phiên trong bản sao lưu.

## Mã thoát

| Mã | Nghĩa |
|---|---|
| 0 | Xong, kể cả khi không có gì để làm |
| 1 | Lỗi |
| 2 | Chưa làm: chưa cài Claude Desktop, chưa đăng nhập, chưa mở tab Code lần nào, Claude đang mở, đã huỷ, thiếu chỗ trống, không thấy gói, sai mật khẩu, mật khẩu ngắn, cách lưu của Claude đã đổi |
| 3 | Làm được một phần |

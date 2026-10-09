# Chuyển dữ liệu khi cài lại Windows

Hai bước: **xuất** trên máy trước khi cài lại, **nhập** trên máy vừa cài xong. Bấm đúp `1_XUAT_DU_LIEU.bat` hoặc `2_NHAP_DU_LIEU.bat`, hoặc chạy từ Trạm Tool. Cửa sổ tự hỏi UAC vì đọc mật khẩu Wi-Fi, driver, khoá BitLocker cần quyền Admin. Không có tham số thì `ChuyenDuLieu.ps1` hiện menu (xuất, nhập, chạy thử từng bước).

## Có gì trong bản sao lưu

| Phần | Lưu gì |
|---|---|
| Wi-Fi | Hồ sơ mọi mạng đã lưu kèm mật khẩu (bỏ mạng do công ty quản lý) |
| Máy in | Máy in, cổng TCP/IP, driver ngoài, cấu hình in, máy in mặc định |
| Claude | `~\.claude` (trừ cache, token đăng nhập), `~\.claude.json`, dữ liệu Claude Desktop, thư mục Cowork nếu nằm trên ổ C, bản HTML đọc được của hội thoại tab Code |
| BitLocker | Khoá khôi phục 48 số của các ổ đang mã hoá (không in ra màn hình) |
| Driver | Driver mạng của hãng (mặc định), mọi driver của hãng, hoặc không |

Không lưu tài liệu, trình duyệt, Zalo, font, danh sách ứng dụng. Thư mục dự án Claude trên ổ C chỉ được liệt kê trong `Claude\thu-muc-du-an.txt`: tự chép trước khi cài.

## Xuất

1. Cắm USB (nên dùng). Công cụ hỏi nơi lưu: USB, ổ cứng ngoài xếp trước, rồi ổ dữ liệu, ổ đang mã hoá BitLocker, ổ Windows sau cùng. Bản sao lưu là thư mục `DuLieu_SaoLuu` ở gốc ổ được chọn (hoặc trong thư mục gõ vào).
2. Không cho lưu trong thư mục Trạm Tool. Lưu trên ổ Windows thì làm xong phải chép ra USB, vì cài lại sẽ xoá ổ đó. Lưu trên ổ dữ liệu đang mã hoá BitLocker thì công cụ cảnh báo: cài lại xong ổ đó bị khoá.
3. Chỗ đó đã có `DuLieu_SaoLuu` thì bản cũ được đổi tên thành `DuLieu_SaoLuu_cu_<giờ>`.
4. Công cụ hỏi có mã hoá không (xem dưới), hỏi trước khi tự đóng Claude Desktop, rồi chép.

## Mã hoá

Chọn mã hoá (hoặc thêm `-MaHoa`) thì hồ sơ Wi-Fi kèm mật khẩu, `settings.json`, `settings.local.json`, `.claude.json`, `claude_desktop_config.json` và `Claude Extensions Settings` không bao giờ ghi ra đĩa dạng chữ: công cụ giữ chúng trong bộ nhớ rồi ghi một lần vào `BiMat.aes`, đọc lại và giải mã thử để chắc mở được.

- Mật khẩu ít nhất 8 ký tự, gõ hai lần trong cửa sổ công cụ (không qua Trạm Tool, không qua tham số). Quên mật khẩu thì không lấy lại được các phần trên, phải nhập mật khẩu Wi-Fi và cấu hình Claude bằng tay.
- `BiMat.aes` là tệp zip mã hoá AES-256-CBC, khoá lấy từ mật khẩu bằng PBKDF2-SHA256 (200.000 vòng), có HMAC-SHA256 để phát hiện sai mật khẩu hay tệp bị sửa.
- Khoá BitLocker, hội thoại Claude, danh sách máy in vẫn ở dạng chữ. Cất USB cẩn thận và xoá bản sao lưu khi đã nhập xong.

## Trạng thái bản sao lưu

`manifest.json` ghi `dang-lam` lúc bắt đầu, `xong` hoặc `mot-phan` (có việc không làm được, liệt kê trong `Loi`) lúc kết thúc, `loi` khi dừng vì lỗi. Cửa sổ bị đóng giữa chừng thì bản sao lưu còn `dang-lam`.

## Nhập

1. Cài driver Wi-Fi nếu Windows chưa tự cài (hoặc chọn phần "driver" để cài driver đã sao lưu).
2. Nên cài Claude Desktop, đăng nhập rồi thoát hẳn trước khi nhập phần Claude.
3. Chạy `2_NHAP_DU_LIEU.bat`. Công cụ tìm `DuLieu_SaoLuu*` ở gốc mọi ổ và USB, cạnh công cụ, và nơi các lần xuất trước ghi trong `ket_qua`. Không thấy thì hỏi đường dẫn.
   - Bản `dang-lam`, `loi`, manifest hỏng: không dùng, có báo lý do.
   - Bản `_cu_`: hỏi trước (mặc định không). Chạy `-Yes` không tự dùng bản cũ; muốn dùng thì chỉ rõ bằng `-Target`.
   - Bản tạo bởi bản 2026.10 trở về trước (chỉ có `thong-tin.json`) được coi là đã xong.
4. Bản có mã hoá: hỏi mật khẩu, sai 3 lần thì hỏi có bỏ qua Wi-Fi và cấu hình Claude để nhập phần còn lại không.
5. Thứ tự: driver, mở khoá ổ BitLocker, Wi-Fi, máy in, Claude. Wi-Fi, máy in đã có thì bỏ qua; hội thoại, file Cowork trên máy mới hơn bản sao lưu được giữ nguyên. Tên tài khoản đổi thì công cụ tự sửa đường dẫn trong cấu hình Claude.

Ổ mở bằng khoá trong bản sao lưu sẽ khoá lại sau khi khởi động lại: dùng công cụ BitLocker (Mở khoá ổ, bật tự mở khoá) hoặc giải mã.

## Tham số

```
ChuyenDuLieu.ps1 -Mode xuat|nhap [-Target <thư mục>] [-MaHoa] [-Driver mang|tat-ca|khong]
                 [-Phan tat-ca|driver|bitlocker|wifi|may-in|claude] [-DryRun] [-Yes] [-NoPause]
```

- `-Target`: xuất là nơi lưu (`E:\` thành `E:\DuLieu_SaoLuu`); nhập là thư mục bản sao lưu hoặc thư mục chứa nó.
- `-DryRun` (`-ChayThu`): chỉ in việc sẽ làm. Không ghi file, không đổi máy, không đọc mật khẩu Wi-Fi hay khoá BitLocker; không cần quyền Admin.
- `-Yes`: nhận câu trả lời mặc định cho mọi câu hỏi. Không tự đóng Claude Desktop, không tự dùng bản `_cu_`, không mã hoá trừ khi có `-MaHoa` (mật khẩu vẫn gõ trong cửa sổ).
- `-NoPause` (`-KhongDung`): không chờ Enter khi xong.
- Hai file .bat nhận thêm các tham số trên, vd `2_NHAP_DU_LIEU.bat -Phan wifi -DryRun`.

Mỗi lần chạy ghi `ket_qua\KetQua_ChuyenDuLieu_<xuat|nhap>_<máy>_<giờ>.json` theo chuẩn kết quả của Trạm Tool (`tramtool.ketqua/1`): chế độ, mã thoát, trạng thái, chạy thử hay không, thư mục bản sao lưu (`thuMucSaoLuu`), lỗi và lưu ý thành danh sách `phatHien`. Trạm Tool hiện các mục này ở Lịch sử. Không có mật khẩu hay khoá. Bản 2.0 ghi tên trường viết hoa (`MaThoat`, `Loi`, `LuuY`); bước nhập và Trạm vẫn đọc được.

## Mã thoát

0 xong, 1 lỗi (kể cả xuất bị dừng giữa chừng), 2 chưa làm gì (thiếu quyền Admin, bấm "Không" ở UAC, huỷ, không có bản sao lưu dùng được, sai mật khẩu mà không bỏ qua), 3 làm được một phần (xem danh sách lỗi cuối cửa sổ).

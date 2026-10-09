# Giờ máy và chữ ký số (USB token)

Ký số thuế điện tử, hoá đơn điện tử, BHXH báo lỗi, trình duyệt báo chứng chỉ không hợp lệ, phần mềm ký không thấy
token: chạy **Kiểm tra** trước. Bấm đúp `GIO_VA_CHU_KY_SO.bat` để mở menu, hoặc chạy từ Trạm Tool.

## Kiểm tra (chỉ đọc, không cần quyền Admin)

Không hỏi PIN, không đọc khoá riêng, không mở kết nối tới token.

| Mục | Cách đọc | Báo khi |
|---|---|---|
| Độ lệch giờ | Hỏi máy chủ giờ bằng NTP (`time.windows.com`, `time.google.com`, `pool.ntp.org`); mạng chặn NTP thì đọc giờ trong tiêu đề của trang http | lệch quá 30 giây (cảnh báo), quá 2 phút (lỗi) |
| Múi giờ | Múi giờ của Windows | không phải *SE Asia Standard Time* (UTC+07:00) |
| Đồng bộ giờ | Dịch vụ Windows Time, kiểu đồng bộ (NTP, NT5DS, NoSync) | dịch vụ bị tắt, đặt giờ tự động bị tắt |
| Dịch vụ token | Smart Card (SCardSvr), Certificate Propagation (CertPropSvc) | bị tắt (thường do phần mềm tối ưu) |
| Token đang cắm | Danh sách đầu đọc của dịch vụ Smart Card; Device Manager | driver token lỗi |
| Chứng thư ký số | Kho `Cert:\CurrentUser\My`: chứng thư có khoá riêng, của nhà cung cấp Việt Nam hoặc dùng để ký | hết hạn, hết hạn trong 30 ngày, chưa tới ngày hiệu lực (giờ máy chậm), Windows chưa tin chứng thư gốc |
| Phần mềm ký số | Tên trong danh sách phần mềm đã cài (eSigner, VNPT-CA, Viettel-CA, FPT-CA, BKAV-CA, iTaxViewer, HTKK...) | chỉ để biết |

## Sửa (cần quyền Admin, cửa sổ tự hỏi UAC)

- **Sửa giờ máy**: bật dịch vụ Windows Time nếu đang tắt (Thủ công, như mặc định), bật đặt giờ tự động nếu đang tắt
  (`time.windows.com`), đặt múi giờ Việt Nam nếu đánh dấu, đồng bộ ngay (`w32tm /resync /force`). Đo lại; vẫn lệch quá
  1 phút (Windows từ chối chỉnh khi lệch quá nhiều) thì đặt giờ theo máy chủ giờ vừa đo. Máy trong domain chỉ đồng bộ
  lại với máy chủ domain, không đổi cấu hình.
- **Sửa dịch vụ đọc USB token**: Smart Card, Certificate Propagation đang tắt thì đặt Thủ công và chạy; chạy lại
  Certificate Propagation để chứng thư trong token hiện lại. Sau đó rút token ra cắm lại. Công cụ không cài driver:
  token cần driver riêng thì cài phần mềm của nhà cung cấp chữ ký số.
- **Trả lại như trước khi sửa**: trước lần sửa đầu tiên, giá trị cũ (kiểu khởi động dịch vụ, cấu hình đồng bộ giờ, múi
  giờ) được lưu vào `ket_qua\TrangThaiGoc_GioChuKySo_<tên máy>.json`; nút này trả về đúng các giá trị đó rồi xoá file.

Mọi nút sửa in việc sẽ làm trước; ô *Chạy thử* (hoặc `-ChayThu`) chỉ xem, không đổi máy.

## Gặp thường

- **Giờ sai sau mỗi lần tắt hẳn máy**: pin CMOS trên bo mạch chủ đã yếu, sửa giờ chỉ đúng tới lần tắt sau. Thay pin
  (CR2032).
- **Chứng thư chưa tới ngày hiệu lực**: giờ máy chậm hơn ngày cấp chứng thư; sửa giờ máy là ký được.
- **Không thấy token**: thử cổng USB khác, cài lại phần mềm của nhà cung cấp; Device Manager báo lỗi driver thì gỡ
  thiết bị rồi cắm lại.

## Kết quả cho Trạm Tool

Mỗi lần chạy ghi `ket_qua\KetQua_GioChuKySo_<tên máy>_<giờ>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): trạng thái máy sau lần chạy, mỗi phát hiện một mã cố định (`GIO_LECH_NHIEU`, `MUI_GIO_KHAC`,
`DICH_VU_SMART_CARD_TAT`, `CHUNG_THU_SAP_HET_HAN`...) kèm nút sửa khi có.

Chạy thẳng: `GIO_VA_CHU_KY_SO.bat -Mode kiem-tra|sua-gio|sua-token|hoan-tac [-MuiGioVN] [-ChayThu] [-KhongDung]`.
Mã thoát: 0 xong (kể cả khi Kiểm tra có cảnh báo), 1 lỗi, 2 thiếu quyền Admin hoặc đã huỷ, 3 làm được một phần.

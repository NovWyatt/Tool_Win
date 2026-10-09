# Tắt/bật dịch vụ nền

Bấm đúp `TAT_BAT_DICH_VU.bat` để mở menu, hoặc chạy từ Trạm Tool. Tắt và Bật lại cần quyền Admin (cửa sổ tự hỏi UAC); Kiểm tra không cần.

## Các dịch vụ

| Dịch vụ | Mặc định Windows | Nên tắt? |
|---|---|---|
| DiagTrack (gửi dữ liệu chẩn đoán, telemetry) | Tự động | Tắt được: bớt gửi dữ liệu sử dụng về Microsoft, Windows Update vẫn chạy. |
| Windows Insider (wisvc) | Thủ công | Tắt được, trừ máy đang nhận bản Windows thử nghiệm (công cụ hỏi lại). |
| SysMain | Tự động | Thường không: nó làm mở ứng dụng nhanh hơn. Chỉ tắt khi ổ HDD hay chạy 100% hoặc RAM 4 GB trở xuống. |
| Tối ưu ổ đĩa (defragsvc) | Thủ công | Không: dịch vụ này chạy TRIM định kỳ cho SSD (công cụ hỏi lại, mặc định là không). |

## Các nút

- **Kiểm tra**: kiểu khởi động thật của từng dịch vụ (Tự động, Thủ công, Đã tắt), đang chạy hay dừng, mặc định của Windows, trạng thái gốc đã lưu. "Đang dừng" không có nghĩa là đã tắt: dịch vụ Thủ công bình thường vẫn dừng.
- **Tắt dịch vụ**: lưu kiểu khởi động hiện tại vào `ket_qua\TrangThaiGoc_<tên máy>.json`, rồi đặt Đã tắt và dừng dịch vụ. Không lưu được file thì không đổi gì. Đọc lại sau khi đổi để chắc Windows đã nhận.
- **Bật lại như trước khi tắt**: trả đúng kiểu khởi động đã lưu (kể cả Tự động trễ) và chạy lại dịch vụ từng chạy. Dịch vụ tắt từ trước khi dùng công cụ thì trả về mặc định của Windows.

Đánh dấu "Chạy thử" (hoặc thêm `-ChayThu`) để chỉ xem việc sẽ làm.

## Mã thoát

0 xong, 1 lỗi, 2 thiếu quyền Admin (bấm "Không" ở UAC), 3 làm được một phần.

Chạy thẳng: `TAT_BAT_DICH_VU.bat -Mode kiem-tra|tat|bat-lai [-DiagTrack] [-WiSvc] [-SysMain] [-DefragSvc] [-ChayThu]`.

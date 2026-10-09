# Tối ưu đồng hồ hệ thống

Bấm đúp `TOI_UU_DONG_HO.bat` để mở menu, hoặc chạy từ Trạm Tool. Cửa sổ tự hỏi UAC vì đọc và đổi cấu hình khởi động (BCD) cần quyền Admin.

## Các nút

| Nút | Làm gì |
|---|---|
| Kiểm tra | Chỉ đọc. In ba thiết lập trong BCD, lời khuyên, giá trị registry bản cũ còn sót, trạng thái BitLocker ổ Windows. |
| Tối ưu cho chơi game | Tắt Dynamic Tick (`disabledynamictick yes`), bỏ ép HPET (xoá `useplatformclock`) nếu đang ép. |
| Trả về mặc định | Xoá `disabledynamictick`, `useplatformclock`, `useplatformtick`: Windows tự chọn đồng hồ như lúc mới cài. |

Hai nút đổi thiết lập in việc sẽ làm trước, đọc lại BCD sau khi đổi để chắc Windows đã nhận, và cần **khởi động lại máy** mới có hiệu lực. Đánh dấu "Chạy thử" (hoặc thêm `-ChayThu`) để chỉ xem.

## Nên dùng khi nào

Phần lớn máy Windows 10/11 hiện đại không mượt hơn khi đổi các thiết lập này. Chỉ thử khi game giật theo nhịp đều mà đã loại trừ driver, nhiệt độ, nguồn điện. Sau khi khởi động lại mà không thấy khác thì chạy "Trả về mặc định". Laptop có thể hao pin hơn một chút khi tắt Dynamic Tick.

Ép HPET (`useplatformclock yes`) thường làm chậm hơn, nên công cụ không bật nó; nút "Tối ưu cho chơi game" còn bỏ ép nếu thấy đang bật.

## BitLocker

Đổi BCD khi ổ Windows đang bật BitLocker có thể làm lần khởi động tới hỏi khoá khôi phục 48 số. Gặp trường hợp này công cụ hỏi trước rồi tạm dừng BitLocker đúng 1 lần khởi động (Windows tự bật lại sau đó). Nên lưu khoá khôi phục trước bằng công cụ BitLocker. Không đọc được trạng thái BitLocker thì công cụ hỏi lại, mặc định là không đổi.

## Bản 1.0

Bản cũ (`ServiceOptimizer.bat`) ghi `useplatformclock`, `disabledynamictick` vào `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel`. Windows không đọc chỗ đó nên bản cũ không có tác dụng dù báo thành công. Hai nút đổi thiết lập của bản này xoá các giá trị đó.

## Mã thoát

0 xong, 1 lỗi, 2 thiếu điều kiện (không có quyền Admin, bấm "Không" ở UAC, không đồng ý tạm dừng BitLocker), 3 làm được một phần.

Chạy thẳng một chế độ: `TOI_UU_DONG_HO.bat -Mode kiem-tra|choi-game|mac-dinh [-ChayThu]`.

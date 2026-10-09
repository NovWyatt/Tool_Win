# Sửa lỗi Windows

Bấm đúp `SUA_LOI_WINDOWS.bat` để mở menu, hoặc chạy từ Trạm Tool. Cửa sổ tự hỏi UAC vì mọi mục cần quyền Admin. Mỗi mục in việc sẽ làm trước; đánh dấu "Chạy thử" (hoặc thêm `-ChayThu`) để chỉ xem.

## Nên chạy gì

| Triệu chứng | Mục |
|---|---|
| Lỗi lạ, màn hình xanh, ứng dụng Windows không mở | DISM rồi SFC (đọc kết quả, còn file không sửa được thì chạy lại sau khi khởi động lại) |
| Vào được Wi-Fi mà không vào được web, DNS lỗi, sau khi gỡ VPN | Đặt lại mạng |
| Phần mềm bị tường lửa chặn mà không tìm ra luật nào | Đặt lại tường lửa (cuối cùng mới dùng) |
| Máy báo lỗi ổ, file hỏng, khởi động chậm bất thường | Quét lỗi ổ đĩa, có lỗi thì Sửa lỗi ổ đĩa |
| Treo, khởi động lại ngẫu nhiên, màn hình xanh lỗi bộ nhớ | Kiểm tra RAM |
| Windows Update báo lỗi mãi, kẹt 0% | Đặt lại Windows Update |
| Ổ C đầy | Công cụ Dọn ổ C an toàn |

## Kết quả đọc thế nào

- **DISM** đọc trạng thái ảnh Windows: không hỏng, hỏng sửa được, hỏng nặng (cài lại Windows giữ dữ liệu bằng ISO cùng phiên bản). Lỗi `0x800F081F` khi sửa: Windows Update không cho tải file sửa; mở ISO cùng phiên bản rồi chạy `DISM /Online /Cleanup-Image /RestoreHealth /Source:wim:<ổ ISO>:\sources\install.wim:1 /LimitAccess`.
- **SFC** đọc kết quả trong `C:\Windows\Logs\CBS\CBS.log` (dòng `[SR]`): bao nhiêu file đã sửa, bao nhiêu không sửa được. SFC dừng giữa chừng thường là do máy đang chờ khởi động lại để cài cập nhật.
- **Đặt lại mạng** chạy `ipconfig /flushdns`, `netsh winsock reset`, `netsh int ip reset` và báo từng lệnh. Lệnh cuối xoá IP tĩnh và DNS đặt tay: công cụ ghi chúng ra `ket_qua\Mang_<tên máy>_<thời gian>.txt` và hỏi trước. Cần khởi động lại máy.
- **Đặt lại tường lửa** sao lưu luật ra `ket_qua\TuongLua_<tên máy>_<thời gian>.wfw` rồi mới hỏi; nút *Khôi phục tường lửa* nạp lại file đó.
- **Ổ đĩa**: Quét dùng `Repair-Volume -Scan` (như `chkdsk /scan`), không cần khởi động lại. Sửa dùng `chkdsk /f` (ổ Windows: hẹn ở lần khởi động lại tới). Không dùng `/r`: ổ hỏng bề mặt thì cứu dữ liệu (CheckWinFix) và thay ổ. Ổ vật lý báo không khoẻ thì công cụ hỏi lại trước khi chạy chkdsk.
- **RAM**: hiện kết quả lần kiểm tra trước trong nhật ký Windows, rồi mở Windows Memory Diagnostic.
- **Windows Update**: đổi tên `SoftwareDistribution`, `catroot2` thành `.old_<thời gian>` (không xoá), chạy lại các dịch vụ đã chạy. Chạy tốt rồi thì xoá các thư mục `.old_` cho nhẹ ổ.

Mỗi lần chạy ghi `ket_qua\KetQua_SuaLoi_<chế độ>_<tên máy>_<thời gian>.json` theo chuẩn `tramtool.ketqua/1` (xem
`docs\THEM-CONG-CU.md`): Trạm Tool hiện kết quả từng việc có mã cố định (`ANH_WINDOWS_HONG_SUA_DUOC`,
`SFC_CON_FILE_HONG`, `O_DIA_CO_LOI`, `O_VAT_LY_KHONG_KHOE`, `IP_DNS_DAT_TAY`...) kèm nút chạy tiếp khi có (vd ảnh
Windows hỏng thì gợi ý *DISM rồi SFC*), và file sao lưu tường lửa, thiết lập mạng cũ đã ghi.

Bản 1.0 có mục *Registry Cleanup* xoá khoá `DelegateFolders` mà Explorer dùng, và *Clean Temp* xoá hết `%TEMP%`; bản này bỏ cả hai.

## Mã thoát

0 xong, 1 lỗi, 2 thiếu điều kiện (không có quyền Admin, chưa đồng ý, không có bản sao lưu), 3 làm được một phần.

Chạy thẳng: `SUA_LOI_WINDOWS.bat -Mode dism-sfc|dism-quet|dism-sua|sfc|mang|tuong-lua|tuong-lua-khoi-phuc|o-dia-quet|o-dia-sua|ram|windows-update [-ODia D] [-TepSaoLuu file.wfw] [-ChayThu]`.

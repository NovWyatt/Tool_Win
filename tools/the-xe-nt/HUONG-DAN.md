# File thẻ xe .nt (phần mềm giữ xe)

Công cụ cho file danh sách thẻ `.nt` nạp vào phần mềm giữ xe ITS Pro: xem phần mềm sẽ đọc file ra sao, sửa file của bên bán bị mất số 0 ở CardID, tạo file `.nt` từ danh sách Excel.

| Nút | Làm gì |
|---|---|
| Xem file thẻ như phần mềm giữ xe đọc | Chỉ đọc. Phần mềm nạp được bao nhiêu thẻ, CardID đúng chưa, lỗi gì. |
| Sửa file thẻ của bên bán | Ghi bản sửa vào thư mục `da-sua` cạnh file gốc, kèm file thử 1 thẻ. |
| Tạo file thẻ .nt từ danh sách Excel | Danh sách có cột số thẻ và cột mã thẻ thành file `<số đầu>-<số cuối>.nt`, kèm file thử 1 thẻ. |

File gốc không bao giờ bị sửa: công cụ đọc trên bản sao trong thư mục tạm, ghi kết quả ra file mới.

## Vì sao nạp xong thẻ không quẹt được

- File `.nt` thực ra là file Excel 97-2003 (`.xls`) đổi đuôi, nên mở bằng Notepad chỉ thấy ký tự lạ. Sheet `Sheet1`, ba cột `STT | CardID | tinhtrang`.
- Bên bán thường để CardID dạng **số** với kiểu hiển thị `0000000000`. Số 0 ở đầu chỉ là cách Excel hiển thị, không nằm trong dữ liệu: ô ghi 9569726 nhưng hiện 0009569726.
- Phần mềm giữ xe đọc giá trị thật của ô nên nhận 9569726. Đầu đọc gửi đủ 10 số 0009569726, hai mã không khớp nên thẻ không quẹt được.
- Cách sửa: CardID phải là **chữ** đủ 10 số. Công cụ ghi đúng như vậy.

## Phần mềm giữ xe đọc file thế nào

Theo mã ITS Pro đã dịch ngược (`frmCommon.cmdimport_active_Click`, `clsExcel.ImportDataFromExcel`, `clsThe.FillDataActive`):

- Đọc bằng Jet OLEDB 4.0 kiểu `Excel 8.0`: sheet đầu tiên, vùng `A1:J65536`, dòng 1 là tiêu đề.
- Lấy cột tên `STT` và `CardID` (không phân biệt hoa thường). Thiếu cột thì phần mềm báo *Vui lòng chọn file Import theo file định dạng của nhà cung cấp*.
- Dòng thiếu STT hoặc CardID bị bỏ qua, không báo. Cột `tinhtrang` không được dùng: thẻ nạp vào luôn ở trạng thái 1.
- Jet đoán kiểu cột theo 8 dòng đầu. Cột CardID lẫn số và chữ thì ô khác kiểu với đa số thành trống, nên dòng đó bị bỏ qua.
- Mỗi thẻ nạp thành một dòng trong bảng `active`, khoá là cặp (STT, CardID):
  - Nạp lại đúng cặp cũ thì dòng đó bị bỏ qua.
  - Cùng STT mà mã khác (vd lần trước mất số 0) thì thêm dòng mới: STT đó có 2 mã.
- Khi quẹt, phần mềm tìm theo CardID và cần **đúng một** dòng. Một mã nằm ở hai STT thì thẻ không được nhận. Vì vậy công cụ coi mã trùng là lỗi.

Công cụ đọc file bằng đúng cách trên (Jet OLEDB 4.0 bản 32 bit, có sẵn trong Windows), nên kết quả *Xem* là thứ phần mềm sẽ thấy.

## 1. Xem file thẻ như phần mềm giữ xe đọc

Chọn file `.nt`. Báo cáo gồm:

- **Phần mềm giữ xe sẽ đọc**:
  - Sheet và các cột (kiểu số hay chữ), số thẻ nạp được.
  - CardID dạng số làm mất số 0: ví dụ thẻ nào đọc ra mã gì, đúng phải là gì.
  - Mã ngắn hơn 10 số, dòng bị bỏ qua.
- **Nội dung file**:
  - Số thẻ, khoảng số thẻ, số thẻ bị thiếu giữa chừng (để xem có sót thẻ không).
  - Lỗi: mã trùng, mã có chữ, mã quá dài, thiếu số thẻ hoặc thiếu mã.
  - Vài thẻ đầu và thẻ cuối để so với số in trên thẻ.
- **Kết luận**: một trong ba trường hợp:
  - File dùng được.
  - Cần chạy *Sửa file thẻ của bên bán*.
  - File có lỗi không tự sửa được: báo bên bán gửi lại.

Báo cáo lưu ở `ket_qua\BaoCao_TheXe_<tên file>_<thời gian>.txt`.

## 2. Sửa file thẻ của bên bán

1. Chọn file `.nt` của bên bán. Thư mục ghi kết quả bỏ trống thì là `da-sua` cạnh file gốc.
2. Công cụ đọc danh sách, báo số thẻ, khoảng số thẻ, số mã được thêm số 0. Có lỗi (mã trùng, có chữ, quá 10 số, thiếu) thì dừng, không ghi gì.
3. File đã đúng (CardID dạng chữ đủ 10 số) thì báo *không cần sửa*.
4. Ghi ba file:
   - `<tên>.nt`: nạp vào phần mềm.
   - `<tên>.xls`: cùng nội dung, bấm đúp để mở xem bằng Excel.
   - `thu-<số thẻ đầu>.nt`: chỉ có thẻ đầu tiên, để nạp thử.
5. Đọc lại file vừa ghi như phần mềm giữ xe, so từng thẻ (số thẻ, mã) với danh sách. Khác một thẻ là báo lỗi.

Đã có file cùng tên thì công cụ hỏi ghi đè (Enter = không).

## 3. Tạo file thẻ .nt từ danh sách Excel

Danh sách bên mua gửi (vd `ID THE XE.xlsx`) cần có:

- Một cột số thẻ: tiêu đề `SỐ THẺ`, `STT`, `STT thẻ`. Có cả `STT` (số dòng) lẫn `SỐ THẺ` thì công cụ lấy `SỐ THẺ`.
- Một cột mã thẻ: tiêu đề `ID`, `CardID`, `Mã thẻ`, `ID thẻ`.
- Dòng tiêu đề nằm trong 15 dòng đầu; các dòng tiêu đề phụ phía trên được bỏ qua.

Nhận `.xlsx`, `.xlsm` (cần Excel), `.xls`, `.nt`, `.csv`, `.txt` (phân cách bằng tab, `;` hoặc `,`). Công cụ ghi `<số thẻ nhỏ nhất>-<số thẻ lớn nhất>.nt`, bản `.xls`, file thử 1 thẻ vào thư mục đã chọn, bỏ trống thì cạnh danh sách. Báo cáo in cột nào được dùng làm số thẻ, cột nào làm mã thẻ để bạn kiểm tra.

## Cách nạp vào phần mềm giữ xe

1. Nạp file thử `thu-<số>.nt` trước, quẹt thử đúng thẻ đó: phần mềm phải nhận mã đủ 10 số.
2. Được rồi thì nạp file đủ.
3. Lô đã từng nạp với mã thiếu số 0: phần mềm thêm dòng mới, STT cũ có 2 mã.
   - Dòng mã sai vô hại vì không thẻ thật nào mang mã đó, nhưng nên xoá trong phần mềm cho gọn.
   - Thẻ đã gán cho khách (thẻ tháng) thì ghi lại trước khi xoá.

Mở file `.xls` bằng Excel có thể thấy tam giác xanh *Number Stored as Text*: bình thường. Đừng bấm *Convert to Number* rồi lưu, số 0 sẽ mất.

## Tuỳ chọn

- **Số chữ số của mã thẻ** (`-DoDai`, mặc định 10): thẻ EM của đầu đọc gửi 10 số. Mã ngắn hơn được thêm số 0 ở đầu, dài hơn thì báo lỗi.

## Kết quả, mã thoát

- Báo cáo, nhật ký: `ket_qua\BaoCao_TheXe_*.txt` (xem), `ket_qua\NhatKy_TheXe_*.txt` (sửa, tạo), có số thẻ và mã thẻ nên không gửi ra ngoài nếu không cần.
- Mã thoát:
  - 0: xong (*Xem* luôn trả 0, kể cả khi file có lỗi).
  - 1: file có lỗi, chưa ghi gì.
  - 2: không thấy file, sai đuôi file, thư mục ghi trùng file gốc.
  - 1223: bạn không cho ghi đè.

## Chạy không cần Trạm Tool

Bấm đúp `THE_XE.bat` để mở menu, rồi kéo thả file vào cửa sổ khi được hỏi. Kéo thả file `.nt` lên biểu tượng `THE_XE.bat` cũng mở menu với file đó. Chạy thẳng:

```bat
THE_XE.bat -Mode xem -File "D:\The xe\3257-3426.nt"
THE_XE.bat -Mode sua -File "D:\The xe\3257-3426.nt"
THE_XE.bat -Mode tao -File "D:\The xe\ID THE XE.xlsx" -ThuMuc "D:\The xe\nap"
```

`THE_XE.bat` chạy PowerShell 32 bit (Jet OLEDB 4.0 chỉ có bản 32 bit). Gọi `TheXe.ps1` bằng PowerShell 64 bit thì script tự mở lại bằng bản 32 bit trong cùng cửa sổ.

Mã nguồn:

- `TheXe.ps1`: menu, chế độ.
- `lib\DocGhi.ps1`: đọc như phần mềm, đọc danh sách, ghi file.
- `lib\TheXe.ps1`: kiểm tra danh sách, các chế độ.
- `lib\Chung.ps1`: in, hỏi, báo cáo.
- `mau\mau-trong.xls`: file mẫu trống, Sheet1, STT số, CardID chữ, tinhtrang số, một dòng mẫu công cụ ghi đè.

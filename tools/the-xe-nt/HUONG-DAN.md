# File thẻ xe .nt (phần mềm giữ xe)

Công cụ cho file danh sách thẻ `.nt` nạp vào phần mềm giữ xe ITS Pro: chuyển danh sách Excel sang `.nt`, kiểm tra file `.nt` có đúng không, chuyển `.nt` sang Excel, sửa file của bên bán bị mất số 0 ở CardID.

| Nút | Làm gì |
|---|---|
| Chuyển Excel sang file .nt | Danh sách có cột số thẻ và cột mã thẻ thành file `<số đầu>-<số cuối>.nt`, kèm file thử 1 thẻ. |
| Kiểm tra file .nt | Chỉ đọc. Phần mềm nạp được bao nhiêu thẻ, CardID đúng chưa, lỗi gì. Chọn thêm danh sách Excel thì so từng thẻ. |
| Chuyển file .nt sang Excel | Ghi `<tên>.xlsx`: mỗi thẻ một dòng, mã phần mềm đọc được, kết quả từng thẻ (ô có vấn đề tô đỏ). |
| Sửa file .nt của bên bán | Ghi bản sửa vào thư mục `da-sua` cạnh file gốc, kèm file thử 1 thẻ. |

File gốc không bao giờ bị sửa: công cụ đọc trên bản sao trong thư mục tạm, ghi kết quả ra file mới. Không cần Excel: file `.nt` đọc, ghi bằng Jet OLEDB 4.0 có sẵn trong Windows, file `.xlsx` đọc, ghi thẳng.

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

Công cụ đọc file bằng đúng cách trên (Jet OLEDB 4.0 bản 32 bit, có sẵn trong Windows), nên kết quả *Kiểm tra* là thứ phần mềm sẽ thấy.

## 1. Chuyển Excel sang file .nt

Danh sách bên mua gửi (vd `ID THE XE.xlsx`) cần có:

- Một cột số thẻ: tiêu đề `SỐ THẺ`, `STT`, `STT thẻ`. Có cả `STT` (số dòng) lẫn `SỐ THẺ` thì công cụ lấy `SỐ THẺ`.
- Một cột mã thẻ: tiêu đề `ID`, `CardID`, `Mã thẻ`, `ID thẻ`.
- Dòng tiêu đề nằm trong 15 dòng đầu; các dòng tiêu đề phụ phía trên được bỏ qua.

Nhận `.xlsx`, `.xlsm`, `.xls`, `.nt`, `.csv`, `.txt` (phân cách bằng tab, `;` hoặc `,`). File `.xlsx` bị đổi đuôi thành `.xls` hay `.nt` vẫn đọc được. Với `.xlsx` công cụ đọc sheet đầu tiên, 26 cột đầu; ô công thức lấy giá trị Excel đã lưu trong file.

Công cụ:

1. Đọc danh sách, báo số thẻ, khoảng số thẻ, cột nào được dùng làm số thẻ, cột nào làm mã thẻ để bạn kiểm tra.
2. Có lỗi (mã trùng, có chữ, quá 10 số, thiếu số thẻ hoặc thiếu mã) thì dừng, không ghi gì.
3. Ghi vào thư mục đã chọn, bỏ trống thì cạnh danh sách:
   - `<số thẻ nhỏ nhất>-<số thẻ lớn nhất>.nt`: nạp vào phần mềm.
   - `<số đầu>-<số cuối>.xls`: cùng nội dung, bấm đúp để mở xem bằng Excel.
   - `thu-<số thẻ đầu>.nt`: chỉ có thẻ đầu tiên, để nạp thử.
4. Đọc lại file vừa ghi như phần mềm giữ xe, so từng thẻ (số thẻ, mã) với danh sách. Khác một thẻ là báo lỗi.

Đã có file cùng tên thì công cụ hỏi ghi đè (Enter = không).

## 2. Kiểm tra file .nt (so với danh sách Excel nếu có)

Chọn file `.nt`; chọn thêm danh sách Excel nếu muốn so từng thẻ. Báo cáo gồm:

- **Phần mềm giữ xe sẽ đọc**:
  - Sheet và các cột (kiểu số hay chữ), số thẻ nạp được.
  - CardID dạng số làm mất số 0: ví dụ thẻ nào đọc ra mã gì, đúng phải là gì.
  - Mã ngắn hơn 10 số, dòng bị bỏ qua.
- **Nội dung file**:
  - Số thẻ, khoảng số thẻ, số thẻ bị thiếu giữa chừng (để xem có sót thẻ không).
  - Lỗi: mã trùng, mã có chữ, mã quá dài, thiếu số thẻ hoặc thiếu mã.
  - Vài thẻ đầu và thẻ cuối để so với số in trên thẻ.
- **So với danh sách** (khi có chọn danh sách): so theo số thẻ, giữa mã phần mềm đọc được và mã trong danh sách (đã thêm số 0 cho đủ 10 số):
  - Khớp.
  - Mất số 0: phần mềm đọc thiếu số 0 ở đầu, ngoài ra giống danh sách.
  - Khác mã: liệt kê tới 10 thẻ, mã trong file và mã trong danh sách.
  - Có trong danh sách nhưng không có trong file `.nt`, và ngược lại.
- **Kết luận**: một trong các trường hợp:
  - File dùng được (và khớp danh sách, nếu có so).
  - Cần chạy *Sửa file .nt của bên bán*.
  - File không khớp danh sách: hỏi lại bên bán, hoặc tạo file từ danh sách bằng *Chuyển Excel sang file .nt*.
  - File có lỗi không tự sửa được: báo bên bán gửi lại.

Báo cáo lưu ở `ket_qua\BaoCao_TheXe_<tên file>_<thời gian>.txt`.

## 3. Chuyển file .nt sang Excel

Ghi `<tên file .nt>.xlsx` vào thư mục đã chọn, bỏ trống thì cạnh file `.nt`. Mỗi dòng có dữ liệu của file `.nt` thành một dòng:

| Cột | Nội dung |
|---|---|
| STT | Số thẻ. |
| CardID | Mã đúng: dạng chữ, đủ 10 số (đã thêm số 0 bị mất). |
| Phần mềm đọc | Mã phần mềm giữ xe đọc được từ dòng này, hoặc `(bỏ qua dòng này)`. |
| Kết quả | `Đúng`, hoặc vấn đề của thẻ (ô tô đỏ): mất số 0, phần mềm bỏ qua dòng, mã trùng với thẻ nào, thiếu mã, mã có chữ... |
| Dòng trong file .nt | Số dòng trong file `.nt`, để tìm lại. |

Dòng tiêu đề cố định khi cuộn, có nút lọc: lọc cột *Kết quả* để chỉ xem thẻ có vấn đề. Cột CardID để dạng chữ nên gõ thêm mã vào vẫn giữ số 0.

Sửa trong Excel xong, muốn ra lại file `.nt`: chạy *Chuyển Excel sang file .nt* với file `.xlsx` này. Công cụ chỉ lấy cột `STT` và `CardID`, bỏ qua các cột khác. Nên chọn thư mục ghi khác thư mục file `.nt` gốc: file ra có cùng tên `<số đầu>-<số cuối>.nt` với file gốc.

Đã có file `.xlsx` cùng tên thì công cụ hỏi ghi đè (Enter = không). File đang mở trong Excel thì đóng lại rồi chạy lại.

## 4. Sửa file .nt của bên bán

1. Chọn file `.nt` của bên bán. Thư mục ghi kết quả bỏ trống thì là `da-sua` cạnh file gốc.
2. Công cụ đọc danh sách, báo số thẻ, khoảng số thẻ, số mã được thêm số 0. Có lỗi (mã trùng, có chữ, quá 10 số, thiếu) thì dừng, không ghi gì.
3. File đã đúng (CardID dạng chữ đủ 10 số) thì báo *không cần sửa*.
4. Ghi ba file như mục 1 (`<tên>.nt`, `<tên>.xls`, `thu-<số thẻ đầu>.nt`), đọc lại như phần mềm và so từng thẻ.

Sửa được cả file `.xlsx` bị đổi đuôi thành `.nt` (phần mềm giữ xe không đọc được loại này).

## Cách nạp vào phần mềm giữ xe

1. Nạp file thử `thu-<số>.nt` trước, quẹt thử đúng thẻ đó: phần mềm phải nhận mã đủ 10 số.
2. Được rồi thì nạp file đủ.
3. Lô đã từng nạp với mã thiếu số 0: phần mềm thêm dòng mới, STT cũ có 2 mã.
   - Dòng mã sai vô hại vì không thẻ thật nào mang mã đó, nhưng nên xoá trong phần mềm cho gọn.
   - Thẻ đã gán cho khách (thẻ tháng) thì ghi lại trước khi xoá.

Mở file `.xls` bằng Excel có thể thấy tam giác xanh *Number Stored as Text*: bình thường. Đừng bấm *Convert to Number* rồi lưu, số 0 sẽ mất.

## Tuỳ chọn

- **Số chữ số của mã thẻ** (`-DoDai`, mặc định 10): thẻ EM của đầu đọc gửi 10 số. Mã ngắn hơn được thêm số 0 ở đầu, dài hơn thì báo lỗi.
- **Danh sách Excel để so** (`-DanhSach`, chỉ cho *Kiểm tra*): bỏ trống thì không so.

## Kết quả, mã thoát

- Báo cáo, nhật ký: `ket_qua\BaoCao_TheXe_*.txt` (kiểm tra), `ket_qua\NhatKy_TheXe_*.txt` (chuyển đổi, sửa), có số thẻ và mã thẻ nên không gửi ra ngoài nếu không cần.
- Mã thoát:
  - 0: xong (*Kiểm tra* luôn trả 0, kể cả khi file có lỗi hoặc không khớp danh sách).
  - 1: file có lỗi, chưa ghi gì; hoặc không ghi được file kết quả.
  - 2: không thấy file, sai đuôi file, thư mục ghi trùng file gốc.
  - 1223: bạn không cho ghi đè.

## Chạy không cần Trạm Tool

Bấm đúp `THE_XE.bat` để mở menu, rồi kéo thả file vào cửa sổ khi được hỏi. Kéo thả file lên biểu tượng `THE_XE.bat` cũng mở menu với file đó. Chạy thẳng:

```bat
THE_XE.bat -Mode tao -File "D:\The xe\ID THE XE.xlsx" -ThuMuc "D:\The xe\nap"
THE_XE.bat -Mode xem -File "D:\The xe\3257-3426.nt"
THE_XE.bat -Mode xem -File "D:\The xe\3257-3426.nt" -DanhSach "D:\The xe\ID THE XE.xlsx"
THE_XE.bat -Mode xuat -File "D:\The xe\3257-3426.nt"
THE_XE.bat -Mode sua -File "D:\The xe\3257-3426.nt"
```

`THE_XE.bat` chạy PowerShell 32 bit (Jet OLEDB 4.0 chỉ có bản 32 bit). Gọi `TheXe.ps1` bằng PowerShell 64 bit thì script tự mở lại bằng bản 32 bit trong cùng cửa sổ.

Mã nguồn:

- `TheXe.ps1`: menu, chế độ.
- `lib\DocGhi.ps1`: đọc như phần mềm, đọc danh sách, ghi file `.nt`, đọc và ghi `.xlsx`.
- `lib\TheXe.ps1`: kiểm tra danh sách, so với danh sách, các chế độ.
- `lib\Chung.ps1`: in, hỏi, báo cáo.
- `mau\mau-trong.xls`: file mẫu trống, Sheet1, STT số, CardID chữ, tinhtrang số, một dòng mẫu công cụ ghi đè.

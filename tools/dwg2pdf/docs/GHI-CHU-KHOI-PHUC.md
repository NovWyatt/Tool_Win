# Recovered DWG -> PDF pipeline ("Chuyển bảng vẽ SAMSORA sang PDF")

Recovered on 2026-10-04 from the Claude Code transcript
`C:\Users\Wyatt\.claude\projects\C--Users-Wyatt-Desktop-convert-card-pdf\8fa39280-fd6b-418f-abc9-cdcedf4e60c8.jsonl`
(session 2026-10-01 03:12–11:17 UTC = 10:12–18:17 local UTC+7, Claude Code 2.1.284, cwd `C:\Users\Wyatt\Desktop\convert_card_pdf`).

In the session, every script lived in the session scratchpad
`C:\Users\Wyatt\AppData\Local\Temp\claude\C--Users-Wyatt-Desktop-convert-card-pdf\8fa39280-fd6b-418f-abc9-cdcedf4e60c8\scratchpad`
(called `$S` below). That folder no longer exists.

---

## 1. User's request, in their own words

* 03:12 UTC (original request):
  > trong thư mục đó tôi có một thư mục "C:\Users\Wyatt\Desktop\convert_card_pdf\Bang ve SAMSORA" có chứa các file bảng vẽ auto card về chung cư bạn có thể chuyển qua pdf giúp tôi không

  (Gist: "the folder `Bang ve SAMSORA` holds AutoCAD drawings of an apartment building. Can you convert them to PDF?")
* Tool choice (AskUserQuestion, 03:13): the user picked **"LibreDWG + Python (Recommended)"**. The other options were "Tôi tự tải ODA File Converter" and "Dùng DWG TrueView".
* Follow-ups:
  * 03:53 "vì sao chạy lâu vậy có thể cho tôi biết tiến trình bao nhiêu rồi không và bao lâu là xong"
  * 07:07 "tiếp tục đi, xong thì báo tôi" (sent twice)
  * 10:34 "hiện tại tôi đang dùng opus 5.5 nhưng quá lâu tôi cần bạn trả lời nhanh hơn có nên đổi model không"
  * 11:16 "còn thiếu file nào nữa không sao tôi vẫn thấy running task"
* Model changes: `/model claude-sonnet-5-5` at 03:36, then back to `/model claude-opus-5-5` at 07:09.

## 2. Files in this folder

| File | What it is | How exact |
|---|---|---|
| `convert.py` | **Main converter, final version.** Turns one DXF into one multi-page PDF, one page per drawing frame (sheet). | Byte-identical to Claude Code file-history backup `a1fbe3c40f3ab67a@v4`. SHA-256 `eb2662d6a6895e65a01beac7d25aca6a68df0912ee8c586a102f76b31127359c`. |
| `vni.py` | Converts legacy VNI-Windows Vietnamese text to Unicode and points VNI text styles at Arial. `convert.py` imports it. | Byte-identical to backup `752d4fea200cffc9@v2`. SHA-256 `aa9d1b40ff91dd957ddf7c25919fb7205c9f187a0816c45d5c883433bb795117`. |
| `session_helpers/ole_patch.py` | Inserts the embedded Excel (OLE) table pictures into an already-rendered PDF. It was run on the KT-02 and KT08 PDFs that were delivered (see §5.6). A fresh run of the final `convert.py` does this by itself. | Rebuilt from its heredoc (#192). |
| `session_helpers/qa_render.py` | Renders QA PNGs for every page: full sheet, title-block strip and a centre detail crop. | heredoc (#127) |
| `session_helpers/sheet.py` | Builds a contact sheet of all pages of a PDF and prints path counts per page. | heredoc (#61) |
| `session_helpers/survey3.py` | Dry run over a DXF: frames, sheet order, frozen-layer inserts, block draw order, VNI count, OLE count, text-repair stats. | heredoc (#171) |
| `session_helpers/survey.py`, `survey2.py` | Earlier frame-detection and merging surveys. | heredocs (#78, #145) |
| `session_helpers/sheetcodes.py` | Lists the sheet codes and titles found inside each detected sheet (written to debug KT03,04). | heredoc (#147) |
| `session_helpers/probe.py` | Maps a pixel rectangle of a QA PNG back to model space and lists the entities there. | heredoc (#131) |
| `session_helpers/dbg_f02.py` | Debugs the overlapping double frames in KT03,04. | heredoc (#66) |
| `session_helpers/dxfinfo.py` | Per-DXF inventory: entity counts, paper-space layouts and viewports, top blocks, text styles and fonts. It was created as `inspect.py` and renamed because that name shadowed the stdlib module, then fixed with `sed`. | heredoc (#15) + `mv` (#16) + `sed` (#17) |
| `session_helpers/overview.py` | First attempt: render the whole model space to one PNG. Took about 10 min on one file; abandoned. | heredoc (#19) |
| `session_helpers/frames.py`, `frames2.py`, `frames3.py` | Experiments to find sheet frames (rectangles, very large entities, A-series aspect ratio). | heredocs (#23–#25) |
| `session_helpers/test1.py`, `test2.py` | Tests of crop vs. no-crop and of the recording bbox vs. the frame bbox. | heredocs (#30, #33) |
| `session_helpers/vnicheck.py`, `vniscan.py`, `shxscan.py`, `vnisample.py` | Scans for VNI, TCVN3 and Vietnamese-SHX text, plus a before/after preview of VNI decoding. | heredocs (#116, #118, #121, #122) |
| `session_helpers/patch_colors.py` | One-off patch that edits `convert.py` **in place** in the current directory (an intermediate version). Superseded; do not run it. | heredoc (#90) |
| `session_helpers/runall.sh` | Runner for an early batch (xargs -P 3, `$S` hard-coded). Superseded. | heredoc (#46) + `sed` (#47) + rewrite (#59) |
| `session_helpers/deliver.sh` | Prepared copy-to-`PDF\` script. It points at `final3` and was **never run**. The real delivery used the inline commands in §5.7. | heredoc (#152, unquoted, `$S` expanded) |
| `session_helpers/convert_v3_backup.py` | `cp` snapshot of `convert.py` taken at 10:23 UTC (Write #141 + Edit #146). It is the version behind the `final3` run. Superseded. | `cp` (#169) |
| `session_helpers/map.tsv` | Maps `f01`–`f14` to the original DWG file names. `deliver.sh` and the delivery commands read it. | from the `cat map.tsv` output (#14) |
| `session_helpers/pdf-sheet-qa-wf_ecd14713-1ea.js`, `pdf-sheet-qa-final-wf_e0610461-251.js` | Claude Code *Workflow* scripts for multi-agent visual QA. They only run inside Claude Code's Workflow tool. | Copied from the session folder; identical to the transcript. |

`#NNN` is the tool call's position in the transcript, counting every tool_use in order.

### How the recovery was done and verified

All Write/Edit tool calls and all Bash heredocs and in-place edits (`sed -i`, `mv`, `cp`, inline Python patches) were replayed in transcript order. **All 6 file-history snapshots** that Claude Code kept (`convert.py` v1–v4, `vni.py` v1–v2, in `C:\Users\Wyatt\.claude\file-history\8fa39280-...`) came out byte-for-byte identical. That checks the replay method, including the gotcha below. The helper scripts have no backups. They are exact heredoc bodies after the backslash transform, which changes nothing in any helper file.

**Gotcha found during recovery.** On this machine, Claude Code's Bash tool rewrites backslashes before bash sees the command, even inside a quoted heredoc. A run of *k* backslashes that is not followed by `"` becomes ceil(*k*/2) backslashes. So heredoc text in a transcript is **not** always the file that landed on disk. In this session it hit two file lines: `"\\P"` in `convert.py` (#37) and `r"\\f(vni…"` in `vni.py` (#117). Edits #45 and #159 fixed both later. It also broke the inline Python patches #42, #58, #73 and #157: it produced a literal `\n`, a backspace byte in a regex, and a form-feed that made a search fail. Those were repaired with Edits. Lesson for the future tool: create files with an editor or the Write tool, not with heredocs through Claude Code's Bash tool.

## 3. Pipeline at a glance

```
14 x .dwg (AC1018/R2004, AC1021/R2007, AC1032/R2018)
   │  copy to short names f01..f14 (map.tsv keeps the original names)
   ▼
LibreDWG 0.14  dwg2dxf.exe -y -o fNN.dxf fNN.dwg          (KT06 needed a padded copy, §5.4)
   ▼
convert.py fNN.dxf fNN.pdf mono      (Python 3.14.7 + ezdxf 1.4.4 + PyMuPDF 1.28.2 + vni.py [+ olefile, Pillow])
   │  model space only; 1 PDF page per title-block frame; vector output; monochrome plot style
   ▼
(KT-02, KT08 only) ole_patch.py  -> inserts embedded Excel tables as 300-dpi images
   ▼
copy final4/fNN.pdf -> "Bang ve SAMSORA\PDF\<original name>.pdf"
```

## 4. DWG -> DXF converter: LibreDWG

* **Download URL:** <https://github.com/LibreDWG/libredwg/releases/download/0.14/libredwg-0.14-win64.zip>
  * 12,084,779 bytes; release tag `0.14`, published 2026-06-27.
  * Found through `https://api.github.com/repos/LibreDWG/libredwg/releases/latest`.
  * A detached signature `…win64.zip.sig` exists but was **not** verified in the session.
* **License:** GNU GPL v3 (`COPYING` in the repo; the GitHub API reports `GPL-3.0`). LibreDWG is a GNU project and is free software.
* **Install location:** none. The zip was downloaded and extracted into `$S\libredwg\`; `dwg2dxf.exe` sits at the root of that folder, next to `dwgread.exe`, `dwg2SVG.exe`, `dxf2dwg.exe` and others.
* **Status on this machine (checked 2026-10-04):** **not present**. The scratchpad is deleted, and no `dwg2dxf.exe` or `libredwg*` turns up under `C:\Users\Wyatt`, `D:\Repo`, `D:\Users\Wyatt`, `C:\Program Files*`, `D:\Program Files` or `C:\ProgramData`. The release asset is still downloadable (HTTP 200, same size), and 0.14 is still the latest release.
* **Rejected alternatives:**
  * ODA File Converter (`https://www.opendesign.com/guestfiles/get?filename=ODAFileConverter_QT6_vc16_amd64dll.msi`): the automated HEAD request returned **403 Forbidden**, so the user would have had to download it by hand.
  * Autodesk DWG TrueView: about 1 GB, manual install, manual plotting.
* A registry scan (#3) found no CAD software on the machine.

## 5. Exact commands used (effective text after the backslash transform)

### 5.1 Download (PowerShell, #10)
```powershell
$s = "C:\Users\Wyatt\AppData\Local\Temp\claude\C--Users-Wyatt-Desktop-convert-card-pdf\8fa39280-fd6b-418f-abc9-cdcedf4e60c8\scratchpad"; New-Item -ItemType Directory -Force $s | Out-Null; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri "https://github.com/LibreDWG/libredwg/releases/download/0.14/libredwg-0.14-win64.zip" -OutFile "$s\libredwg.zip" -UseBasicParsing; Expand-Archive -Force "$s\libredwg.zip" "$s\libredwg"
```

### 5.2 Python packages (#11, #162)
```bash
python -m pip install --quiet ezdxf pymupdf matplotlib     # -> ezdxf 1.4.4, PyMuPDF 1.28.2 (user site-packages of Python 3.14)
python -m pip install --quiet olefile                      # later, for the OLE tables
```
* `python` was `C:\Python314\python.exe` (Python 3.14.7). numpy 2.5.2 and Pillow 12.3.0 were already installed.
* matplotlib was installed but is **not used**.
* **None of this exists any more.** `C:\Python314` and `%APPDATA%\Python\Python314` are gone, `py -3.11` points to a missing `D:\Users\Wyatt\AppData\Local\Programs\Python\Python311\python.exe`, and no working Python is on the machine.

### 5.3 DWG -> DXF (Git Bash, #13)
```bash
S=".../scratchpad"; SRC="/c/Users/Wyatt/Desktop/convert_card_pdf/Bang ve SAMSORA"
mkdir -p "$S/dxf"; i=0; : > "$S/dxf/map.tsv"
for f in "$SRC"/*.dwg; do i=$((i+1)); n=$(printf 'f%02d' $i); cp "$f" "$S/dxf/$n.dwg"; printf '%s\t%s\n' "$n" "$(basename "$f")" >> "$S/dxf/map.tsv"; done
cd "$S/dxf"; for n in f*.dwg; do b=${n%.dwg}; timeout 600 "$S/libredwg/dwg2dxf.exe" -y -o "$b.dxf" "$n" > "$b.log" 2>&1; done
```
Each file took 0–5 s and returned rc=0. LibreDWG writes very noisy logs, mostly `Warning: Unknown object` and `Unstable Class` lines; f04's log had 51,150 warning/error lines. Only f10 actually failed (§5.4).

### 5.4 Rescue of `2018.1.03  KT06- RAM DỐC, BẬC CẤP.dwg` (f10, #99, then #172)
`dwg2dxf` failed with `ERROR: Invalid System Section` and produced a 7 kB DXF. The cause is a sanity check in LibreDWG's `src/decode_r2007.c`: `section->data_size > 10 * dat->size` rejects this R2007 file even though the file is fine. Workaround: pad a **copy** with 2 MB of zeros. The original file was not touched.
```bash
cd "$S/rescue"; cp ../dxf/f10.dwg f10pad.dwg; head -c 2000000 /dev/zero >> f10pad.dwg
timeout 600 "$S/libredwg/dwg2dxf.exe" -y -o f10.dxf f10pad.dwg > f10pad.log 2>&1      # rc=0, 6.3 MB, 4 sheets KT06-01..04
cp "$S/rescue/f10.dxf" "$S/dxf/f10.dxf"                                             # done at the start of the final batch
```
(The autosave file `sav1E68.tmp` in the drawing folder was also converted. It turned out to be a copy of KT10, not KT06.)

### 5.5 Final batch: produced the delivered PDFs (#172, 10:27 UTC; finished at 18:13 local)
```bash
mkdir -p "$S/final4"; cp "$S/rescue/f10.dxf" "$S/dxf/f10.dxf"; cd "$S/dxf"
printf '%s\n' f12 f02 f13 f05 f10 f04 f11 f08 f01 f03 f07 f14 f06 f09 | PYTHONIOENCODING=utf-8 PYTHONPATH="$S" xargs -P 4 -I{} sh -c "python '$S/convert.py' {}.dxf ../final4/{}.pdf mono > ../final4/{}.log 2>&1"
```
At that moment `convert.py` was the 10:26 version (Write #170 = backup v3). The final file in this folder adds only Edits #190 and #191. Those read the real OLE frame corners, because LibreDWG writes dummy corner points.

### 5.6 OLE tables patched into KT-02 (f12) and KT08 (f13) (#192, #196)
```bash
cd "$S" && for f in f12 f13; do PYTHONIOENCODING=utf-8 PYTHONPATH="$S" python ole_patch.py dxf/$f.dxf final4/$f.pdf final4/${f}_ole.pdf; done
cd "$S/final4"; mv f12_ole.pdf f12.pdf; mv f13_ole.pdf f13.pdf
```
`ole_patch.py` imports the **final** `convert.py`. Placements: KT01-01 ×2, KT01-02, KT02-01, KT02-02 ×2, and KT08-02 ×2.

### 5.7 Delivery (#197, #198)
```bash
DST="/c/Users/Wyatt/Desktop/convert_card_pdf/Bang ve SAMSORA/PDF"; mkdir -p "$DST"
while IFS=$'\t' read -r id name; do [ "$id" = "f09" ] && continue; cp "$S/final4/$id.pdf" "$DST/${name%.dwg}.pdf"; done < "$S/dxf/map.tsv"
# f09 (KT10) was copied the same way once it finished at 18:13 local
```
The folder was later moved to `D:\Repo\Tool_Win\convert_card_pdf\Bang ve SAMSORA\PDF\`. A check on 2026-10-04 found all 14 PDFs there; their modified times (18:05 and 18:13 on Oct 1) match these copies. KT-02 contains 6 embedded images and KT08 contains 2, which are the OLE tables. The `PDF.zip` next to the folder (18:17) was not made by any tool call in the transcript.

## 6. How the final `convert.py` works

Usage: `python convert.py <in.dxf> <out.pdf> [mono]`.
* `mono` is the default and the only mode ever used.
* `vni.py` must be importable (same folder or `PYTHONPATH`).
* Set `PYTHONIOENCODING=utf-8` on Windows, or the cp1252 console crashes when printing Vietnamese.

1. **Read** with `ezdxf.recover.readfile`, which tolerates LibreDWG's DXF.
2. **Sanitize:**
   * Empty linetypes on entities and layers become BYLAYER or Continuous, including MLINE style elements. Without this, `DXFInvalidLineType: Linetype ""` crashed f03.
   * Layer `DEFPOINTS` and every layer with plot=off are switched off.
   * INSERTs on **frozen** layers are made invisible; AutoCAD hides them, ezdxf did not.
   * Each block's own **SORTENTSTABLE** draw order is applied; ezdxf ignores it when expanding an INSERT.
3. **Text repairs:**
   * `rejoin_utf8`: LibreDWG splits long strings mid UTF-8 sequence, which showed up as `□□□`, e.g. "CHỐNG".
   * MTEXT: drop empty column records (type NONE), which pushed text into a phantom second column.
   * MTEXT: emulate a large first-line indent `\pi…;` by shifting and narrowing the text box; ezdxf otherwise dropped the paragraph's first word ("CÔNG TY CỔ PHẦN").
   * MTEXT: strip other indents larger than 3× the text height.
   * Then `vni.fix_document`; see §7.
4. **Find sheets (frames).** Paper space is ignored. Every DWG keeps its sheets in **model space** as title-block block references such as `A1 1-200` on layer `00-KHUNG`. The `Layout1` tabs held 0–4 viewports on A3 paper (297×420, or 420×297 in f04) and were not used.
   * A frame is an INSERT on a printing layer whose name contains `KHUNG`, whose bounding box has an aspect ratio of 1.38–1.45, and whose long side is at least 1000 units. Duplicates are removed.
   * Also counted: the same block placed on other printing layers (this recovered KT03-03 and KT03-04), and frames nested inside other blocks up to depth 4 (this recovered KT12-03).
   * Fallback when nothing is on a KHUNG layer: blocks whose name starts with `A0`–`A4`.
   * Frames that overlap by more than 1 % are **merged** into one long sheet.
5. **Page size per sheet** = sheet bbox ÷ scale.
   * scale = frame long side ÷ the ISO long side of the A-size in the block name, default A1 (841 mm).
   * Normal sheets come out at **841×594 mm (A1 landscape)**. The merged KT03/KT04 elevations come out at **896×594 mm**.
   * With no frames at all, the output is one page of the whole model, at most 1189×841 mm.
6. **Render once.** ezdxf `Frontend(...).draw_layout(msp)` records the whole model space into `PyMuPdfBackend` with:
   * `BackgroundPolicy.WHITE`, `ColorPolicy.COLOR`, `LineweightPolicy.ABSOLUTE` (DXF lineweights in mm);
   * `hatching_timeout=3.0`;
   * `min_hatch_line_distance = 0.35 mm × units-per-mm`, where units-per-mm = median frame long side ÷ 841. Patterns denser than that are filled solid instead of hanging for hours.

   Monkeypatches:
   * MTEXT layout errors fall back to plain text instead of dropping it.
   * WIPEOUTs are marked with a sentinel colour.
   * Too-dense patterns are marked.
   * `DXFPolygon.transform` is fixed: ezdxf scaled or rotated hatch patterns inside scaled blocks twice.
7. **Plot style ("mono", like monochrome.ctb):** a pass over the recorded properties applies these rules.
   * Wipeouts become white.
   * Too-dense patterns become light grey `#c8c8c8` and are drawn **underneath** everything else on the sheet.
   * Neutral greys (R=G=B, strictly between 0 and 255) stay as screening. Greys lighter than `#a0a0a0` are darkened to `#a0a0a0`; darker greys are kept.
   * Every other colour becomes black.
   * No CTB/STB file is read.
8. **Order:**
   * First by position: rows top to bottom, then left to right.
   * Then by the sheet code in each frame's bottom-right corner (`KT05-01`, …), provided every sheet has one.
9. **Per sheet:**
   * Replay a private deep copy of only the records that touch the sheet box: `render_box`, `fit_page`, `crop_at_margins`.
   * Set `_init_flip_y=True` for every replay; without it, pages 2+ came out upside down.
   * Insert the OLE pictures that overlap the sheet.
10. **OLE2FRAME (embedded Excel):**
    * The cached EMF preview is taken from the `\x02OlePres000` stream with `olefile` and rendered by Pillow at 300 dpi (EMF rendering in Pillow is Windows-only).
    * It is placed using the real corners: 4×3 doubles at offsets 2/26/50/74 of the 128-byte header.
11. Save with `deflate=True, garbage=3`.

## 7. Vietnamese text and fonts

* **No VNI or .Vn fonts were installed** (`C:\Windows\Fonts`, checked in #18 and again now). The session therefore did **not** substitute fonts; it **re-encoded** the text.
* **VNI-Windows** (e.g. `KÍNH CÖÔØNG LÖÏC` → `KÍNH CƯỜNG LỰC`) is handled by `vni.py`:
  * a style counts as VNI when its font name starts with `vni`, `vavo`, `vhelv`, `vtime`, … (see `VNI_FONT_PREFIXES`);
  * TEXT, ATTRIB, ATTDEF and MTEXT that "look VNI" are decoded, and the style's font is set to `arial.ttf`;
  * inline MTEXT `\fVNI-…` switches become `\fArial`;
  * `Þ` maps to `Ø` (diameter sign).
  * Converted per file: KT07 hồ bơi 1, KT05 11, KT14 12, KT-02 33, KT12-1,2,3 38.
* **TCVN3 / ABC (.VnTime, .VnArial…) is NOT handled.** See §9.
* **Vietnamese SHX fonts** (`vnroman.shx`, `vn_vni.shx`) were only used for ASCII text, so nothing was needed there.
* **Other fonts** named by the drawings are not installed either. Examples: `VAVON_2.TTF`, `VHELVEN*.TTF`, `arial_2.ttf`, `Copy of arial.ttf`, `romans.shx`, `simplex.shx`, `chhbg.shx`. ezdxf picks its own substitutes, so letter shapes differ from an AutoCAD plot.
* Text is drawn as **vector outlines**: the PDFs have no text layer and are not searchable.

## 8. Problems hit during the session and how they were solved (chronological)

1. **No CAD software installed.** LibreDWG + ezdxf was chosen with the user's approval. ODA's automated download returned 403.
2. **`inspect.py` shadowed the stdlib module.** Renamed to `dxfinfo.py`. The cp1252 console crash was fixed with `PYTHONIOENCODING=utf-8`.
3. **Rendering a whole model space was slow and useless.** Sheets are scattered over millions of drawing units. The fix: render once, then replay per frame.
4. **MTEXT `LayoutError: not enough space`** dropped text. The fix: a plain-text fallback.
5. **Replay mutates the recording and flips Y.** The fix: a private copy per sheet plus `_init_flip_y=True`.
6. **A small block on a KHUNG layer was taken as a sheet.** The fix: the aspect-ratio filter.
7. **Hatching hung for over 2 hours at about 10 GB RAM per process.** The fix: the hatch density limit, the 3 s timeout, and per-sheet filtered replay. KT-02 dropped to about 35 min.
8. **f03 crashed on empty linetypes, including MLINE styles.** The fix: `sanitize_linetypes`.
9. **WIPEOUTs printed as black boxes over labels.** The fix: COLOR rendering followed by the mono pass.
10. **Long elevations built from two overlapping A1 frames were split, with the title block cut.** The fix: `merge_overlapping`.
11. **KT06 DWG "Invalid System Section".** The fix: the zero-padding workaround (§5.4).
12. **VNI mojibake.** The fix: `vni.py`. The inline `\f` VNI detection was broken by the backslash gotcha and fixed by Edit #159.
13. **`□□□` characters.** The fix: `rejoin_utf8`.
14. **Missing first word in the title-block owner box.** Indents were first stripped; the final version emulates them.
15. **DEFPOINTS and non-plot layers were printed** (revision clouds, construction lines). The fix: those layers are hidden.
16. **Missing sheets KT03-03, KT03-04 and KT12-03.** The fix: same-block frames on other layers, and nested frames.
17. **Black or grey bands** from dense patterns and double-scaled block hatches. The fix: light grey drawn underneath, plus the `DXFPolygon.transform` patch.
18. **The KT11 legend was hidden by a wipeout** because the block draw order was ignored. The fix: `apply_block_draw_order`.
19. **Pipe network on a frozen layer was printed.** The fix: hide INSERTs on frozen layers.
20. **KT07-05 title overflowed into a phantom column.** The fix: drop empty column records.
21. **Embedded Excel tables were missing** (drawing list and coordinate tables). The fix: EMF → PNG, placed at the corners read from the OLE header.
22. **Pages were interleaved.** The fix: sort by sheet code.
23. **Leftover background wait loops** kept the "running task" indicator alive. They were killed at the end.

QA:
* Two multi-agent visual QA workflows ran on intermediate outputs: 9 agents on `final`; 29 agents (inspectors plus adversarial verifiers) on `final3`.
* Most of the later fixes (items 13–22) were found or confirmed through those QA rounds.
* **The delivered `final4` output got only spot checks.** The user asked for speed, so no agent QA was run on it.

## 9. Results and known limitations

| id | DWG (original name) | ver | pages | sheets (in PDF order) | render time |
|---|---|---|---|---|---|
| f01 | 2017.1.02 KT09 CHI TIET CAN HO SACOM BINH THANG | R2007 | 8 | KT09-01…08 | 233 s |
| f02 | 2017.1.2 KT03,04MC-MD -  TKKT SACOM | R2007 | 9 | KT03-01…04, KT04-01…05 (merged sheets 896×594) | 1874 s |
| f03 | 2017.11.30 KT13-MB CHONG MOI | R2004 | 3 | KT13-01…03 | 318 s |
| f04 | 2017.12.26 KT07 CHI TIET VS | R2018 | 3 | KT07-01…03 | 75 s |
| f05 | 2017.12.29 KT07 CHI TIET HO BOI | R2018 | 2 | KT07-04, 05 | 81 s |
| f06 | 2017.12.29 KT11-MB TRAN DEN  SACOM BINH THANG | R2004 | 6 | KT11-01…06 | 487 s |
| f07 | 2018.01.02 KT05-THANG BO-THANG MAY SACOM BINH THANG-15 | R2007 | 9 | KT05-01…09 | 290 s |
| f08 | 2018.01.02.KT14 CHI TIET NHA TRAM,NHÀ XE | R2018 | 6 | KT14-01…06 | 101 s |
| f09 | 2018.01.03 KT10 LAT GACH SACOM BINH THANG-1 | R2007 | 8 | KT10-01…08 | 896 s |
| f10 | 2018.1.03  KT06- RAM DỐC, BẬC CẤP | R2007 | 4 | KT06-01…04 (padded-DWG rescue) | 77 s |
| f11 | 2018.1.2 KT12-5,6 BỂ NƯỚC NGẦM,BỂ TỰ HOẠI | R2004 | 2 | KT12-06, 07 (file name says 5,6) | 25 s |
| f12 | 2018.1.3  TKKT KT-02 SACOM BINH THANG( DT) | R2018 | 11 | KT01-01…04, KT02-01…07 (+6 OLE tables) | 2082 s |
| f13 | 2018.1.3  TKKT KT08-MB CUA SACOM BINH THANG | R2004 | 9 | KT08-01…09 (+2 OLE tables) | 1347 s |
| f14 | 2018.1.3 KT12-1,2,3, CHI TIET SAN VUON - DUY | R2007 | 6 | KT12-01, 02, 02, 03, 04, 05 | 749 s |

**Total: 86 pages.** The session's final message said "94 trang", which is an arithmetic slip; page counts were re-checked in the delivered files. With 4 workers the whole batch took about 46 min.

### Known limitations and residual defects
* **TCVN3 text is still garbled** in KT-02, sheet KT01-02 ("BẢN ĐỒ HIỆN TRẠNG VỊ TRÍ", page 2 of the delivered PDF). The final QA verified this as a real conversion bug, but it was never fixed and never reported to the user.
  * The survey-map labels use style `Style-CHAR_FAST_FONT`, whose font is named only in xdata as `.VnArial Narrow`.
  * They render as `®-êng ®Êt` (Đường đất), `s©n` (sân) and `Tê 8BT.3` (Tờ 8BT.3).
  * A TCVN3→Unicode table and xdata font lookup would be needed.
* The final `convert.py` was **never run end-to-end in exactly this form**. The delivered PDFs come from the v3 file plus `ole_patch.py`, and `ole_patch.py` ran the new OLE-corner code by importing the final `convert.py`.
* Minor QA findings from `final3` that may persist, since `final4` was not re-inspected by agents:
  * KT07-VS: the GHI CHÚ legend line wraps out of order.
  * KT03,04 p8: a grey fill is drawn over dimension text.
  * KT08-02: an opaque grey fire-truck band; transparency is not reproduced.
  * KT13 and KT10: road labels clipped at frame or viewport edges.
  * KT14-05: a toilet symbol is hidden by its own white fill.
* Reproduced as in the source drawings, not conversion bugs: two versions of KT12-02, stray hatches in KT-02 and the KT12 owner box, and "SAM HOLDING" without the S in KT12.
* OLE tables are raster images (not selectable). Text is outlines (not searchable). Fonts are substitutes (§7).
* The heuristics are specific to this drawing set:
  * the `KHUNG` layer name;
  * A-size block names;
  * the `XXnn-nn` sheet-code regex in the bottom-right corner;
  * A1 as the default scale reference.
* `convert.py` monkeypatches **ezdxf 1.4.4 internals**:
  * `Frontend.draw_mtext_entity`, `draw_wipeout_entity`, `draw_hatch_pattern`;
  * `DXFPolygon.transform`;
  * the Recorder/Player internals `_init_flip_y`, `records`, `property_hash`;
  * `MText._columns`;
  * `BlockLayout.entity_space`.

  Pin `ezdxf==1.4.4` and `PyMuPDF==1.28.2`, or re-test after upgrading.
* LibreDWG quirks: the false "Invalid System Section" rejection, split UTF-8 strings, dummy OLE corner points, and noisy warnings.
* Resource use: KT-02 needs about 35 min and several GB of RAM. Do not run more than 3–4 files in parallel on a 16-thread, 16 GB-class machine.

"""DXF (from LibreDWG) -> multi-page PDF, one page per drawing frame."""
import sys, time, re, copy, math, io, collections
import pymupdf
from ezdxf import recover, bbox, reorder
from ezdxf.math import BoundingBox2d, Vec3
from ezdxf.math.transformtools import OCSTransform
from ezdxf.entities.polygon import DXFPolygon
from ezdxf.render import hatching
from ezdxf.tools import text_layout
from ezdxf.addons.drawing import Frontend, RenderContext, pymupdf as ezpdf, layout, config
from ezdxf.addons.drawing.recorder import Recorder, Player
import tcvn3
import vni

ISO = {"A0": (1189, 841), "A1": (841, 594), "A2": (594, 420), "A3": (420, 297), "A4": (297, 210)}
STATS = collections.Counter()

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

# --- MTEXT fallback: keep the text instead of dropping it when ezdxf's layout fails
def _safe_mtext(self, entity, properties):
    try:
        from ezdxf.addons.drawing.frontend import is_complex_mtext
        if is_complex_mtext(entity):
            try:
                return self.draw_complex_mtext(entity, properties)
            except text_layout.LayoutError:
                STATS["mtext_fallback"] += 1
                m = entity.copy()
                m.text = entity.plain_text(split=False).replace("\n", "\\P")
                return self.draw_simple_mtext(m, properties)
        return self.draw_simple_mtext(entity, properties)
    except Exception:
        STATS["mtext_dropped"] += 1
Frontend.draw_mtext_entity = _safe_mtext

# --- WIPEOUT: AutoCAD paints it in the paper colour; mark it so the mono pass can keep it white
WIPE = "#fefefd"
def _wipeout(self, entity, properties):
    from ezdxf.addons.drawing.properties import Filling
    properties.filling = Filling()
    properties.color = WIPE
    self.pipeline.draw_filled_polygon(entity.boundary_path_wcs(), properties)
Frontend.draw_wipeout_entity = _wipeout

# --- pattern hatch too dense to draw line by line: ezdxf fills it solid; mark it so it prints as a
#     light grey tone drawn underneath everything (a real pattern is see-through between its lines)
DENSE = "#a9a9a8"
DENSE_OUT = "#c8c8c8"
_orig_hatch_pattern = Frontend.draw_hatch_pattern
def _hatch_pattern(self, polygon, paths, properties):
    try:
        return _orig_hatch_pattern(self, polygon, paths, properties)
    except hatching.DenseHatchingLinesError:
        STATS["dense_hatch"] += 1
        properties.color = DENSE
        raise
Frontend.draw_hatch_pattern = _hatch_pattern

# --- ezdxf bug: a hatch inside a scaled/rotated block gets its (already scaled) pattern scaled by the
#     absolute new pattern scale and rotated by the absolute new angle; it must be the relative change.
def _polygon_transform(self, m):
    dxf = self.dxf
    ocs = OCSTransform(dxf.extrusion, m)
    elevation = Vec3(dxf.elevation).z
    self.paths.transform(ocs, elevation=elevation)
    dxf.elevation = ocs.transform_vertex(Vec3(0, 0, elevation)).replace(x=0.0, y=0.0)
    dxf.extrusion = ocs.new_extrusion
    if self.pattern:
        old_scale = dxf.pattern_scale or 1.0
        old_angle = dxf.pattern_angle
        new_scale = ocs.transform_length((old_scale, 0, 0))
        new_angle = ocs.transform_deg_angle(old_angle)
        self.pattern.scale(new_scale / old_scale, new_angle - old_angle)
        dxf.pattern_scale = new_scale
        dxf.pattern_angle = new_angle
    self.post_transform(m)
    return self
DXFPolygon.transform = _polygon_transform

def to_print_colors(be):
    """Plot-style pass (like monochrome.ctb): wipeouts white, dense patterns and greys as screening, rest black."""
    for k, v in list(be.properties.items()):
        c = v.color.lower()
        if c.startswith(WIPE):
            col = "#ffffff"
        elif c.startswith(DENSE):
            col = DENSE_OUT
        else:
            r, g, b = int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)
            if r == g == b and 0 < r < 255:
                col = "#%02x%02x%02x" % ((min(r, 160),) * 3)
            else:
                col = "#000000"
        be.properties[k] = v._replace(color=col)

# --- text repairs -------------------------------------------------------------
SURROGATE = re.compile("[\udc80-\udcff]")
PARA_CODE = re.compile(r"\\p([^;\\]*);")  # lowercase \p = paragraph properties (\P is a line break)
LEAD_INDENT = re.compile(r"^\\px?i(-?[\d.]+);")

def rejoin_utf8(s):
    """LibreDWG splits long strings into DXF chunks mid UTF-8 sequence; ezdxf keeps the broken bytes as surrogates."""
    if SURROGATE.search(s):
        STATS["utf8_rejoined"] += 1
        return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")
    return s

def fix_mtext_layout(e):
    """ezdxf drops the first word of a paragraph with a large indent: emulate a leading first-line
    indent by moving/narrowing the text box, strip other large indents; drop empty column records."""
    if e.has_columns and int(e._columns.column_type) == 0:
        e._columns = None
        STATS["columns_removed"] += 1
    s = e.text
    h = e.dxf.get("char_height", 1.0) or 1.0
    m = LEAD_INDENT.match(s)
    if m and float(m.group(1)) > 0:
        v = float(m.group(1))
        att = e.dxf.get("attachment_point", 1)
        col = (att - 1) % 3  # 0 left, 1 centre, 2 right
        shift = v if col == 0 else (v / 2 if col == 1 else 0.0)
        ang = math.radians(e.get_rotation())
        ins = Vec3(e.dxf.insert)
        e.dxf.insert = ins + Vec3(math.cos(ang), math.sin(ang), 0) * shift
        w = e.dxf.get("width", 0) or 0
        if w > v:
            e.dxf.width = w - v
        s = s[m.end():]
        STATS["indent_emulated"] += 1
    def repl(mm):
        body = mm.group(1)
        ext = body.startswith("x")
        items = [it for it in (body[1:] if ext else body).split(",") if it]
        keep = []
        for it in items:
            if it[0] in "ilr":
                try:
                    if abs(float(it[1:])) > 3 * h:
                        STATS["indent_stripped"] += 1
                        continue
                except ValueError:
                    pass
            keep.append(it)
        return ("\\p" + ("x" if ext else "") + ",".join(keep) + ";") if keep else ""
    s = PARA_CODE.sub(repl, s)
    if s != e.text:
        e.text = s

def all_text_entities(doc):
    containers = [doc.modelspace()] + [l for l in doc.layouts if l.name != "Model"]
    containers += [b for b in doc.blocks if not b.name.lower().startswith(("*model_space", "*paper_space"))]
    for c in containers:
        for e in c:
            t = e.dxftype()
            if t in ("TEXT", "MTEXT", "ATTDEF"):
                yield e
            elif t == "INSERT":
                yield from e.attribs

def repair_texts(doc):
    for e in all_text_entities(doc):
        if e.dxftype() == "MTEXT":
            t = rejoin_utf8(e.text)
            if t != e.text:
                e.text = t
            fix_mtext_layout(e)
        else:
            t = rejoin_utf8(e.dxf.text)
            if t != e.dxf.text:
                e.dxf.text = t

# --- layers / draw order --------------------------------------------------------
def hide_non_plotting_layers(doc):
    hidden = []
    for lay in doc.layers:
        if lay.dxf.name.upper() == "DEFPOINTS" or not lay.dxf.get("plot", 1):
            if not lay.is_off():
                lay.off()
            hidden.append(lay.dxf.name)
    return hidden

def layer_prints(doc, name):
    lay = doc.layers.get(name)
    if lay is None:
        return True
    return not (lay.is_off() or lay.is_frozen() or not lay.dxf.get("plot", 1) or name.upper() == "DEFPOINTS")

def hide_inserts_on_frozen_layers(doc):
    """AutoCAD hides a block reference on a frozen layer completely; ezdxf only checks the nested entities."""
    frozen = {l.dxf.name.lower() for l in doc.layers if l.is_frozen()}
    n = 0
    containers = [doc.modelspace()] + [b for b in doc.blocks if not b.name.lower().startswith(("*model_space", "*paper_space"))]
    for c in containers:
        for e in c.query("INSERT"):
            if e.dxf.layer.lower() in frozen and not e.dxf.get("invisible", 0):
                e.dxf.invisible = 1; n += 1
    return n

def apply_block_draw_order(doc):
    """ezdxf ignores a block's own SORTENTSTABLE when it expands an INSERT: store the entities sorted."""
    n = 0
    for blk in doc.blocks:
        if blk.name.lower().startswith(("*model_space", "*paper_space")):
            continue
        try:
            order = dict(blk.get_redraw_order())
        except Exception:
            continue
        if not order:
            continue
        blk.entity_space.entities = list(reorder.ascending(list(blk.entity_space), order))
        n += 1
    return n

# --- OLE objects (embedded Excel tables): render the cached EMF picture -----------
def ole_pictures(doc, msp):
    out = []
    try:
        import olefile
        from PIL import Image
    except ImportError:
        return out
    for e in msp.query("OLE2FRAME"):
        if not layer_prints(doc, e.dxf.layer):
            continue
        try:
            data = e.binary_data()
            # LibreDWG writes dummy corner points (10/11); the real WCS corners are 4 x (x,y,z) doubles
            # at offsets 2, 26, 50, 74 of the 128-byte header that precedes the OLE compound file.
            import struct
            pts = [struct.unpack_from("<3d", data, off) for off in (2, 26, 50, 74)]
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            i = data.find(b"\xd0\xcf\x11\xe0")
            o = olefile.OleFileIO(io.BytesIO(data[i:]))
            pres = o.openstream("\x02OlePres000").read()
            j = pres.find(b" EMF")
            emf = pres[j - 40:]
            emf = emf[:int.from_bytes(emf[48:52], "little")]
            im = Image.open(io.BytesIO(emf))
            im.load(dpi=300)
            buf = io.BytesIO()
            im.convert("RGB").save(buf, "PNG")
            box = BoundingBox2d([(min(xs), min(ys)), (max(xs), max(ys))])
            out.append((box, buf.getvalue()))
        except Exception as ex:
            log(f"  OLE {e.dxf.handle} skipped: {type(ex).__name__}: {ex}")
    return out

# --- sheets -------------------------------------------------------------------
def is_frame_like(bb):
    w, h = bb.size.x, bb.size.y
    if min(w, h) <= 0:
        return False
    r = max(w, h) / min(w, h)
    return 1.38 <= r <= 1.45 and max(w, h) >= 1000

def find_frames(doc, msp):
    cache = bbox.Cache()
    out, seen = [], set()
    def add(e):
        try:
            bb = bbox.extents([e], cache=cache)
        except Exception:
            return
        if not bb.has_data or not is_frame_like(bb):
            return
        key = (round(bb.extmin.x / 10), round(bb.extmin.y / 10), round(bb.size.x / 10))
        if key in seen:
            return
        seen.add(key)
        out.append((bb, e.dxf.name))
    inserts = [e for e in msp.query("INSERT") if layer_prints(doc, e.dxf.layer) and not e.dxf.get("invisible", 0)]
    for e in inserts:
        if "KHUNG" in e.dxf.layer.upper():
            add(e)
    method = "KHUNG layer"
    if out:
        names = {n for _, n in out}
        before = len(out)
        for e in inserts:  # the same frame blocks placed on other printing layers, e.g. extension frames
            if e.dxf.name in names and "KHUNG" not in e.dxf.layer.upper():
                add(e)
        if len(out) > before:
            method += f" + {len(out) - before} same-block frame(s) on other layers"
        before = len(out)
        for v in nested_frames(doc, inserts, names):  # frames pasted inside other blocks
            add(v)
        if len(out) > before:
            method += f" + {len(out) - before} nested frame(s)"
    else:  # fallback: A-size named blocks
        for e in inserts:
            if re.match(r"\s*A[0-4]\b", e.dxf.name, re.I):
                add(e)
        method = "A-size block name"
    return out, method

def nested_frames(doc, inserts, frame_names):
    contains = {}
    def has_frame(bname, depth=0):
        if bname in contains:
            return contains[bname]
        contains[bname] = False
        blk = doc.blocks.get(bname)
        if blk is None or depth > 4:
            return False
        r = any(i.dxf.name in frame_names or has_frame(i.dxf.name, depth + 1) for i in blk.query("INSERT"))
        contains[bname] = r
        return r
    found = []
    def walk(ins, depth):
        try:
            virtuals = list(ins.virtual_entities())
        except Exception:
            return
        for v in virtuals:
            if v.dxftype() != "INSERT" or v.dxf.get("invisible", 0):
                continue
            if v.dxf.name in frame_names and layer_prints(doc, v.dxf.layer):
                found.append(v)
            elif depth < 4 and has_frame(v.dxf.name):
                walk(v, depth + 1)
    for e in inserts:
        if e.dxf.name not in frame_names and has_frame(e.dxf.name):
            walk(e, 1)
    return found

def merge_overlapping(frames):
    """Frames that overlap form one extended sheet (e.g. two A1 frames joined for a long elevation)."""
    groups = []  # [box, name, scale, members]
    for bb, name in frames:
        lng = max(bb.size.x, bb.size.y)
        m = re.match(r"\s*(A[0-4])\b", name or "", re.I)
        scale = lng / ISO[m.group(1).upper() if m else "A1"][0]  # drawing units per paper-mm
        hit = None
        for g in groups:
            gb = g[0]
            ox = min(gb.extmax.x, bb.extmax.x) - max(gb.extmin.x, bb.extmin.x)
            oy = min(gb.extmax.y, bb.extmax.y) - max(gb.extmin.y, bb.extmin.y)
            if ox > 0.01 * bb.size.x and oy > 0.01 * bb.size.y:
                hit = g; break
        if hit:
            hit[0] = BoundingBox2d([(min(hit[0].extmin.x, bb.extmin.x), min(hit[0].extmin.y, bb.extmin.y)),
                                    (max(hit[0].extmax.x, bb.extmax.x), max(hit[0].extmax.y, bb.extmax.y))])
            hit[3] += 1
        else:
            groups.append([BoundingBox2d([(bb.extmin.x, bb.extmin.y), (bb.extmax.x, bb.extmax.y)]), name, scale, 1])
    merged = True  # a group can grow into another one -> merge until stable
    while merged:
        merged = False
        for i in range(len(groups)):
            for j in range(i + 1, len(groups)):
                a, b = groups[i][0], groups[j][0]
                ox = min(a.extmax.x, b.extmax.x) - max(a.extmin.x, b.extmin.x)
                oy = min(a.extmax.y, b.extmax.y) - max(a.extmin.y, b.extmin.y)
                if ox > 0.01 * min(a.size.x, b.size.x) and oy > 0.01 * min(a.size.y, b.size.y):
                    groups[i][0] = BoundingBox2d([(min(a.extmin.x, b.extmin.x), min(a.extmin.y, b.extmin.y)),
                                                  (max(a.extmax.x, b.extmax.x), max(a.extmax.y, b.extmax.y))])
                    groups[i][3] += groups[j][3]
                    del groups[j]
                    merged = True
                    break
            if merged:
                break
    return groups

SHEET_CODE = re.compile(r"\b([A-Z]{1,3})\s?(\d{1,2})\s?-\s?(\d{1,2})\b")

def sheet_code_texts(doc, msp):
    """(x, y, text) of every text that could be a title-block sheet code, incl. attributes and pasted blocks."""
    out = []
    def take(e):
        t = e.dxftype()
        try:
            if t in ("TEXT", "ATTRIB"):
                s = e.dxf.text
            elif t == "MTEXT":
                s = e.plain_text(split=False)
            else:
                return
            if SHEET_CODE.search(s):
                p = e.dxf.insert
                out.append((p.x, p.y, s))
        except Exception:
            pass
    for e in msp:
        take(e)
        if e.dxftype() == "INSERT":
            for a in e.attribs:
                take(a)
            if e.dxf.name.upper().startswith("A$C") and layer_prints(doc, e.dxf.layer):
                try:
                    for v in e.virtual_entities():
                        take(v)
                except Exception:
                    pass
    return out

def order_sheets(groups, texts):
    """Sort sheets by the code in their title block (bottom-right corner); keep position order otherwise."""
    keys = []
    for box, *_ in groups:
        w, h = box.size.x, box.size.y
        best = None
        for x, y, s in texts:
            if box.extmin.x + 0.75 * w <= x <= box.extmax.x and box.extmin.y <= y <= box.extmin.y + 0.2 * h:
                d = (box.extmax.x - x) + (y - box.extmin.y)
                if best is None or d < best[0]:
                    m = SHEET_CODE.search(s)
                    best = (d, (m.group(1), int(m.group(2)), int(m.group(3))))
        keys.append(best[1] if best else None)
    if all(keys):
        order = sorted(range(len(groups)), key=lambda i: keys[i])
        return [groups[i] for i in order], [keys[i] for i in order]
    return groups, keys

def sheet_player(be, box):
    """Player holding private copies of only those records that touch `box`; dense-pattern tones go first."""
    src = Recorder.player(be)
    p = Player()
    p.config, p.background, p.properties = src.config, "#ffffff", src.properties
    under, keep = [], []
    for r in src.records:
        bb = r.bbox()
        if (bb.has_data and bb.extmax.x >= box.extmin.x and bb.extmin.x <= box.extmax.x
                and bb.extmax.y >= box.extmin.y and bb.extmin.y <= box.extmax.y):
            (under if src.properties[r.property_hash].color == DENSE_OUT else keep).append(r)
    p.records = copy.deepcopy(under + keep)
    p.has_shared_recordings = False
    return p

def replay_pdf(be, page, settings, box):
    """get_pdf_bytes() on a private, spatially filtered copy of the recording (replay mutates it)."""
    orig = be.player
    be.player = (lambda: sheet_player(be, box)) if box is not None else (lambda: Recorder.player(be).copy())
    be._init_flip_y = True  # every replay starts from the original (unflipped) recording
    try:
        return be.get_pdf_bytes(page, settings=settings, render_box=box)
    finally:
        be.player = orig

def sanitize_linetypes(doc):
    fixed = 0
    for e in list(doc.entitydb.values()):
        try:
            if e.dxf.hasattr("linetype") and not e.dxf.linetype:
                e.dxf.linetype = "BYLAYER"; fixed += 1
        except Exception:
            pass
    for lay in doc.layers:
        if not lay.dxf.linetype:
            lay.dxf.linetype = "Continuous"; fixed += 1
    for _name, style in doc.mline_styles:  # MLINE elements are exploded into LINEs with these linetypes
        els = style.elements.elements  # list of immutable NamedTuples
        for i, el in enumerate(els):
            if not el.linetype or el.linetype not in doc.linetypes:
                els[i] = el._replace(linetype="BYLAYER"); fixed += 1
    return fixed

def main(src, dst, mode):
    t0 = time.time()
    doc, aud = recover.readfile(src)
    msp = doc.modelspace()
    log(f"read {src} ({time.time()-t0:.0f}s) entities={len(msp)} audit_errors={len(aud.errors)}")
    log(f"sanitized empty linetypes: {sanitize_linetypes(doc)}")
    log(f"non-plotting layers hidden: {hide_non_plotting_layers(doc)}")
    log(f"inserts on frozen layers hidden: {hide_inserts_on_frozen_layers(doc)}; "
        f"blocks re-sorted by their draw order: {apply_block_draw_order(doc)}")
    repair_texts(doc)
    tcvn3.fix_document(doc, log=log)  # first: VNI decoding skips texts that are Unicode by then
    vni.fix_document(doc, log=log)
    log("text repairs: " + ", ".join(f"{k}={STATS[k]}" for k in
        ("utf8_rejoined", "indent_emulated", "indent_stripped", "columns_removed")))
    frames, method = find_frames(doc, msp)
    log(f"frames found: {len(frames)} via {method} ({time.time()-t0:.0f}s)")
    oles = ole_pictures(doc, msp)
    log(f"OLE pictures: {len(oles)}")
    units_per_mm = (sorted(max(b.size.x, b.size.y) for b, _ in frames)[len(frames) // 2] / 841.0) if frames else 1.0
    min_hatch = 0.35 * units_per_mm
    log(f"drawing units per paper-mm ~ {units_per_mm:.1f}; min hatch line distance {min_hatch:.1f}")
    cfg = config.Configuration(
        min_hatch_line_distance=min_hatch,
        hatching_timeout=3.0,
        background_policy=config.BackgroundPolicy.WHITE,
        color_policy=config.ColorPolicy.COLOR,
        lineweight_policy=config.LineweightPolicy.ABSOLUTE,
    )
    t1 = time.time()
    be = ezpdf.PyMuPdfBackend()
    Frontend(RenderContext(doc), be, config=cfg).draw_layout(msp)
    if mode == "mono":
        to_print_colors(be)
    log(f"drawn ({time.time()-t1:.0f}s) mtext_fallback={STATS['mtext_fallback']} "
        f"mtext_dropped={STATS['mtext_dropped']} dense_hatch={STATS['dense_hatch']}")
    out = pymupdf.open()
    settings = layout.Settings(fit_page=True, crop_at_margins=True)
    if frames:
        groups = merge_overlapping(frames)
        hmed = sorted(g[0].size.y for g in groups)[len(groups) // 2]
        groups.sort(key=lambda g: (-round(g[0].center.y / (hmed * 0.6)), g[0].center.x))
        groups, codes = order_sheets(groups, sheet_code_texts(doc, msp))
        log("sheet order: " + ", ".join(f"{c[0]}{c[1]:02d}-{c[2]:02d}" if c else "?" for c in codes))
        for i, (box, name, scale, members) in enumerate(groups, 1):
            pw, ph = round(box.size.x / scale), round(box.size.y / scale)
            page = layout.Page(pw, ph, layout.Units.mm)
            data = replay_pdf(be, page, settings, box)
            out.insert_pdf(pymupdf.open(stream=data, filetype="pdf"))
            pg = out[-1]
            n_ole = 0
            for obox, png in oles:
                ix0, iy0 = max(obox.extmin.x, box.extmin.x), max(obox.extmin.y, box.extmin.y)
                ix1, iy1 = min(obox.extmax.x, box.extmax.x), min(obox.extmax.y, box.extmax.y)
                if ix1 <= ix0 or iy1 <= iy0:
                    continue
                sx, sy = pg.rect.width / box.size.x, pg.rect.height / box.size.y
                r = pymupdf.Rect((obox.extmin.x - box.extmin.x) * sx, (box.extmax.y - obox.extmax.y) * sy,
                                 (obox.extmax.x - box.extmin.x) * sx, (box.extmax.y - obox.extmin.y) * sy)
                pg.insert_image(r, stream=png, keep_proportion=False)
                n_ole += 1
            tag = f" (merged {members} frames)" if members > 1 else ""
            tag += f" +{n_ole} OLE" if n_ole else ""
            log(f"  sheet {i}/{len(groups)} {name!r}{tag} {box.size.x:.0f}x{box.size.y:.0f} -> {pw}x{ph}mm ({time.time()-t0:.0f}s)")
    else:
        page = layout.Page(0, 0, layout.Units.mm, max_width=1189, max_height=841)
        data = replay_pdf(be, page, settings, None)
        out.insert_pdf(pymupdf.open(stream=data, filetype="pdf"))
        log("  NO FRAME FOUND -> single page of whole model")
    out.save(dst, deflate=True, garbage=3)
    log(f"DONE {dst} pages={len(out)} total={time.time()-t0:.0f}s")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "mono")

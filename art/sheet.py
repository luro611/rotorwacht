"""Developer aid: composes layers into one contact sheet. blender -b -P art/sheet.py -- out.png bg layer1.png layer2.png ..."""
import bpy, sys, numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
out, bg, files = a[0], a[1], a[2:]
def load(p):
    im = bpy.data.images.load(p); w, h = im.size
    return np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
base = load(files[0]); h, w, _ = base.shape
col = {"light": (0.80, 0.86, 0.92), "dark": (0.2, 0.2, 0.22), "sand": (0.7, 0.62, 0.45)}[bg]
canvas = np.ones((h, w, 4), np.float32); canvas[..., :3] = col
for f in files:
    im = load(f)
    if im.shape[:2] != (h, w): continue
    al = im[..., 3:4]
    canvas[..., :3] = im[..., :3] * al + canvas[..., :3] * (1 - al)
res = bpy.data.images.new("o", w, h, alpha=True)
res.pixels = canvas.flatten().tolist()
res.filepath_raw = out; res.file_format = "PNG"; res.save()

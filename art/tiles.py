"""Developer aid: tiles images side by side on a flat background. blender -b -P art/tiles.py -- out.png scale cols f1 f2 ..."""
import bpy, sys, numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
out, cols, files = a[0], int(a[1]), a[2:]
ims = []
for p in files:
    im = bpy.data.images.load(p); w, h = im.size
    ims.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4))
h = max(i.shape[0] for i in ims); w = max(i.shape[1] for i in ims)
rows = (len(ims) + cols - 1) // cols
canvas = np.ones((rows * h, cols * w, 4), np.float32); canvas[..., :3] = (0.78, 0.84, 0.9)
for i, im in enumerate(ims):
    r, c = divmod(i, cols)
    ih, iw = im.shape[:2]
    sl = canvas[(rows - 1 - r) * h:(rows - 1 - r) * h + ih, c * w:c * w + iw]
    al = im[..., 3:4]
    sl[..., :3] = im[..., :3] * al + sl[..., :3] * (1 - al)
res = bpy.data.images.new("o", cols * w, rows * h, alpha=True)
res.pixels = canvas.flatten().tolist(); res.filepath_raw = out; res.file_format = "PNG"; res.save()

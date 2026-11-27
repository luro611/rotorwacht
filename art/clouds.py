"""Clouds as soft sprites (Renders/sky): four heaped clouds and two flat banks, white and grey; the game tints them
to the light of each Einsatz. Generated from noise, no external pictures.

Usage: blender -b -P art/clouds.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import numpy as np

DIR = os.path.join(OUT, "sky")


def value_noise(w, h, cell_x, cell_y, rng):
    gx, gy = int(w / cell_x) + 3, int(h / cell_y) + 3
    g = rng.random((gy, gx))
    x = np.arange(w) / cell_x
    y = np.arange(h) / cell_y
    xi, yi = x.astype(int), y.astype(int)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g[np.ix_(yi, xi)] * (1 - fx) + g[np.ix_(yi, xi + 1)] * fx
    b = g[np.ix_(yi + 1, xi)] * (1 - fx) + g[np.ix_(yi + 1, xi + 1)] * fx
    return a * (1 - fy[:, None]) + b * fy[:, None]


def fbm(w, h, cell, rng, octaves=7, stretch=1.0, gain=0.56):
    total, amp, norm = np.zeros((h, w)), 1.0, 0.0
    for _ in range(octaves):
        total += amp * value_noise(w, h, max(2.0, cell * stretch), max(2.0, cell), rng)
        norm += amp
        amp *= gain
        cell /= 2
    return total / norm


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def save(name, rgb, alpha):
    h, w = alpha.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    px = np.zeros((h, w, 4), np.float32)
    px[..., :3] = rgb[::-1]           # rows are stored bottom up
    px[..., 3] = alpha[::-1]
    img.pixels = px.flatten().tolist()
    img.filepath_raw = os.path.join(DIR, name + ".png")
    img.file_format = "PNG"
    img.save()


def cloud(name, w, h, seed, flat):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w].astype(float)
    u, v = x / w, y / h                  # v: 0 top, 1 bottom
    body = np.zeros((h, w))
    if flat:
        for _ in range(9):
            cx, cy = rng.uniform(0.22, 0.78), rng.uniform(0.46, 0.6)
            rx, ry = rng.uniform(0.14, 0.26), rng.uniform(0.07, 0.15)
            body = np.maximum(body, 1 - np.hypot((u - cx) / rx, (v - cy) / ry))
        noise_ = fbm(w, h, h / 3.5, rng, stretch=3.2)
        density = body * 1.1 + (noise_ - 0.5) * 2.2
        base = np.ones((h, w))
    else:
        for i in range(11):
            cx = rng.uniform(0.2, 0.8)
            r = rng.uniform(0.07, 0.17) * (1.25 - abs(cx - 0.5) * 1.4)
            cy = 0.7 - r * w / h * rng.uniform(0.35, 0.8)
            body = np.maximum(body, 1 - np.hypot((u - cx) / r, (v - cy) / (r * w / h)))
        noise_ = fbm(w, h, h / 3.0, rng)
        billow = 1 - np.abs(fbm(w, h, h / 5.0, rng) * 2 - 1)
        density = body * 1.25 + (noise_ - 0.5) * 1.5 + (billow - 0.75) * 0.5
        base = smooth(0.8, 0.66, v + (fbm(w, h, h / 6.0, rng) - 0.5) * 0.16)   # a flat underside
    # keep clear of the picture border
    border = smooth(0.0, 0.1, u) * smooth(1.0, 0.9, u) * smooth(0.0, 0.08, v) * smooth(1.0, 0.9, v)
    alpha = smooth(0.02, 0.55, density) * base * border * (0.78 if flat else 0.95)
    # light from the upper left: thinner towards the light is brighter
    shift = int(h * 0.07)
    towards = np.roll(np.roll(density, shift, axis=0), shift, axis=1)
    lit = np.clip(0.5 + (density - towards) * 1.1, 0, 1)
    height = smooth(0.82, 0.25, v)
    shade = np.clip(0.25 + 0.45 * height + 0.55 * (lit - 0.4) + (noise_ - 0.5) * 0.35, 0, 1)
    dark = np.array([0.64, 0.69, 0.76])
    light = np.array([1.0, 0.99, 0.97])
    rgb = dark + (light - dark) * shade[..., None]
    save(name, rgb, alpha)
    print("cloud", name)


def main():
    os.makedirs(DIR, exist_ok=True)
    for i, seed in enumerate((3, 11, 27, 42)):
        cloud("cumulus-%d" % i, 640, 300, seed, False)
    for i, seed in enumerate((5, 19)):
        cloud("bank-%d" % i, 900, 220, seed, True)


if __name__ == "__main__":
    main()

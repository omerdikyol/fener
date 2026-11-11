// The demo desktop's wallpaper: a pixel night scene lit by a lantern. Drawn at a quarter of the
// size with ordered (Bayer) dithering and scaled up crisp. The flame flickers; moving the mouse
// over the desktop picks the lantern up, and leaving puts it back on the hill.
"use strict";
(() => {
  const canvas = document.querySelector(".scene");
  if (!canvas) return;
  const desk = canvas.parentElement, ctx = canvas.getContext("2d");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const CELL = 4;

  // Night to lantern light, in Tokyo Night's colors.
  const RAMP = ["#07080f", "#0c0f1d", "#121730", "#1b2142", "#2c2846", "#563447", "#93504b", "#d47750", "#ff9e64", "#ffc98f", "#fff1cf"]
    .map((h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]);
  const BAYER = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
                 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21]
    .map((v) => (v + 0.5) / 64);
  // A pixel lantern, 7 x 11: f frame, g glass, w flame, . empty.
  const SPRITE = ["..fff..", ".f...f.", "fffffff", ".fgggf.", ".fgwgf.", ".fwwwf.", ".fgwgf.", ".fgggf.", ".fgggf.", "fffffff", ".fffff."];
  const SPRITE_COLORS = { f: [192, 202, 245], g: [255, 199, 119], w: [255, 248, 230] };

  let W = 0, H = 0, img, stars = [], far = [], near = [];
  function layout() {
    W = Math.ceil(desk.clientWidth / CELL); H = Math.ceil(desk.clientHeight / CELL);
    canvas.width = W; canvas.height = H;
    img = ctx.createImageData(W, H);
    let seed = 7; const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    stars = Array.from({ length: Math.round(W * H / 420) }, () => ({ x: Math.floor(rand() * W), y: Math.floor(rand() * H * 0.62), p: rand() * 6.3, b: 0.25 + rand() * 0.5 }));
    far = Array.from({ length: W }, (_, x) => Math.round(H * (0.70 + 0.035 * Math.sin(x * 0.045 + 2) + 0.025 * Math.sin(x * 0.013))));
    near = Array.from({ length: W }, (_, x) => Math.round(H * (0.80 + 0.05 * Math.sin(x * 0.021 + 0.6) + 0.02 * Math.sin(x * 0.07))));
  }
  layout();
  new ResizeObserver(() => { layout(); if (reduce) draw(performance.now()); }).observe(desk);

  // The lantern rests on the near hill, left of the panel; the pointer carries it.
  const rest = () => { const x = Math.round(W * 0.2); return { x, y: near[x] - 6 }; };
  let pos = rest(), target = null, last = performance.now(), noise = 0;
  desk.addEventListener("pointermove", (e) => {
    const r = desk.getBoundingClientRect();
    target = { x: (e.clientX - r.left) / CELL, y: (e.clientY - r.top) / CELL };
    if (reduce) { pos = { ...target }; draw(performance.now()); }
  });
  desk.addEventListener("pointerleave", () => { target = null; if (reduce) { pos = rest(); draw(performance.now()); } });

  function draw(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    const goal = target || rest(), k = 1 - Math.exp(-dt * (target ? 9 : 3));
    if (!reduce) { pos.x += (goal.x - pos.x) * k; pos.y += (goal.y - pos.y) * k; }

    noise += (Math.random() - 0.5) * 0.2; noise *= 0.9;
    const flick = reduce ? 1 : 1 + 0.05 * Math.sin(now * 0.009) + 0.03 * Math.sin(now * 0.023 + 1.7) + 0.05 * noise;
    const radius = W * 0.16 * flick, lx = pos.x, ly = pos.y + 3;
    const d = img.data;

    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let v;
        if (y >= near[x]) v = 0.035;                       // near hill
        else if (y >= far[x]) v = 0.075;                   // far hill
        else v = 0.07 + 0.11 * (y / H);                    // sky, lighter toward the horizon
        const dx = x - lx, dy = (y - ly) * 1.1, dist2 = (dx * dx + dy * dy) / (radius * radius);
        let light = 0.9 / (1 + dist2 * 2.6);
        if (y >= near[x]) light *= 1.25;                   // the ground near it catches more
        v = Math.min(1, v + light * (y >= far[x] ? 1 : 0.85));
        const t = v * (RAMP.length - 1), i = Math.floor(t);
        const c = RAMP[Math.min(RAMP.length - 1, t - i > BAYER[(y & 7) * 8 + (x & 7)] ? i + 1 : i)];
        const o = (y * W + x) * 4;
        d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = 255;
      }
    }
    for (const s of stars) {                                // stars fade in the lantern's light
      const dx = s.x - lx, dy = s.y - ly;
      const a = s.b * (reduce ? 1 : 0.75 + 0.25 * Math.sin(now * 0.002 + s.p)) * Math.min(1, (dx * dx + dy * dy) / (radius * radius * 1.5));
      if (a < 0.2 || s.y >= far[s.x]) continue;
      const o = (s.y * W + s.x) * 4, c = Math.round(110 + 120 * a);
      d[o] = c; d[o + 1] = c; d[o + 2] = Math.min(255, c + 30);
    }
    const sx = Math.round(lx - 3), sy = Math.round(pos.y - 5);
    SPRITE.forEach((row, r) => [...row].forEach((ch, cIdx) => {
      const x = sx + cIdx, y = sy + r;
      if (ch === "." || x < 0 || y < 0 || x >= W || y >= H) return;
      const col = ch === "w" && !reduce && Math.random() < 0.08 ? SPRITE_COLORS.g : SPRITE_COLORS[ch], o = (y * W + x) * 4;
      d[o] = col[0]; d[o + 1] = col[1]; d[o + 2] = col[2];
    }));
    ctx.putImageData(img, 0, 0);
  }

  if (reduce) { draw(performance.now()); return; }
  let visible = true, frameAt = 0;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(desk);
  (function loop(now) {
    if (visible && now - frameAt > 33) { frameAt = now; draw(now); }   // about 30 frames a second
    requestAnimationFrame(loop);
  })(performance.now());
})();

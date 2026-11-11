// Lantern light, drawn in pixels. Three scenes share one renderer: a lantern hanging over the
// hero, the demo desktop's night (where the pointer carries the lantern), and the lantern
// resting on the ground at the foot of the page. Each canvas is drawn at a fraction of its size
// with ordered (Bayer) dithering and scaled up crisp. The flame flickers; reduced motion stills it.
"use strict";
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // From the page's own black, through Tokyo Night's blues, to the flame.
  const RAMP = ["#09090d", "#0c0e1a", "#111527", "#191e3a", "#2a2742", "#4f3244", "#874a49", "#c66e4e", "#f2945f", "#ffc28a", "#ffefcf"]
    .map((h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]);
  const BAYER = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
                 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21]
    .map((v) => (v + 0.5) / 64);
  // A pixel lantern, 7 x 11: f frame, g glass, w flame.
  const SPRITE = ["..fff..", ".f...f.", "fffffff", ".fgggf.", ".fgwgf.", ".fwwwf.", ".fgwgf.", ".fgggf.", ".fgggf.", "fffffff", ".fffff."];
  const INK = { f: [192, 202, 245], g: [255, 199, 119], w: [255, 248, 230], c: [86, 95, 137] };

  function scene(canvas, kind) {
    const host = canvas.parentElement, ctx = canvas.getContext("2d");
    const CELL = kind === "desktop" ? 4 : 5, glowOnly = kind === "glow";
    let W = 0, H = 0, img, stars = [], far = [], near = [];
    let pos = { x: 0, y: 0 }, target = null, theta = 0.05, omega = 0, last = performance.now(), noise = 0;
    const mouse = { x: -1e4, y: -1e4, vx: 0, t: 0 };

    function layout() {
      W = Math.max(1, Math.ceil(host.clientWidth / CELL)); H = Math.max(1, Math.ceil(host.clientHeight / CELL));
      canvas.width = W; canvas.height = H; img = ctx.createImageData(W, H);
      let seed = kind.length * 977; const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      const starRate = kind === "desktop" ? 420 : kind === "hang" ? 900 : 0;
      stars = starRate ? Array.from({ length: Math.round(W * H / starRate) }, () => ({ x: Math.floor(rand() * W), y: Math.floor(rand() * H * 0.7), p: rand() * 6.3, b: 0.2 + rand() * 0.5 })) : [];
      far = Array.from({ length: W }, (_, x) => kind === "desktop" ? Math.round(H * (0.70 + 0.035 * Math.sin(x * 0.045 + 2) + 0.025 * Math.sin(x * 0.013))) : H + 1);
      near = Array.from({ length: W }, (_, x) =>
        kind === "desktop" ? Math.round(H * (0.80 + 0.05 * Math.sin(x * 0.021 + 0.6) + 0.02 * Math.sin(x * 0.07)))
        : kind === "ground" ? Math.round(H * (0.80 + 0.03 * Math.sin(x * 0.018 + 1) + 0.015 * Math.sin(x * 0.061))) : H + 1);
      pos = rest();
    }
    // Where the lantern is when nobody holds it.
    function rest() {
      if (kind === "hang") return { x: W / 2, y: Math.min(H * 0.22, 26) };
      if (glowOnly) return { x: W / 2, y: H * 0.98 };
      const x = Math.round(kind === "ground" ? W / 2 : W * 0.2);
      return { x, y: near[Math.min(W - 1, x)] - 6 };
    }

    if (kind === "desktop") {
      host.addEventListener("pointermove", (e) => { const r = host.getBoundingClientRect(); target = { x: (e.clientX - r.left) / CELL, y: (e.clientY - r.top) / CELL }; });
      host.addEventListener("pointerleave", () => { target = null; });
    }
    if (kind === "hang") {
      addEventListener("pointermove", (e) => {
        const r = host.getBoundingClientRect(), now = performance.now(), dt = Math.max(8, now - mouse.t);
        const x = (e.clientX - r.left) / CELL, y = (e.clientY - r.top) / CELL;
        mouse.vx = (x - mouse.x) / dt; mouse.x = x; mouse.y = y; mouse.t = now;
      }, { passive: true });
    }

    function draw(now) {
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      noise += (Math.random() - 0.5) * 0.2; noise *= 0.9;
      const flick = reduce ? 1 : 1 + 0.05 * Math.sin(now * 0.009) + 0.03 * Math.sin(now * 0.023 + 1.7) + 0.05 * noise;

      // Where the light comes from this frame.
      let lx, ly, chainTop = null;
      if (kind === "hang") {
        if (!reduce) {
          const near = Math.hypot(mouse.x - pos.x, mouse.y - pos.y) < 22 && now - mouse.t < 80;
          if (near) omega -= Math.max(-0.6, Math.min(0.6, mouse.vx * 30)) * dt;
          omega += (-6 * Math.sin(theta) - 0.6 * omega + 0.12 * Math.sin(now * 0.0009)) * dt;
          theta = Math.max(-0.5, Math.min(0.5, theta + omega * dt));
        }
        const r = rest(), len = r.y + 4;
        chainTop = { x: W / 2, y: 0 };
        lx = W / 2 - Math.sin(theta) * len; ly = Math.cos(theta) * len;
        pos = { x: lx, y: ly - 4 };
      } else {
        const goal = target || rest(), k = 1 - Math.exp(-dt * (target ? 9 : 3));
        if (!reduce) { pos.x += (goal.x - pos.x) * k; pos.y += (goal.y - pos.y) * k; } else pos = { ...goal };
        lx = pos.x; ly = pos.y + 3;
      }

      const radius = (glowOnly ? W * 0.42 : kind === "desktop" ? W * 0.16 : kind === "hang" ? Math.max(W * 0.2, 60) : Math.max(W * 0.17, 50)) * flick;
      const gain = glowOnly ? 0.8 : kind === "desktop" ? 0.9 : kind === "hang" ? 0.72 : 0.8;
      const d = img.data;
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
          let v;
          if (y >= near[x]) v = kind === "ground" ? 0.02 : 0.035;
          else if (y >= far[x]) v = 0.075;
          else v = kind === "desktop" ? 0.07 + 0.11 * (y / H) : glowOnly ? 0.03 : 0.01 + 0.05 * (y / H);
          const dx = x - lx, dy = (y - ly) * 1.1, dist2 = (dx * dx + dy * dy) / (radius * radius);
          let light = gain / (1 + dist2 * 2.6);
          if (kind === "hang") {                           // faint beams fanning down, fading in below the lantern
            const w = Math.min(1, Math.max(0, (y - ly) / 14)), a = Math.atan2(dx, Math.max(1, y - ly));
            light *= 1 - w * (0.18 - 0.18 * Math.cos(a * 9 + (reduce ? 0 : now * 0.0004)));
          }
          if (y >= near[x]) light *= 1.25;
          v = Math.min(1, v + light);
          const t = v * (RAMP.length - 1), i = Math.floor(t);
          const c = RAMP[Math.min(RAMP.length - 1, t - i > BAYER[(y & 7) * 8 + (x & 7)] ? i + 1 : i)];
          const o = (y * W + x) * 4;
          d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = 255;
        }
      }
      for (const s of stars) {                              // stars fade near the light
        if (s.y >= far[s.x]) continue;
        const dx = s.x - lx, dy = s.y - ly;
        const a = s.b * (reduce ? 1 : 0.75 + 0.25 * Math.sin(now * 0.002 + s.p)) * Math.min(1, (dx * dx + dy * dy) / (radius * radius * 1.5));
        if (a < 0.2) continue;
        const o = (s.y * W + s.x) * 4, c = Math.round(100 + 120 * a);
        d[o] = c; d[o + 1] = c; d[o + 2] = Math.min(255, c + 30);
      }
      const put = (x, y, col) => { x = Math.round(x); y = Math.round(y); if (x < 0 || y < 0 || x >= W || y >= H) return; const o = (y * W + x) * 4; d[o] = col[0]; d[o + 1] = col[1]; d[o + 2] = col[2]; };
      if (chainTop) {                                       // the chain, every other cell a link
        const steps = Math.ceil(Math.hypot(pos.x - chainTop.x, pos.y - chainTop.y));
        for (let i = 0; i < steps; i += 1) if (i % 2 === 0) put(chainTop.x + (pos.x - chainTop.x) * i / steps, chainTop.y + (pos.y - 1 - chainTop.y) * i / steps, INK.c);
      }
      if (!glowOnly) SPRITE.forEach((row, r) => [...row].forEach((ch, ci) => {
        if (ch === ".") return;
        put(pos.x - 3 + ci, pos.y - 5 + r, ch === "w" && !reduce && Math.random() < 0.08 ? INK.g : INK[ch]);
      }));
      ctx.putImageData(img, 0, 0);
    }

    layout();
    new ResizeObserver(() => { layout(); draw(performance.now()); }).observe(host);
    draw(performance.now());
    if (reduce) {
      if (kind === "desktop") ["pointermove", "pointerleave"].forEach((t) => host.addEventListener(t, () => draw(performance.now())));
      return;
    }
    let visible = false, frameAt = 0;
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(host);
    (function loop(now) {
      if (visible && now - frameAt > 33) { frameAt = now; draw(now); }   // about 30 frames a second
      requestAnimationFrame(loop);
    })(performance.now());
  }

  document.querySelectorAll("canvas[data-scene]").forEach((c) => scene(c, c.dataset.scene));
})();

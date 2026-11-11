// The lantern: a pendulum that sways on its own and when the cursor brushes past, a flame that
// flickers, embers that rise from it, and its light written into CSS variables for the glow,
// the panel's lit frame and shadow, and the dotted wall. With reduced motion it hangs still.
"use strict";
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const demo = document.querySelector(".hero-demo"), lantern = demo.querySelector(".lantern");
  const core = lantern.querySelector(".core"), flame = lantern.querySelector(".flame");
  const light = demo.querySelector(".light"), panel = document.getElementById("panel");
  const canvas = demo.querySelector(".embers"), ctx = canvas.getContext("2d");
  const wall = document.querySelector(".wall");

  // ---- headings brighten as they come into view (not tied to the lantern's position) ----
  const lit = new IntersectionObserver((entries) => entries.forEach((e) => {
    if (e.isIntersecting) { e.target.classList.add("lit"); lit.unobserve(e.target); }
  }), { rootMargin: "0px 0px -18% 0px" });
  document.querySelectorAll("main > section:not(.hero) h2, .manual dl").forEach((el) => reduce ? el.classList.add("lit") : lit.observe(el));

  // ---- cursor: a faint second light on the wall, and what nudges the lantern ----
  const mouse = { x: -999, y: -999, vx: 0, t: 0 };
  addEventListener("pointermove", (e) => {
    const now = performance.now(), dt = Math.max(8, now - mouse.t);
    mouse.vx = (e.clientX - mouse.x) / dt; mouse.x = e.clientX; mouse.y = e.clientY; mouse.t = now;
    wall.style.setProperty("--cx", e.clientX + "px"); wall.style.setProperty("--cy", e.clientY + "px");
  }, { passive: true });
  document.addEventListener("pointerleave", () => { wall.style.setProperty("--cx", "-999px"); });

  // ---- embers ----
  let embers = [], nextEmber = 0, dpr = 1;
  function size() {
    dpr = Math.min(2, devicePixelRatio || 1);
    canvas.width = canvas.offsetWidth * dpr; canvas.height = canvas.offsetHeight * dpr;
  }
  size(); addEventListener("resize", size);

  // ---- the loop ----
  let theta = reduce ? 0 : 0.09, omega = 0, last = performance.now(), visible = true, drift = 0;
  const start = last + 350;     // ignition starts after a beat
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(demo);

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;

    // brightness: ignite over 1.6 s, then flicker
    const ignite = reduce ? 1 : Math.min(1, Math.max(0, (now - start) / 1600));
    const eased = 1 - Math.pow(1 - ignite, 3);
    drift += (Math.random() - 0.5) * 0.08; drift *= 0.92;
    const flicker = reduce ? 1 : 0.93 + 0.035 * Math.sin(now * 0.011) + 0.025 * Math.sin(now * 0.029 + 1.3) + drift * 0.25;
    const glow = eased * flicker;

    if (visible) {
      // pendulum: gravity, damping, a slow idle sway, and pushes from a passing cursor
      if (!reduce) {
        const r = core.getBoundingClientRect();
        const near = Math.hypot(mouse.x - r.x, mouse.y - (r.y - 30)) < 130 && now - mouse.t < 60;
        if (near) omega -= Math.max(-0.9, Math.min(0.9, mouse.vx * 0.9)) * dt * 6;   // CSS rotate is clockwise: a push to the right is negative
        omega += (-7.5 * Math.sin(theta) - 0.75 * omega + 0.32 * Math.sin(now * 0.0011)) * dt;
        theta = Math.max(-0.7, Math.min(0.7, theta + omega * dt));
        lantern.style.transform = `rotate(${theta}rad)`;
        flame.style.transform = `scale(${0.96 + 0.06 * (flicker - 0.93) * 8}, ${0.9 + 0.12 * (flicker - 0.9) * 6}) rotate(${-theta * 0.6}rad)`;
      }
      const c = core.getBoundingClientRect(), cx = c.x, cy = c.y;
      const lr = light.getBoundingClientRect(), pr = panel.getBoundingClientRect();
      demo.style.setProperty("--glow", glow.toFixed(3));
      light.style.setProperty("--gx", (cx - lr.x).toFixed(1) + "px");
      light.style.setProperty("--gy", (cy - lr.y).toFixed(1) + "px");
      panel.style.setProperty("--ex", (cx - pr.x).toFixed(1) + "px");
      panel.style.setProperty("--ey", (cy - pr.y).toFixed(1) + "px");
      panel.style.setProperty("--sx", ((pr.x + pr.width / 2 - cx) * 0.07).toFixed(1) + "px");
      panel.style.setProperty("--sy", (24 + (pr.y + pr.height / 2 - cy) * 0.04).toFixed(1) + "px");
      wall.style.setProperty("--lx", cx.toFixed(1) + "px");
      wall.style.setProperty("--ly", cy.toFixed(1) + "px");
      wall.style.setProperty("--lr", (520 * glow).toFixed(0) + "px");

      // embers rise from the cap, drift, and fade
      if (!reduce) {
        const cr = canvas.getBoundingClientRect();
        if (ignite >= 1 && now > nextEmber && embers.length < 14) {
          const ox = cx - cr.x + Math.sin(theta) * -70, oy = cy - cr.y - Math.cos(theta) * 70;
          embers.push({ x: ox + (Math.random() - 0.5) * 16, y: oy, vx: (Math.random() - 0.5) * 10, vy: -(14 + Math.random() * 16),
                        age: 0, life: 2.6 + Math.random() * 1.8, r: 0.7 + Math.random() * 1.1, phase: Math.random() * 6 });
          nextEmber = now + 380 + Math.random() * 520;
        }
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        embers = embers.filter((p) => (p.age += dt) < p.life);
        for (const p of embers) {
          p.x += (p.vx + Math.sin(p.age * 2.2 + p.phase) * 7) * dt; p.y += p.vy * dt; p.vy *= 0.995;
          const a = Math.sin(Math.PI * p.age / p.life) * 0.85;
          ctx.beginPath(); ctx.arc(p.x * dpr, p.y * dpr, p.r * dpr, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(255, ${170 + Math.floor(60 * (1 - p.age / p.life))}, 110, ${a})`; ctx.fill();
        }
      }
    } else {
      wall.style.setProperty("--lr", "0px");
    }
    if (!reduce || ignite < 1) requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  // Once lit, the panel starts showing what it can do, until someone uses it.
  if (!reduce) setTimeout(() => window.fenerDemo && window.fenerDemo(), 2300);
})();

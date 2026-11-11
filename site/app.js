// A small copy of fener's panel for the website: the main menu, apps, system actions, answers
// (math, units, currency with example rates, time zones, dates), emoji and the web row.
// Everything runs in the page; nothing is sent anywhere.
"use strict";

const glyph = (name) => (window.ICONS && ICONS[name]) || "";

// ---- data -------------------------------------------------------------------------------

const APPS = [
  ["Safari", "md-compass_outline"], ["Mail", "md-email_outline"], ["Notes", "md-note_text_outline"],
  ["Calendar", "md-calendar_month"], ["Music", "md-music_note"], ["Terminal", "md-console_line"],
  ["Finder", "fa-folder"], ["System Settings", "md-cog_outline"], ["Calculator", "md-calculator"],
  ["Passwords", "md-lock_outline"], ["Preview", "md-image"], ["Dictionary", "md-book_open_variant"],
];
const SYSTEM = [
  ["Lock Screen", "md-lock", "system"], ["Sleep", "md-power_sleep", "system"], ["Restart", "md-restart", "system"],
  ["Empty Trash", "md-delete", "system"], ["Pick Color", "md-eyedropper", "system"], ["Dark Mode", "md-weather_night", "toggle"],
];
const SNIPPETS = [["Daily Note", "md-text_box_edit", "snippet"], ["Today", "md-text_box_edit", "snippet"], ["Shrug", "md-text_box_edit", "snippet"]];
const MENU = [
  ["Apps", "md-apps", "apps"], ["Find", "md-magnify", "find"], ["Learn", "md-brain", "learn"],
  ["Appearance", "md-palette", "appearance"], ["Trigger", "fa-rocket", "trigger"], ["Setup", "fa-cog", "setup"],
  ["Update", "fa-refresh", "update"], ["About", "md-information_outline", "about"], ["System", "md-power", "system"],
];
const SUBMENUS = {
  find: [["Files", "md-file_document_outline"], ["Recent Files", "md-clock_outline"], ["Screenshots", "md-monitor_screenshot"],
         ["Clipboard History", "md-clipboard_text"], ["Bookmarks", "md-web"], ["Projects", "md-folder_cog"]],
  learn: [["Keybindings", "md-keyboard"], ["Dictionary", "md-book_open_variant"], ["macOS Shortcuts", "md-keyboard"]],
  appearance: [["Theme", "md-palette"], ["Background", "md-image"]],
  trigger: [["Toggle", "md-toggle_switch"], ["Emoji", "md-emoticon_outline"], ["Clipboard History", "md-clipboard_text"],
            ["Focus Timer", "md-timer_outline"], ["Generate", "md-dice_5", "UUID, password, lorem"], ["Audio Devices", "md-volume_high"],
            ["Snippets", "md-text_box_edit"], ["Color Picker", "md-eyedropper", "copies the hex"]],
  setup: [["fener Settings", "md-cog_outline"], ["fener", "md-file_cog", "config.toml"], ["Keyboard Shortcuts", "md-keyboard"]],
  update: [["Homebrew", "fa-refresh", "update and upgrade"], ["macOS", "fa-refresh", "Software Update"]],
  about: [["fener", "md-information_outline", "0.1.0"], ["This Mac", "md-information_outline", "system report"]],
};
const EMOJI = [
  ["❤️", "red heart"], ["🫶", "heart hands"], ["💘", "heart with arrow"], ["💝", "heart with ribbon"], ["💔", "broken heart"],
  ["💕", "two hearts"], ["💙", "blue heart"], ["💚", "green heart"], ["💛", "yellow heart"], ["🎉", "party popper tada"],
  ["🚀", "rocket"], ["✨", "sparkles"], ["🔥", "fire"], ["👍", "thumbs up"], ["👀", "eyes"], ["😂", "face with tears of joy"],
  ["🙏", "folded hands"], ["☕", "hot beverage coffee"], ["🏮", "red paper lantern"], ["🪔", "diya lamp"], ["💡", "light bulb"],
  ["✅", "check mark button"], ["⚠️", "warning"], ["→", "rightwards arrow"], ["⌘", "place of interest sign command"], ["€", "euro sign"],
];
// Example rates per euro, for the demo only. fener itself uses the ECB's daily file.
const RATES = { EUR: 1, USD: 1.08, GBP: 0.84, JPY: 162, CHF: 0.95, TRY: 46.5, CAD: 1.48, AUD: 1.64 };
const CITIES = {
  istanbul: "Europe/Istanbul", london: "Europe/London", tokyo: "Asia/Tokyo", "new york": "America/New_York",
  paris: "Europe/Paris", berlin: "Europe/Berlin", "san francisco": "America/Los_Angeles", "los angeles": "America/Los_Angeles",
  sydney: "Australia/Sydney", singapore: "Asia/Singapore", dubai: "Asia/Dubai", "sao paulo": "America/Sao_Paulo", utc: "UTC",
};
const UNITS = {
  km: ["length", 1000], m: ["length", 1], cm: ["length", 0.01], mi: ["length", 1609.344], ft: ["length", 0.3048], in: ["length", 0.0254],
  kg: ["mass", 1], g: ["mass", 0.001], lb: ["mass", 0.45359237], oz: ["mass", 0.028349523],
  h: ["time", 3600], min: ["time", 60], s: ["time", 1], gb: ["data", 1e9], mb: ["data", 1e6], gib: ["data", 1073741824], mib: ["data", 1048576],
};

// ---- answers ----------------------------------------------------------------------------

const fmt = (n) => Number.isInteger(n) ? n.toLocaleString("en-US") : (+n.toPrecision(10)).toLocaleString("en-US", { maximumFractionDigits: 6 });

/** Recursive-descent calculator: + - * / ^ % and parentheses. No eval. */
function calc(src) {
  const s = src.replace(/,/g, ".").replace(/\s+/g, "").replace(/×/g, "*").replace(/÷/g, "/");
  if (!/^[\d.+\-*/^%()]+$/.test(s) || !/\d/.test(s) || /^[\d.]+$/.test(s)) return null;
  let i = 0;
  const peek = () => s[i];
  function num() {
    if (peek() === "(") { i++; const v = sum(); if (s[i++] !== ")") throw 0; return v; }
    const m = /^\d*\.?\d+/.exec(s.slice(i)); if (!m) throw 0; i += m[0].length; return parseFloat(m[0]);
  }
  function unary() { if (peek() === "-") { i++; return -unary(); } if (peek() === "+") { i++; return unary(); } return power(); }
  function power() { let b = num(); while (peek() === "%") { i++; b /= 100; } if (peek() === "^") { i++; return Math.pow(b, unary()); } return b; }
  function product() { let v = unary(); while (peek() === "*" || peek() === "/") { const o = s[i++]; const r = unary(); v = o === "*" ? v * r : v / r; } return v; }
  function sum() { let v = product(); while (peek() === "+" || peek() === "-") { const o = s[i++]; const r = product(); v = o === "+" ? v + r : v - r; } return v; }
  try { const v = sum(); return i === s.length && isFinite(v) ? v : null; } catch { return null; }
}

function convert(q) {
  const m = /^([\d.,]+)\s*([a-z]+)\s+(?:to|in)\s+([a-z]+)$/i.exec(q.trim());
  if (!m) return null;
  const n = parseFloat(m[1].replace(",", ".")), from = m[2].toLowerCase(), to = m[3].toLowerCase();
  if (RATES[from.toUpperCase()] && RATES[to.toUpperCase()]) {
    const v = n / RATES[from.toUpperCase()] * RATES[to.toUpperCase()];
    return { value: v.toFixed(2), sub: `${fmt(n)} ${from.toUpperCase()} → ${to.toUpperCase()} · example rate`, icon: "md-cash" };
  }
  const temps = { c: "°C", f: "°F" };
  if (temps[from] && temps[to] && from !== to) {
    const v = from === "c" ? n * 9 / 5 + 32 : (n - 32) * 5 / 9;
    return { value: fmt(+v.toFixed(2)) + temps[to], sub: `${fmt(n)}${temps[from]} → ${temps[to]}`, icon: "md-calculator" };
  }
  const a = UNITS[from], b = UNITS[to];
  if (a && b && a[0] === b[0]) return { value: fmt(n * a[1] / b[1]), sub: `${fmt(n)} ${from} → ${to}`, icon: "md-calculator" };
  return null;
}

function offsetMinutes(zone, at = new Date()) {
  const p = new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "longOffset" }).formatToParts(at).find((x) => x.type === "timeZoneName").value;
  const m = /GMT([+-])(\d\d):(\d\d)/.exec(p);
  return m ? (m[1] === "-" ? -1 : 1) * (+m[2] * 60 + +m[3]) : 0;
}
const city = (name) => Object.keys(CITIES).find((c) => c === name.trim().toLowerCase());
const title = (c) => c.replace(/\b\w/g, (x) => x.toUpperCase());

function timeAnswer(q) {
  q = q.trim().toLowerCase();
  let m = /^(?:time in\s+(.+)|(.+?)\s+time)$/.exec(q);
  if (m) {
    const c = city(m[1] || m[2]); if (!c) return null;
    const t = new Intl.DateTimeFormat("en-GB", { timeZone: CITIES[c], hour: "2-digit", minute: "2-digit" }).format(new Date());
    const d = new Intl.DateTimeFormat("en-GB", { timeZone: CITIES[c], weekday: "short", day: "numeric", month: "short" }).format(new Date());
    return { value: t, sub: `${title(c)} · ${d}`, icon: "md-calendar_clock" };
  }
  m = /^(\d{1,2})(?::(\d\d))?\s*(am|pm)?\s+(?:in\s+)?(.+?)\s+(?:to|in)\s+(.+)$/.exec(q);
  if (m) {
    const from = city(m[4]), to = city(m[5]); if (!from || !to) return null;
    let h = +m[1] % 24; const min = +(m[2] || 0);
    if (m[3] === "pm" && h < 12) h += 12; if (m[3] === "am" && h === 12) h = 0;
    let total = h * 60 + min - offsetMinutes(CITIES[from]) + offsetMinutes(CITIES[to]);
    total = ((total % 1440) + 1440) % 1440;
    const pad = (x) => String(x).padStart(2, "0");
    return { value: `${pad(Math.floor(total / 60))}:${pad(total % 60)}`, sub: `${pad(h)}:${pad(min)} ${title(from)} → ${title(to)}`, icon: "md-calendar_clock" };
  }
  m = /^days (until|since) (.+)$/.exec(q);
  if (m) {
    const now = new Date(); now.setHours(0, 0, 0, 0);
    let d = new Date(m[2].replace(/^(\d+) (\w+)$/, "$2 $1") + (/\d{4}/.test(m[2]) ? "" : " " + now.getFullYear()));
    if (isNaN(d)) return null;
    if (m[1] === "until" && d < now && !/\d{4}/.test(m[2])) d.setFullYear(d.getFullYear() + 1);
    const days = Math.round(Math.abs(d - now) / 86400000);
    const label = d.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
    return { value: `${days} day${days === 1 ? "" : "s"}`, sub: `days ${m[1]} ${label}`, icon: "md-calendar_clock" };
  }
  return null;
}

// ---- search -----------------------------------------------------------------------------

/** Subsequence match with a bonus for word starts and the beginning; null when no match. */
function fuzzy(q, text) {
  q = q.toLowerCase(); const t = text.toLowerCase();
  if (!q) return 1;
  let ti = 0, score = 0, prev = -2;
  for (const ch of q) {
    const at = t.indexOf(ch, ti); if (at < 0) return null;
    score += at === prev + 1 ? 6 : 1;
    if (at === 0 || /[\s\-_.]/.test(t[at - 1])) score += 8;
    prev = at; ti = at + 1;
  }
  return score - t.length * 0.05 + (t.startsWith(q) ? 20 : 0);
}

const item = (title, icon, sub = "", extra = {}) => ({ title, icon, sub, ...extra });
const web = (q) => item(`Search DuckDuckGo for “${q}”`, "md-duck", "", { accessory: "d", run: () => say(`fener would open DuckDuckGo for “${q}” in your browser`) });

function answerItem(q) {
  const v = calc(q);
  if (v !== null) return item(fmt(v), "md-calculator", `${q.trim()}  ·  ⏎ copies`, { answer: String(fmt(v)) });
  const c = convert(q) || timeAnswer(q);
  return c && item(c.value, c.icon, `${c.sub}  ·  ⏎ copies`, { answer: c.value });
}

function rootSearch(q) {
  if (!q) return MENU.map(([t, ic, sub]) => item(t, ic, "", { accessory: "›", submenu: sub }));
  if (q.startsWith(":")) return emojiSearch(q.slice(1));
  if (q.startsWith("=")) { const a = answerItem(q.slice(1)); return a ? [a] : []; }
  const out = [];
  const a = answerItem(q); if (a) out.push(a);
  const pool = [
    ...APPS.map(([t, ic]) => item(t, ic, "", { run: () => say(`fener would open <b>${t}</b>`) })),
    ...SYSTEM.map(([t, ic, s]) => item(t, ic, s, { run: () => say(`fener would run <b>${t}</b>`) })),
    ...SNIPPETS.map(([t, ic, s]) => item(t, ic, s, { run: () => say(`fener would copy the <b>${t}</b> snippet`) })),
    ...MENU.map(([t, ic, sub]) => item(t, ic, "Menu", { accessory: "›", submenu: sub })),
  ];
  pool.map((it) => [it, fuzzy(q, it.title)]).filter(([, s]) => s !== null && s > q.length * 2)
    .sort((x, y) => y[1] - x[1]).slice(0, 8).forEach(([it]) => out.push(it));
  out.push(web(q));
  return out;
}

function emojiSearch(q) {
  return EMOJI.filter(([, n]) => !q || n.includes(q.toLowerCase().trim())).map(([e, n]) =>
    item(n.split(" ").slice(0, 3).join(" "), null, "U+" + e.codePointAt(0).toString(16).toUpperCase(), { emoji: e, answer: e }));
}

function menuSearch(name) {
  const entries = name === "apps" ? APPS : name === "system" ? SYSTEM : SUBMENUS[name] || [];
  return (q) => entries.filter(([t]) => fuzzy(q, t) !== null).map(([t, ic, s]) =>
    item(t, ic, s || "", { run: () => say(`fener would run <b>${t}</b>`) }));
}

// ---- panel ------------------------------------------------------------------------------

const panel = document.getElementById("panel"), input = document.getElementById("q"), list = document.getElementById("rows");
const status = document.getElementById("status");
let stack = [{ prompt: "Search…", search: rootSearch, query: "" }], items = [], sel = 0;

function say(html) { status.innerHTML = html; }

function render() {
  list.innerHTML = "";
  items.forEach((it, i) => {
    const li = document.createElement("li");
    li.setAttribute("role", "option");
    if (i === sel) { li.className = "sel"; li.setAttribute("aria-selected", "true"); }
    const ic = document.createElement("i");
    if (it.emoji) { ic.className = "emoji"; ic.textContent = it.emoji; } else ic.textContent = glyph(it.icon);
    const b = document.createElement("b"); b.textContent = it.title;
    li.append(ic, b);
    if (it.sub) { const s = document.createElement("span"); s.textContent = it.sub; li.append(s); }
    const acc = i === sel && !it.accessory ? "⌘K" : it.accessory;
    if (acc) { const e = document.createElement("em"); e.textContent = acc; li.append(e); }
    li.addEventListener("mousemove", () => { if (sel !== i) { sel = i; render(); } });
    li.addEventListener("click", () => { sel = i; run(); input.focus(); });
    list.append(li);
  });
  panel.classList.toggle("fade", items.length > 9);
}

function filter() {
  const mode = stack[stack.length - 1];
  items = mode.search(input.value);
  sel = 0;
  render();
}

function push(name, title) {
  stack[stack.length - 1].query = input.value;
  stack.push({ prompt: title + "…", search: menuSearch(name) });
  input.value = ""; input.placeholder = title + "…";
  filter();
}

function pop() {
  if (stack.length < 2) return;
  stack.pop();
  const mode = stack[stack.length - 1];
  input.value = mode.query || ""; input.placeholder = mode.prompt;
  filter();
}

async function run() {
  const it = items[sel]; if (!it) return;
  if (it.submenu) return push(it.submenu, it.title);
  if (it.answer !== undefined) {
    try { await navigator.clipboard.writeText(it.answer); say(`Copied <b>${it.answer}</b>`); }
    catch { say(`fener would copy <b>${it.answer}</b>`); }
    return;
  }
  if (it.run) it.run();
}

input.addEventListener("input", filter);
input.addEventListener("keydown", (e) => {
  const k = e.key;
  if (k === "ArrowDown" || (e.ctrlKey && (k === "n" || k === "j"))) { e.preventDefault(); sel = (sel + 1) % Math.max(items.length, 1); render(); }
  else if (k === "ArrowUp" || (e.ctrlKey && (k === "p" || k === "k"))) { e.preventDefault(); sel = (sel - 1 + items.length) % Math.max(items.length, 1); render(); }
  else if (k === "Enter") { e.preventDefault(); run(); }
  else if (k === "Escape") { e.preventDefault(); if (stack.length > 1) { stack = [stack[0]]; input.placeholder = "Search…"; } input.value = ""; filter(); }
  else if (k === "Backspace" && !input.value && stack.length > 1) { e.preventDefault(); pop(); }
});

// "Try typing" buttons type into the panel, a character at a time.
let typing = 0, demoOn = false;
document.querySelectorAll(".try button").forEach((b) => b.addEventListener("click", () => {
  demoOn = false;
  const text = b.dataset.q, id = ++typing;
  stack = [stack[0]]; input.placeholder = "Search…"; input.value = ""; filter(); input.focus();
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) { input.value = text; return filter(); }
  [...text].forEach((ch, i) => setTimeout(() => { if (id === typing) { input.value += ch; filter(); } }, 40 * i));
}));

// ---- the config file section --------------------------------------------------------------

const toggle = document.getElementById("theme-toggle"), mini = document.getElementById("mini");
toggle.addEventListener("click", () => {
  const next = mini.dataset.theme === "tokyo-night" ? "catppuccin-mocha" : "tokyo-night";
  mini.dataset.theme = next; panel.dataset.theme = next;
  toggle.textContent = `"${next}"`;
});
document.querySelectorAll("[data-icon]").forEach((el) => { el.textContent = glyph(el.dataset.icon); });

document.querySelectorAll("[data-copy]").forEach((b) => b.addEventListener("click", async () => {
  try { await navigator.clipboard.writeText(b.previousElementSibling.textContent); b.textContent = "copied"; }
  catch { b.textContent = "select it"; }
  setTimeout(() => (b.textContent = "copy"), 1600);
}));

// Shows a few queries on its own after the lantern lights, until the visitor touches the panel.
window.fenerDemo = () => {
  if (input.value || document.activeElement === input) return;
  demoOn = true;
  const queries = ["100 usd to try", "time in tokyo", ":heart", "2 * (3 + 4)^2", "lock", ""];
  let qi = 0;
  const step = () => {
    if (!demoOn) return;
    const text = queries[qi++ % queries.length], id = ++typing;
    input.value = ""; filter();
    [...text].forEach((ch, i) => setTimeout(() => { if (demoOn && id === typing) { input.value += ch; filter(); } }, 70 * i + 120));
    setTimeout(step, 70 * text.length + (text ? 2300 : 1600));
  };
  step();
};
const stopDemo = () => { if (demoOn) { demoOn = false; typing++; input.value = ""; filter(); } };
panel.addEventListener("pointerdown", stopDemo);
input.addEventListener("focus", stopDemo);

// fener.../?q=100+usd+to+try (or #q=…) opens the page with that typed.
const fromUrl = new URLSearchParams(location.search).get("q") || decodeURIComponent((location.hash.match(/^#q=(.*)$/) || [])[1] || "");
if (fromUrl) input.value = fromUrl;
filter();

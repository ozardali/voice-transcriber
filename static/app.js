const $ = (id) => document.getElementById(id);
const queue = [];
const jobs = [];
let busy = false;

const ICON_PLAY = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/></svg>';
const ICON_PAUSE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>';

// settings

let catalog = null;

// language names in English, plus the native name: "Turkish (Türkçe)"
function languageName(code, native = true) {
  const c = code === "jw" ? "jv" : code;  // whisper uses an old code for Javanese
  try {
    const en = new Intl.DisplayNames(["en"], { type: "language" }).of(c);
    if (!native) return en;
    const own = new Intl.DisplayNames([c], { type: "language" }).of(c);
    return own && own.toLowerCase() !== en.toLowerCase() ? `${en} (${own})` : en;
  } catch {
    return code;
  }
}

const stored = (key) => { try { return localStorage.getItem(key); } catch { return null; } };
const store = (key, value) => { try { localStorage.setItem(key, value); } catch {} };

const ICON_CHECK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>';
const ICON_DOWNLOAD = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 20h14"/></svg>';
const ICON_INFO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/></svg>';
const ICON_EXT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 17 17 7M8 7h9v9"/></svg>';

async function loadModels() {
  catalog = await fetch("/api/models").then((r) => r.json());

  if (!languageItems.length) {
    const saved = stored("language") || catalog.default_language;
    initLanguages(catalog.languages.includes(saved) || saved === "auto" ? saved : catalog.default_language);
  }

  const gpu = document.querySelector("input[name=device][value=gpu]");
  gpu.disabled = !catalog.gpu;
  const savedDevice = catalog.gpu ? (stored("device") || "gpu") : "cpu";
  document.querySelector(`input[name=device][value=${savedDevice}]`).checked = true;
  // no GPU: a switch with one usable side is just noise
  $("device-section").hidden = !catalog.gpu;
  const { count, bytes } = catalog.storage;
  $("storage-text").textContent = count
    ? `${count} model${count === 1 ? "" : "s"} downloaded · ${fmtSize(bytes)}`
    : "No models downloaded yet";
  $("cpu-only").hidden = catalog.gpu;
  renderModels();
}

// recently used languages first, so nobody has to scroll through 100 every time
function recentLanguages() {
  try {
    const list = JSON.parse(stored("recent-languages") || "[]");
    return Array.isArray(list) ? list.filter((c) => catalog.languages.includes(c)) : [];
  } catch {
    return [];
  }
}

// --- language combobox: type to filter, arrows + Enter to pick, Esc to cancel

let language = "en";
let languageItems = [];   // { code, name, key } for every option
let shownOptions = [];    // codes currently in the list, in order
let activeIndex = -1;
const combo = $("language");
const listbox = $("language-list");

// "Türkçe" -> "turkce", so typing without special letters still finds it
const fold = (t) => t.normalize("NFD").replace(/\p{M}/gu, "").replace(/ı/g, "i").toLowerCase();

function initLanguages(value) {
  languageItems = [
    { code: "auto", name: "Detect automatically", key: "detect automatically auto" },
    ...catalog.languages.map((code) => {
      const name = languageName(code);
      return { code, name, key: fold(`${name} ${code}`) };
    }).sort((a, b) => a.name.localeCompare(b.name, "en")),
  ];
  setLanguage(value, false);
}

const labelFor = (code) => languageItems.find((i) => i.code === code)?.name || code;

function setLanguage(code, remember = true) {
  language = code;
  combo.value = labelFor(code);
  if (remember) {
    store("language", code);
    if (code !== "auto") {
      store("recent-languages", JSON.stringify([code, ...recentLanguages().filter((c) => c !== code)].slice(0, 5)));
    }
  }
  if (catalog) renderModels();
}

function renderOptions(query) {
  const q = fold(query.trim());
  const byCode = (c) => languageItems.find((i) => i.code === c);
  const option = (item) => {
    shownOptions.push(item.code);
    const i = shownOptions.length - 1;
    return `<li role="option" id="lang-opt-${i}" data-i="${i}" aria-selected="${item.code === language}">` +
      `<span>${item.name}</span>${item.code === "auto" ? "" : `<span class="code">${item.code}</span>`}</li>`;
  };
  shownOptions = [];
  let html = "";
  if (!q) {
    const recent = recentLanguages();
    html += option(languageItems[0]);
    if (recent.length) html += `<li class="group" role="presentation">Recently used</li>` + recent.map((c) => option(byCode(c))).join("");
    html += `<li class="group" role="presentation">All languages</li>` + languageItems.slice(1).map(option).join("");
  } else {
    const hits = languageItems.filter((i) => i.key.includes(q));
    // exact code first ("de" -> German), then names that start with the query
    const score = (i) => (i.code === q ? 2 : i.key.startsWith(q) ? 1 : 0);
    hits.sort((a, b) => score(b) - score(a));
    html = hits.length ? hits.map(option).join("") : `<li class="none" role="presentation">No language matches “${query.replace(/[<&]/g, "")}”</li>`;
  }
  listbox.innerHTML = html;
  const current = shownOptions.indexOf(language);
  setActive(q ? 0 : current, true);
}

function setActive(i, center = false) {
  listbox.querySelector(".active")?.classList.remove("active");
  activeIndex = shownOptions.length ? Math.max(0, Math.min(i, shownOptions.length - 1)) : -1;
  const el = activeIndex >= 0 ? $(`lang-opt-${activeIndex}`) : null;
  if (el) {
    el.classList.add("active");
    combo.setAttribute("aria-activedescendant", el.id);
    el.scrollIntoView({ block: center ? "center" : "nearest" });
  } else {
    combo.removeAttribute("aria-activedescendant");
  }
}

function openList() {
  if (!listbox.hidden) return;
  listbox.hidden = false;
  combo.setAttribute("aria-expanded", "true");
  renderOptions("");
  combo.select();
}

function closeList(pick) {
  if (pick !== undefined) setLanguage(pick);
  listbox.hidden = true;
  combo.setAttribute("aria-expanded", "false");
  combo.removeAttribute("aria-activedescendant");
  combo.value = labelFor(language);
}

combo.addEventListener("focus", openList);
combo.addEventListener("click", openList);
combo.addEventListener("input", () => { listbox.hidden = false; combo.setAttribute("aria-expanded", "true"); renderOptions(combo.value); });
combo.addEventListener("blur", () => closeList());
combo.addEventListener("keydown", (ev) => {
  if (ev.key === "ArrowDown" || ev.key === "ArrowUp") {
    ev.preventDefault();
    if (listbox.hidden) return openList();
    setActive(activeIndex + (ev.key === "ArrowDown" ? 1 : -1));
  } else if (ev.key === "Enter") {
    ev.preventDefault();
    if (!listbox.hidden && activeIndex >= 0) { closeList(shownOptions[activeIndex]); combo.blur(); }
  } else if (ev.key === "Escape") {
    ev.preventDefault();
    closeList();
    combo.blur();
  }
});
// mousedown, not click: keeps focus in the input so blur doesn't close the list first
listbox.addEventListener("mousedown", (ev) => {
  ev.preventDefault();
  const li = ev.target.closest("[role=option]");
  if (li) { closeList(shownOptions[Number(li.dataset.i)]); combo.blur(); }
});
listbox.addEventListener("mousemove", (ev) => {
  const li = ev.target.closest("[role=option]");
  if (li && Number(li.dataset.i) !== activeIndex) setActive(Number(li.dataset.i));
});

let shownGroup = null;

// "Turkish · Best (large-v3-turbo)" on the drop zone, so the settings are visible where you drop
function updateUsing() {
  const lang = selectedLanguage();
  const m = catalog.models[lang === "en" ? "en" : "multi"].find((x) => x.id === selectedModel());
  const name = lang === "auto" ? "Any language" : languageName(lang, false);
  $("using").innerHTML = `<b>${name}</b> · ${m.name} (${m.model})${$("fast").checked ? " · speed boost" : ""}`;
}

function renderModels() {
  const lang = selectedLanguage();
  const group = lang === "en" ? "en" : "multi";
  const recommended = selectedDevice() === "gpu" && catalog.gpu ? "best" : "balanced";
  const saved = selectedModel() || stored("model") || catalog.default;
  const box = $("models");
  box.innerHTML = catalog.models[group].map((m) => `
    <label class="model">
      <input type="radio" name="model" value="${m.id}" data-model="${m.model}" ${m.id === saved ? "checked" : ""}>
      <span class="dot" aria-hidden="true"></span>
      <span class="name"><b>${m.name}</b>${m.id === recommended ? '<span class="badge">Recommended</span>' : ""}</span>
      <span class="tag ${m.downloaded ? "ok" : ""}">${m.downloaded ? `${ICON_CHECK}ready` : `${ICON_DOWNLOAD}${m.size.replace("~", "")}`}</span>
      <span class="note">${m.note}</span>
      <span class="id">${m.model}</span>
      <a class="info-link" href="https://huggingface.co/${m.repo}" target="_blank" rel="noopener"
        title="About ${m.model} (opens Hugging Face)" aria-label="About ${m.model} (opens Hugging Face)">${ICON_INFO}</a>
    </label>`).join("");
  if (!box.querySelector("input:checked")) box.querySelector("input").checked = true;
  box.querySelectorAll("input").forEach((r) => r.addEventListener("change", () => { store("model", r.value); updateUsing(); }));

  // the cards swap to other models: make that visible
  if (shownGroup && shownGroup !== group) {
    box.classList.remove("swapped");
    void box.offsetWidth;
    box.classList.add("swapped");
  }
  shownGroup = group;

  updateUsing();
  $("model-label").textContent =
    lang === "auto" ? "Model · any language" : `Model · for ${languageName(lang, false)}`;
  $("model-hint").textContent =
    group === "en"
      ? "English-only models, a bit more accurate for English."
      : lang === "auto" ? "Multilingual models. The language is detected from the start of the audio."
      : "Multilingual models, about 100 languages.";
}

$("fast").checked = stored("fast") === "1";
$("fast").addEventListener("change", () => { store("fast", $("fast").checked ? "1" : "0"); updateUsing(); });

document.querySelectorAll("input[name=device]").forEach((r) =>
  r.addEventListener("change", () => { store("device", r.value); renderModels(); }));

const selectedLanguage = () => language;
const selectedModel = () => document.querySelector("input[name=model]:checked")?.value;
const selectedDevice = () => document.querySelector("input[name=device]:checked")?.value || "gpu";

// list

// WhatsApp file names contain the timestamp, so name order = recording order
const byName = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

function addFiles(files) {
  const sorted = [...files].sort((a, b) => byName.compare(a.name, b.name));
  for (const file of sorted) {
    const card = document.createElement("article");
    card.className = "result";
    card.innerHTML = `
      <header tabindex="0" role="button" aria-expanded="true">
        <span class="num" aria-hidden="true"></span>
        <svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
        <span class="title"><span class="file"></span><span class="info">queued</span><span class="preview"></span></span>
        <button type="button" class="remove" aria-label="Remove from list" title="Remove">×</button>
      </header>
      <div class="body"><p class="wait"><span class="spin"></span><span>Waiting…</span></p></div>`;
    card.querySelector(".file").textContent = file.name;
    card.querySelector(".file").title = file.name;
    const job = { file, card, model: selectedModel(), language: selectedLanguage(), device: selectedDevice(), fast: $("fast").checked, state: "queued",
      modelName: document.querySelector("input[name=model]:checked")?.dataset.model };
    const header = card.querySelector("header");
    header.addEventListener("click", () => setCollapsed(job, !card.classList.contains("collapsed")));
    header.addEventListener("keydown", (ev) => {
      if (ev.target === header && (ev.key === "Enter" || ev.key === " ")) { ev.preventDefault(); header.click(); }
    });
    card.querySelector(".remove").addEventListener("click", (ev) => { ev.stopPropagation(); removeJob(job); });
    jobs.push(job);
    queue.push(job);
    $("results").append(card);
  }
  updateList();
  runQueue();
}

function setCollapsed(job, collapsed) {
  job.card.classList.toggle("collapsed", collapsed);
  job.card.querySelector("header").setAttribute("aria-expanded", String(!collapsed));
  if (collapsed) job.audio?.pause();
  updateList();
}

function removeJob(job) {
  if (job.state === "running") return;
  const qi = queue.indexOf(job);
  if (qi !== -1) queue.splice(qi, 1);
  jobs.splice(jobs.indexOf(job), 1);
  if (job.audio) { job.audio.pause(); URL.revokeObjectURL(job.audio.src); }
  job.card.remove();
  updateList();
}

function updateList() {
  $("list-head").hidden = jobs.length === 0;
  $("drop").classList.toggle("compact", jobs.length > 0);
  $("drop-title").textContent = jobs.length ? "Add more files" : "Drop audio or video files here";
  $("tools").hidden = jobs.length === 0;
  $("count").textContent = jobs.length ? ` · ${jobs.length}` : "";
  const allCollapsed = jobs.length > 0 && jobs.every((j) => j.card.classList.contains("collapsed"));
  $("toggle-all").textContent = allCollapsed ? "Expand all" : "Collapse all";
  $("clear-done").disabled = !jobs.some((j) => j.state === "done" || j.state === "error");
  for (const j of jobs) {
    j.card.querySelector(".remove").hidden = j.state === "running";
    j.card.classList.toggle("running", j.state === "running");
    j.card.classList.toggle("failed", j.state === "error");
  }
}

$("toggle-all").addEventListener("click", () => {
  const collapse = !jobs.every((j) => j.card.classList.contains("collapsed"));
  jobs.forEach((j) => setCollapsed(j, collapse));
});
$("clear-done").addEventListener("click", () => {
  jobs.filter((j) => j.state === "done" || j.state === "error").forEach(removeJob);
});

// transcription

async function runQueue() {
  if (busy) return;
  busy = true;
  while (queue.length) {
    const job = queue.shift();
    job.state = "running";
    updateList();
    await transcribe(job);
    updateList();
  }
  busy = false;
}

async function transcribe(job) {
  const { file, card, model, language, device } = job;
  const box = card.querySelector(".body");
  const info = card.querySelector(".info");
  const firstUse = !Object.values(catalog.models).flat()
    .some((m) => m.model === job.modelName && m.downloaded);
  info.textContent = "transcribing";
  card.querySelector(".preview").textContent = "Transcribing…";
  card.querySelector(".wait span:last-child").textContent =
    firstUse ? "Downloading the model, then transcribing. The first run takes a while…" : "Transcribing…";

  const form = new FormData();
  form.append("file", file);
  form.append("model", model);
  form.append("language", language);
  form.append("device", device);
  form.append("fast", job.fast ? "1" : "0");
  let data;
  try {
    data = await fetch("/api/transcribe", { method: "POST", body: form, headers: { "X-Voice-Transcriber": "1" } }).then((r) => r.json());
  } catch (e) {
    data = { error: "Could not reach the app. Is it still running?" };
  }
  box.innerHTML = "";

  if (data.error) {
    job.state = "error";
    info.textContent = "error";
    card.querySelector(".preview").textContent = data.error;
    const p = document.createElement("p");
    p.className = "error";
    p.textContent = data.error;
    box.append(p);
    return;
  }

  job.state = "done";
  const ran = data.device === "cuda" ? "GPU" : "CPU";
  const fellBack = device === "gpu" && ran === "CPU" ? " (GPU unavailable)" : "";
  const load = data.load > 0 ? ` + ${data.load}s loading the model` : "";
  const langInfo = data.detected
    ? `${languageName(data.language)} (detected, ${Math.round(data.language_probability * 100)}%)`
    : languageName(data.language);
  info.textContent = `${langInfo} · ${data.model}${data.fast ? " (speed boost)" : ""} · ${ran}${fellBack} · ${fmtLong(data.duration)} audio · took ${data.elapsed}s${load}`;
  card.querySelector(".preview").textContent = data.text || "(No speech found.)";

  box.append(buildPlayer(job, data.duration));
  box.append(buildText(job, data));
  box.append(buildActions(job, data.text));
  if (firstUse) loadModels();
}

// player + highlight

function buildPlayer(job, duration) {
  const audio = new Audio(URL.createObjectURL(job.file));
  audio.preload = "metadata";
  job.audio = audio;

  const el = document.createElement("div");
  el.className = "player";
  el.innerHTML = `
    <button type="button" class="play" aria-label="Play">${ICON_PLAY}</button>
    <input type="range" class="seek" min="0" step="0.01" value="0" aria-label="Position">
    <span class="time">0:00 / ${fmt(duration)}</span>`;
  const play = el.querySelector(".play");
  const seek = el.querySelector(".seek");
  const time = el.querySelector(".time");
  seek.max = duration;

  play.addEventListener("click", () => (audio.paused ? playOnly(job) : audio.pause()));
  seek.addEventListener("input", () => { audio.currentTime = Number(seek.value); highlight(job); });
  audio.addEventListener("loadedmetadata", () => {
    if (isFinite(audio.duration)) { seek.max = audio.duration; time.textContent = `0:00 / ${fmt(audio.duration)}`; }
  });
  audio.addEventListener("play", () => { setIcon(play, true); tick(job); });
  audio.addEventListener("pause", () => setIcon(play, false));
  audio.addEventListener("ended", () => { setIcon(play, false); clearHighlight(job); });
  audio.addEventListener("timeupdate", () => {
    seek.value = audio.currentTime;
    time.textContent = `${fmt(audio.currentTime)} / ${fmt(Number(seek.max))}`;
    if (audio.paused) highlight(job);
  });
  return el;
}

function setIcon(button, playing) {
  button.innerHTML = playing ? ICON_PAUSE : ICON_PLAY;
  button.setAttribute("aria-label", playing ? "Pause" : "Play");
}

function playOnly(job) {
  for (const j of jobs) if (j !== job) j.audio?.pause();
  job.audio.play();
}

// whisper segments can span several sentences, so split on . ! ? ourselves
function buildText(job, data) {
  const p = document.createElement("p");
  p.className = "text";
  p.lang = data.language || "";
  p.dir = "auto";  // Arabic, Hebrew, Persian, Urdu read right to left
  const words = (data.segments || []).flatMap((s) => s.words);
  job.words = [];
  job.sentences = [];
  if (!words.length) {
    p.textContent = data.text || "(No speech found.)";
    return p;
  }
  let sentence = null;
  words.forEach((w, i) => {
    // keep whisper's spacing, otherwise "rip-off" becomes "rip -off"
    const space = i > 0 && /^\s/.test(w.word) ? " " : "";
    if (!sentence) {
      sentence = document.createElement("span");
      sentence.className = "sentence";
      job.sentences.push({ el: sentence, start: w.start, end: w.end });
      if (space) p.append(space);
    } else if (space) {
      sentence.append(space);
    }
    const span = document.createElement("span");
    span.className = "w";
    span.textContent = w.word.trim();
    span.addEventListener("click", () => {
      job.audio.currentTime = w.start;
      playOnly(job);
    });
    sentence.append(span);
    job.words.push({ el: span, start: w.start, end: w.end });
    job.sentences.at(-1).end = w.end;
    if (/[.!?。！？؟।]["')\]」』]*$/.test(w.word.trim())) {
      p.append(sentence);
      sentence = null;
    }
  });
  if (sentence) p.append(sentence);
  return p;
}

function buildActions(job, text) {
  const actions = document.createElement("div");
  actions.className = "actions";
  const copy = button("Copy", async () => {
    await navigator.clipboard.writeText(text);
    copy.textContent = "Copied";
    setTimeout(() => (copy.textContent = "Copy"), 1500);
  });
  const save = button("Save .txt", () => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([text + "\n"], { type: "text/plain" }));
    a.download = job.file.name.replace(/\.[^.]+$/, "") + ".txt";
    a.click();
    URL.revokeObjectURL(a.href);
  });
  const tip = document.createElement("span");
  tip.className = "tip";
  if (job.words.length) tip.textContent = "Click a word to play from there";
  actions.append(copy, save, tip);
  return actions;
}

// timeupdate only fires ~4x/sec, too choppy for word highlight
function tick(job) {
  if (job.audio.paused) return;
  highlight(job);
  requestAnimationFrame(() => tick(job));
}

function findAt(list, t) {
  let lo = 0, hi = list.length - 1, found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (list[mid].start <= t) { found = mid; lo = mid + 1; } else hi = mid - 1;
  }
  return found;
}

function highlight(job) {
  if (!job.words?.length) return;
  const t = job.audio.currentTime;
  const wi = findAt(job.words, t);
  const si = findAt(job.sentences, t);
  setNow(job, "word", wi >= 0 ? job.words[wi].el : null);
  const s = si >= 0 && t <= job.sentences[si].end + 0.6 ? job.sentences[si].el : null;
  setNow(job, "sentence", s);
  if (!job.audio.paused && wi >= 0 && wi !== job.lastScrolled) {
    job.lastScrolled = wi;
    keepVisible(job.words[wi].el);
  }
}

function setNow(job, kind, el) {
  const key = "now_" + kind;
  if (job[key] === el) return;
  job[key]?.classList.remove("now");
  el?.classList.add("now");
  job[key] = el;
}

function clearHighlight(job) {
  setNow(job, "word", null);
  setNow(job, "sentence", null);
}

function keepVisible(el) {
  const r = el.getBoundingClientRect();
  if (r.top < 80 || r.bottom > window.innerHeight - 80) {
    el.scrollIntoView({ block: "center", behavior: "smooth" });
  }
}

// helpers

function button(label, onClick) {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = label;
  b.addEventListener("click", onClick);
  return b;
}

function fmtSize(bytes) {
  return bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.round(bytes / 1e6)} MB`;
}

function fmt(sec) {
  sec = Math.max(0, Math.floor(sec || 0));
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
}

function fmtLong(sec) {
  const m = Math.floor(sec / 60), s = Math.round(sec % 60);
  return m ? `${m}m ${s}s` : `${s}s`;
}

// drag and drop

const drop = $("drop");
["dragenter", "dragover"].forEach((e) => drop.addEventListener(e, (ev) => { ev.preventDefault(); drop.classList.add("over"); }));
["dragleave", "drop"].forEach((e) => drop.addEventListener(e, (ev) => { ev.preventDefault(); drop.classList.remove("over"); }));
drop.addEventListener("drop", (ev) => addFiles(ev.dataTransfer.files));
drop.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); $("picker").click(); } });
$("picker").addEventListener("change", (ev) => { addFiles(ev.target.files); ev.target.value = ""; });
window.addEventListener("dragover", (ev) => ev.preventDefault());
window.addEventListener("drop", (ev) => {
  ev.preventDefault();
  if (ev.target.closest?.(".drop") === null && ev.dataTransfer.files.length) addFiles(ev.dataTransfer.files);
});

// space = play/pause the last used recording
document.addEventListener("keydown", (ev) => {
  if (ev.key !== " " || ev.target.closest("button, input, header, label, [tabindex]")) return;
  const playing = jobs.find((j) => j.audio && !j.audio.paused);
  const last = playing || jobs.findLast((j) => j.audio && j.audio.currentTime > 0);
  if (!last) return;
  ev.preventDefault();
  last.audio.paused ? playOnly(last) : last.audio.pause();
});

// appearance: auto follows the system
const themeNow = document.documentElement.dataset.theme || "auto";
document.querySelectorAll('input[name="theme"]').forEach((r) => {
  r.checked = r.value === themeNow;
  r.addEventListener("change", () => {
    if (r.value === "auto") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = r.value;
    try { localStorage.setItem("theme", r.value); } catch {}
  });
});

$("storage").addEventListener("click", () => {
  fetch("/api/open-models", { method: "POST", headers: { "X-Voice-Transcriber": "1" } }).catch(() => {});
});

$("quit").addEventListener("click", async () => {
  if (busy && !confirm("A file is still being transcribed. Quit anyway?")) return;
  try {
    await fetch("/api/quit", { method: "POST", headers: { "X-Voice-Transcriber": "1" } });
  } catch (e) {}
  const done = document.createElement("div");
  done.className = "stopped";
  done.innerHTML = "<div><h1>App stopped</h1><p>You can close this tab. Start it again from the Voice Transcriber icon.</p></div>";
  document.body.append(done);
});

loadModels();

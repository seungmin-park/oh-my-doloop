// 목업 페이지 공용: 아이콘 모음과 라이트·다크 전환.
const MOCK_ICONS = `
  <symbol id="i-check" viewBox="0 0 16 16"><path d="m3.5 8.5 3 3 6-7"/></symbol>
  <symbol id="i-rest" viewBox="0 0 16 16"><path d="M4 8h8"/></symbol>
  <symbol id="i-plus" viewBox="0 0 16 16"><path d="M8 3v10M3 8h10"/></symbol>
  <symbol id="i-today" viewBox="0 0 20 20"><rect x="3" y="4" width="14" height="13" rx="2"/><path d="M3 8h14M7 2.5v3M13 2.5v3"/></symbol>
  <symbol id="i-week" viewBox="0 0 20 20"><path d="M4 5h12M4 10h12M4 15h7"/></symbol>
  <symbol id="i-inbox" viewBox="0 0 20 20"><path d="M3 11.5 5 4h10l2 7.5V16H3zM3 11.5h4.5l1 2h3l1-2H17"/></symbol>
  <symbol id="i-calendar" viewBox="0 0 20 20"><rect x="3" y="4" width="14" height="13" rx="2"/><path d="M3 8h14M8 8v9M13 8v9M3 12.5h14"/></symbol>
  <symbol id="i-stats" viewBox="0 0 20 20"><path d="M4 16v-5M10 16V4M16 16V8"/></symbol>
  <symbol id="i-list" viewBox="0 0 20 20"><circle cx="10" cy="10" r="6.5"/></symbol>
  <symbol id="i-more" viewBox="0 0 20 20"><path d="M4.5 10h.01M10 10h.01M15.5 10h.01"/></symbol>
  <symbol id="i-focus" viewBox="0 0 20 20"><circle cx="10" cy="10" r="7"/><path d="M10 6v4l2.5 2"/></symbol>
  <symbol id="i-search" viewBox="0 0 20 20"><circle cx="9" cy="9" r="5.5"/><path d="m13.2 13.2 3.3 3.3"/></symbol>
  <symbol id="i-edit" viewBox="0 0 20 20"><path d="m4 13-.5 3.5L7 16l9-9-3-3zM11.5 5.5l3 3"/></symbol>
  <symbol id="i-theme" viewBox="0 0 20 20"><circle cx="10" cy="10" r="6.5"/><path d="M10 3.5v13"/></symbol>
  <symbol id="i-left" viewBox="0 0 16 16"><path d="m10 3-5 5 5 5"/></symbol>
  <symbol id="i-right" viewBox="0 0 16 16"><path d="m6 3 5 5-5 5"/></symbol>`;

document.body.insertAdjacentHTML(
  "afterbegin",
  `<svg class="icon-sprite" aria-hidden="true">${MOCK_ICONS}</svg>`,
);

function applyMockTheme(theme) {
  document.documentElement.dataset.theme = theme;
  document.querySelectorAll("[data-theme-set]").forEach((button) => {
    button.setAttribute("aria-pressed", button.dataset.themeSet === theme);
  });
}

// 고른 테마는 화면을 옮겨도 유지한다. 주소의 #dark, #light가 있으면 그것을 먼저 쓴다.
function setMockTheme(theme) {
  applyMockTheme(theme);
  try {
    localStorage.setItem("doloop-theme", theme);
  } catch {
    // 저장소를 못 쓰면 이 화면에서만 적용한다.
  }
}

function savedMockTheme() {
  try {
    return localStorage.getItem("doloop-theme");
  } catch {
    return null;
  }
}

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-theme-set]");
  if (button) setMockTheme(button.dataset.themeSet);
});

const hashTheme = ["#dark", "#light"].includes(location.hash) ? location.hash.slice(1) : null;
const initialTheme = hashTheme ?? (savedMockTheme() === "dark" ? "dark" : "light");
applyMockTheme(initialTheme);
// 이 스크립트는 버튼보다 먼저 실행되므로 문서가 준비되면 눌림 표시를 다시 맞춘다.
document.addEventListener("DOMContentLoaded", () => applyMockTheme(document.documentElement.dataset.theme));

// 목업 공용 데이터. 화면마다 같은 습관과 할 일을 보여 준다.
const MOCK_ITEMS = [
  { id: "r1", kind: "routine", group: "아침", title: "비타민 먹기", context: "커피 내리기 전", state: "done", streak: 11 },
  { id: "r2", kind: "routine", group: "아침", title: "책 10쪽 읽기", context: "출근길에", state: "done", streak: 2 },
  { id: "r3", kind: "routine", group: "저녁", title: "저녁 달리기", context: "퇴근 후", state: "rest", streak: 6 },
  { id: "r4", kind: "routine", group: "저녁", title: "영어 듣기", context: "설거지하며", state: "skipped", streak: 2 },
  { id: "r5", kind: "routine", group: "저녁", title: "일기 세 줄", context: "자기 전", state: "empty", streak: 8 },
  { id: "t1", kind: "task", group: "낮", title: "세금 신고 자료 모으기", weight: "heavy", due: 1, list: "집안일", state: "empty" },
  { id: "t2", kind: "task", group: "낮", title: "장보기 목록 정리", weight: "light", due: 0, list: "집안일", state: "empty" },
  { id: "t3", kind: "task", group: "낮", title: "치과 예약 전화", weight: "light", due: 5, list: "집안일", state: "done" },
  { id: "t4", kind: "task", group: "언제든", title: "여행 숙소 비교", weight: "heavy", due: 12, list: "여행 준비", state: "empty" },
];
const stateName = { empty: "안 함", done: "달성", rest: "쉼", skipped: "건너뜀" };
const monthName = { done: "달성", partial: "일부", missed: "미달", rest: "쉼" };
const monthState = { d: "done", p: "partial", m: "missed", r: "rest" };
const november = "rdddpddddrddmdddpddddrdd".padEnd(30, "d");

// streak은 어제까지의 기록이다. 오늘 달성하면 하루를 더한다.
const streakOf = (item) => item.streak + (item.state === "done" ? 1 : 0);
function dayState(item, day) {
  // 시작일 전에는 기록이 없다. 새 습관이 지난 신호등과 통계를 바꾸면 안 된다.
  if (item.startDay && day < item.startDay) return "";
  if (day === 23) return item.state === "done" || item.state === "rest" ? item.state : "";
  if (day > 23) return "";
  const missedDay = 22 - item.streak;
  if (day === missedDay) return "missed";
  return day > missedDay ? "done" : monthState[november[day - 1]];
}

// 그날의 신호등. 쉼은 분모에서 빼고, 전부 쉬면 쉼이다.
function dayLight(day) {
  const states = MOCK_ITEMS.filter((i) => i.kind === "routine").map((i) => dayState(i, day)).filter(Boolean);
  const counted = states.filter((s) => s !== "rest");
  if (!counted.length) return states.length ? "rest" : "";
  const done = counted.filter((s) => s === "done").length;
  return done === counted.length ? "done" : done ? "partial" : "missed";
}
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const mockIcon = (id, cls = "") => `<svg class="icon ${cls}"><use href="#i-${id}"/></svg>`;

function renderMacSidebar(active) {
  const link = (id, href, iconId, label, count = "") => `<a class="side-item ${id === active ? "is-active" : ""}" href="${href}" ${id === active ? 'aria-current="page"' : ""}>${mockIcon(iconId, "icon--sidebar")}<span class="side-item__label">${label}</span><span class="side-item__count" ${id === "today" ? "data-open-count" : ""}>${count}</span></a>`;
  const open = MOCK_ITEMS.filter((i) => i.state === "empty").length;
  document.querySelector("[data-mac-sidebar]").innerHTML = `
    ${link("today", "today.html", "today", "오늘", open)}
    ${link("calendar", "mac-calendar.html", "calendar", "캘린더")}
    ${link("focus", "mac-focus.html", "focus", "집중")}
    ${link("stats", "mac-stats.html", "stats", "통계")}
    <h2 class="side-title">목록</h2>
    ${link("inbox", "mac-command.html#add", "inbox", "수집함", 3)}
    ${link("home", "today.html", "list", "집안일", 5)}
    ${link("work", "today.html", "list", "회사", 8)}
    ${link("trip", "today.html", "list", "여행 준비", 2)}
    <a class="side-item side-item--command ${active === "command" ? "is-active" : ""}" href="${active === "command" ? "mac-command.html" : "mac-command.html?from=sidebar"}">${mockIcon("search", "icon--sidebar")}<span class="side-item__label">찾기와 명령</span><kbd class="menu__key">⌘K</kbd></a>`;
}

document.addEventListener("keydown", (event) => {
  if (event.metaKey && event.key.toLowerCase() === "k" && document.querySelector("[data-mac-sidebar]") && !location.pathname.endsWith("mac-command.html")) {
    event.preventDefault();
    location.href = "mac-command.html?from=shortcut";
  }
});

let toastTimer;
function showToast(text, undo) {
  document.querySelector(".toast--floating")?.remove();
  clearTimeout(toastTimer);
  const toast = document.createElement("div");
  toast.className = "toast toast--floating";
  toast.setAttribute("role", "status");
  toast.innerHTML = `<span></span>${undo ? '<button class="toast__action">실행 취소</button>' : ""}`;
  toast.firstElementChild.textContent = text;
  toast.querySelector("button")?.addEventListener("click", () => {
    toast.remove();
    undo();
  });
  document.body.append(toast);
  toastTimer = setTimeout(() => toast.remove(), 5000);
}

let closeOpenMenu = null;
function openMenu({ x, y, label, items, current, onPick, onClose }) {
  closeOpenMenu?.();
  const menu = document.createElement("div");
  menu.className = "menu menu--floating";
  menu.setAttribute("role", "menu");
  menu.setAttribute("aria-label", label);
  menu.innerHTML = items.map((item, i) => `<button class="menu__item ${item.value === current ? "is-current" : ""}" role="menuitem" tabindex="-1" data-menu-i="${i}">${item.mark}<span class="menu__label">${item.label}</span><kbd class="menu__key">${item.key}</kbd></button>`).join("");
  document.body.append(menu);
  const box = menu.getBoundingClientRect();
  menu.style.left = `${Math.max(0, Math.min(x, innerWidth - box.width))}px`;
  menu.style.top = `${Math.max(0, Math.min(y, innerHeight - box.height))}px`;
  const buttons = [...menu.children];
  (buttons[items.findIndex((item) => item.value === current)] ?? buttons[0]).focus();

  const outside = (event) => {
    if (!menu.contains(event.target)) close(true);
  };
  function close(notify) {
    menu.remove();
    document.removeEventListener("pointerdown", outside, true);
    closeOpenMenu = null;
    if (notify) onClose?.();
  }
  closeOpenMenu = () => close(false);
  document.addEventListener("pointerdown", outside, true);
  menu.addEventListener("click", (event) => {
    const button = event.target.closest("[data-menu-i]");
    if (!button) return;
    close(false);
    onPick(items[Number(button.dataset.menuI)].value);
  });
  menu.addEventListener("keydown", (event) => {
    const at = buttons.indexOf(document.activeElement);
    const direct = items.find((item) => item.key === event.key);
    if (event.key === "ArrowDown") buttons[(at + 1) % buttons.length].focus();
    else if (event.key === "ArrowUp") buttons[(at - 1 + buttons.length) % buttons.length].focus();
    else if (event.key === "Home") buttons[0].focus();
    else if (event.key === "End") buttons.at(-1).focus();
    else if (event.key === "Escape" || event.key === "Tab") close(true);
    else if (direct) {
      close(false);
      onPick(direct.value);
    } else return;
    event.preventDefault();
    event.stopPropagation();
  });
}

const BAND_START = { 아침: 6, 낮: 12, 저녁: 18 };
const pad = (n) => String(n).padStart(2, "0");
const bandOf = (time) => {
  const hour = Number(time.slice(0, 2));
  // 하루는 새벽 4시에 바뀐다. 그 전의 시각은 전날 저녁이다.
  if (hour < 4) return "저녁";
  return hour < 12 ? "아침" : hour < 18 ? "낮" : "저녁";
};

function pressChip(group, band) {
  group.querySelectorAll(".chip").forEach((item) => {
    item.setAttribute("aria-pressed", item.dataset.band === band);
  });
}

const smooth = () => (matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth");

// 스크롤로 굴리는 휠. loop면 항목을 세 벌 깔고 멈출 때 가운데 벌로 되돌린다.
function createWheel(el, labels, { loop, label, onPick }) {
  const count = labels.length;
  const copies = loop ? 3 : 1;
  const base = loop ? count : 0;
  let value = 0;
  let timer;
  let keyTarget = null; // 부드러운 스크롤 중 연속 키 입력의 목표 줄
  let keyDeadline = 0;
  el.innerHTML = Array.from({ length: count * copies }, (_, i) => `<div class="time-wheel__item" data-i="${i}">${labels[i % count]}</div>`).join("");
  el.tabIndex = 0;
  el.setAttribute("role", "spinbutton");
  el.setAttribute("aria-label", label);
  el.setAttribute("aria-valuemin", 0);
  el.setAttribute("aria-valuemax", count - 1);
  const rowHeight = () => el.firstElementChild.offsetHeight;

  function paint() {
    const row = rowHeight();
    if (!row) return;
    const center = el.scrollTop / row;
    const first = Math.max(0, Math.floor(center) - 3);
    const last = Math.min(el.children.length - 1, Math.ceil(center) + 3);
    for (let i = first; i <= last; i += 1) {
      const distance = i - center;
      const item = el.children[i];
      item.style.transform = `rotateX(${distance * -18}deg)`;
      item.style.opacity = Math.max(0.15, 1 - Math.abs(distance) * 0.34);
    }
  }

  function announce() {
    el.setAttribute("aria-valuenow", value);
    el.setAttribute("aria-valuetext", labels[value]);
  }

  function pick(next) {
    if (next === value) return;
    value = next;
    announce();
    onPick();
  }

  function settle() {
    const row = rowHeight();
    if (!row) return;
    // 키로 움직이는 중에는 목표 줄에 닿을 때까지 값을 스크롤 위치로 덮어쓰지 않는다.
    if (keyTarget !== null) {
      if (Math.abs(el.scrollTop - keyTarget * row) > 1) {
        if (Date.now() < keyDeadline) {
          timer = setTimeout(settle, 100);
          return;
        }
        el.scrollTop = keyTarget * row;
      }
      keyTarget = null;
    }
    const index = Math.round(el.scrollTop / row);
    const next = loop ? ((index % count) + count) % count : Math.min(count - 1, Math.max(0, index));
    if (loop && (index < count || index >= count * 2)) el.scrollTop = (count + next) * row;
    pick(next);
  }

  el.addEventListener("scroll", () => {
    requestAnimationFrame(paint);
    clearTimeout(timer);
    timer = setTimeout(settle, 100);
  });
  // 사용자가 직접 굴리면 키 입력의 목표를 버린다.
  for (const type of ["wheel", "pointerdown", "touchstart"]) {
    el.addEventListener(type, () => { keyTarget = null; }, { passive: true });
  }
  el.addEventListener("click", (event) => {
    const item = event.target.closest("[data-i]");
    if (item) el.scrollTo({ top: Number(item.dataset.i) * rowHeight(), behavior: smooth() });
  });
  el.addEventListener("keydown", (event) => {
    const step = { ArrowUp: -1, ArrowDown: 1 }[event.key];
    if (!step) return;
    event.preventDefault();
    const next = loop ? (value + step + count) % count : Math.min(count - 1, Math.max(0, value + step));
    if (next === value) return;
    const row = rowHeight();
    keyTarget = (keyTarget ?? Math.round(el.scrollTop / row)) + step;
    if (loop && (keyTarget < count / 2 || keyTarget >= count * 2.5)) {
      const shift = keyTarget < count / 2 ? count : -count;
      el.scrollTop += shift * row;
      keyTarget += shift;
    }
    keyDeadline = Date.now() + 1000;
    clearTimeout(timer);
    timer = setTimeout(settle, 100);
    el.scrollTo({ top: keyTarget * row, behavior: smooth() });
    pick(next);
  });
  announce();

  return {
    get value() { return value; },
    show(next) {
      value = next;
      announce();
      el.scrollTop = (base + next) * rowHeight();
      paint();
    },
  };
}

function setupPicker(root) {
  const el = root.querySelector("[data-time-picker]");
  const toggle = el.querySelector("[data-time-switch]");
  const dial = el.querySelector("[data-time-wheel]");
  const readout = el.querySelector("[data-time-value]");
  const chips = root.querySelector("[data-demo-chips]");
  let band = chips.querySelector('[aria-pressed="true"]').dataset.band;
  let time = "";

  const readWheels = () => {
    const hour = (wheels.hour.value + 1) % 12 + (wheels.period.value ? 12 : 0);
    return `${pad(hour)}:${pad(wheels.minute.value)}`;
  };
  const onPick = () => {
    time = readWheels();
    band = bandOf(time);
    pressChip(chips, band);
    render();
  };
  const wheels = {
    period: createWheel(el.querySelector('[data-wheel="period"]'), ["오전", "오후"], { loop: false, label: "오전 오후", onPick }),
    hour: createWheel(el.querySelector('[data-wheel="hour"]'), Array.from({ length: 12 }, (_, i) => String(i + 1)), { loop: true, label: "시", onPick }),
    minute: createWheel(el.querySelector('[data-wheel="minute"]'), Array.from({ length: 60 }, (_, i) => pad(i)), { loop: true, label: "분", onPick }),
  };

  function render() {
    el.hidden = !band;
    dial.hidden = !time;
    toggle.setAttribute("aria-checked", Boolean(time));
    if (!time) {
      readout.textContent = "";
      return;
    }
    const hour = Number(time.slice(0, 2));
    readout.textContent = `${hour < 12 ? "오전" : "오후"} ${hour % 12 || 12}:${time.slice(3)}`;
  }

  function showWheels() {
    render();
    if (!time) return;
    const hour = Number(time.slice(0, 2));
    wheels.period.show(hour < 12 ? 0 : 1);
    wheels.hour.show((hour + 11) % 12);
    wheels.minute.show(Number(time.slice(3)));
  }

  toggle.addEventListener("click", () => {
    time = time ? "" : `${pad(BAND_START[band])}:00`;
    showWheels();
  });
  render();

  return {
    // 시각이 새 시간대에 속하지 않으면 그 시간대의 시작으로 옮긴다.
    setBand(next) {
      band = next;
      if (!band) time = "";
      else if (time && bandOf(time) !== band) time = `${pad(BAND_START[band])}:00`;
      showWheels();
    },
  };
}


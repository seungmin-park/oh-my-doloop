// iPhone 목업 공용: 탭, 화면 사이 상태 유지, 처음 상태로 되돌리기.
const PHONE_ONLY = location.pathname.split("/").pop().startsWith("ios-")
  || new URLSearchParams(location.search).get("device") === "phone";
const PHONE_KEY = "doloop-phone-state";
const PHONE_TODAY = "today.html?device=phone";
let phoneClosing = { note: "", closed: false };
let phoneCalendar = {}; // 할 일 id별 { day, slot }

if (new URLSearchParams(location.search).get("device") === "mac") document.documentElement.dataset.device = "mac";
if (PHONE_ONLY) document.documentElement.dataset.device = "phone";
// 미리보기는 저장된 시안 상태를 읽지도 쓰지도 않는다.
if (PHONE_ONLY && !MOCK_EMBED) {
  try {
    const saved = JSON.parse(sessionStorage.getItem(PHONE_KEY) ?? "null");
    if (saved?.items?.length) MOCK_ITEMS.splice(0, MOCK_ITEMS.length, ...saved.items);
    if (saved?.closing) phoneClosing = saved.closing;
    if (saved?.calendar) phoneCalendar = saved.calendar;
    mockDayClosed = Boolean(phoneClosing.closed);
  } catch {
    // 저장값을 못 읽으면 처음 상태로 시작한다.
  }
}

// 뒤로 가기로 복원된 화면은 옛 상태를 들고 있으므로 저장값으로 다시 연다.
addEventListener("pageshow", (event) => {
  if (event.persisted && PHONE_ONLY && !MOCK_EMBED) location.reload();
});

function savePhoneState() {
  if (!PHONE_ONLY || MOCK_EMBED) return;
  try {
    sessionStorage.setItem(PHONE_KEY, JSON.stringify({ items: MOCK_ITEMS, closing: phoneClosing, calendar: phoneCalendar }));
  } catch {
    // 저장소를 못 쓰면 이 화면에서만 유지한다.
  }
}

function renderPhoneTabs(active) {
  const host = document.querySelector("[data-phone-tabs]");
  if (!host) return;
  const tabs = [
    ["today", PHONE_TODAY, "today", "오늘"],
    ["calendar", "ios-calendar.html", "calendar", "캘린더"],
    ["stats", "ios-stats.html", "stats", "통계"],
    ["closing", "ios-closing.html", "moon", "마감"],
  ];
  host.innerHTML = tabs.map(([id, href, iconId, label]) => `<a class="tab ${id === active ? "is-active" : ""}" href="${href}" ${id === active ? 'aria-current="page"' : ""}>${mockIcon(iconId, "icon--sidebar")}${label}</a>`).join("");
}

function initPhone(active) {
  renderPhoneTabs(active);
  if (!PHONE_ONLY) return;
  document.querySelector(".device--phone")?.setAttribute("data-toast-host", "");
  const tools = document.querySelector(".mock-tools");
  if (tools && !tools.querySelector("[data-phone-reset]")) {
    tools.insertAdjacentHTML("beforeend", '<button class="btn" data-phone-reset>시안 처음 상태로</button>');
    tools.querySelector("[data-phone-reset]").addEventListener("click", () => {
      try {
        sessionStorage.removeItem(PHONE_KEY);
      } catch {
        // 저장소를 못 쓰면 새로고침만 한다.
      }
      location.reload();
    });
  }
}

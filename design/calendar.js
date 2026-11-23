// 주간 시간표의 데이터와 규칙. Mac과 iPhone 캘린더가 같이 쓴다. 화면마다 render()를 둔다.
const DAYS = [["월", 23], ["화", 24], ["수", 25], ["목", 26], ["금", 27], ["토", 28], ["일", 29]];
const SLOTS = 32; // 07:00부터 23:00까지 30분 칸
const toSlot = (h, m = 0) => (h - 7) * 2 + m / 30;
const slotTime = (slot) => `${String(7 + Math.floor(slot / 2)).padStart(2, "0")}:${slot % 2 ? "30" : "00"}`;
const span = (task) => (task.weight === "heavy" ? 2 : 1);
const minutes = (task) => span(task) * 30;

const routineBlocks = [
  { id: "r1", slot: toSlot(7, 30) }, { id: "r2", slot: toSlot(8) }, { id: "r3", slot: toSlot(18, 30) },
  { id: "r4", slot: toSlot(20) }, { id: "r5", slot: toSlot(22) },
].map((b) => ({ ...b, title: MOCK_ITEMS.find((i) => i.id === b.id).title, n: 1 }));

const fixedFor = (day) => [
  ...(day < 5 ? [{ title: "회사", slot: toSlot(9), n: 18 }] : []),
  ...(day === 3 ? [{ title: "저녁 약속", slot: toSlot(20, 30), n: 3 }] : []),
];

const tasks = [
  { id: "t2", title: "장보기 목록 정리", weight: "light", day: 0, slot: toSlot(19) },
  { id: "t1", title: "세금 신고 자료 모으기", weight: "heavy", day: 1, slot: toSlot(19) },
  { id: "t3", title: "치과 예약 전화", weight: "light", day: 5, slot: toSlot(10) },
  { id: "c1", title: "발표 자료 초안", weight: "heavy", day: 3, slot: null },
  { id: "c2", title: "보고서 검토", weight: "heavy", day: 3, slot: null },
  { id: "c3", title: "회의 준비", weight: "heavy", day: 3, slot: null },
  { id: "c4", title: "메일 정리", weight: "light", day: 3, slot: null },
  { id: "t4", title: "여행 숙소 비교", weight: "heavy", day: null, slot: null },
  { id: "p1", title: "책장 정리", weight: "heavy", day: null, slot: null },
  { id: "p2", title: "택배 반품", weight: "light", day: null, slot: null },
  { id: "p3", title: "세차 예약", weight: "light", day: null, slot: null },
];
let picked = null;

const load = (day) => tasks.filter((t) => t.day === day).reduce((sum, t) => sum + minutes(t), 0);
const free = (day) => SLOTS * 30 - [...fixedFor(day), ...routineBlocks].reduce((sum, b) => sum + b.n * 30, 0);
const hours = (m) => String(m / 60);
const duration = durationText;
const overDay = () => DAYS.findIndex((_, day) => load(day) > free(day));

function busy(day, slot, n, ignore) {
  const blocks = [...fixedFor(day), ...routineBlocks, ...tasks.filter((t) => t.day === day && t.slot !== null && t !== ignore).map((t) => ({ slot: t.slot, n: span(t) }))];
  return blocks.some((b) => slot < b.slot + b.n && b.slot < slot + n);
}

function place(task, day, slot) {
  const n = span(task);
  const start = Math.max(0, Math.min(SLOTS - n, slot));
  if (busy(day, start, n, task)) {
    showToast(`${DAYS[day][1]}일 ${slotTime(start)}에는 다른 일이 있습니다`);
    return;
  }
  const before = { day: task.day, slot: task.slot };
  Object.assign(task, { day, slot: start });
  picked = null;
  render();
  showToast(`${task.title}을 ${DAYS[day][1]}일 ${slotTime(start)}에 놓았습니다`, () => {
    Object.assign(task, before);
    render();
  });
}

const slotAt = (column, clientY) => {
  const box = column.getBoundingClientRect();
  return Math.floor(((clientY - box.top) / box.height) * SLOTS);
};

// 넘친 날에서 시간을 안 정한 가장 가벼운 일을 다음 날로 옮긴다.
function relieveDay(day) {
  const task = tasks.filter((t) => t.day === day && t.slot === null).sort((a, b) => span(a) - span(b))[0];
  if (!task || day === 6) {
    showToast("옮길 수 있는 일이 없습니다");
    return;
  }
  task.day = day + 1;
  render();
  showToast(`${task.title}을 ${DAYS[day + 1][1]}일로 옮겼습니다`, () => {
    task.day = day;
    render();
  });
}

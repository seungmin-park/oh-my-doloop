// 습관 통계. Mac과 iPhone 통계 화면이 같이 쓴다.
const DAYS_SO_FAR = 23;

// 쉼은 실패가 아니므로 달성률의 분모에서 뺀다. 오늘은 달성했을 때만 센다.
function summary(item) {
  const states = Array.from({ length: DAYS_SO_FAR }, (_, n) => dayState(item, n + 1)).filter(Boolean);
  const count = (s) => states.filter((x) => x === s).length;
  const counted = count("done") + count("partial") + count("missed");
  return { done: count("done"), rest: count("rest"), rate: counted ? Math.round((count("done") / counted) * 100) : null };
}

function statMonth(item) {
  const blanks = '<span class="month__cell month__cell--blank"></span>'.repeat(6);
  const cells = Array.from({ length: 30 }, (_, n) => {
    const day = n + 1;
    const s = dayState(item, day);
    return `<span class="month__cell ${s ? `month__cell--${s}` : ""} ${day === 23 ? "is-today" : ""}" role="img" aria-label="11월 ${day}일${s ? ` ${monthName[s]}` : ""}">${day}</span>`;
  }).join("");
  return `<div class="month">${blanks}${cells}</div>`;
}

function statCard(item) {
  const s = summary(item);
  return `<article class="stat-card"><header class="stat-card__head"><div><h2 class="row__title">${escapeHtml(item.title)}</h2><span class="row__context">${escapeHtml(item.context)}</span></div><strong class="stat-card__rate ${s.rate === null ? "stat-card__rate--empty" : ""}">${s.rate === null ? (s.rest ? "쉼만 기록" : "기록 전") : `${s.rate}%`}</strong></header>${statMonth(item)}<p class="stat-card__foot">${streakOf(item)}일 연속, 이번 달 ${s.done}일 달성, ${s.rest}일 쉼</p></article>`;
}

function renderStats(root) {
  const habits = MOCK_ITEMS.filter((i) => i.kind === "routine");
  const all = habits.map(summary);
  const totalDone = all.reduce((sum, s) => sum + s.done, 0);
  const totalRest = all.reduce((sum, s) => sum + s.rest, 0);
  // 기록이 없는 습관은 평균에 넣지 않는다.
  const rated = all.filter((s) => s.rate !== null);
  const average = rated.length ? `${Math.round(rated.reduce((sum, s) => sum + s.rate, 0) / rated.length)}%` : "없음";
  const longest = Math.max(...habits.map(streakOf));
  const longestName = habits.find((h) => streakOf(h) === longest).title;
  root.innerHTML = `
  <header class="screen-bar"><h1 class="large-title">11월</h1><div class="screen-bar__actions"><span class="legend"><i class="light light--done"></i>달성</span><span class="legend"><i class="light light--partial"></i>일부</span><span class="legend"><i class="light light--missed"></i>미달</span><span class="legend"><i class="light light--rest"></i>쉼</span></div></header>
  <dl class="stat-line">
    <div><dt>평균 달성률</dt><dd>${average}</dd></div>
    <div><dt>달성한 횟수</dt><dd>${totalDone}번</dd></div>
    <div><dt>쉰 횟수</dt><dd>${totalRest}번</dd></div>
    <div><dt>${escapeHtml(longestName)}</dt><dd>${longest}일 연속</dd></div>
  </dl>
  <div class="stat-grid">${habits.map(statCard).join("")}</div>`;
}

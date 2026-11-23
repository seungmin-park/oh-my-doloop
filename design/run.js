// 루틴 순서대로 실행. Mac 집중 화면과 iPhone 루틴 실행이 같이 쓴다.
let steps = [];
let current = 0;
let left = 0;
let running = false;
let timer = null;
let runOptions = {};

const clock = (s) => `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
const finished = () => current >= steps.length;
const nextOpen = (from) => {
  let index = from;
  while (index < steps.length && steps[index].state !== "empty") index += 1;
  return index;
};

function mark(state) {
  if (state === "done") return `<span class="status status--done">${mockIcon("check", "icon-check")}</span>`;
  if (state === "rest") return `<span class="status status--rest">${mockIcon("rest", "icon-rest")}</span>`;
  return state === "skipped" ? '<span class="status status--skipped"></span>' : '<span class="status"></span>';
}

function renderSteps() {
  const list = document.querySelector("[data-steps]");
  if (list) {
    list.innerHTML = `<h2 class="detail__title">저녁 루틴</h2><p class="detail__sub">${steps.filter((s) => s.state !== "empty").length}/${steps.length} 끝남</p>
    <ol class="step-list">${steps.map((s, i) => `<li class="step ${i === current ? "is-current" : ""}" ${i === current ? 'aria-current="step"' : ""}>${mark(s.state)}<span class="step__main"><span class="row__title">${escapeHtml(s.title)}</span><span class="row__context">${escapeHtml(s.context)}</span></span><span class="row__meta">${s.minutes}분</span></li>`).join("")}</ol>`;
  }
  const strip = document.querySelector("[data-step-strip]");
  if (strip) {
    strip.innerHTML = steps.map((s, i) => `<li class="run-strip__item ${i === current ? "is-current" : ""}" ${i === current ? 'aria-current="step"' : ""}>${mark(s.state)}<span class="sr-only">${escapeHtml(s.title)}: ${stateName[s.state]}</span></li>`).join("");
  }
}

function renderMain() {
  const root = document.querySelector("[data-focus]");
  if (finished()) {
    const done = steps.filter((s) => s.state === "done").length;
    const restart = runOptions.allowRestart ? '<button class="btn btn--primary" data-restart>처음부터 다시</button>' : "";
    root.innerHTML = `<div class="empty"><p class="empty__title">저녁 루틴을 마쳤습니다</p><p class="empty__text">${steps.length}개 중 ${done}개를 달성했습니다.</p>${restart}<a class="btn btn--link" href="${runOptions.homeHref}">오늘로 돌아가기</a></div>`;
    return;
  }
  const step = steps[current];
  const total = step.minutes * 60;
  const timeUp = left === 0;
  root.innerHTML = `<p class="focus-step">${timeUp ? "시간이 끝났습니다. 했는지 골라 주세요." : `${current + 1}번째, ${steps.length}개 중`}</p>
    <h1 class="large-title">${escapeHtml(step.title)}</h1>
    <p class="detail__sub">${escapeHtml(step.context)}</p>
    <div class="focus-ring" role="timer" aria-label="남은 시간">
      <svg viewBox="0 0 120 120" aria-hidden="true"><circle class="focus-ring__track" cx="60" cy="60" r="54" pathLength="100"/><circle class="focus-ring__value" data-ring cx="60" cy="60" r="54" pathLength="100" stroke-dasharray="${Math.min(100, (left / total) * 100)} 100"/></svg>
      <span class="focus-ring__time" data-clock>${clock(left)}</span>
    </div>
    <div class="focus-actions">
      <button class="btn" data-skip>건너뛰기</button>
      ${timeUp ? '<button class="btn btn--primary btn--wide" data-extend>5분 더</button>' : `<button class="btn btn--primary btn--wide" data-play>${running ? "일시정지" : left < total ? "이어서" : "시작"}</button>`}
      <button class="btn" data-done>달성하고 다음</button>
    </div>`;
}

function render() {
  renderMain();
  renderSteps();
}

function stop() {
  running = false;
  clearInterval(timer);
}

function advance(state) {
  stop();
  document.querySelector("[data-live]").textContent = "";
  steps[current].state = state;
  runOptions.onRecord?.(steps[current], state);
  current = nextOpen(current + 1);
  if (!finished()) left = steps[current].minutes * 60;
  render();
}

function tick() {
  left -= 1;
  // 시간이 끝나도 달성으로 기록하지 않는다. 사용자가 고른다.
  if (left <= 0) {
    left = 0;
    stop();
    renderMain();
    document.querySelector("[data-live]").textContent = `${steps[current].title} 시간이 끝났습니다. 했는지 골라 주세요.`;
    return;
  }
  document.querySelector("[data-clock]").textContent = clock(left);
  document.querySelector("[data-ring]").setAttribute("stroke-dasharray", `${Math.min(100, (left / (steps[current].minutes * 60)) * 100)} 100`);
}

document.addEventListener("click", (e) => {
  if (e.target.closest("[data-play]")) {
    if (running) stop();
    else {
      running = true;
      timer = setInterval(tick, 1000);
    }
    renderMain();
  } else if (e.target.closest("[data-extend]")) {
    left = 300;
    document.querySelector("[data-live]").textContent = "";
    running = true;
    timer = setInterval(tick, 1000);
    renderMain();
  } else if (e.target.closest("[data-done]")) advance("done");
  else if (e.target.closest("[data-skip]")) advance("skipped");
  else if (e.target.closest("[data-restart]")) {
    steps.forEach((s) => { s.state = "empty"; });
    current = 0;
    left = steps[0].minutes * 60;
    render();
  }
});

function startRun(list, options) {
  steps = list;
  runOptions = options;
  current = nextOpen(0);
  left = finished() ? 0 : steps[current].minutes * 60;
  render();
}

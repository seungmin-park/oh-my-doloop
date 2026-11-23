// 습관·할 일 편집 폼. Mac 편집 화면과 iPhone 편집 시트가 같이 쓴다.
const FORM_WEEK = ["월", "화", "수", "목", "금", "토", "일"];

const chipRow = (label, attr, options, value) => `<span class="chips" role="group" aria-label="${label}" ${attr}>${options.map(([v, text]) => `<button type="button" class="chip" aria-pressed="${v === value}" data-value="${escapeHtml(v)}">${text}</button>`).join("")}</span>`;

function whenRow(item) {
  const band = item.group === "언제든" ? "" : item.group;
  return `<div class="form-row" data-time-root><span class="form-row__label">언제</span>
    <span class="form-row__value form-row__stack">
      <span class="chips" role="group" aria-label="시간대" data-demo-chips>${[["아침", "아침"], ["낮", "낮"], ["저녁", "저녁"], ["", "안 정함"]].map(([v, text]) => `<button type="button" class="chip" aria-pressed="${v === band}" data-band="${v}">${text}</button>`).join("")}</span>
      <div class="time-picker time-picker--form" data-time-picker>
        <div class="time-picker__head">
          <span>정확한 시각 <span class="time-picker__value" data-time-value></span></span>
          <button type="button" class="switch" role="switch" aria-checked="false" aria-label="정확한 시각 사용" data-time-switch><span class="switch__thumb"></span></button>
        </div>
        <div class="time-wheel" data-time-wheel hidden>
          <span class="time-wheel__band"></span>
          <div class="time-wheel__col" data-wheel="period"></div>
          <div class="time-wheel__col" data-wheel="hour"></div>
          <div class="time-wheel__col" data-wheel="minute"></div>
        </div>
      </div>
    </span></div>`;
}

function formFields(item) {
  const title = `<label class="form-row"><span class="form-row__label">이름</span>
    <span class="form-row__value"><input class="text-input" name="title" value="${escapeHtml(item.title)}" aria-describedby="title-error"><span class="form-error" id="title-error" data-title-error hidden>이름을 입력하세요</span></span></label>`;
  if (item.kind === "task") {
    return `${title}
      <div class="form-row"><span class="form-row__label">목록</span><span class="form-row__value">${chipRow("목록", "data-single data-field=list", ["집안일", "회사", "여행 준비", "수집함"].map((v) => [v, v]), item.list)}</span></div>
      <div class="form-row"><span class="form-row__label">무게</span><span class="form-row__value">${chipRow("무게", "data-single data-field=weight", [["heavy", "무거움, 1시간 이상"], ["light", "가벼움, 30분 이내"]], item.weight)}</span></div>
      ${whenRow(item)}`;
  }
  return `${title}
    <label class="form-row"><span class="form-row__label">상황</span>
      <span class="form-row__value"><input class="text-input" name="context" value="${escapeHtml(item.context)}"></span></label>
    <div class="form-row"><span class="form-row__label">작게·크게</span>
      <span class="form-row__value form-row__pair"><input class="text-input" aria-label="작은 목표" placeholder="작은 목표" value="${escapeHtml(item.mini ?? "")}"><input class="text-input" aria-label="큰 목표" placeholder="큰 목표" value="${escapeHtml(item.maxi ?? "")}"></span></div>
    <div class="form-row"><span class="form-row__label">하루 횟수</span>
      <span class="form-row__value stepper"><button type="button" class="btn" data-count="-1" aria-label="하루 횟수 줄이기">−</button><output data-count-value>1</output><button type="button" class="btn" data-count="1" aria-label="하루 횟수 늘리기">+</button></span></div>
    <div class="form-row"><span class="form-row__label">반복</span>
      <span class="form-row__value form-row__stack">
        <span class="chips" role="group" aria-label="반복 방식" data-repeat>
          <button type="button" class="chip" aria-pressed="true" data-kind="daily">매일</button>
          <button type="button" class="chip" aria-pressed="false" data-kind="days">요일 지정</button>
          <button type="button" class="chip" aria-pressed="false" data-kind="weekly">주 n회</button>
        </span>
        <span class="weekdays" role="group" aria-label="반복 요일" data-weekdays></span>
        <span class="stepper" data-weekly hidden><button type="button" class="btn" data-weekly-step="-1" aria-label="주 횟수 줄이기">−</button><output data-weekly-value>3</output><span>회</span><button type="button" class="btn" data-weekly-step="1" aria-label="주 횟수 늘리기">+</button></span>
        <span class="form-error" data-weekday-error hidden>요일을 하나 이상 고르세요</span>
      </span></div>
    ${whenRow(item)}
    <div class="form-row"><span class="form-row__label">묶음</span>
      <span class="form-row__value">${chipRow("루틴 묶음", "data-single data-field=bundle", [["아침", "아침 루틴"], ["저녁", "저녁 루틴"], ["", "없음"]], ["아침", "저녁"].includes(item.group) ? item.group : "")}</span></div>`;
}

function setupHabitForm(form, item, { onSave, onDirty = () => {} }) {
  const q = (selector) => form.querySelector(selector);
  const isRoutine = item.kind === "routine";
  const picked = new Set([0, 1, 2, 3, 4, 5, 6]);
  let kind = "daily";
  let count = 1;
  let weekly = 3;
  const picker = setupPicker(q("[data-time-root]"), onDirty);
  if (item.time) picker.setTime(item.time);

  function renderRepeat() {
    if (!isRoutine) return;
    form.querySelectorAll("[data-repeat] .chip").forEach((chip) => chip.setAttribute("aria-pressed", chip.dataset.kind === kind));
    const days = q("[data-weekdays]");
    days.hidden = kind !== "days";
    days.innerHTML = FORM_WEEK.map((w, i) => `<button type="button" class="weekday" aria-pressed="${picked.has(i)}" data-weekday="${i}" aria-label="${w}요일">${w}</button>`).join("");
    q("[data-weekly]").hidden = kind !== "weekly";
    q("[data-weekly-value]").textContent = weekly;
    q("[data-count-value]").textContent = count;
    q("[data-weekday-error]").hidden = kind !== "days" || picked.size > 0;
  }

  form.addEventListener("input", onDirty);
  form.addEventListener("click", (e) => {
    const band = e.target.closest("[data-demo-chips] .chip");
    const repeat = e.target.closest("[data-repeat] .chip");
    const day = e.target.closest("[data-weekday]");
    const step = e.target.closest("[data-count]");
    const weeklyStep = e.target.closest("[data-weekly-step]");
    const single = e.target.closest("[data-single] .chip");
    if (band || repeat || day || step || weeklyStep || single || e.target.closest("[data-time-switch]")) onDirty();
    if (band) {
      pressChip(band.parentElement, band.dataset.band);
      picker.setBand(band.dataset.band);
    } else if (repeat) {
      kind = repeat.dataset.kind;
      renderRepeat();
    } else if (day) {
      const i = Number(day.dataset.weekday);
      if (picked.has(i)) picked.delete(i);
      else picked.add(i);
      renderRepeat();
      q(`[data-weekday="${i}"]`).focus();
    } else if (step) {
      count = Math.min(9, Math.max(1, count + Number(step.dataset.count)));
      renderRepeat();
    } else if (weeklyStep) {
      weekly = Math.min(6, Math.max(1, weekly + Number(weeklyStep.dataset.weeklyStep)));
      renderRepeat();
    } else if (single) {
      single.parentElement.querySelectorAll(".chip").forEach((chip) => chip.setAttribute("aria-pressed", chip === single));
    }
  });

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const title = form.elements.title;
    const missing = !title.value.trim();
    q("[data-title-error]").hidden = !missing;
    title.setAttribute("aria-invalid", missing);
    if (missing) {
      title.focus();
      return;
    }
    if (isRoutine && kind === "days" && picked.size === 0) {
      q("[data-weekday-error]").hidden = false;
      return;
    }
    const field = (name) => q(`[data-field="${name}"] [aria-pressed="true"]`)?.dataset.value;
    const { band, time } = picker.value();
    onSave({ title: title.value.trim(), group: band || "언제든", time, list: field("list"), weight: field("weight") });
  });
  renderRepeat();
}

// 기기 안에서 아래로부터 올라오는 편집 시트.
function openEditSheet(device, item, { onSave, onClose }) {
  const isRoutine = item.kind === "routine";
  const heading = isRoutine ? "습관 고치기" : "할 일 고치기";
  const note = isRoutine ? "저장하면 내일부터 적용됩니다. 지난 기록과 통계는 바뀌지 않습니다." : "저장하면 바로 적용됩니다.";
  const layer = document.createElement("div");
  layer.className = "sheet-layer";
  layer.innerHTML = `<form class="sheet sheet--form form" role="dialog" aria-modal="true" aria-label="${heading}" tabindex="-1" data-form novalidate>
    <span class="sheet__handle"></span>
    <header class="sheet-head"><button type="button" class="btn" data-sheet-cancel>취소</button><h2 class="popover__title">${heading}</h2><button class="btn btn--primary">저장</button></header>
    ${formFields(item)}
    <p class="form-foot__note">${note}</p>
  </form>`;
  const behind = [...device.children];
  behind.forEach((el) => { el.inert = true; });
  device.append(layer);
  const form = layer.querySelector("form");
  let dirty = false;
  let pressedBackdrop = false;

  function onKey(e) {
    if (e.key !== "Escape") return;
    e.preventDefault();
    attemptClose();
  }
  function close() {
    document.removeEventListener("keydown", onKey);
    layer.remove();
    behind.forEach((el) => { el.inert = false; });
    onClose?.();
  }
  // 고친 내용이 있으면 바깥을 눌러도 닫지 않는다.
  function attemptClose() {
    if (dirty) showToast("저장하거나 취소를 누르세요");
    else close();
  }

  document.addEventListener("keydown", onKey);
  layer.addEventListener("pointerdown", (e) => { pressedBackdrop = e.target === layer; });
  layer.addEventListener("click", (e) => {
    if (e.target === layer && pressedBackdrop) attemptClose();
    if (e.target.closest("[data-sheet-cancel]")) close();
  });
  setupHabitForm(form, item, {
    onDirty: () => { dirty = true; },
    onSave: (values) => {
      close();
      onSave(values);
    },
  });
  form.focus();
}

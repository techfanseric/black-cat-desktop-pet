// 启动两个黑猫实例：首屏的小猫和下面的大画布。

import { DesktopCat } from "./app.js";
import { GESTURES } from "./pet.js";

window.addEventListener("error", (event) => {
  console.error("黑猫桌宠启动失败:", event.message, event.filename, event.lineno);
});

const hint = document.querySelector("#hint");
const statusKey = document.querySelector("#status-key");
const statusDesc = document.querySelector("#status-desc");
const liveIndicator = document.querySelector("#live-indicator");

const STATUS = {
  [GESTURES.listen]: ["耳朵动了", "指针从侧面靠近时，它会转一下耳朵"],
  [GESTURES.groom]: ["在舔爪子", "安静够久，它会抬起爪子舔两下"],
  [GESTURES.scratch]: ["被抓到了", "在它旁边来回逗，它会伸爪划过屏幕"]
};

function describe(cat) {
  const behavior = cat.behavior;
  if (behavior.gesture) {
    const entry = STATUS[behavior.gesture.kind];
    if (entry) return entry;
  }
  if (behavior.enjoying > 0.4) return ["被摸得很舒服", "指针停在两耳之间，它会眯眼侧脸蹭你"];
  if (behavior.typingActivity > 0.35) return ["跟着你敲键盘", "键帽会亮起来，键名也会浮出来"];
  if (cat.pointerActivity > 0.5) return ["在握鼠标", "它会跟着指针移动，屏幕四角是极限位置"];
  return ["等待输入", "猫会盯住指针，也会追着你的手指敲键盘"];
}

function refreshStatus(cat) {
  const entry = describe(cat);
  statusKey.textContent = entry[0];
  statusDesc.textContent = entry[1];
}

// 任务系统：把五种互动变成可以收集的小目标。
const QUESTS = ["type", "mouse", "pet", "tease", "idle"];
const questState = new Set();
const questItems = new Map();
document.querySelectorAll("#quests li").forEach((item) => {
  questItems.set(item.dataset.quest, item);
});
const questBarFill = document.querySelector("#quest-bar-fill");
const questCount = document.querySelector("#quest-count");
const questClear = document.querySelector("#quest-clear");

function completeQuest(name) {
  if (questState.has(name)) return;
  questState.add(name);
  const item = questItems.get(name);
  if (item) item.classList.add("is-done");
  questBarFill.style.width = `${(questState.size / QUESTS.length) * 100}%`;
  questCount.textContent = `${questState.size} / ${QUESTS.length}`;
  if (questState.size === QUESTS.length) {
    questClear.classList.add("is-on");
  }
}

function attach(cat, { focusOnKey = false } = {}) {
  const canvas = cat.canvas;
  canvas.addEventListener("pointerdown", () => {
    canvas.focus();
    if (focusOnKey) hint.classList.add("is-hidden");
  });
  return cat;
}

const petCanvas = document.querySelector("#pet-canvas");
const petOverlay = document.querySelector("#pet-overlay");
const pet = new DesktopCat(petCanvas, {
  overlay: petOverlay,
  onGesture: () => {
    refreshStatus(pet);
  }
});
attach(pet, { focusOnKey: true });
pet.start();
window.blackCat = pet;

const heroCanvas = document.querySelector("#hero-canvas");
const hero = new DesktopCat(heroCanvas);
hero.start();

window.addEventListener("keydown", () => refreshStatus(pet));
window.addEventListener("pointermove", () => refreshStatus(pet));
setInterval(() => {
  refreshStatus(pet);
  const behavior = pet.behavior;
  const gesture = behavior.gesture;
  if (pet.typingActivity > 0.35) completeQuest("type");
  if (pet.pointerActivity > 0.5) completeQuest("mouse");
  if (behavior.enjoying > 0.4) completeQuest("pet");
  if (gesture && gesture.kind === GESTURES.scratch) completeQuest("tease");
  if (gesture && gesture.kind === GESTURES.groom) completeQuest("idle");
}, 250);

document.querySelectorAll(".controls .chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    if (chip.dataset.demo) {
      pet.behavior.start(GESTURES[chip.dataset.demo], performance.now() / 1000, chip.dataset.demo === "scratch" ? 1 : -1, true);
      refreshStatus(pet);
      return;
    }
    document.querySelectorAll(".controls .chip").forEach((other) => other.classList.remove("is-on"));
    chip.classList.add("is-on");
    const value = chip.dataset.pose;
    pet.fixedDesign = value === "auto" ? null : Number(value);
  });
});

const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        liveIndicator.textContent = "运行中";
        pet.start();
      }
    }
  },
  { threshold: 0.2 }
);
observer.observe(petCanvas);

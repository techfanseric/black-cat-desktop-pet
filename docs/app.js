// 介绍页的互动层：接上真实键盘、指针和触摸，再交给黑猫引擎。

import { drawCat, keyPosition, point, blend, clamp, ease, clawPath } from "./cat.js";
import { Behavior, GESTURES } from "./pet.js";

const ART_WIDTH = 280;
const ART_HEIGHT = 240;
const CAP_LIFETIME = 0.52;

const KEY_LABELS = {
  Backquote: "`", Digit1: "1", Digit2: "2", Digit3: "3", Digit4: "4", Digit5: "5",
  Digit6: "6", Digit7: "7", Digit8: "8", Digit9: "9", Digit0: "0",
  Minus: "-", Equal: "=", Backspace: "⌫", Tab: "⇥",
  KeyQ: "Q", KeyW: "W", KeyE: "E", KeyR: "R", KeyT: "T", KeyY: "Y", KeyU: "U",
  KeyI: "I", KeyO: "O", KeyP: "P", BracketLeft: "[", BracketRight: "]", Backslash: "\\",
  KeyA: "A", KeyS: "S", KeyD: "D", KeyF: "F", KeyG: "G", KeyH: "H", KeyJ: "J",
  KeyK: "K", KeyL: "L", Semicolon: ";", Quote: "'", Enter: "⏎",
  ShiftLeft: "⇧", ShiftRight: "⇧", KeyZ: "Z", KeyX: "X", KeyC: "C", KeyV: "V",
  KeyB: "B", KeyN: "N", KeyM: "M", Comma: ",", Period: ".", Slash: "/",
  ControlLeft: "⌃", ControlRight: "⌃", AltLeft: "⌥", AltRight: "⌥",
  MetaLeft: "⌘", MetaRight: "⌘", Space: "␣", ArrowLeft: "←", ArrowRight: "→",
  ArrowUp: "↑", ArrowDown: "↓", Escape: "Esc", CapsLock: "⇪"
};

// 只回显真正能打印出来的字符，修饰键和功能键不进便签。
const PRINTABLE = /^[a-zA-Z0-9 !"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]$/;

export class DesktopCat {
  constructor(canvas, options = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.overlay = options.overlay ?? null;
    this.overlayCtx = this.overlay ? this.overlay.getContext("2d") : null;
    this.behavior = new Behavior();
    this.fixedDesign = options.fixedDesign ?? null;
    this.caps = [];
    this.strokes = [null, null];
    this.gaze = point(0, 0);
    this.pointerActivity = 0;
    this.typingActivity = 0;
    this.mouseOffset = point(0, 0);
    this.mouseUntil = 0;
    this.pointer = null;
    this.clientX = window.innerWidth / 2;
    this.clientY = window.innerHeight / 2;
    this.hasPointer = false;
    this.headCenter = point(146, 84);
    this.headZone = { x: 146, y: 84, radius: 30 };
    this.lastSample = performance.now() / 1000;
    this.startTime = performance.now() / 1000;
    this.onGesture = options.onGesture || (() => {});
    this.scratchMarks = [];
    this.frame = () => this.tick();
    this.delta = point(0, 0);
    this.speed = 0;
    this.travel = 0;
    this.windowTravel = 0;
    this.speedWindowStart = 0;
    this.screenPosition = null;
    this.headTouch = null;
    this.pressed = false;
    this.buttons = 0;
    this.overCanvas = false;
    this.previousPointer = null;
    this.lastGestureKind = null;
    this.typed = "";
    this.onType = options.onType || (() => {});
    this.headScreen = null;
    this.onFrame = options.onFrame || (() => {});
    this.bind();
  }

  bind() {
    // 指针在整个页面都要感应：猫是桌宠，指针在哪它都该看着。
    window.addEventListener("pointermove", (event) => this.handlePointerMove(event), { passive: true });
    window.addEventListener("pointerdown", (event) => this.handlePointerMove(event), { passive: true });
    window.addEventListener("pointerup", () => { this.buttons = 0; });
    window.addEventListener("pointercancel", () => { this.buttons = 0; });
    window.addEventListener("keydown", (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const label = KEY_LABELS[event.code];
      if (!label) return;
      event.preventDefault();
      if (PRINTABLE.test(event.key ?? "")) {
        this.typed = (this.typed + event.key).slice(-42);
        this.onType(this.typed);
      }
      this.hit(label);
    });
  }

  artworkPoint(event) {
    const rect = this.canvas.getBoundingClientRect();
    const scale = Math.min(rect.width / ART_WIDTH, rect.height / ART_HEIGHT);
    const offsetX = (rect.width - ART_WIDTH * scale) / 2;
    const offsetY = (rect.height - ART_HEIGHT * scale) / 2;
    // 指针在画布外时，坐标会落在美术范围之外。用一个标记区分两种情况：
    // 在画布内才算摸头，视线则始终按方向计算，两种情况都会跟着指针。
    const inside =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;
    this.overCanvas = inside;
    return point(
      (event.clientX - rect.left - offsetX) / scale,
      (event.clientY - rect.top - offsetY) / scale
    );
  }

  handlePointerMove(event) {
    const art = this.artworkPoint(event);
    this.pointer = art;
    this.hasPointer = true;
    this.clientX = event.clientX;
    this.clientY = event.clientY;
    this.buttons = event.buttons;
    // 和 Swift 版映射整个桌面一样，这里映射整个视口，
    // 猫的小鼠标才会跟着指针在整页范围内走，而不是只在画布里。
    this.screenPosition = {
      x: clamp(event.clientX / Math.max(1, window.innerWidth), 0, 1),
      y: clamp(event.clientY / Math.max(1, window.innerHeight), 0, 1)
    };
    // 只有指针真的落在猫身上时才算摸头。
    this.headTouch = this.overCanvas ? this.headHit(art) : null;
  }

  // 头部区域固定在耳朵之间，避免姿态漂移导致判定忽隐忽现。
  headHit(art) {
    const headX = 146;
    const headY = 80;
    const across = (art.x - headX) / 32;
    const vertical = (art.y - headY + 6) / 28;
    return Math.hypot(across, vertical) <= 1 ? across : null;
  }

  hit(label) {
    const time = performance.now() / 1000;
    const last = this.caps[this.caps.length - 1];
    if (last && last.label === label && time - last.time < 0.08) return;
    this.caps.push({ label, time });
    if (this.caps.length > 5) this.caps.shift();
    const position = keyPosition(label);
    const slot = position.x < 155 && time >= this.mouseUntil && this.pointerActivity < 0.8 ? 0 : 1;
    this.strokes[slot] = { label, time };
  }

  update(time) {
    const now = time;
    this.pressed = this.buttons > 0;
    const lastKeyAge = this.caps.length ? now - this.caps[this.caps.length - 1].time : 1;
    const typingTarget = lastKeyAge < 0.36 ? 1 : 0;
    const speed = this.hasPointer ? this.speed : 0;
    // 摸头判定：指针在头部附近，且这次移动的幅度不大，属于“轻轻摸”。
    // 和 Swift 版一致：速度阈值 440（Swift 是 30fps，即每帧约 14.7 像素）。
    const gentle = this.speed < 440;
    const touch = this.headTouch !== null && this.headTouch !== undefined && gentle && typingTarget === 0 ? this.headTouch : null;
    this.lastTouch = touch;
    if (touch === null && (speed > 0 || this.pressed)) this.mouseUntil = now + 0.55;
    const target = touch === null ? (now < this.mouseUntil ? 1 : 0) : this.pointerActivity > 0.5 ? 1 : 0;
    this.pointerActivity += (target - this.pointerActivity) * (target > 0 ? 0.27 : 0.17);
    if (target > 0 && touch === null && this.screenPosition) {
      const desired = point(-0.115 + 0.156 * this.screenPosition.x, -0.34 + 0.68 * this.screenPosition.y);
      const coupling = clamp((this.pointerActivity - 0.45) / 0.45, 0, 1);
      this.mouseOffset.x += (desired.x - this.mouseOffset.x) * coupling;
      this.mouseOffset.y += (desired.y - this.mouseOffset.y) * coupling;
    }
    this.behavior.update(now, {
      speed,
      scroll: false,
      down: this.pressed,
      typing: typingTarget > 0,
      fixed: this.fixedDesign,
      // 只有指针在猫附近时才参与逗猫判定，指针在页面别处不会误触发。
      pointer: this.pointer,
      headTouch: touch,
      gentle
    });
    this.behavior.typingActivity = this.typingActivity;
    this.typingActivity += (typingTarget - this.typingActivity) * 0.28;
    // 视线按「指针相对猫的方向」算，和 Swift 版一致：指针在页面任何位置，
    // 猫都会朝那边看，而不是只有指针落在画布里才有反应。
    const rect = this.canvas.getBoundingClientRect();
    const dx = this.clientX - (rect.left + rect.width / 2);
    const dy = rect.top + rect.height * 0.31 - this.clientY;
    const distance = Math.max(95, Math.hypot(dx, dy));
    const look = point((dx / distance) * 8, (dy / distance) * 8);
    this.gaze = point(this.gaze.x * 0.75 + look.x * 0.25, this.gaze.y * 0.75 + look.y * 0.25);
    this.caps = this.caps.filter((cap) => now - cap.time < 0.6);
    const gesture = this.behavior.gesture;
    if (gesture && gesture.kind === "scratch" && gesture.markAlpha > 0) {
      const existing = this.scratchMarks[this.scratchMarks.length - 1];
      if (!existing || now - existing.time > 0.25) {
        this.scratchMarks.push({ time: now, alpha: gesture.markAlpha });
      }
    }
    this.scratchMarks = this.scratchMarks.filter((mark) => now - mark.time < 1.2);
  }

  draw(time) {
    const ctx = this.ctx;
    const rect = this.canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (this.canvas.width !== Math.round(rect.width * dpr) || this.canvas.height !== Math.round(rect.height * dpr)) {
      this.canvas.width = Math.round(rect.width * dpr);
      this.canvas.height = Math.round(rect.height * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, rect.width, rect.height);
    const scale = Math.min(rect.width / ART_WIDTH, rect.height / ART_HEIGHT);
    ctx.save();
    ctx.translate((rect.width - ART_WIDTH * scale) / 2, (rect.height - ART_HEIGHT * scale) / 2);
    ctx.scale(scale, scale);

    const pose = {
      mouse: this.pointerActivity,
      gaze: point(this.gaze.x / 8, this.gaze.y / 8),
      blink: Math.max(0, 1 - Math.abs((time % 4.35) - 0.13) / 0.13),
      keyPress: 0,
      leftPress: 0,
      excitement: Math.min(1, this.caps.length / 4) + this.behavior.weights[2] * 0.5,
      phase: time * 10,
      mix: this.behavior.weights,
      gesture: this.behavior.gesture,
      scratchOverlay: Boolean(this.overlay),
      mouseOffset: this.mouseOffset,
      enjoying: this.behavior.enjoying,
      cheek: this.behavior.cheek
    };
    for (const [index, event] of this.strokes.entries()) {
      if (!event) continue;
      const age = Math.max(0, time - event.time);
      const strength = clamp(age / 0.045, 0, 1) * clamp((0.32 - age) / 0.14, 0, 1);
      const target = keyPosition(event.label);
      if (index === 0) {
        pose.leftTarget = target;
        pose.leftPress = strength;
      } else {
        pose.rightTarget = target;
        pose.keyPress = strength;
      }
    }
    pose.gaze.y = Math.min(1, pose.gaze.y * (1 - this.typingActivity) + this.typingActivity * 0.9);
    this.headCenter = drawCat(ctx, this.behavior.selected, pose);
    // 猫头的实际位置，给气泡用，这样气泡不会挡住脸。
    this.headScreen = {
      x: (rect.width - ART_WIDTH * scale) / 2 + this.headCenter.x * scale,
      y: (rect.height - ART_HEIGHT * scale) / 2 + this.headCenter.y * scale
    };

    // 键名标签画在猫之后，避免被身体盖住。
    for (const [index, cap] of this.caps.entries()) {
      const age = Math.max(0, time - cap.time);
      if (age >= CAP_LIFETIME) continue;
      const target = keyPosition(cap.label);
      const width = cap.label.length > 2 ? 26 : 20;
      const x = target.x + ((index % 3) - 1) * 6;
      const y = 163 - age * 27 - (index % 2) * 6;
      ctx.save();
      ctx.globalAlpha = clamp((CAP_LIFETIME - age) * 5, 0, 1);
      ctx.fillStyle = "rgba(25.5, 28.1, 33.2, 0.75)";
      roundedRect(ctx, x - width / 2, y + 1.4, width, 15, 4);
      ctx.fill();
      ctx.fillStyle = "rgba(247.4, 249.4, 244.8, 1)";
      roundedRect(ctx, x - width / 2, y, width, 15, 4);
      ctx.fill();
      ctx.fillStyle = "rgba(25.5, 28.1, 33.2, 1)";
      ctx.font = `${cap.label.length > 2 ? 8 : 10}px ui-sans-serif, "PingFang SC", system-ui, sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(cap.label, x, y + 7);
      ctx.restore();
    }
    ctx.restore();
    this.drawOverlay(time);
    this.onFrame(this);
  }

  // 抓痕留在整块屏幕上，而不是只留在猫那一小块画布里。
  drawOverlay(time) {
    if (!this.overlayCtx) return;
    const ctx = this.overlayCtx;
    const rect = this.overlay.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (this.overlay.width !== Math.round(rect.width * dpr) || this.overlay.height !== Math.round(rect.height * dpr)) {
      this.overlay.width = Math.round(rect.width * dpr);
      this.overlay.height = Math.round(rect.height * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, rect.width, rect.height);
    const gesture = this.behavior.gesture;
    if (!gesture || gesture.kind !== "scratch") return;
    const side = gesture.side;
    const progress = gesture.slash;
    if (progress <= 0.001) return;
    const scale = Math.min(rect.width / ART_WIDTH, rect.height / ART_HEIGHT);
    const offsetX = (rect.width - ART_WIDTH * scale) / 2;
    const offsetY = (rect.height - ART_HEIGHT * scale) / 2;
    const toScreen = (art) => point(offsetX + art.x * scale, offsetY + art.y * scale);
    const start = toScreen(clawPath(side, 0));
    const end = toScreen(clawPath(side, progress));
    const control = toScreen(point(clawPath(side, 0).x + side * 10.5 * progress, clawPath(side, 0).y + 28.5 * progress));
    const alpha = gesture.markAlpha;
    ctx.lineCap = "round";
    for (const tine of [-1, 0, 1]) {
      const offset = tine * 4 * scale;
      for (const [paint, width] of [
        [`rgba(30.6, 30.6, 30.6, ${0.5 * alpha})`, 3],
        [`rgba(255, 255, 255, ${0.85 * alpha})`, 1.4]
      ]) {
        ctx.beginPath();
        ctx.moveTo(start.x + offset, start.y - 2 * scale);
        ctx.quadraticCurveTo(control.x + offset, control.y - 2 * scale, end.x + offset, end.y - 2 * scale);
        ctx.strokeStyle = paint;
        ctx.lineWidth = width;
        ctx.stroke();
      }
    }
  }

  tick() {
    const time = performance.now() / 1000;
    const elapsed = Math.max(0.001, time - this.lastSample);
    // 位移和速度用屏幕像素算，指针在页面任何位置都成立。
    if (this.hasPointer && this.lastClient) {
      const dx = this.clientX - this.lastClient.x;
      const dy = this.clientY - this.lastClient.y;
      this.delta = point(dx, dy);
      this.travel = Math.hypot(dx, dy);
      // Swift 版用固定 30fps 定时器算速度，浏览器是 rAF（约 60fps）。
      // 这里统一按 1/30 秒算，阈值才和 Swift 版一致。
      this.speed = this.travel / (1 / 30);
    } else {
      this.delta = point(0, 0);
      this.travel = 0;
      this.speed = 0;
    }
    this.lastClient = { x: this.clientX, y: this.clientY };
    this.lastSample = time;
    this.update(time);
    this.draw(time);
    const gesture = this.behavior.gesture;
    if (gesture && gesture.kind !== this.lastGestureKind) {
      this.lastGestureKind = gesture.kind;
      this.onGesture(gesture.kind);
    } else if (!gesture) {
      this.lastGestureKind = null;
    }
    requestAnimationFrame(this.frame);
  }

  start() {
    requestAnimationFrame(this.frame);
  }
}

function roundedRect(ctx, x, y, width, height, radius) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + width, y, x + width, y + height, radius);
  ctx.arcTo(x + width, y + height, x, y + height, radius);
  ctx.arcTo(x, y + height, x, y, radius);
  ctx.arcTo(x, y, x + width, y, radius);
  ctx.closePath();
}

export { KEY_LABELS };

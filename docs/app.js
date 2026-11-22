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
    this.desiredMouseOffset = point(0, 0);
    this.mouseUntil = 0;
    this.pointer = null;
    this.headCenter = point(146, 84);
    this.headZone = { x: 146, y: 84, radius: 30 };
    this.lastPointer = null;
    this.lastSample = performance.now() / 1000;
    this.startTime = performance.now() / 1000;
    this.onGesture = options.onGesture || (() => {});
    this.pointerInside = false;
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
    this.previousPointer = null;
    this.lastGestureKind = null;
    this.typed = "";
    this.onType = options.onType || (() => {});
    this.headScreen = null;
    this.onFrame = options.onFrame || (() => {});
    this.bind();
  }

  bind() {
    this.canvas.addEventListener("pointermove", (event) => this.handlePointerMove(event));
    this.canvas.addEventListener("pointerdown", (event) => this.handlePointerMove(event));
    this.canvas.addEventListener("pointerleave", () => {
      this.pointerInside = false;
      this.pointer = null;
    });
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
    return point(
      (event.clientX - rect.left - offsetX) / scale,
      (event.clientY - rect.top - offsetY) / scale
    );
  }

  handlePointerMove(event) {
    const art = this.artworkPoint(event);
    this.pointer = art;
    this.pointerInside = true;
    const rect = this.canvas.getBoundingClientRect();
    this.screenPosition = {
      x: clamp((event.clientX - rect.left) / rect.width, 0, 1),
      y: clamp((event.clientY - rect.top) / rect.height, 0, 1)
    };
    // 头部区域固定在耳朵之间，避免姿态漂移导致判定忽隐忽现。
    const headX = 146;
    const headY = 80;
    const across = (art.x - headX) / 32;
    const vertical = (art.y - headY + 6) / 28;
    this.headTouch = Math.hypot(across, vertical) <= 1 ? across : null;
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
    const lastKeyAge = this.caps.length ? now - this.caps[this.caps.length - 1].time : 1;
    const typingTarget = lastKeyAge < 0.36 ? 1 : 0;
    const speed = this.lastPointer ? this.speed : 0;
    // 摸头判定：指针在头部附近，且这次移动的幅度不大，属于“轻轻摸”。
    // 阈值按美术单位计，网页上一次轻微摆动约 18 单位。
    const gentle = this.travel < 26;
    const touch = this.headTouch !== null && this.headTouch !== undefined && gentle && typingTarget === 0 ? this.headTouch : null;
    this.lastTouch = touch;
    if (touch === null && (speed > 0 || this.pressed)) this.mouseUntil = now + 0.55;
    const target = touch === null ? (now < this.mouseUntil ? 1 : 0) : this.pointerActivity > 0.5 ? 1 : 0;
    this.pointerActivity += (target - this.pointerActivity) * (target > 0 ? 0.27 : 0.17);
    if (touch === null && speed > 0) {
      this.desiredMouseOffset.x = clamp(this.desiredMouseOffset.x + this.delta.x * 0.00077, -0.115, 0.041);
      this.desiredMouseOffset.y = clamp(this.desiredMouseOffset.y + this.delta.y * 0.0027, -0.34, 0.34);
    }
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
      pointer: this.pointer,
      headTouch: touch,
      gentle
    });
    this.behavior.typingActivity = this.typingActivity;
    this.typingActivity += (typingTarget - this.typingActivity) * 0.28;
    const look = this.pointer
      ? point(clamp((this.pointer.x - 140) / 45, -1, 1) * 8, clamp((this.pointer.y - 92) / 45, -1, 1) * 8)
      : point(0, 0);
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
    const pointer = this.pointer;
    if (pointer && this.lastPointer) {
      const dx = pointer.x - this.lastPointer.x;
      const dy = pointer.y - this.lastPointer.y;
      this.delta = point(dx, dy);
      const travel = Math.hypot(dx, dy);
      this.travel = travel;
      // 浏览器只在指针移动时派发事件，所以单帧位移就是这次移动的真实距离。
      this.speed = travel / elapsed;
    } else {
      this.delta = point(0, 0);
      this.travel = 0;
      this.recentTravel = 0;
      this.speed = 0;
    }
    this.lastPointer = pointer;
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

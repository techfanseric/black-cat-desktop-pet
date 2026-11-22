// 网页版黑猫的行为状态机，移植自 Swift 版 BlackCatBehavior.swift。

import { clamp } from "./cat.js";

export const GESTURES = { listen: "listen", groom: "groom", scratch: "scratch" };

const DURATION = { listen: 0.85, groom: 2.45, scratch: 2.05 };

export class GestureFrame {
  constructor(kind, side) {
    this.kind = kind;
    this.age = 0;
    this.side = side;
    this.strength = 1;
  }

  ramp(start, end) {
    const unit = clamp((this.age - start) / (end - start), 0, 1);
    return unit * unit * (3 - 2 * unit);
  }

  get lift() {
    if (this.kind === "listen") return 0;
    if (this.kind === "groom") return this.strength * (this.ramp(0, 0.52) - this.ramp(1.94, 2.45));
    return this.ramp(0.13, 0.44) - this.ramp(0.66, 1.04);
  }

  get lick() {
    if (this.kind !== "groom") return 0;
    return this.strength * (this.ramp(0.58, 0.81) - this.ramp(0.83, 1.05) + this.ramp(1.27, 1.52) - this.ramp(1.54, 1.78));
  }

  get ear() {
    if (this.kind !== "listen") return 0;
    return this.ramp(0, 0.14) - this.ramp(0.22, 0.48) + 0.42 * (this.ramp(0.48, 0.57) - this.ramp(0.57, 0.85));
  }

  get slash() {
    return this.kind === "scratch" ? this.ramp(0.44, 0.66) : 0;
  }

  get markAlpha() {
    return this.slash > 0 ? 1 - this.ramp(1, 2.05) : 0;
  }
}

export class Behavior {
  constructor() {
    this.activity = null;
    this.curiousUntil = 0;
    this.alertUntil = 0;
    this.tracking = 0;
    this.lastTick = null;
    this.lastClick = -10;
    this.buttonDown = false;
    this.gestureStart = 0;
    this.cancelledAt = null;
    this.demonstrating = false;
    this.gesture = null;
    this.groomed = false;
    this.nextScratch = 0;
    this.nextListen = 0;
    this.near = false;
    this.extremeX = 0;
    this.direction = 0;
    this.turns = 0;
    this.lastLeg = 0;
    this.touchTime = 0;
    this.enjoying = 0;
    this.cheek = 0;
    this.selected = 0;
    this.weights = [1, 0, 0, 0];
  }

  update(time, { speed = 0, scroll = false, down = false, typing = false, fixed = null, pointer = null, headTouch = null, gentle = true }) {
    const elapsed = Math.min(0.12, Math.max(0.001, time - (this.lastTick ?? time - 1 / 30)));
    this.lastTick = time;
    if (time < (this.activity ?? Infinity)) this.activity = time;
    const moved = speed > 12;

    const stroking = headTouch !== null && !typing && !scroll && gentle && this.gesture?.kind !== "scratch" && !(this.gesture && this.demonstrating);
    this.touchTime = stroking ? this.touchTime + elapsed : 0;
    const content = this.touchTime >= 0.33;
    const rate = content ? 7 : 5;
    this.enjoying += ((content ? 1 : 0) - this.enjoying) * (1 - Math.exp(-elapsed * rate));
    if (headTouch !== null && stroking) this.cheek += (headTouch - this.cheek) * (1 - Math.exp(-elapsed * 8));

    if (moved || scroll || down || typing || stroking) this.activity = time;
    if (down && !this.buttonDown) {
      if (time - this.lastClick < 0.38) this.alertUntil = time + 1.15;
      this.lastClick = time;
    }
    this.buttonDown = down;
    if (speed > 1750) this.alertUntil = time + 0.95;
    this.tracking = moved ? Math.min(1, this.tracking + elapsed) : Math.max(0, this.tracking - elapsed * 2);
    if (scroll || down || this.tracking > 0.17) this.curiousUntil = time + 0.55;

    if (fixed !== null) this.selected = fixed;
    else if (this.alertUntil > time) this.selected = 2;
    else if (typing || content) this.selected = 0;
    else if (this.curiousUntil > time) this.selected = 1;
    else if (time - (this.activity ?? time) >= 35) this.selected = 3;
    else this.selected = 0;

    const target = [0, 0, 0, 0];
    target[this.selected] = 1;
    const blendRate = this.selected === 3 ? 2.2 : 7.2;
    const factor = 1 - Math.exp(-elapsed * blendRate);
    this.weights = this.weights.map((weight, index) => weight + (target[index] - weight) * factor);

    const busy = moved || down || scroll || typing || stroking;
    if (busy) this.groomed = false;
    if (this.gesture) {
      if (this.gesture.kind === "groom" && busy && !this.demonstrating && this.cancelledAt === null) this.cancelledAt = time;
      this.gesture.age = (this.cancelledAt ?? time) - this.gestureStart;
      if (this.cancelledAt !== null) this.gesture.strength = Math.max(0, 1 - (time - this.cancelledAt) / 0.2);
      this.gesture = this.gesture.age >= DURATION[this.gesture.kind] || this.gesture.strength <= 0 ? null : this.gesture;
    }
    if (!this.groomed && !this.gesture && time - (this.activity ?? time) >= 12 && time - (this.activity ?? time) < 35) {
      this.start(GESTURES.groom, time, -1);
    }

    if (!pointer || typing || scroll || down || stroking) {
      this.near = false;
      this.turns = 0;
      return;
    }
    // 逗猫区覆盖猫身左右两侧，比头部判定大得多。
    const distance = Math.hypot((pointer.x - 140) / 96, (pointer.y - 112) / 88);
    if (distance > (this.near ? 1.18 : 1)) {
      this.near = false;
      this.turns = 0;
      return;
    }
    const side = pointer.x < 140 ? -1 : 1;
    // 头部区域归摸头所有，不参与逗弄判定。
    const onHead = Math.hypot((pointer.x - 146) / 32, (pointer.y - 80 + 6) / 28) <= 1;
    if (!this.near || time - this.lastLeg > 0.95) {
      if (!this.near && moved && time >= this.nextListen && !this.gesture && !onHead) {
        this.start(GESTURES.listen, time, side);
      }
      this.direction = 0;
      this.turns = 0;
      this.extremeX = pointer.x;
      this.lastLeg = time;
    }
    this.near = true;
    if (onHead) {
      this.direction = 0;
      this.turns = 0;
      this.extremeX = pointer.x;
      this.lastLeg = time;
      return;
    }
    const delta = pointer.x - this.extremeX;
    if (this.direction * delta > 0) this.extremeX = pointer.x;
    if (Math.abs(delta) < 23 || this.direction * delta > 0) return;
    if (this.direction !== 0) this.turns += 1;
    this.direction = delta < 0 ? -1 : 1;
    this.extremeX = pointer.x;
    this.lastLeg = time;
    if (this.turns >= 2 && time >= this.nextScratch && (!this.gesture || (this.gesture.kind === "listen" && !this.demonstrating))) {
      this.start(GESTURES.scratch, time, side);
      this.turns = 0;
    }
  }

  start(kind, time, side, demo = false) {
    this.gesture = new GestureFrame(kind, side);
    this.gestureStart = time;
    this.cancelledAt = null;
    this.demonstrating = demo;
    if (kind === GESTURES.listen) this.nextListen = time + 3;
    if (kind === GESTURES.scratch) this.nextScratch = time + 6;
    if (kind === GESTURES.groom) this.groomed = true;
  }
}

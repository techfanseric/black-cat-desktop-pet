// 网页版黑猫桌宠引擎。绘制逻辑从 Swift 版 BlackCat.swift 移植，保持同一套几何与手感。

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const lerp = (a, b, t) => a + (b - a) * t;
const ease = (value) => {
  const unit = clamp(value, 0, 1);
  return unit * unit * (3 - 2 * unit);
};
const point = (x, y) => ({ x, y });
const blend = (start, end, amount) => point(lerp(start.x, end.x, amount), lerp(start.y, end.y, amount));

const COLORS = {
  fur: "rgba(19.2, 19.7, 21.7, 1)",
  lime: "rgba(201.5, 232.1, 79.1, 1)",
  keyFace: "rgba(248.4, 248.4, 241.0, 1)",
  gold: "rgba(249.9, 188.7, 51.2, 1)",
  seam: "rgba(66.3, 67.7, 67.7, 1)",
  edge: "rgba(81.6, 81.6, 86.7, 1)",
  tongue: "rgba(232.1, 140.3, 150.2, 1)"
};

const KEY_ROWS = [
  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
  ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
  ["A", "S", "D", "F", "G", "H", "J", "K", "L", "⏎"],
  ["⇧", "Z", "X", "C", "V", "B", "N", "M", ",", "."],
  ["⌃", "⌥", "⌘", "␣", "⌘", "⌥", "←", "→"]
];

export { KEY_ROWS };

function desk(across, depth, height = 0) {
  const perspective = 1 + depth * 0.12;
  return point(
    160 + (across * 151) / perspective + depth * 5,
    202 + (depth * -32 + across * 7 - height) / perspective
  );
}

function keyCenter(row, column) {
  const offset = row === 4 && column === 4 ? 0.1745 : 0.0335;
  return desk(-0.452 + column * 0.0708 + offset, -0.26 + row * 0.17 + 0.079, 4.2);
}

// 键盘键位到 artwork 坐标的映射，和 Swift 版 keyPosition 保持一致。
function keyPosition(label) {
  for (let row = 0; row < KEY_ROWS.length; row += 1) {
    const index = KEY_ROWS[row].indexOf(label);
    if (index < 0) continue;
    const bottom = [12, 11, 10, 4, 3, 2, 1, 0];
    return keyCenter(row, row === 4 ? bottom[index] : 12 - index);
  }
  return keyCenter(2, 1);
}

function makeInk(ctx) {
  return {
    shape(paint, draw) {
      ctx.beginPath();
      draw(ctx);
      ctx.closePath();
      ctx.fillStyle = paint;
      ctx.fill();
    },
    stroke(paint, width, draw) {
      ctx.beginPath();
      draw(ctx);
      ctx.strokeStyle = paint;
      ctx.lineWidth = width;
      ctx.stroke();
    },
    oval(paint, x, y, width, height) {
      ctx.beginPath();
      ctx.ellipse(x + width / 2, y + height / 2, width / 2, height / 2, 0, 0, Math.PI * 2);
      ctx.fillStyle = paint;
      ctx.fill();
    }
  };
}

// 爪子在屏幕上的划动轨迹，网页版用它把抓痕画到整块屏幕上。
function clawPath(side, progress) {
  return point(140 + side * (48 + 21 * progress + 12 * progress * progress), 53 + 57 * progress);
}

export function drawCat(ctx, design, pose) {
  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  const ink = makeInk(ctx);
  const reach = clamp(pose.mouse, 0, 1);
  const press = clamp(pose.keyPress, 0, 1);
  const preset = [0, 0, 0, 0];
  preset[design] = 1;
  const weights = pose.mix || preset;
  const mix = (values) => values.reduce((sum, value, index) => sum + value * weights[index], 0);

  const shift = mix([25, 26, 33, 24]);
  const torsoWidth = mix([34, 29, 37, 38]);
  const headSize = mix([0.96, 0.9, 1.01, 0.99]);
  const headY = mix([84, 73, 92, 91]);
  const tilt = mix([-0.045, -0.075, -0.19, 0.085]);
  const weight = ease(reach / 0.84);
  const settled = ease((reach - 0.6) / 0.4);
  const stepping = Math.sin(Math.PI * reach);
  const pressing = ease(press);

  const mouseCenter = desk(-0.588 + pose.mouseOffset.x, 0.115 + pose.mouseOffset.y, 3);
  const mouseRest = desk(-0.588, 0.115, 3);
  const nuzzle = pose.enjoying * (pose.cheek * 5 + 1.4 * Math.sin(pose.phase * 0.28));

  const gesture = pose.gesture;
  const grooming = gesture && gesture.kind === "groom" ? gesture.lift : 0;
  const swiping = gesture && gesture.kind === "scratch" ? gesture.lift : 0;
  const side = gesture ? gesture.side : -1;
  const lick = gesture ? gesture.lick : 0;
  const stroke = gesture ? gesture.slash : 0;

  const claw = (progress) => clawPath(side, progress);

  function body(across, level) {
    const upper = ease(level);
    const lean = -5 * grooming + side * swiping * (11 + 5 * stroke);
    const follow = (mouseCenter.x - mouseRest.x) * 0.44 * settled + nuzzle;
    const center = 146 + (lean + follow - shift * weight) * upper + 3.5 * settled * (1 - upper);
    const widening = 1 + 0.08 * stepping * Math.sin(Math.PI * level) + 0.035 * pressing;
    const rise = (mouseCenter.y - mouseRest.y) * 0.27 * settled - 4 * pose.enjoying;
    return point(
      center + across * widening,
      178 +
        (headY - 178) * level +
        upper * (rise + 4 * stepping + 1.7 * settled + 2.8 * pressing + 8 * grooming + 3 * lick - 6 * swiping)
    );
  }

  const head = body(0, 1);
  const hip = body(0, 0);
  ink.oval("rgba(0, 0, 0, 0.10)", hip.x - 39, 180, 85, 10);

  const tailLift = mix([0, 0, -9, 7]) + Math.sin(pose.phase) * pose.excitement * 6 + pose.enjoying * (3 * Math.sin(pose.phase * 0.26) - 5);
  ink.stroke(COLORS.fur, 9, (path) => {
    path.moveTo(hip.x + 17, hip.y - 9);
    path.bezierCurveTo(hip.x + 58, hip.y + 2, hip.x + 49, hip.y - 33 + tailLift, hip.x + 75, hip.y - 33 + tailLift);
  });

  ink.shape(COLORS.fur, (path) => {
    path.moveTo(body(-18, 0.83).x, body(-18, 0.83).y);
    path.bezierCurveTo(body(-17, 0.68).x, body(-17, 0.68).y, body(-torsoWidth - 4, 0.33).x, body(-torsoWidth - 4, 0.33).y, body(-torsoWidth, 0.13).x, body(-torsoWidth, 0.13).y);
    path.bezierCurveTo(body(-torsoWidth, 0.025).x, body(-torsoWidth, 0.025).y, body(-25, -0.09).x, body(-25, -0.09).y, body(-15, -0.055).x, body(-15, -0.055).y);
    path.bezierCurveTo(body(-8, -0.027).x, body(-8, -0.027).y, body(7, -0.02).x, body(7, -0.02).y, body(15, -0.055).x, body(15, -0.055).y);
    path.bezierCurveTo(body(31, -0.12).x, body(31, -0.12).y, body(torsoWidth + 3, -0.025).x, body(torsoWidth + 3, -0.025).y, body(torsoWidth, 0.11).x, body(torsoWidth, 0.11).y);
    path.bezierCurveTo(body(torsoWidth + 3, 0.37).x, body(torsoWidth + 3, 0.37).y, body(17, 0.64).x, body(17, 0.64).y, body(19, 0.84).x, body(19, 0.84).y);
  });

  const highlight = [];
  if (pose.leftTarget && pose.leftPress > 0.65) highlight.push(pose.leftTarget);
  if (pose.rightTarget && press > 0.65) highlight.push(pose.rightTarget);
  drawDesk(ink, highlight, mouseCenter);

  const mouseStep = ease((reach - 0.1) / 0.85);
  const keyStep = ease((press - 0.06) / 0.91);
  let left = blend(point(133, 184), point(mouseCenter.x, mouseCenter.y - 2), mouseStep);
  let right = blend(point(158, 184), pose.rightTarget || desk(0.14, 0.16, 4), keyStep);
  left.y -= 8 * Math.sin(Math.PI * mouseStep);
  if (pose.leftTarget) left = blend(left, pose.leftTarget, ease(pose.leftPress));
  right.y -= 4 * Math.sin(Math.PI * keyStep);

  const leftLift = grooming + (side < 0 ? swiping : 0);
  const rightLift = side > 0 ? swiping : 0;
  const pawAtMouth = point(head.x - 22, head.y + 22 * headSize);
  left = blend(blend(left, point(head.x - 37, head.y + 48), grooming), claw(stroke), side < 0 ? swiping : 0);
  right = blend(right, claw(stroke), rightLift);

  // 有独立覆盖层时，抓痕由覆盖层画在整块屏幕上，避免两处重复。
  if (gesture && gesture.markAlpha > 0 && !pose.scratchOverlay) {
    for (const tine of [-1, 0, 1]) {
      const offset = tine * 4;
      const start = claw(0);
      const end = claw(stroke);
      const control = point(start.x + side * 10.5 * stroke, start.y + 28.5 * stroke);
      const paints = [
        [`rgba(30.6, 30.6, 30.6, ${0.67 * gesture.markAlpha})`, 2.5],
        [`rgba(255, 255, 255, ${0.91 * gesture.markAlpha})`, 1.1]
      ];
      for (const [paint, width] of paints) {
        ink.stroke(paint, width, (path) => {
          path.moveTo(start.x + offset, start.y - 2);
          path.quadraticCurveTo(control.x + offset, control.y - 2, end.x + offset, end.y - 2);
        });
      }
    }
  }

  const tip = (paw, angle, x, y) =>
    point(paw.x + x * Math.cos(angle) - y * Math.sin(angle), paw.y + x * Math.sin(angle) + y * Math.cos(angle));
  const leftAngle = side < 0 ? 2.55 * swiping : 0;
  const rightAngle = -2.55 * rightLift;
  const lp = (x, y) => tip(left, leftAngle, x, y);
  const rp = (x, y) => tip(right, rightAngle, x, y);
  const leftAxilla = body(-13, 0.27 + 0.23 * mouseStep);
  const rightAxilla = body(13, 0.27 + 0.14 * keyStep);
  const leftWrist = lp(-5, -4);
  const rightWrist = rp(5, -4);

  ink.shape(COLORS.fur, (path) => {
    path.moveTo(body(-20, 0.92).x, body(-20, 0.92).y);
    path.bezierCurveTo(body(-19, 0.83).x, body(-19, 0.83).y, body(-22, 0.75).x, body(-22, 0.75).y, body(-23, 0.68).x, body(-23, 0.68).y);
    path.bezierCurveTo(body(-24, 0.61).x, body(-24, 0.61).y, blend(lp(-5 + 11 * mouseStep, -24), lp(-5, -8), grooming).x, blend(lp(-5 + 11 * mouseStep, -24), lp(-5, -8), grooming).y, leftWrist.x, leftWrist.y);
    path.bezierCurveTo(lp(-6.5 - 2 * mouseStep, -1).x, lp(-6.5 - 2 * mouseStep, -1).y, lp(-6.8, 3.6).x, lp(-6.8, 3.6).y, lp(-2, 4.1).x, lp(-2, 4.1).y);
    path.bezierCurveTo(lp(2.7, 4.6).x, lp(2.7, 4.6).y, lp(5.5, 2.5).x, lp(5.5, 2.5).y, lp(5.5, -1.6).x, lp(5.5, -1.6).y);
    path.bezierCurveTo(lp(5.5, -10 - 13 * swiping).x, lp(5.5, -10 - 13 * swiping).y, leftAxilla.x - 3 - 8 * mouseStep - 12 * leftLift, leftAxilla.y + 16 - 9 * leftLift, leftAxilla.x, leftAxilla.y);
    path.bezierCurveTo(leftAxilla.x + 3, leftAxilla.y - 8, body(-9, 0.15).x, body(-9, 0.15).y, body(0, 0.15).x, body(0, 0.15).y);
    path.bezierCurveTo(body(10, 0.15).x, body(10, 0.15).y, rightAxilla.x - 3, rightAxilla.y - 8, rightAxilla.x, rightAxilla.y);
    path.bezierCurveTo(rightAxilla.x + 3 + 20 * rightLift, rightAxilla.y + 9 - 9 * rightLift, rp(-5.5, -11 - 13 * rightLift).x, rp(-5.5, -11 - 13 * rightLift).y, rp(-5.5, -2).x, rp(-5.5, -2).y);
    path.bezierCurveTo(rp(-5.5, 2).x, rp(-5.5, 2).y, rp(-3, 4.6).x, rp(-3, 4.6).y, rp(1.5, 4.2).x, rp(1.5, 4.2).y);
    path.bezierCurveTo(rp(6.5, 4).x, rp(6.5, 4).y, rp(7, 0).x, rp(7, 0).y, rightWrist.x, rightWrist.y);
    path.bezierCurveTo(rp(5 - 3 * keyStep, -21).x, rp(5 - 3 * keyStep, -21).y, body(25, 0.6).x, body(25, 0.6).y, body(23, 0.68).x, body(23, 0.68).y);
    path.bezierCurveTo(body(21, 0.76).x, body(21, 0.76).y, body(19, 0.85).x, body(19, 0.85).y, body(20, 0.92).x, body(20, 0.92).y);
  });

  for (const [paw, pawSide, amount] of [
    [left, -1, Math.max(mouseStep, leftLift)],
    [right, 1, Math.max(keyStep, rightLift)]
  ]) {
    const anchor = body(pawSide * 8, 0.23);
    ink.stroke(`rgba(66.3, 67.7, 67.7, ${0.7 * (1 - amount)})`, 0.65, (path) => {
      path.moveTo(paw.x - pawSide * 4.5, paw.y - 3);
      path.quadraticCurveTo(paw.x - pawSide * 4.2, paw.y - 12, anchor.x, anchor.y);
    });
  }

  for (const [paw, angle, sign, opacity] of [
    [left, leftAngle, -1, 1 - grooming],
    [right, rightAngle, 1, 1]
  ]) {
    const pad = (x, y) => tip(paw, angle, sign * x, y);
    ink.stroke(`rgba(81.6, 81.6, 86.7, ${0.82 * opacity})`, 0.95, (path) => {
      path.moveTo(pad(4.8, -6).x, pad(4.8, -6).y);
      path.quadraticCurveTo(pad(7, -1).x, pad(7, -1).y, pad(4.9, 2).x, pad(4.9, 2).y);
      path.quadraticCurveTo(pad(1.2, 6).x, pad(1.2, 6).y, pad(-4.4, 2.6).x, pad(-4.4, 2.6).y);
    });
    ink.stroke(`rgba(81.6, 81.6, 86.7, ${0.64 * opacity})`, 0.8, (path) => {
      path.moveTo(pad(1.3, 3.4).x, pad(1.3, 3.4).y);
      path.quadraticCurveTo(pad(2, 1.4).x, pad(2, 1.4).y, pad(1, -0.3).x, pad(1, -0.3).y);
    });
  }

  ctx.save();
  ctx.translate(head.x, head.y);
  ctx.rotate(tilt * (0.35 + 0.65 * reach) + 0.17 * grooming + side * 0.06 * swiping + nuzzle * 0.026);
  ctx.scale(headSize, headSize);
  const earTop = mix([-29, -34, -29, -25]);
  const flick = gesture ? gesture.ear : 0;
  const le = side < 0 ? flick : 0;
  const re = side > 0 ? flick : 0;

  ink.shape(COLORS.fur, (path) => {
    path.moveTo(-28, -5);
    path.bezierCurveTo(-30, -12, -27 - 8 * le, earTop - 1 + 9 * le, -23 - 10 * le, earTop + 9 * le);
    path.bezierCurveTo(-20 - 8 * le, earTop - 1 + 8 * le, -15, -20, -12, -18);
    path.bezierCurveTo(-4, -20, 5, -20, 12, -18);
    path.bezierCurveTo(18, -23, 21 + 8 * re, earTop - 2 + 8 * re, 25 + 10 * re, earTop - 1 + 9 * re);
    path.bezierCurveTo(28 + 8 * re, earTop + 9 * re, 29, -15, 28, -7);
    path.bezierCurveTo(36, 11, 24, 23, 4, 24);
    path.bezierCurveTo(-16, 25, -37, 16, -28, -5);
  });

  const gaze = point(clamp(pose.gaze.x, -1, 1), clamp(pose.gaze.y, -1, 1));
  for (const eyeSide of [-1, 1]) {
    const wide = mix([8.9, 8.9, 10.4, 8.9]);
    const tall = mix([7.9, 7.9, 10.6, 4.2]);
    const eyeY = eyeSide * mix([0, 0, 1.3, 0]) - 1;
    const pupilWidth = mix([3.5, 3.5, 3.2, 3.2]);
    const pupilHeight = tall * 0.58;
    const factor = (1 - pose.enjoying) * (1 - clamp(Math.max(pose.blink, 0.43 * grooming + 0.46 * lick), 0, 1));
    ctx.save();
    ctx.translate(eyeSide * 13, eyeY);
    ctx.rotate(eyeSide * mix([0, 0, 0, -0.16]));
    ctx.save();
    ctx.globalAlpha = 1 - pose.enjoying;
    ctx.beginPath();
    ctx.ellipse(0, 0, wide, Math.max(0.6, tall * factor), 0, 0, Math.PI * 2);
    ctx.clip();
    ctx.fillStyle = COLORS.lime;
    ctx.fillRect(-wide, -tall, wide * 2, tall * 2);
    if (factor > 0.13) {
      // 瞳孔必须留在眼睛里，否则向上看的时候会被切成月牙。
      const slackX = Math.max(0, wide - pupilWidth);
      const slackY = Math.max(0, tall - pupilHeight);
      ink.oval(
        COLORS.fur,
        clamp(gaze.x * slackX, -slackX, slackX) - pupilWidth,
        clamp(gaze.y * slackY, -slackY, slackY) - pupilHeight,
        pupilWidth * 2,
        pupilHeight * 2
      );
    }
    ctx.restore();
    if (pose.enjoying > 0.001) {
      ink.stroke(`rgba(201.5, 232.1, 79.1, ${pose.enjoying})`, 1.45, (path) => {
        path.moveTo(-wide * 0.87, 0);
        path.quadraticCurveTo(0, 4.2 * pose.enjoying, wide * 0.87, 0);
      });
    }
    ctx.restore();
    for (let strand = 0; strand < 3; strand += 1) {
      const offset = strand;
      ink.stroke("rgba(173.4, 173.4, 173.4, 0.85)", 0.6, (path) => {
        path.moveTo(eyeSide * 17, 10 + offset * 2);
        path.lineTo(eyeSide * (23 - offset), 9 + offset * 3);
      });
    }
  }
  ctx.restore();

  if (grooming > 0.01) {
    const end = blend(left, pawAtMouth, grooming);
    const angle = Math.atan2(end.y - left.y, end.x - left.x);
    const foreleg = (fraction, along, across) =>
      tip(blend(left, end, fraction), angle, along * grooming, across * grooming);
    const pawEdge = (path) => {
      path.moveTo(foreleg(0, 0, -5).x, foreleg(0, 0, -5).y);
      path.bezierCurveTo(foreleg(0.3, 0, -5).x, foreleg(0.3, 0, -5).y, foreleg(0.8, 0, -7).x, foreleg(0.8, 0, -7).y, foreleg(1, -3, -6).x, foreleg(1, -3, -6).y);
      path.bezierCurveTo(foreleg(1, 5, -6).x, foreleg(1, 5, -6).y, foreleg(1, 5, 5).x, foreleg(1, 5, 5).y, foreleg(1, -2, 6).x, foreleg(1, -2, 6).y);
      path.quadraticCurveTo(foreleg(0.4, 0, 5).x, foreleg(0.4, 0, 5).y, foreleg(0, 0, 5).x, foreleg(0, 0, 5).y);
    };
    ink.shape(`rgba(${19.2 + 12.2 * grooming}, ${19.7 + 12 * grooming}, ${21.7 + 12.5 * grooming}, 1)`, (path) => {
      pawEdge(path);
      path.quadraticCurveTo(foreleg(0, -9, 0).x, foreleg(0, -9, 0).y, foreleg(0, 0, -5).x, foreleg(0, 0, -5).y);
    });
    ink.stroke(`rgba(81.6, 81.6, 86.7, ${0.84 * grooming})`, 0.95, pawEdge);
    ink.stroke(`rgba(81.6, 81.6, 86.7, ${grooming})`, 0.85, (path) => {
      path.moveTo(foreleg(1, 1.7, -2).x, foreleg(1, 1.7, -2).y);
      path.quadraticCurveTo(foreleg(1, 0, -2).x, foreleg(1, 0, -2).y, foreleg(1, -1.2, -1).x, foreleg(1, -1.2, -1).y);
    });
    if (lick > 0.01) {
      ink.stroke(COLORS.tongue, 3.2 * lick, (path) => {
        path.moveTo(head.x - 12, head.y + 16 * headSize);
        path.quadraticCurveTo(
          head.x - 14,
          head.y + 16 * headSize + 6 * lick,
          head.x - 12 - 9 * lick,
          head.y + 16 * headSize + 4 * lick
        );
      });
    }
  }
  ctx.restore();
  return head;
}

function drawDesk(ink, highlight, mouseCenter) {
  const tile = (left, near, right, far, height, fill) => {
    ink.shape(fill, (path) => {
      path.moveTo(desk(left, near, height).x, desk(left, near, height).y);
      path.lineTo(desk(right, near, height).x, desk(right, near, height).y);
      path.lineTo(desk(right, far, height).x, desk(right, far, height).y);
      path.lineTo(desk(left, far, height).x, desk(left, far, height).y);
    });
  };
  tile(-0.47, -0.31, 0.48, 0.62, -1.6, COLORS.fur);
  tile(-0.47, -0.31, 0.48, 0.62, 2.7, "rgba(74.0, 74.0, 74.0, 1)");
  for (let row = 0; row < 5; row += 1) {
    for (let column = 0; column < 13; column += 1) {
      if (row === 4 && column >= 5 && column <= 8) continue;
      const left = -0.452 + column * 0.0708;
      const near = -0.26 + row * 0.17;
      const width = row === 4 && column === 4 ? 0.349 : 0.067;
      const center = keyCenter(row, column);
      const active = highlight.some((target) => Math.abs(target.x - center.x) < 0.5 && Math.abs(target.y - center.y) < 0.5);
      const gold = (row === 3 && column === 0) || (row === 0 && column === 12);
      tile(left, near, left + width, near + 0.158, active ? 3.4 : 4.2, active ? COLORS.lime : gold ? COLORS.gold : COLORS.keyFace);
    }
  }
  ink.oval("rgba(0, 0, 0, 0.14)", mouseCenter.x - 8.7, mouseCenter.y - 5.5, 18.3, 16.5);
  ink.oval("rgba(122.4, 122.4, 117.3, 1)", mouseCenter.x - 8.4, mouseCenter.y - 8, 17.3, 17.1);
  ink.oval(COLORS.keyFace, mouseCenter.x - 8.4, mouseCenter.y - 9.3, 17.1, 17);
  ink.stroke(COLORS.gold, 1.2, (path) => {
    path.moveTo(mouseCenter.x, mouseCenter.y + 1);
    path.lineTo(mouseCenter.x - 0.5, mouseCenter.y + 4);
  });
}

export { keyPosition, desk, point, blend, clamp, ease, clawPath };

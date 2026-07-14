import { GestureFrame, HandGesture, HandLandmarks, HandPoint } from '../models/DomainModels';

export interface GestureInterpreterOptions {
  minimumConfidence: number;
  pinchDistance: number;
  fistHoldMs: number;
  selectionCooldownMs: number;
}
/**
 * 将 21 点手部关键点解释为星图操作。该类只消费真实模型输出，不负责也不会伪造关键点。
 * 点位顺序采用 MediaPipe/MindSpore 常用规范：腕部 0，拇指 1–4，其余四指依次为 5–20。
 */
export class GestureInterpreter {
  private options: GestureInterpreterOptions;
  private previousHands: HandLandmarks[] = [];
  private pinchActive: boolean = false;
  private fistStartedAtMs: number = 0;
  private fistResetEmitted: boolean = false;
  private lastSelectionAtMs: number = 0;

  constructor(options?: GestureInterpreterOptions) {
    this.options = options === undefined ? {
      minimumConfidence: 0.65,
      pinchDistance: 0.055,
      fistHoldMs: 500,
      selectionCooldownMs: 450
    } : options;
  }

  reset(): void {
    this.previousHands = [];
    this.pinchActive = false;
    this.fistStartedAtMs = 0;
    this.fistResetEmitted = false;
    this.lastSelectionAtMs = 0;
  }

  interpret(hands: HandLandmarks[], timestampMs: number = Date.now()): GestureFrame {
    const validHands: HandLandmarks[] = this.validHands(hands);
    let result: GestureFrame = this.emptyFrame(timestampMs);
    if (validHands.length >= 2 && this.isOpenPalm(validHands[0]) && this.isOpenPalm(validHands[1])) {
      result = this.interpretTwoHands(validHands[0], validHands[1], timestampMs);
      this.clearFistState();
      this.pinchActive = false;
    } else if (validHands.length === 1) {
      result = this.interpretOneHand(validHands[0], timestampMs);
    } else {
      this.clearFistState();
      this.pinchActive = false;
    }
    this.previousHands = this.copyHands(validHands);
    return result;
  }

  private interpretOneHand(hand: HandLandmarks, timestampMs: number): GestureFrame {
    if (this.isFist(hand)) {
      if (this.fistStartedAtMs === 0) {
        this.fistStartedAtMs = timestampMs;
      }
      if (!this.fistResetEmitted && timestampMs - this.fistStartedAtMs >= this.options.fistHoldMs) {
        this.fistResetEmitted = true;
        return this.frame(HandGesture.FIST_RESET, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
          hand.confidence, timestampMs);
      }
      return this.emptyFrame(timestampMs);
    }
    this.clearFistState();

    const thumbTip: HandPoint = hand.points[4];
    const indexTip: HandPoint = hand.points[8];
    const pinchDistance: number = this.distance(thumbTip, indexTip);
    const pinching: boolean = pinchDistance <= this.options.pinchDistance;
    if (pinching) {
      if (!this.pinchActive && timestampMs - this.lastSelectionAtMs >= this.options.selectionCooldownMs) {
        this.pinchActive = true;
        this.lastSelectionAtMs = timestampMs;
        return this.frame(HandGesture.PINCH_SELECT, 0.0, 0.0, 0.0, 1.0,
          (thumbTip.x + indexTip.x) / 2.0, (thumbTip.y + indexTip.y) / 2.0,
          hand.confidence, timestampMs);
      }
      // 保持捏合或仍处于冷却期时必须吞掉拖拽，否则一次选择会继续带动星图。
      this.pinchActive = true;
      return this.emptyFrame(timestampMs);
    }
    this.pinchActive = false;

    if (this.isOpenPalm(hand)) {
      const previous: HandLandmarks | undefined = this.findPrevious(hand.trackingId);
      if (previous !== undefined) {
        const currentCenter: HandPoint = this.palmCenter(hand);
        const previousCenter: HandPoint = this.palmCenter(previous);
        return this.frame(HandGesture.DRAG, currentCenter.x - previousCenter.x,
          currentCenter.y - previousCenter.y, 0.0, 1.0, currentCenter.x, currentCenter.y,
          hand.confidence, timestampMs);
      }
    }
    return this.emptyFrame(timestampMs);
  }

  private interpretTwoHands(first: HandLandmarks, second: HandLandmarks,
    timestampMs: number): GestureFrame {
    const firstCenter: HandPoint = this.palmCenter(first);
    const secondCenter: HandPoint = this.palmCenter(second);
    const previousFirst: HandLandmarks | undefined = this.findPrevious(first.trackingId);
    const previousSecond: HandLandmarks | undefined = this.findPrevious(second.trackingId);
    if (previousFirst === undefined || previousSecond === undefined) {
      return this.emptyFrame(timestampMs);
    }
    const previousFirstCenter: HandPoint = this.palmCenter(previousFirst);
    const previousSecondCenter: HandPoint = this.palmCenter(previousSecond);
    const currentDistance: number = Math.max(this.distance(firstCenter, secondCenter), 0.0001);
    const previousDistance: number = Math.max(this.distance(previousFirstCenter, previousSecondCenter), 0.0001);
    const currentAngle: number = Math.atan2(secondCenter.y - firstCenter.y, secondCenter.x - firstCenter.x);
    const previousAngle: number = Math.atan2(previousSecondCenter.y - previousFirstCenter.y,
      previousSecondCenter.x - previousFirstCenter.x);
    return this.frame(HandGesture.ROTATE_SCALE, 0.0, 0.0,
      (currentAngle - previousAngle) * 180.0 / Math.PI,
      this.clamp(currentDistance / previousDistance, 0.75, 1.33),
      (firstCenter.x + secondCenter.x) / 2.0, (firstCenter.y + secondCenter.y) / 2.0,
      Math.min(first.confidence, second.confidence), timestampMs);
  }

  private validHands(hands: HandLandmarks[]): HandLandmarks[] {
    const valid: HandLandmarks[] = [];
    for (let index: number = 0; index < hands.length && valid.length < 2; index++) {
      if (hands[index].confidence >= this.options.minimumConfidence && hands[index].points.length >= 21) {
        valid.push(hands[index]);
      }
    }
    return valid;
  }

  private isOpenPalm(hand: HandLandmarks): boolean {
    const wrist: HandPoint = hand.points[0];
    let extendedCount: number = 0;
    const tips: number[] = [8, 12, 16, 20];
    const joints: number[] = [6, 10, 14, 18];
    for (let index: number = 0; index < tips.length; index++) {
      if (this.distance(hand.points[tips[index]], wrist) > this.distance(hand.points[joints[index]], wrist) * 1.12) {
        extendedCount++;
      }
    }
    return extendedCount >= 3;
  }

  private isFist(hand: HandLandmarks): boolean {
    const wrist: HandPoint = hand.points[0];
    const tips: number[] = [8, 12, 16, 20];
    const joints: number[] = [6, 10, 14, 18];
    for (let index: number = 0; index < tips.length; index++) {
      if (this.distance(hand.points[tips[index]], wrist) > this.distance(hand.points[joints[index]], wrist) * 1.05) {
        return false;
      }
    }
    return this.distance(hand.points[4], hand.points[9]) < 0.22;
  }

  private palmCenter(hand: HandLandmarks): HandPoint {
    const indices: number[] = [0, 5, 9, 13, 17];
    let x: number = 0.0;
    let y: number = 0.0;
    let confidence: number = 0.0;
    for (let index: number = 0; index < indices.length; index++) {
      const point: HandPoint = hand.points[indices[index]];
      x += point.x;
      y += point.y;
      confidence += point.confidence;
    }
    return { x: x / indices.length, y: y / indices.length, confidence: confidence / indices.length };
  }

  private findPrevious(trackingId: number): HandLandmarks | undefined {
    for (let index: number = 0; index < this.previousHands.length; index++) {
      if (this.previousHands[index].trackingId === trackingId) {
        return this.previousHands[index];
      }
    }
    return undefined;
  }

  private copyHands(hands: HandLandmarks[]): HandLandmarks[] {
    const copied: HandLandmarks[] = [];
    for (let handIndex: number = 0; handIndex < hands.length; handIndex++) {
      const points: HandPoint[] = [];
      for (let pointIndex: number = 0; pointIndex < hands[handIndex].points.length; pointIndex++) {
        const point: HandPoint = hands[handIndex].points[pointIndex];
        points.push({ x: point.x, y: point.y, confidence: point.confidence });
      }
      copied.push({
        trackingId: hands[handIndex].trackingId,
        points: points,
        confidence: hands[handIndex].confidence,
        timestampMs: hands[handIndex].timestampMs
      });
    }
    return copied;
  }

  private distance(first: HandPoint, second: HandPoint): number {
    const deltaX: number = first.x - second.x;
    const deltaY: number = first.y - second.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  private clearFistState(): void {
    this.fistStartedAtMs = 0;
    this.fistResetEmitted = false;
  }

  private emptyFrame(timestampMs: number): GestureFrame {
    return this.frame(HandGesture.NONE, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, timestampMs);
  }

  private frame(gesture: HandGesture, deltaX: number, deltaY: number, rotationDegrees: number,
    scale: number, selectX: number, selectY: number, confidence: number, timestampMs: number): GestureFrame {
    return {
      gesture: gesture,
      deltaX: deltaX,
      deltaY: deltaY,
      rotationDegrees: rotationDegrees,
      scale: scale,
      selectX: selectX,
      selectY: selectY,
      confidence: confidence,
      timestampMs: timestampMs
    };
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

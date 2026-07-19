import {
  GestureFrame,
  HandGesture,
  HandLandmarks,
  HandPoint,
  SingleHandTransform
} from '../models/DomainModels';

export interface GestureInterpreterOptions {
  minimumConfidence: number;
  /** 拇指与食指距离相对掌面尺寸的闭合阈值，避免手部远近改变时固定像素阈值失真。 */
  pinchCloseRatio: number;
  /** 捏合释放阈值必须高于闭合阈值，用迟滞抑制阈值附近抖动造成的重复选择。 */
  pinchReleaseRatio: number;
  fistHoldMs: number;
  /** 拇指指尖到中指根部距离相对掌面尺寸的上限，保证远近变化时握拳判定一致。 */
  fistThumbCloseRatio: number;
  selectionCooldownMs: number;
  stableOpenPalmFrames: number;
  translationDeadZone: number;
  rotationDeadZoneDegrees: number;
  scaleDeadZone: number;
  maximumRotationDegreesPerFrame: number;
  minimumScalePerFrame: number;
  maximumScalePerFrame: number;
  lostHandGraceMs: number;
  smoothingFactor: number;
  minimumPalmFacingConfidence: number;
}

interface PalmGeometry {
  centerX: number;
  centerY: number;
  angleRadians: number;
  size: number;
  facingConfidence: number;
  confidence: number;
  timestampMs: number;
}

/**
 * 将 21 点手部关键点解释为普通星图操作。该类只消费真实模型输出，不负责也不会伪造关键点。
 *
 * 点位顺序采用 MediaPipe Hands 规范：腕部 0，拇指 1–4，其余四指依次为 5–20。
 * 三轴变换只使用腕部和掌指关节 0、5、9、13、17，避免弯曲指尖把选择动作污染成缩放。
 */
export class GestureInterpreter {
  private options: GestureInterpreterOptions;
  private activeTrackingId: number = -1;
  private previousPalm: PalmGeometry | undefined = undefined;
  private openPalmStableFrames: number = 0;
  private lastHandSeenAtMs: number = -1;
  private pinchActive: boolean = false;
  private fistStartedAtMs: number = -1;
  private fistResetEmitted: boolean = false;
  private lastSelectionAtMs: number = -1;
  private smoothedDeltaX: number = 0.0;
  private smoothedDeltaY: number = 0.0;
  private smoothedRotationDegrees: number = 0.0;
  private smoothedScaleDelta: number = 0.0;

  constructor(options?: GestureInterpreterOptions) {
    this.options = options === undefined ? {
      minimumConfidence: 0.65,
      pinchCloseRatio: 0.32,
      pinchReleaseRatio: 0.42,
      fistHoldMs: 500,
      fistThumbCloseRatio: 0.72,
      selectionCooldownMs: 450,
      stableOpenPalmFrames: 2,
      translationDeadZone: 0.008,
      rotationDeadZoneDegrees: 2.0,
      scaleDeadZone: 0.025,
      maximumRotationDegreesPerFrame: 8.0,
      minimumScalePerFrame: 0.92,
      maximumScalePerFrame: 1.08,
      lostHandGraceMs: 150,
      smoothingFactor: 0.65,
      minimumPalmFacingConfidence: 0.35
    } : options;
  }

  reset(): void {
    this.activeTrackingId = -1;
    this.previousPalm = undefined;
    this.openPalmStableFrames = 0;
    this.lastHandSeenAtMs = -1;
    this.pinchActive = false;
    this.fistStartedAtMs = -1;
    this.fistResetEmitted = false;
    this.lastSelectionAtMs = -1;
    this.clearSmoothing();
  }

  interpret(hands: HandLandmarks[], timestampMs: number = Date.now()): GestureFrame {
    const hand: HandLandmarks | undefined = this.highestConfidenceHand(hands);
    if (hand === undefined) {
      return this.handleMissingHand(timestampMs);
    }

    if (this.activeTrackingId !== hand.trackingId) {
      // 跟踪 ID 改变时必须重建基准；即使新手位置接近，也不能继承上一只手的位移。
      this.beginTracking(hand.trackingId);
    }
    this.lastHandSeenAtMs = timestampMs;

    // 优先级固定为握拳 > 捏合 > 张掌，防止握拳或选择过程中继续移动星图。
    if (this.isFist(hand)) {
      this.pinchActive = false;
      this.clearOpenPalmTransaction();
      if (this.fistStartedAtMs < 0) {
        this.fistStartedAtMs = timestampMs;
      }
      if (!this.fistResetEmitted &&
        timestampMs - this.fistStartedAtMs >= this.options.fistHoldMs) {
        this.fistResetEmitted = true;
        return this.frame(HandGesture.FIST_RESET, this.identityTransform(0.0, 0.0),
          0.0, 0.0, hand.confidence, timestampMs);
      }
      return this.emptyFrame(timestampMs);
    }
    this.clearFistState();

    const thumbTip: HandPoint = hand.points[4];
    const indexTip: HandPoint = hand.points[8];
    const pinchRatio: number = this.normalizedPinchDistance(hand, thumbTip, indexTip);
    const releaseRatio: number = Math.max(
      this.options.pinchCloseRatio, this.options.pinchReleaseRatio);
    // 已经闭合后使用更宽的释放阈值；只有手指真正分开才结束本次捏合事务。
    const pinchThreshold: number = this.pinchActive ?
      releaseRatio : this.options.pinchCloseRatio;
    const pinching: boolean = pinchRatio <= pinchThreshold;
    if (pinching) {
      this.clearOpenPalmTransaction();
      const canSelect: boolean = !this.pinchActive &&
        (this.lastSelectionAtMs < 0 ||
        timestampMs - this.lastSelectionAtMs >= this.options.selectionCooldownMs);
      this.pinchActive = true;
      if (canSelect) {
        this.lastSelectionAtMs = timestampMs;
        return this.frame(HandGesture.PINCH_SELECT, this.identityTransform(0.0, 0.0),
          (thumbTip.x + indexTip.x) / 2.0, (thumbTip.y + indexTip.y) / 2.0,
          hand.confidence, timestampMs);
      }
      // 捏合保持和冷却期都吞掉三轴变换，确保一次选择不会顺手拖动星图。
      return this.emptyFrame(timestampMs);
    }
    this.pinchActive = false;

    if (!this.isOpenPalm(hand)) {
      this.clearOpenPalmTransaction();
      return this.emptyFrame(timestampMs);
    }
    return this.interpretOpenPalm(hand, timestampMs);
  }

  private interpretOpenPalm(hand: HandLandmarks, timestampMs: number): GestureFrame {
    const current: PalmGeometry = this.palmGeometry(hand, timestampMs);
    const previous: PalmGeometry | undefined = this.previousPalm;
    if (previous === undefined || timestampMs <= previous.timestampMs ||
      timestampMs - previous.timestampMs > this.options.lostHandGraceMs) {
      this.previousPalm = current;
      this.openPalmStableFrames = 1;
      this.clearSmoothing();
      return this.emptyFrame(timestampMs);
    }

    this.openPalmStableFrames++;
    this.previousPalm = current;
    if (this.openPalmStableFrames < this.options.stableOpenPalmFrames) {
      return this.emptyFrame(timestampMs);
    }

    const rawDeltaX: number = current.centerX - previous.centerX;
    const rawDeltaY: number = current.centerY - previous.centerY;
    const rawRotationDegrees: number = this.normalizeAngleDegrees(
      (current.angleRadians - previous.angleRadians) * 180.0 / Math.PI);
    let rawScale: number = 1.0;
    if (current.facingConfidence >= this.options.minimumPalmFacingConfidence &&
      previous.facingConfidence >= this.options.minimumPalmFacingConfidence &&
      previous.size > 0.000001) {
      rawScale = current.size / previous.size;
    }

    const smoothingFactor: number = this.clamp(this.options.smoothingFactor, 0.0, 1.0);
    this.smoothedDeltaX = this.smooth(this.smoothedDeltaX, rawDeltaX, smoothingFactor);
    this.smoothedDeltaY = this.smooth(this.smoothedDeltaY, rawDeltaY, smoothingFactor);
    this.smoothedRotationDegrees = this.smooth(
      this.smoothedRotationDegrees, rawRotationDegrees, smoothingFactor);
    this.smoothedScaleDelta = this.smooth(
      this.smoothedScaleDelta, rawScale - 1.0, smoothingFactor);

    let deltaX: number = 0.0;
    let deltaY: number = 0.0;
    const translationMagnitude: number = Math.sqrt(
      this.smoothedDeltaX * this.smoothedDeltaX + this.smoothedDeltaY * this.smoothedDeltaY);
    if (translationMagnitude >= this.options.translationDeadZone) {
      deltaX = this.smoothedDeltaX;
      deltaY = this.smoothedDeltaY;
    }

    let rotationDegrees: number = 0.0;
    if (Math.abs(this.smoothedRotationDegrees) >= this.options.rotationDeadZoneDegrees) {
      rotationDegrees = this.clamp(
        this.smoothedRotationDegrees,
        -this.options.maximumRotationDegreesPerFrame,
        this.options.maximumRotationDegreesPerFrame);
    }

    let scale: number = 1.0;
    if (Math.abs(this.smoothedScaleDelta) >= this.options.scaleDeadZone) {
      scale = this.clamp(
        1.0 + this.smoothedScaleDelta,
        this.options.minimumScalePerFrame,
        this.options.maximumScalePerFrame);
    }

    const transform: SingleHandTransform = {
      deltaX: deltaX,
      deltaY: deltaY,
      rotationDegrees: rotationDegrees,
      scale: scale,
      anchorX: current.centerX,
      anchorY: current.centerY
    };
    return this.frame(HandGesture.SINGLE_HAND_TRANSFORM, transform, 0.0, 0.0,
      Math.min(hand.confidence, current.confidence), timestampMs);
  }

  private highestConfidenceHand(hands: HandLandmarks[]): HandLandmarks | undefined {
    let selected: HandLandmarks | undefined = undefined;
    for (let index: number = 0; index < hands.length; index++) {
      const candidate: HandLandmarks = hands[index];
      if (candidate.points.length < 21 || candidate.confidence < this.options.minimumConfidence) {
        continue;
      }
      if (selected === undefined || candidate.confidence > selected.confidence) {
        selected = candidate;
      }
    }
    return selected;
  }

  private handleMissingHand(timestampMs: number): GestureFrame {
    const withinGracePeriod: boolean = this.lastHandSeenAtMs >= 0 &&
      timestampMs >= this.lastHandSeenAtMs &&
      timestampMs - this.lastHandSeenAtMs <= this.options.lostHandGraceMs;
    if (!withinGracePeriod) {
      this.activeTrackingId = -1;
      this.lastHandSeenAtMs = -1;
      this.pinchActive = false;
      this.clearFistState();
      this.clearOpenPalmTransaction();
    }
    return this.emptyFrame(timestampMs);
  }

  private beginTracking(trackingId: number): void {
    this.activeTrackingId = trackingId;
    this.pinchActive = false;
    this.clearFistState();
    this.clearOpenPalmTransaction();
  }

  private isOpenPalm(hand: HandLandmarks): boolean {
    const wrist: HandPoint = hand.points[0];
    const aspectRatio: number = this.coordinateAspectRatio(hand);
    let extendedCount: number = 0;
    const tips: number[] = [8, 12, 16, 20];
    const joints: number[] = [6, 10, 14, 18];
    for (let index: number = 0; index < tips.length; index++) {
      if (this.distance2d(hand.points[tips[index]], wrist, aspectRatio) >
        this.distance2d(hand.points[joints[index]], wrist, aspectRatio) * 1.12) {
        extendedCount++;
      }
    }
    return extendedCount >= 3;
  }

  private isFist(hand: HandLandmarks): boolean {
    const wrist: HandPoint = hand.points[0];
    const aspectRatio: number = this.coordinateAspectRatio(hand);
    const tips: number[] = [8, 12, 16, 20];
    const joints: number[] = [6, 10, 14, 18];
    for (let index: number = 0; index < tips.length; index++) {
      if (this.distance2d(hand.points[tips[index]], wrist, aspectRatio) >
        this.distance2d(hand.points[joints[index]], wrist, aspectRatio) * 1.05) {
        return false;
      }
    }
    const palmSize: number = this.palmSize(hand);
    if (!Number.isFinite(palmSize) || palmSize <= 0.000001) {
      return false;
    }
    return this.distance2d(
      hand.points[4], hand.points[9], aspectRatio) / palmSize <
      this.options.fistThumbCloseRatio;
  }

  private palmGeometry(hand: HandLandmarks, timestampMs: number): PalmGeometry {
    const indices: number[] = [0, 5, 9, 13, 17];
    let centerX: number = 0.0;
    let centerY: number = 0.0;
    let confidence: number = 0.0;
    for (let index: number = 0; index < indices.length; index++) {
      const point: HandPoint = hand.points[indices[index]];
      centerX += point.x;
      centerY += point.y;
      confidence += point.confidence;
    }

    const wrist: HandPoint = hand.points[0];
    const indexBase: HandPoint = hand.points[5];
    const middleBase: HandPoint = hand.points[9];
    const littleBase: HandPoint = hand.points[17];
    const coordinateAspectRatio: number = this.coordinateAspectRatio(hand);
    const palmWidth: number =
      this.distance2d(indexBase, littleBase, coordinateAspectRatio);
    const palmLength: number =
      this.distance2d(wrist, middleBase, coordinateAspectRatio);
    const palmAspectRatio: number = palmWidth / Math.max(0.000001, palmLength);
    const aspectFacingConfidence: number =
      this.clamp((palmAspectRatio - 0.20) / 0.50, 0.0, 1.0);
    const orientationWrist: HandPoint = this.orientationPoint(hand, 0);
    const orientationIndexBase: HandPoint = this.orientationPoint(hand, 5);
    const orientationLittleBase: HandPoint = this.orientationPoint(hand, 17);
    const orientationAspectRatio: number =
      hand.worldPoints !== undefined && hand.worldPoints.length > 17 ?
        1.0 : coordinateAspectRatio;
    const normalFacingConfidence: number = this.palmNormalFacingConfidence(
      orientationWrist, orientationIndexBase, orientationLittleBase, orientationAspectRatio);
    let facingConfidence: number = Math.min(
      aspectFacingConfidence, normalFacingConfidence);
    if (hand.palmFacingConfidence !== undefined) {
      facingConfidence = Math.min(
        facingConfidence, this.clamp(hand.palmFacingConfidence, 0.0, 1.0));
    }
    let palmConfidence: number = confidence / indices.length;
    if (hand.palmConfidence !== undefined) {
      palmConfidence = Math.min(palmConfidence, hand.palmConfidence);
    }
    return {
      centerX: centerX / indices.length,
      centerY: centerY / indices.length,
      angleRadians: Math.atan2(
        littleBase.y - indexBase.y,
        (littleBase.x - indexBase.x) * coordinateAspectRatio),
      size: this.palmSize(hand),
      facingConfidence: facingConfidence,
      confidence: palmConfidence,
      timestampMs: timestampMs
    };
  }

  /**
   * 使用掌宽与腕部到中指根部距离的几何平均值归一化捏合距离。
   * 该比例随整只手在画面中等比放大或缩小时保持稳定，不能被解释为真实物理距离。
   */
  private normalizedPinchDistance(hand: HandLandmarks, thumbTip: HandPoint,
    indexTip: HandPoint): number {
    const size: number = this.palmSize(hand);
    if (!Number.isFinite(size) || size <= 0.000001) {
      return Number.POSITIVE_INFINITY;
    }
    return this.distance2d(
      thumbTip, indexTip, this.coordinateAspectRatio(hand)) / size;
  }

  private palmSize(hand: HandLandmarks): number {
    const wrist: HandPoint = hand.points[0];
    const indexBase: HandPoint = hand.points[5];
    const middleBase: HandPoint = hand.points[9];
    const littleBase: HandPoint = hand.points[17];
    const aspectRatio: number = this.coordinateAspectRatio(hand);
    const palmWidth: number = this.distance2d(indexBase, littleBase, aspectRatio);
    const palmLength: number = this.distance2d(wrist, middleBase, aspectRatio);
    return Math.sqrt(
      Math.max(0.000001, palmWidth) * Math.max(0.000001, palmLength));
  }

  private orientationPoint(hand: HandLandmarks, index: number): HandPoint {
    if (hand.worldPoints !== undefined && hand.worldPoints.length > index) {
      return hand.worldPoints[index];
    }
    return hand.points[index];
  }

  private palmNormalFacingConfidence(wrist: HandPoint, indexBase: HandPoint,
    littleBase: HandPoint, coordinateAspectRatio: number): number {
    const firstX: number = (indexBase.x - wrist.x) * coordinateAspectRatio;
    const firstY: number = indexBase.y - wrist.y;
    const firstZ: number = this.pointZ(indexBase) - this.pointZ(wrist);
    const secondX: number = (littleBase.x - wrist.x) * coordinateAspectRatio;
    const secondY: number = littleBase.y - wrist.y;
    const secondZ: number = this.pointZ(littleBase) - this.pointZ(wrist);
    const normalX: number = firstY * secondZ - firstZ * secondY;
    const normalY: number = firstZ * secondX - firstX * secondZ;
    const normalZ: number = firstX * secondY - firstY * secondX;
    const normalLength: number = Math.sqrt(
      normalX * normalX + normalY * normalY + normalZ * normalZ);
    if (normalLength <= 0.000001) {
      return 0.0;
    }
    return this.clamp(Math.abs(normalZ) / normalLength, 0.0, 1.0);
  }

  private pointZ(point: HandPoint): number {
    return point.z === undefined || !Number.isFinite(point.z) ? 0.0 : point.z;
  }

  private coordinateAspectRatio(hand: HandLandmarks): number {
    if (hand.coordinateAspectRatio === undefined ||
      !Number.isFinite(hand.coordinateAspectRatio)) {
      return 1.0;
    }
    return this.clamp(hand.coordinateAspectRatio, 0.25, 4.0);
  }

  private distance2d(first: HandPoint, second: HandPoint,
    coordinateAspectRatio: number = 1.0): number {
    const deltaX: number = (first.x - second.x) * coordinateAspectRatio;
    const deltaY: number = first.y - second.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  private normalizeAngleDegrees(value: number): number {
    let normalized: number = value;
    while (normalized > 180.0) {
      normalized -= 360.0;
    }
    while (normalized < -180.0) {
      normalized += 360.0;
    }
    return normalized;
  }

  private smooth(previous: number, current: number, factor: number): number {
    return previous * (1.0 - factor) + current * factor;
  }

  private clearFistState(): void {
    this.fistStartedAtMs = -1;
    this.fistResetEmitted = false;
  }

  private clearOpenPalmTransaction(): void {
    this.previousPalm = undefined;
    this.openPalmStableFrames = 0;
    this.clearSmoothing();
  }

  private clearSmoothing(): void {
    this.smoothedDeltaX = 0.0;
    this.smoothedDeltaY = 0.0;
    this.smoothedRotationDegrees = 0.0;
    this.smoothedScaleDelta = 0.0;
  }

  private identityTransform(anchorX: number, anchorY: number): SingleHandTransform {
    return {
      deltaX: 0.0,
      deltaY: 0.0,
      rotationDegrees: 0.0,
      scale: 1.0,
      anchorX: anchorX,
      anchorY: anchorY
    };
  }

  private emptyFrame(timestampMs: number): GestureFrame {
    return this.frame(
      HandGesture.NONE, this.identityTransform(0.0, 0.0),
      0.0, 0.0, 0.0, timestampMs);
  }

  private frame(gesture: HandGesture, transform: SingleHandTransform,
    selectX: number, selectY: number, confidence: number, timestampMs: number): GestureFrame {
    return {
      gesture: gesture,
      transform: transform,
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

import { NormalSkyViewState, SkyMapSize } from '../models/NormalSkyModels';
import { NormalSkyViewStateService } from './NormalSkyViewStateService';

export interface NormalSkyGestureUpdate {
  viewState: NormalSkyViewState;
  changed: boolean;
  scaleChanged: boolean;
  rotationChanged: boolean;
}

/**
 * 普通星图触控和前摄手势共用的变换事务。
 * 指针事件提供手势起点以来的累计值，双掌识别提供相邻帧增量，因此分别维护阈值累计，
 * 但最终都只调用同一套球面投影变换，避免两种输入产生不同的缩放和旋转语义。
 */
export class NormalSkyGestureController {
  static readonly SCALE_ACTIVATION_DELTA: number = 0.02;
  static readonly ROTATION_ACTIVATION_DEGREES: number = 3.0;

  private pointerScaleActive: boolean = false;
  private pointerRotationActive: boolean = false;
  private lastPointerScale: number = 1.0;
  private lastPointerRotationDegrees: number = 0.0;
  private handScaleActive: boolean = false;
  private handRotationActive: boolean = false;
  private pendingHandScale: number = 1.0;
  private pendingHandRotationDegrees: number = 0.0;

  beginPointerScale(): void {
    this.pointerScaleActive = false;
    this.lastPointerScale = 1.0;
  }

  endPointerScale(): void {
    this.pointerScaleActive = false;
    this.lastPointerScale = 1.0;
  }

  beginPointerRotation(): void {
    this.pointerRotationActive = false;
    this.lastPointerRotationDegrees = 0.0;
  }

  endPointerRotation(): void {
    this.pointerRotationActive = false;
    this.lastPointerRotationDegrees = 0.0;
  }

  updatePointerScale(viewState: NormalSkyViewState, size: SkyMapSize, totalScale: number,
    anchorX: number, anchorY: number): NormalSkyGestureUpdate {
    if (!Number.isFinite(totalScale) || totalScale <= 0.0) {
      return this.unchanged(viewState);
    }
    if (!this.pointerScaleActive) {
      if (Math.abs(totalScale - 1.0) < NormalSkyGestureController.SCALE_ACTIVATION_DELTA) {
        return this.unchanged(viewState);
      }
      this.pointerScaleActive = true;
    }
    const incrementalScale: number = totalScale / Math.max(0.001, this.lastPointerScale);
    this.lastPointerScale = totalScale;
    return {
      viewState: NormalSkyViewStateService.zoomAt(
        viewState, size, incrementalScale, anchorX, anchorY),
      changed: true,
      scaleChanged: true,
      rotationChanged: false
    };
  }

  updatePointerRotation(viewState: NormalSkyViewState, size: SkyMapSize, totalDegrees: number,
    anchorX: number, anchorY: number): NormalSkyGestureUpdate {
    if (!Number.isFinite(totalDegrees)) {
      return this.unchanged(viewState);
    }
    if (!this.pointerRotationActive) {
      if (Math.abs(totalDegrees) < NormalSkyGestureController.ROTATION_ACTIVATION_DEGREES) {
        return this.unchanged(viewState);
      }
      this.pointerRotationActive = true;
    }
    const incrementalDegrees: number = totalDegrees - this.lastPointerRotationDegrees;
    this.lastPointerRotationDegrees = totalDegrees;
    return {
      viewState: NormalSkyViewStateService.rotateAt(
        viewState, size, incrementalDegrees, anchorX, anchorY),
      changed: true,
      scaleChanged: false,
      rotationChanged: true
    };
  }

  updateHandTransform(viewState: NormalSkyViewState, size: SkyMapSize, incrementalScale: number,
    incrementalRotationDegrees: number, anchorX: number, anchorY: number): NormalSkyGestureUpdate {
    const safeScale: number = Number.isFinite(incrementalScale) && incrementalScale > 0.0 ?
      Math.max(0.75, Math.min(1.33, incrementalScale)) : 1.0;
    const safeRotation: number = Number.isFinite(incrementalRotationDegrees) ?
      incrementalRotationDegrees : 0.0;
    this.pendingHandScale *= safeScale;
    this.pendingHandRotationDegrees += safeRotation;

    let candidate: NormalSkyViewState = viewState;
    let scaleChanged: boolean = false;
    let rotationChanged: boolean = false;
    if (this.handScaleActive ||
      Math.abs(this.pendingHandScale - 1.0) >= NormalSkyGestureController.SCALE_ACTIVATION_DELTA) {
      this.handScaleActive = true;
      candidate = NormalSkyViewStateService.zoomAt(
        candidate, size, this.pendingHandScale, anchorX, anchorY);
      this.pendingHandScale = 1.0;
      scaleChanged = true;
    }
    if (this.handRotationActive ||
      Math.abs(this.pendingHandRotationDegrees) >= NormalSkyGestureController.ROTATION_ACTIVATION_DEGREES) {
      this.handRotationActive = true;
      candidate = NormalSkyViewStateService.rotateAt(
        candidate, size, this.pendingHandRotationDegrees, anchorX, anchorY);
      this.pendingHandRotationDegrees = 0.0;
      rotationChanged = true;
    }
    return {
      viewState: candidate,
      changed: scaleChanged || rotationChanged,
      scaleChanged: scaleChanged,
      rotationChanged: rotationChanged
    };
  }

  endHandTransform(): void {
    this.handScaleActive = false;
    this.handRotationActive = false;
    this.pendingHandScale = 1.0;
    this.pendingHandRotationDegrees = 0.0;
  }

  reset(): void {
    this.endPointerScale();
    this.endPointerRotation();
    this.endHandTransform();
  }

  private unchanged(viewState: NormalSkyViewState): NormalSkyGestureUpdate {
    return {
      viewState: viewState,
      changed: false,
      scaleChanged: false,
      rotationChanged: false
    };
  }
}

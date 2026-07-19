import { SingleHandTransform } from '../models/DomainModels';
import { NormalSkyViewState, SkyMapSize } from '../models/NormalSkyModels';
import { NormalSkyViewStateService } from './NormalSkyViewStateService';

export interface NormalSkyGestureUpdate {
  viewState: NormalSkyViewState;
  changed: boolean;
  translationChanged: boolean;
  scaleChanged: boolean;
  rotationChanged: boolean;
}

/**
 * 普通星图触控和前摄手势共用的变换事务。
 * 指针事件提供手势起点以来的累计值；单掌识别则在一帧中同时提供平移、旋转和缩放。
 * 三轴只生成一个视口结果，页面不会在同一帧触发三次重绘。
 */
export class NormalSkyGestureController {
  static readonly SCALE_ACTIVATION_DELTA: number = 0.02;
  static readonly ROTATION_ACTIVATION_DEGREES: number = 3.0;
  static readonly MINIMUM_HAND_SCALE: number = 0.92;
  static readonly MAXIMUM_HAND_SCALE: number = 1.08;
  static readonly MAXIMUM_HAND_ROTATION_DEGREES: number = 8.0;
  static readonly MAXIMUM_HAND_TRANSLATION: number = 0.25;

  private pointerScaleActive: boolean = false;
  private pointerRotationActive: boolean = false;
  private lastPointerScale: number = 1.0;
  private lastPointerRotationDegrees: number = 0.0;

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
      translationChanged: false,
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
      translationChanged: false,
      scaleChanged: false,
      rotationChanged: true
    };
  }

  updateSingleHandTransform(viewState: NormalSkyViewState, size: SkyMapSize,
    transform: SingleHandTransform): NormalSkyGestureUpdate {
    const safeDeltaX: number = Number.isFinite(transform.deltaX) ?
      this.clamp(transform.deltaX,
        -NormalSkyGestureController.MAXIMUM_HAND_TRANSLATION,
        NormalSkyGestureController.MAXIMUM_HAND_TRANSLATION) : 0.0;
    const safeDeltaY: number = Number.isFinite(transform.deltaY) ?
      this.clamp(transform.deltaY,
        -NormalSkyGestureController.MAXIMUM_HAND_TRANSLATION,
        NormalSkyGestureController.MAXIMUM_HAND_TRANSLATION) : 0.0;
    const safeScale: number = Number.isFinite(transform.scale) && transform.scale > 0.0 ?
      this.clamp(transform.scale,
        NormalSkyGestureController.MINIMUM_HAND_SCALE,
        NormalSkyGestureController.MAXIMUM_HAND_SCALE) : 1.0;
    const safeRotation: number = Number.isFinite(transform.rotationDegrees) ?
      this.clamp(transform.rotationDegrees,
        -NormalSkyGestureController.MAXIMUM_HAND_ROTATION_DEGREES,
        NormalSkyGestureController.MAXIMUM_HAND_ROTATION_DEGREES) : 0.0;
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const currentAnchorX: number = this.clamp(
      Number.isFinite(transform.anchorX) ? transform.anchorX * width : width / 2.0,
      0.0, width);
    const currentAnchorY: number = this.clamp(
      Number.isFinite(transform.anchorY) ? transform.anchorY * height : height / 2.0,
      0.0, height);
    const deltaXPixels: number = safeDeltaX * width;
    const deltaYPixels: number = safeDeltaY * height;
    const previousAnchorX: number = this.clamp(currentAnchorX - deltaXPixels, 0.0, width);
    const previousAnchorY: number = this.clamp(currentAnchorY - deltaYPixels, 0.0, height);
    const translationChanged: boolean = safeDeltaX !== 0.0 || safeDeltaY !== 0.0;
    const scaleChanged: boolean = safeScale !== 1.0;
    const rotationChanged: boolean = safeRotation !== 0.0;
    if (!translationChanged && !scaleChanged && !rotationChanged) {
      return this.unchanged(viewState);
    }

    // 先围绕上一帧掌心完成缩放和旋转，再把该锚点平移到当前掌心。
    // 这样组合手势只提交一次视口状态，并且天体不会在三轴依次更新时从掌心下漂走。
    let candidate: NormalSkyViewState = viewState;
    if (scaleChanged) {
      candidate = NormalSkyViewStateService.zoomAt(
        candidate, size, safeScale, previousAnchorX, previousAnchorY);
    }
    if (rotationChanged) {
      candidate = NormalSkyViewStateService.rotateAt(
        candidate, size, safeRotation, previousAnchorX, previousAnchorY);
    }
    if (translationChanged) {
      candidate = NormalSkyViewStateService.panFromTo(
        candidate, size, previousAnchorX, previousAnchorY, currentAnchorX, currentAnchorY);
    }
    return {
      viewState: candidate,
      changed: true,
      translationChanged: translationChanged,
      scaleChanged: scaleChanged,
      rotationChanged: rotationChanged
    };
  }

  /**
   * 单掌事务的平滑和短时丢失状态由 GestureInterpreter 维护；这里保留结束入口，
   * 让页面在切换模式或关闭相机时仍能统一终止所有输入事务。
   */
  endHandTransform(): void {
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
      translationChanged: false,
      scaleChanged: false,
      rotationChanged: false
    };
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

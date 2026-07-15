import {
  EquatorialCoordinate,
  ObserverState
} from '../models/DomainModels';
import {
  NormalSkyQuaternion,
  NormalSkyViewState,
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../models/NormalSkyModels';
import { AstronomyService } from './AstronomyService';
import { NormalSkyProjectionService } from './NormalSkyProjectionService';

interface ViewVector3 {
  x: number;
  y: number;
  z: number;
}

/**
 * 普通星图的三维姿态控制器。所有交互先更新单位四元数，赤经、赤纬和屏幕旋转只在
 * snapshot() 中生成，避免天极附近反复分解欧拉角造成 180 度翻转。
 */
export class NormalSkyViewStateService {
  static readonly MAX_ANGULAR_VELOCITY_DEGREES_PER_SECOND: number = 90.0;

  static defaultState(): NormalSkyViewState {
    return NormalSkyViewStateService.fromViewport(
      NormalSkyProjectionService.defaultViewport());
  }

  static home(observer?: ObserverState,
    orientation: SkyMapOrientation = SkyMapOrientation.EQUATORIAL_NORTH_UP): NormalSkyViewState {
    return NormalSkyViewStateService.fromViewport(
      NormalSkyProjectionService.homeViewport(observer, orientation));
  }

  static fromViewport(viewport: NormalSkyViewport): NormalSkyViewState {
    const normalized: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport(viewport);
    const rightAscension: number = normalized.centerRaHours * Math.PI / 12.0;
    const declination: number = normalized.centerDecDegrees * Math.PI / 180.0;
    const rotation: number = normalized.rotationDegrees * Math.PI / 180.0;
    const forward: ViewVector3 = {
      x: Math.cos(declination) * Math.cos(rightAscension),
      y: Math.cos(declination) * Math.sin(rightAscension),
      z: Math.sin(declination)
    };
    const east: ViewVector3 = {
      x: -Math.sin(rightAscension),
      y: Math.cos(rightAscension),
      z: 0.0
    };
    const north: ViewVector3 = {
      x: -Math.sin(declination) * Math.cos(rightAscension),
      y: -Math.sin(declination) * Math.sin(rightAscension),
      z: Math.cos(declination)
    };
    // 正旋转角与既有 Canvas 语义一致：画面顺时针旋转，东/北基底随之反向滚转。
    const rolledEast: ViewVector3 = {
      x: east.x * Math.cos(rotation) - north.x * Math.sin(rotation),
      y: east.y * Math.cos(rotation) - north.y * Math.sin(rotation),
      z: east.z * Math.cos(rotation) - north.z * Math.sin(rotation)
    };
    const rolledNorth: ViewVector3 = {
      x: east.x * Math.sin(rotation) + north.x * Math.cos(rotation),
      y: east.y * Math.sin(rotation) + north.y * Math.cos(rotation),
      z: east.z * Math.sin(rotation) + north.z * Math.cos(rotation)
    };
    return NormalSkyViewStateService.normalizeState({
      viewQuaternion: NormalSkyViewStateService.quaternionFromBasis(
        forward, rolledEast, rolledNorth),
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      orientation: normalized.orientation
    });
  }

  static snapshot(state: NormalSkyViewState): NormalSkyViewport {
    const normalized: NormalSkyViewState = NormalSkyViewStateService.normalizeState(state);
    const forward: ViewVector3 = NormalSkyViewStateService.rotateVector(
      normalized.viewQuaternion, { x: 1.0, y: 0.0, z: 0.0 });
    const rolledEast: ViewVector3 = NormalSkyViewStateService.rotateVector(
      normalized.viewQuaternion, { x: 0.0, y: 1.0, z: 0.0 });
    const horizontalLength: number = Math.sqrt(forward.x * forward.x + forward.y * forward.y);
    const rightAscension: number = horizontalLength < 0.000000001 ? 0.0 :
      Math.atan2(forward.y, forward.x);
    const declination: number = Math.atan2(forward.z, horizontalLength);
    const east: ViewVector3 = {
      x: -Math.sin(rightAscension),
      y: Math.cos(rightAscension),
      z: 0.0
    };
    const north: ViewVector3 = {
      x: -Math.sin(declination) * Math.cos(rightAscension),
      y: -Math.sin(declination) * Math.sin(rightAscension),
      z: Math.cos(declination)
    };
    const rotation: number = Math.atan2(
      -NormalSkyViewStateService.dot(rolledEast, north),
      NormalSkyViewStateService.dot(rolledEast, east)) * 180.0 / Math.PI;
    return NormalSkyProjectionService.normalizeViewport({
      centerRaHours: AstronomyService.normalizeHours(rightAscension * 12.0 / Math.PI),
      centerDecDegrees: declination * 180.0 / Math.PI,
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      rotationDegrees: rotation,
      orientation: normalized.orientation
    });
  }

  static pan(state: NormalSkyViewState, size: SkyMapSize,
    deltaXPixels: number, deltaYPixels: number): NormalSkyViewState {
    const centerX: number = Math.max(1.0, size.widthPixels) / 2.0;
    const centerY: number = Math.max(1.0, size.heightPixels) / 2.0;
    return NormalSkyViewStateService.panFromTo(
      state, size, centerX, centerY, centerX + deltaXPixels, centerY + deltaYPixels);
  }

  static panFromTo(state: NormalSkyViewState, size: SkyMapSize,
    fromX: number, fromY: number, toX: number, toY: number): NormalSkyViewState {
    const normalized: NormalSkyViewState = NormalSkyViewStateService.normalizeState(state);
    const previousDirection: ViewVector3 = NormalSkyViewStateService.localDirection(
      fromX, fromY, normalized.fieldOfViewDegrees, size);
    const currentDirection: ViewVector3 = NormalSkyViewStateService.localDirection(
      toX, toY, normalized.fieldOfViewDegrees, size);
    const localRotation: NormalSkyQuaternion = NormalSkyViewStateService.quaternionFromTo(
      currentDirection, previousDirection);
    return NormalSkyViewStateService.normalizeState({
      viewQuaternion: NormalSkyViewStateService.multiply(
        normalized.viewQuaternion, localRotation),
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      orientation: normalized.orientation
    });
  }

  static panWithVelocity(state: NormalSkyViewState, size: SkyMapSize,
    velocityXPixelsPerSecond: number, velocityYPixelsPerSecond: number,
    deltaSeconds: number): NormalSkyViewState {
    const normalized: NormalSkyViewState = NormalSkyViewStateService.normalizeState(state);
    const safeDelta: number = NormalSkyViewStateService.clamp(deltaSeconds, 0.0, 0.05);
    const pixelSpeed: number = Math.sqrt(
      velocityXPixelsPerSecond * velocityXPixelsPerSecond +
      velocityYPixelsPerSecond * velocityYPixelsPerSecond);
    if (!Number.isFinite(pixelSpeed) || pixelSpeed <= 0.0 || safeDelta <= 0.0) return normalized;
    const halfFieldRadians: number = normalized.fieldOfViewDegrees * Math.PI / 360.0;
    const planeHalfWidth: number = 2.0 * Math.tan(halfFieldRadians / 2.0);
    const pixelScale: number = Math.max(1.0, size.widthPixels) /
      (2.0 * Math.max(0.000001, planeHalfWidth));
    const angularSpeed: number = pixelSpeed / pixelScale * 180.0 / Math.PI;
    const limitScale: number = angularSpeed <=
      NormalSkyViewStateService.MAX_ANGULAR_VELOCITY_DEGREES_PER_SECOND ? 1.0 :
      NormalSkyViewStateService.MAX_ANGULAR_VELOCITY_DEGREES_PER_SECOND / angularSpeed;
    return NormalSkyViewStateService.pan(normalized, size,
      velocityXPixelsPerSecond * limitScale * safeDelta,
      velocityYPixelsPerSecond * limitScale * safeDelta);
  }

  static zoomAt(state: NormalSkyViewState, size: SkyMapSize, scale: number,
    anchorX: number, anchorY: number): NormalSkyViewState {
    const normalized: NormalSkyViewState = NormalSkyViewStateService.normalizeState(state);
    const safeScale: number = NormalSkyViewStateService.clamp(scale, 0.2, 5.0);
    const nextField: number = NormalSkyViewStateService.clamp(
      normalized.fieldOfViewDegrees / safeScale,
      NormalSkyProjectionService.MIN_FIELD_OF_VIEW_DEGREES,
      NormalSkyProjectionService.MAX_FIELD_OF_VIEW_DEGREES);
    const previousLocal: ViewVector3 = NormalSkyViewStateService.localDirection(
      anchorX, anchorY, normalized.fieldOfViewDegrees, size);
    const candidateLocal: ViewVector3 = NormalSkyViewStateService.localDirection(
      anchorX, anchorY, nextField, size);
    const previousWorld: ViewVector3 = NormalSkyViewStateService.rotateVector(
      normalized.viewQuaternion, previousLocal);
    const candidateWorld: ViewVector3 = NormalSkyViewStateService.rotateVector(
      normalized.viewQuaternion, candidateLocal);
    const correction: NormalSkyQuaternion = NormalSkyViewStateService.quaternionFromTo(
      candidateWorld, previousWorld);
    return NormalSkyViewStateService.normalizeState({
      viewQuaternion: NormalSkyViewStateService.multiply(
        correction, normalized.viewQuaternion),
      fieldOfViewDegrees: nextField,
      orientation: normalized.orientation
    });
  }

  static rotateAt(state: NormalSkyViewState, size: SkyMapSize, deltaDegrees: number,
    anchorX: number, anchorY: number): NormalSkyViewState {
    const normalized: NormalSkyViewState = NormalSkyViewStateService.normalizeState(state);
    if (!Number.isFinite(deltaDegrees)) return normalized;
    const anchorLocal: ViewVector3 = NormalSkyViewStateService.localDirection(
      anchorX, anchorY, normalized.fieldOfViewDegrees, size);
    const previousWorld: ViewVector3 = NormalSkyViewStateService.rotateVector(
      normalized.viewQuaternion, anchorLocal);
    const localRoll: NormalSkyQuaternion = NormalSkyViewStateService.axisAngle(
      { x: 1.0, y: 0.0, z: 0.0 }, -deltaDegrees * Math.PI / 180.0);
    const candidateQuaternion: NormalSkyQuaternion = NormalSkyViewStateService.multiply(
      normalized.viewQuaternion, localRoll);
    const candidateWorld: ViewVector3 = NormalSkyViewStateService.rotateVector(
      candidateQuaternion, anchorLocal);
    const correction: NormalSkyQuaternion = NormalSkyViewStateService.quaternionFromTo(
      candidateWorld, previousWorld);
    return NormalSkyViewStateService.normalizeState({
      viewQuaternion: NormalSkyViewStateService.multiply(correction, candidateQuaternion),
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      orientation: normalized.orientation
    });
  }

  static resetNorth(state: NormalSkyViewState, observer?: ObserverState): NormalSkyViewState {
    const snapshot: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
    if (snapshot.orientation === SkyMapOrientation.HORIZON_ZENITH) {
      return NormalSkyViewStateService.home(observer, SkyMapOrientation.HORIZON_ZENITH);
    }
    snapshot.rotationDegrees = 0.0;
    return NormalSkyViewStateService.fromViewport(snapshot);
  }

  static flyTo(state: NormalSkyViewState, coordinate: EquatorialCoordinate,
    fieldOfViewDegrees: number = 30.0): NormalSkyViewState {
    const snapshot: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
    return NormalSkyViewStateService.fromViewport(
      NormalSkyProjectionService.flyTo(snapshot, coordinate, fieldOfViewDegrees));
  }

  static interpolate(first: NormalSkyViewState, second: NormalSkyViewState,
    progress: number): NormalSkyViewState {
    const start: NormalSkyViewState = NormalSkyViewStateService.normalizeState(first);
    const finish: NormalSkyViewState = NormalSkyViewStateService.normalizeState(second);
    const ratio: number = NormalSkyViewStateService.clamp(progress, 0.0, 1.0);
    return NormalSkyViewStateService.normalizeState({
      viewQuaternion: NormalSkyViewStateService.slerp(
        start.viewQuaternion, finish.viewQuaternion, ratio),
      fieldOfViewDegrees: start.fieldOfViewDegrees +
        (finish.fieldOfViewDegrees - start.fieldOfViewDegrees) * ratio,
      orientation: ratio < 0.5 ? start.orientation : finish.orientation
    });
  }

  static normalizeState(state: NormalSkyViewState): NormalSkyViewState {
    return {
      viewQuaternion: NormalSkyViewStateService.normalizeQuaternion(state.viewQuaternion),
      fieldOfViewDegrees: NormalSkyViewStateService.clamp(state.fieldOfViewDegrees,
        NormalSkyProjectionService.MIN_FIELD_OF_VIEW_DEGREES,
        NormalSkyProjectionService.MAX_FIELD_OF_VIEW_DEGREES),
      orientation: state.orientation
    };
  }

  private static localDirection(xPixels: number, yPixels: number,
    fieldOfViewDegrees: number, size: SkyMapSize): ViewVector3 {
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const halfFieldRadians: number = fieldOfViewDegrees * Math.PI / 360.0;
    const planeHalfWidth: number = 2.0 * Math.tan(halfFieldRadians / 2.0);
    const pixelScale: number = width / (2.0 * Math.max(0.000001, planeHalfWidth));
    const east: number = -(xPixels - width / 2.0) / pixelScale;
    const north: number = -(yPixels - height / 2.0) / pixelScale;
    const radiusSquared: number = east * east + north * north;
    const denominator: number = 1.0 + radiusSquared / 4.0;
    return NormalSkyViewStateService.normalizeVector({
      x: (1.0 - radiusSquared / 4.0) / denominator,
      y: east / denominator,
      z: north / denominator
    });
  }

  private static quaternionFromBasis(forward: ViewVector3, east: ViewVector3,
    north: ViewVector3): NormalSkyQuaternion {
    const m00: number = forward.x;
    const m01: number = east.x;
    const m02: number = north.x;
    const m10: number = forward.y;
    const m11: number = east.y;
    const m12: number = north.y;
    const m20: number = forward.z;
    const m21: number = east.z;
    const m22: number = north.z;
    const trace: number = m00 + m11 + m22;
    let quaternion: NormalSkyQuaternion;
    if (trace > 0.0) {
      const scale: number = Math.sqrt(trace + 1.0) * 2.0;
      quaternion = {
        w: 0.25 * scale,
        x: (m21 - m12) / scale,
        y: (m02 - m20) / scale,
        z: (m10 - m01) / scale
      };
    } else if (m00 > m11 && m00 > m22) {
      const scale: number = Math.sqrt(1.0 + m00 - m11 - m22) * 2.0;
      quaternion = {
        w: (m21 - m12) / scale,
        x: 0.25 * scale,
        y: (m01 + m10) / scale,
        z: (m02 + m20) / scale
      };
    } else if (m11 > m22) {
      const scale: number = Math.sqrt(1.0 + m11 - m00 - m22) * 2.0;
      quaternion = {
        w: (m02 - m20) / scale,
        x: (m01 + m10) / scale,
        y: 0.25 * scale,
        z: (m12 + m21) / scale
      };
    } else {
      const scale: number = Math.sqrt(1.0 + m22 - m00 - m11) * 2.0;
      quaternion = {
        w: (m10 - m01) / scale,
        x: (m02 + m20) / scale,
        y: (m12 + m21) / scale,
        z: 0.25 * scale
      };
    }
    return NormalSkyViewStateService.normalizeQuaternion(quaternion);
  }

  private static quaternionFromTo(from: ViewVector3, to: ViewVector3): NormalSkyQuaternion {
    const source: ViewVector3 = NormalSkyViewStateService.normalizeVector(from);
    const target: ViewVector3 = NormalSkyViewStateService.normalizeVector(to);
    const cosine: number = NormalSkyViewStateService.clamp(
      NormalSkyViewStateService.dot(source, target), -1.0, 1.0);
    if (cosine > 0.999999999) return { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
    if (cosine < -0.999999999) {
      const reference: ViewVector3 = Math.abs(source.z) < 0.9 ?
        { x: 0.0, y: 0.0, z: 1.0 } : { x: 0.0, y: 1.0, z: 0.0 };
      return NormalSkyViewStateService.axisAngle(
        NormalSkyViewStateService.normalizeVector(
          NormalSkyViewStateService.cross(source, reference)), Math.PI);
    }
    const axis: ViewVector3 = NormalSkyViewStateService.cross(source, target);
    return NormalSkyViewStateService.normalizeQuaternion({
      x: axis.x,
      y: axis.y,
      z: axis.z,
      w: 1.0 + cosine
    });
  }

  private static axisAngle(axis: ViewVector3, angleRadians: number): NormalSkyQuaternion {
    const normalized: ViewVector3 = NormalSkyViewStateService.normalizeVector(axis);
    const halfAngle: number = angleRadians / 2.0;
    const sine: number = Math.sin(halfAngle);
    return NormalSkyViewStateService.normalizeQuaternion({
      x: normalized.x * sine,
      y: normalized.y * sine,
      z: normalized.z * sine,
      w: Math.cos(halfAngle)
    });
  }

  private static multiply(first: NormalSkyQuaternion,
    second: NormalSkyQuaternion): NormalSkyQuaternion {
    return {
      x: first.w * second.x + first.x * second.w + first.y * second.z - first.z * second.y,
      y: first.w * second.y - first.x * second.z + first.y * second.w + first.z * second.x,
      z: first.w * second.z + first.x * second.y - first.y * second.x + first.z * second.w,
      w: first.w * second.w - first.x * second.x - first.y * second.y - first.z * second.z
    };
  }

  private static rotateVector(quaternion: NormalSkyQuaternion, vector: ViewVector3): ViewVector3 {
    const normalized: NormalSkyQuaternion = NormalSkyViewStateService.normalizeQuaternion(quaternion);
    const quaternionVector: ViewVector3 = { x: normalized.x, y: normalized.y, z: normalized.z };
    const firstCross: ViewVector3 = NormalSkyViewStateService.cross(quaternionVector, vector);
    const twiceCross: ViewVector3 = {
      x: firstCross.x * 2.0,
      y: firstCross.y * 2.0,
      z: firstCross.z * 2.0
    };
    const secondCross: ViewVector3 = NormalSkyViewStateService.cross(quaternionVector, twiceCross);
    return NormalSkyViewStateService.normalizeVector({
      x: vector.x + normalized.w * twiceCross.x + secondCross.x,
      y: vector.y + normalized.w * twiceCross.y + secondCross.y,
      z: vector.z + normalized.w * twiceCross.z + secondCross.z
    });
  }

  private static slerp(first: NormalSkyQuaternion, second: NormalSkyQuaternion,
    ratio: number): NormalSkyQuaternion {
    const start: NormalSkyQuaternion = NormalSkyViewStateService.normalizeQuaternion(first);
    let finish: NormalSkyQuaternion = NormalSkyViewStateService.normalizeQuaternion(second);
    let cosine: number = start.x * finish.x + start.y * finish.y +
      start.z * finish.z + start.w * finish.w;
    if (cosine < 0.0) {
      finish = { x: -finish.x, y: -finish.y, z: -finish.z, w: -finish.w };
      cosine = -cosine;
    }
    if (cosine > 0.9995) {
      return NormalSkyViewStateService.normalizeQuaternion({
        x: start.x + (finish.x - start.x) * ratio,
        y: start.y + (finish.y - start.y) * ratio,
        z: start.z + (finish.z - start.z) * ratio,
        w: start.w + (finish.w - start.w) * ratio
      });
    }
    const angle: number = Math.acos(NormalSkyViewStateService.clamp(cosine, -1.0, 1.0));
    const sine: number = Math.sin(angle);
    const firstWeight: number = Math.sin((1.0 - ratio) * angle) / sine;
    const secondWeight: number = Math.sin(ratio * angle) / sine;
    return NormalSkyViewStateService.normalizeQuaternion({
      x: start.x * firstWeight + finish.x * secondWeight,
      y: start.y * firstWeight + finish.y * secondWeight,
      z: start.z * firstWeight + finish.z * secondWeight,
      w: start.w * firstWeight + finish.w * secondWeight
    });
  }

  private static normalizeQuaternion(quaternion: NormalSkyQuaternion): NormalSkyQuaternion {
    const length: number = Math.sqrt(quaternion.x * quaternion.x + quaternion.y * quaternion.y +
      quaternion.z * quaternion.z + quaternion.w * quaternion.w);
    if (!Number.isFinite(length) || length <= 0.0000000001) {
      return { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
    }
    const sign: number = quaternion.w < 0.0 ? -1.0 : 1.0;
    return {
      x: quaternion.x / length * sign,
      y: quaternion.y / length * sign,
      z: quaternion.z / length * sign,
      w: quaternion.w / length * sign
    };
  }

  private static normalizeVector(vector: ViewVector3): ViewVector3 {
    const length: number = Math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z);
    if (!Number.isFinite(length) || length <= 0.0000000001) {
      return { x: 1.0, y: 0.0, z: 0.0 };
    }
    return { x: vector.x / length, y: vector.y / length, z: vector.z / length };
  }

  private static dot(first: ViewVector3, second: ViewVector3): number {
    return first.x * second.x + first.y * second.y + first.z * second.z;
  }

  private static cross(first: ViewVector3, second: ViewVector3): ViewVector3 {
    return {
      x: first.y * second.z - first.z * second.y,
      y: first.z * second.x - first.x * second.z,
      z: first.x * second.y - first.y * second.x
    };
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

import { EquatorialCoordinate, ObserverState } from '../models/DomainModels';
import {
  NormalSkyProjection,
  NormalSkyViewport,
  ProjectedSkyObject,
  SkyMapOrientation,
  SkyMapSize
} from '../models/NormalSkyModels';
import { AstronomyService } from './AstronomyService';

interface SkyVector3 {
  x: number;
  y: number;
  z: number;
}

/** 普通星图的无 UI 球面投影核心，可在本地单元测试中独立验证。 */
export class NormalSkyProjectionService {
  static readonly MIN_FIELD_OF_VIEW_DEGREES: number = 8.0;
  static readonly MAX_FIELD_OF_VIEW_DEGREES: number = 160.0;

  static defaultViewport(): NormalSkyViewport {
    return {
      centerRaHours: 0.0,
      centerDecDegrees: 0.0,
      fieldOfViewDegrees: 100.0,
      rotationDegrees: 0.0,
      orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
    };
  }

  /**
   * 回到当前天空。有定位时以天顶为中心；无定位时仍返回可用的赤道零点视图。
   * 地平模式会额外旋转画面，使本地北方位于屏幕上方、东方位于左侧。
   */
  static homeViewport(observer?: ObserverState,
    orientation: SkyMapOrientation = SkyMapOrientation.EQUATORIAL_NORTH_UP): NormalSkyViewport {
    if (observer === undefined) {
      const fallback: NormalSkyViewport = NormalSkyProjectionService.defaultViewport();
      fallback.orientation = orientation;
      return fallback;
    }
    const zenith: EquatorialCoordinate = AstronomyService.horizontalToEquatorial({
      altitudeDegrees: 90.0,
      azimuthDegrees: 0.0,
      aboveHorizon: true
    }, observer);
    const viewport: NormalSkyViewport = {
      centerRaHours: zenith.raHours,
      centerDecDegrees: zenith.decDegrees,
      fieldOfViewDegrees: 100.0,
      rotationDegrees: 0.0,
      orientation: orientation
    };
    if (orientation === SkyMapOrientation.HORIZON_ZENITH) {
      const north: EquatorialCoordinate = AstronomyService.horizontalToEquatorial({
        altitudeDegrees: 80.0,
        azimuthDegrees: 0.0,
        aboveHorizon: true
      }, observer);
      const northProjection: NormalSkyProjection = NormalSkyProjectionService.project(
        north, viewport, { widthPixels: 1000.0, heightPixels: 1000.0 });
      const deltaX: number = northProjection.xPixels - 500.0;
      const deltaY: number = northProjection.yPixels - 500.0;
      const currentAngle: number = Math.atan2(deltaY, deltaX) * 180.0 / Math.PI;
      viewport.rotationDegrees = NormalSkyProjectionService.normalizeSignedDegrees(-90.0 - currentAngle);
    }
    return NormalSkyProjectionService.normalizeViewport(viewport);
  }

  /** 立体投影：北方默认向上、赤经增加方向（东方）默认向左。 */
  static project(coordinate: EquatorialCoordinate, viewport: NormalSkyViewport,
    size: SkyMapSize): NormalSkyProjection {
    const normalized: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport(viewport);
    const basis: SkyVector3[] = NormalSkyProjectionService.viewBasis(normalized);
    const target: SkyVector3 = NormalSkyProjectionService.equatorialVector(coordinate);
    const centerDot: number = NormalSkyProjectionService.dot(target, basis[0]);
    const denominator: number = 1.0 + centerDot;
    const angularDistance: number = Math.acos(NormalSkyProjectionService.clamp(centerDot, -1.0, 1.0)) *
      180.0 / Math.PI;
    if (denominator <= 0.0000001) {
      return {
        xPixels: Number.MAX_VALUE,
        yPixels: Number.MAX_VALUE,
        inViewport: false,
        angularDistanceDegrees: angularDistance
      };
    }
    const planeEast: number = 2.0 * NormalSkyProjectionService.dot(target, basis[1]) / denominator;
    const planeNorth: number = 2.0 * NormalSkyProjectionService.dot(target, basis[2]) / denominator;
    const scale: number = NormalSkyProjectionService.pixelScale(normalized, size);
    const rawX: number = -planeEast * scale;
    const rawY: number = -planeNorth * scale;
    const rotated: SkyVector3 = NormalSkyProjectionService.rotateScreen(rawX, rawY,
      normalized.rotationDegrees);
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const x: number = width / 2.0 + rotated.x;
    const y: number = height / 2.0 + rotated.y;
    return {
      xPixels: x,
      yPixels: y,
      inViewport: x >= 0.0 && x <= width && y >= 0.0 && y <= height,
      angularDistanceDegrees: angularDistance
    };
  }

  static unproject(xPixels: number, yPixels: number, viewport: NormalSkyViewport,
    size: SkyMapSize): EquatorialCoordinate {
    const normalized: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport(viewport);
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const unrotated: SkyVector3 = NormalSkyProjectionService.rotateScreen(
      xPixels - width / 2.0, yPixels - height / 2.0, -normalized.rotationDegrees);
    const scale: number = NormalSkyProjectionService.pixelScale(normalized, size);
    const planeEast: number = -unrotated.x / scale;
    const planeNorth: number = -unrotated.y / scale;
    const radiusSquared: number = planeEast * planeEast + planeNorth * planeNorth;
    const denominator: number = 1.0 + radiusSquared / 4.0;
    const centerFactor: number = (1.0 - radiusSquared / 4.0) / denominator;
    const tangentFactor: number = 1.0 / denominator;
    const basis: SkyVector3[] = NormalSkyProjectionService.viewBasis(normalized);
    const result: SkyVector3 = NormalSkyProjectionService.normalizeVector({
      x: centerFactor * basis[0].x + tangentFactor *
        (planeEast * basis[1].x + planeNorth * basis[2].x),
      y: centerFactor * basis[0].y + tangentFactor *
        (planeEast * basis[1].y + planeNorth * basis[2].y),
      z: centerFactor * basis[0].z + tangentFactor *
        (planeEast * basis[1].z + planeNorth * basis[2].z)
    });
    return NormalSkyProjectionService.vectorCoordinate(result);
  }

  /** 手指移动多少像素，星空就跟随移动多少像素；返回值始终是新的球面中心。 */
  static pan(viewport: NormalSkyViewport, size: SkyMapSize,
    deltaXPixels: number, deltaYPixels: number): NormalSkyViewport {
    const normalized: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport(viewport);
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const center: EquatorialCoordinate = NormalSkyProjectionService.unproject(
      width / 2.0 - deltaXPixels, height / 2.0 - deltaYPixels, normalized, size);
    const previousBasis: SkyVector3[] = NormalSkyProjectionService.viewBasis(normalized);
    const previousCenter: SkyVector3 = previousBasis[0];
    const nextCenter: SkyVector3 = NormalSkyProjectionService.equatorialVector(center);
    const rotationRadians: number = normalized.rotationDegrees * Math.PI / 180.0;
    const previousScreenUp: SkyVector3 = NormalSkyProjectionService.normalizeVector({
      x: Math.sin(rotationRadians) * previousBasis[1].x + Math.cos(rotationRadians) * previousBasis[2].x,
      y: Math.sin(rotationRadians) * previousBasis[1].y + Math.cos(rotationRadians) * previousBasis[2].y,
      z: Math.sin(rotationRadians) * previousBasis[1].z + Math.cos(rotationRadians) * previousBasis[2].z
    });
    // 赤经在天极处没有唯一值。这里沿最短球面路径搬动画面“上方”向量，再反算新旋转角，
    // 使跨越南北天极时方向连续，而不是因赤经跳变 12 小时导致画面瞬间翻转 180 度。
    const transportedScreenUp: SkyVector3 = NormalSkyProjectionService.transportVector(
      previousScreenUp, previousCenter, nextCenter);
    const nextCoordinate: EquatorialCoordinate = NormalSkyProjectionService.vectorCoordinateWithFallback(
      nextCenter, normalized.centerRaHours);
    const nextBasis: SkyVector3[] = NormalSkyProjectionService.viewBasis({
      centerRaHours: nextCoordinate.raHours,
      centerDecDegrees: nextCoordinate.decDegrees,
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      rotationDegrees: 0.0,
      orientation: normalized.orientation
    });
    const nextRotation: number = Math.atan2(
      NormalSkyProjectionService.dot(transportedScreenUp, nextBasis[1]),
      NormalSkyProjectionService.dot(transportedScreenUp, nextBasis[2])) * 180.0 / Math.PI;
    return NormalSkyProjectionService.normalizeViewport({
      centerRaHours: nextCoordinate.raHours,
      centerDecDegrees: nextCoordinate.decDegrees,
      fieldOfViewDegrees: normalized.fieldOfViewDegrees,
      rotationDegrees: nextRotation,
      orientation: normalized.orientation
    });
  }

  /** 缩放时保持锚点下方的天体方向不漂移。scale > 1 表示放大。 */
  static zoomAt(viewport: NormalSkyViewport, size: SkyMapSize, scale: number,
    anchorX: number, anchorY: number): NormalSkyViewport {
    const safeScale: number = NormalSkyProjectionService.clamp(scale, 0.2, 5.0);
    const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(anchorX, anchorY, viewport, size);
    const candidate: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport({
      centerRaHours: viewport.centerRaHours,
      centerDecDegrees: viewport.centerDecDegrees,
      fieldOfViewDegrees: viewport.fieldOfViewDegrees / safeScale,
      rotationDegrees: viewport.rotationDegrees,
      orientation: viewport.orientation
    });
    return NormalSkyProjectionService.keepAnchor(candidate, size, anchor, anchorX, anchorY);
  }

  /** 旋转时保持双指中心下方的天体方向不漂移。正角度表示画面顺时针旋转。 */
  static rotateAt(viewport: NormalSkyViewport, size: SkyMapSize, deltaDegrees: number,
    anchorX: number, anchorY: number): NormalSkyViewport {
    const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(anchorX, anchorY, viewport, size);
    const candidate: NormalSkyViewport = NormalSkyProjectionService.normalizeViewport({
      centerRaHours: viewport.centerRaHours,
      centerDecDegrees: viewport.centerDecDegrees,
      fieldOfViewDegrees: viewport.fieldOfViewDegrees,
      rotationDegrees: viewport.rotationDegrees + deltaDegrees,
      orientation: viewport.orientation
    });
    return NormalSkyProjectionService.keepAnchor(candidate, size, anchor, anchorX, anchorY);
  }

  static flyTo(viewport: NormalSkyViewport, coordinate: EquatorialCoordinate,
    fieldOfViewDegrees: number = 30.0): NormalSkyViewport {
    return NormalSkyProjectionService.normalizeViewport({
      centerRaHours: coordinate.raHours,
      centerDecDegrees: coordinate.decDegrees,
      fieldOfViewDegrees: fieldOfViewDegrees,
      rotationDegrees: 0.0,
      orientation: viewport.orientation
    });
  }

  /** 使用球面插值避免跨越 0h 或天极时绕远路。 */
  static interpolate(first: NormalSkyViewport, second: NormalSkyViewport, progress: number): NormalSkyViewport {
    const ratio: number = NormalSkyProjectionService.clamp(progress, 0.0, 1.0);
    const firstVector: SkyVector3 = NormalSkyProjectionService.equatorialVector({
      raHours: first.centerRaHours, decDegrees: first.centerDecDegrees, epoch: 2000.0
    });
    const secondVector: SkyVector3 = NormalSkyProjectionService.equatorialVector({
      raHours: second.centerRaHours, decDegrees: second.centerDecDegrees, epoch: 2000.0
    });
    const center: EquatorialCoordinate = NormalSkyProjectionService.vectorCoordinate(
      NormalSkyProjectionService.slerp(firstVector, secondVector, ratio));
    const rotationDelta: number = NormalSkyProjectionService.normalizeSignedDegrees(
      second.rotationDegrees - first.rotationDegrees);
    return NormalSkyProjectionService.normalizeViewport({
      centerRaHours: center.raHours,
      centerDecDegrees: center.decDegrees,
      fieldOfViewDegrees: first.fieldOfViewDegrees +
        (second.fieldOfViewDegrees - first.fieldOfViewDegrees) * ratio,
      rotationDegrees: first.rotationDegrees + rotationDelta * ratio,
      orientation: ratio < 0.5 ? first.orientation : second.orientation
    });
  }

  static hitTest(objects: ProjectedSkyObject[], xPixels: number, yPixels: number,
    minimumRadiusPixels: number = 18.0): ProjectedSkyObject | undefined {
    let selected: ProjectedSkyObject | undefined = undefined;
    let selectedDistance: number = Number.MAX_VALUE;
    for (let index: number = 0; index < objects.length; index++) {
      const object: ProjectedSkyObject = objects[index];
      const deltaX: number = object.xPixels - xPixels;
      const deltaY: number = object.yPixels - yPixels;
      const distance: number = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
      const radius: number = Math.max(minimumRadiusPixels, object.hitRadiusPixels);
      if (distance > radius) {
        continue;
      }
      if (selected === undefined || distance < selectedDistance - 8.0 ||
        (Math.abs(distance - selectedDistance) <= 8.0 && object.hitPriority > selected.hitPriority)) {
        selected = object;
        selectedDistance = distance;
      }
    }
    return selected;
  }

  static normalizeViewport(viewport: NormalSkyViewport): NormalSkyViewport {
    return {
      centerRaHours: AstronomyService.normalizeHours(viewport.centerRaHours),
      centerDecDegrees: NormalSkyProjectionService.clamp(viewport.centerDecDegrees, -90.0, 90.0),
      fieldOfViewDegrees: NormalSkyProjectionService.clamp(viewport.fieldOfViewDegrees,
        NormalSkyProjectionService.MIN_FIELD_OF_VIEW_DEGREES,
        NormalSkyProjectionService.MAX_FIELD_OF_VIEW_DEGREES),
      rotationDegrees: NormalSkyProjectionService.normalizeSignedDegrees(viewport.rotationDegrees),
      orientation: viewport.orientation
    };
  }

  private static keepAnchor(viewport: NormalSkyViewport, size: SkyMapSize,
    anchor: EquatorialCoordinate, desiredX: number, desiredY: number): NormalSkyViewport {
    let candidate: NormalSkyViewport = viewport;
    // 少量迭代即可抵消北向基底随中心变化带来的误差，同时保留天极附近的稳定性。
    for (let iteration: number = 0; iteration < 6; iteration++) {
      const actual: NormalSkyProjection = NormalSkyProjectionService.project(anchor, candidate, size);
      if (!Number.isFinite(actual.xPixels) || !Number.isFinite(actual.yPixels)) {
        break;
      }
      const deltaX: number = desiredX - actual.xPixels;
      const deltaY: number = desiredY - actual.yPixels;
      if (Math.abs(deltaX) + Math.abs(deltaY) < 0.05) {
        break;
      }
      candidate = NormalSkyProjectionService.pan(candidate, size, deltaX, deltaY);
    }
    return NormalSkyProjectionService.normalizeViewport(candidate);
  }

  /** 返回中心、东、北三个正交向量。 */
  private static viewBasis(viewport: NormalSkyViewport): SkyVector3[] {
    const raRadians: number = viewport.centerRaHours * 15.0 * Math.PI / 180.0;
    const decRadians: number = viewport.centerDecDegrees * Math.PI / 180.0;
    return [
      {
        x: Math.cos(decRadians) * Math.cos(raRadians),
        y: Math.cos(decRadians) * Math.sin(raRadians),
        z: Math.sin(decRadians)
      },
      { x: -Math.sin(raRadians), y: Math.cos(raRadians), z: 0.0 },
      {
        x: -Math.sin(decRadians) * Math.cos(raRadians),
        y: -Math.sin(decRadians) * Math.sin(raRadians),
        z: Math.cos(decRadians)
      }
    ];
  }

  private static equatorialVector(coordinate: EquatorialCoordinate): SkyVector3 {
    const raRadians: number = coordinate.raHours * 15.0 * Math.PI / 180.0;
    const decRadians: number = coordinate.decDegrees * Math.PI / 180.0;
    return {
      x: Math.cos(decRadians) * Math.cos(raRadians),
      y: Math.cos(decRadians) * Math.sin(raRadians),
      z: Math.sin(decRadians)
    };
  }

  private static vectorCoordinate(vector: SkyVector3): EquatorialCoordinate {
    const normalized: SkyVector3 = NormalSkyProjectionService.normalizeVector(vector);
    return {
      raHours: AstronomyService.normalizeHours(Math.atan2(normalized.y, normalized.x) * 12.0 / Math.PI),
      decDegrees: Math.asin(NormalSkyProjectionService.clamp(normalized.z, -1.0, 1.0)) * 180.0 / Math.PI,
      epoch: 2000.0
    };
  }

  /** 天极附近沿用上一帧赤经，避免 atan2(0, 0) 的数值噪声改变整套切平面基底。 */
  private static vectorCoordinateWithFallback(vector: SkyVector3, fallbackRaHours: number): EquatorialCoordinate {
    const normalized: SkyVector3 = NormalSkyProjectionService.normalizeVector(vector);
    const horizontalLength: number = Math.sqrt(normalized.x * normalized.x + normalized.y * normalized.y);
    const raHours: number = horizontalLength < 0.0000001 ?
      AstronomyService.normalizeHours(fallbackRaHours) :
      AstronomyService.normalizeHours(Math.atan2(normalized.y, normalized.x) * 12.0 / Math.PI);
    return {
      raHours: raHours,
      decDegrees: Math.atan2(normalized.z, horizontalLength) * 180.0 / Math.PI,
      epoch: 2000.0
    };
  }

  /**
   * 用把 fromCenter 旋到 toCenter 的最短三维旋转搬运切平面向量。
   * 单次拖拽不应到达对跖点；仍为该退化情形保留确定轴，确保永不返回 NaN。
   */
  private static transportVector(vector: SkyVector3, fromCenter: SkyVector3,
    toCenter: SkyVector3): SkyVector3 {
    const cosine: number = NormalSkyProjectionService.clamp(
      NormalSkyProjectionService.dot(fromCenter, toCenter), -1.0, 1.0);
    const cross: SkyVector3 = NormalSkyProjectionService.cross(fromCenter, toCenter);
    const sine: number = Math.sqrt(NormalSkyProjectionService.dot(cross, cross));
    if (sine < 0.0000001) {
      if (cosine >= 0.0) {
        return vector;
      }
      return NormalSkyProjectionService.rotateAroundAxis(vector,
        NormalSkyProjectionService.normalizeVector(vector), Math.PI);
    }
    const axis: SkyVector3 = {
      x: cross.x / sine,
      y: cross.y / sine,
      z: cross.z / sine
    };
    return NormalSkyProjectionService.normalizeVector(
      NormalSkyProjectionService.rotateAroundAxis(vector, axis, Math.atan2(sine, cosine)));
  }

  private static rotateAroundAxis(vector: SkyVector3, axis: SkyVector3, angleRadians: number): SkyVector3 {
    const cosine: number = Math.cos(angleRadians);
    const sine: number = Math.sin(angleRadians);
    const axisDot: number = NormalSkyProjectionService.dot(axis, vector);
    const axisCross: SkyVector3 = NormalSkyProjectionService.cross(axis, vector);
    return {
      x: vector.x * cosine + axisCross.x * sine + axis.x * axisDot * (1.0 - cosine),
      y: vector.y * cosine + axisCross.y * sine + axis.y * axisDot * (1.0 - cosine),
      z: vector.z * cosine + axisCross.z * sine + axis.z * axisDot * (1.0 - cosine)
    };
  }

  private static pixelScale(viewport: NormalSkyViewport, size: SkyMapSize): number {
    const halfFieldRadians: number = viewport.fieldOfViewDegrees * Math.PI / 360.0;
    const planeHalfWidth: number = 2.0 * Math.tan(halfFieldRadians / 2.0);
    return Math.max(1.0, size.widthPixels) / (2.0 * Math.max(0.000001, planeHalfWidth));
  }

  private static rotateScreen(x: number, y: number, angleDegrees: number): SkyVector3 {
    const radians: number = angleDegrees * Math.PI / 180.0;
    return {
      x: x * Math.cos(radians) - y * Math.sin(radians),
      y: x * Math.sin(radians) + y * Math.cos(radians),
      z: 0.0
    };
  }

  private static slerp(first: SkyVector3, second: SkyVector3, ratio: number): SkyVector3 {
    const cosine: number = NormalSkyProjectionService.clamp(
      NormalSkyProjectionService.dot(first, second), -1.0, 1.0);
    const angle: number = Math.acos(cosine);
    if (angle < 0.000001) {
      return first;
    }
    const sine: number = Math.sin(angle);
    if (Math.abs(sine) < 0.000001) {
      return NormalSkyProjectionService.normalizeVector({
        x: first.x * (1.0 - ratio) + second.x * ratio,
        y: first.y * (1.0 - ratio) + second.y * ratio,
        z: first.z * (1.0 - ratio) + second.z * ratio
      });
    }
    const firstWeight: number = Math.sin((1.0 - ratio) * angle) / sine;
    const secondWeight: number = Math.sin(ratio * angle) / sine;
    return NormalSkyProjectionService.normalizeVector({
      x: first.x * firstWeight + second.x * secondWeight,
      y: first.y * firstWeight + second.y * secondWeight,
      z: first.z * firstWeight + second.z * secondWeight
    });
  }

  private static normalizeVector(vector: SkyVector3): SkyVector3 {
    const length: number = Math.max(0.0000001,
      Math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z));
    return { x: vector.x / length, y: vector.y / length, z: vector.z / length };
  }

  private static dot(first: SkyVector3, second: SkyVector3): number {
    return first.x * second.x + first.y * second.y + first.z * second.z;
  }

  private static cross(first: SkyVector3, second: SkyVector3): SkyVector3 {
    return {
      x: first.y * second.z - first.z * second.y,
      y: first.z * second.x - first.x * second.z,
      z: first.x * second.y - first.y * second.x
    };
  }

  private static normalizeSignedDegrees(value: number): number {
    const normalized: number = AstronomyService.normalizeDegrees(value);
    return normalized > 180.0 ? normalized - 360.0 : normalized;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

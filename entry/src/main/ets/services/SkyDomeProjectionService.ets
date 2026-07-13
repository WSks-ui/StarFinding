import {
  ArPoseSample,
  Quaternion,
  SkyDomeFrame,
  SkyDomeMarker,
  SkyDomePoint,
  SkyDomePolyline,
  SkyDomeRenderOptions,
  SkyDomeStarInput,
  SkyDomeViewport
} from '../models/ArSkyModels';

interface Vector3 {
  x: number;
  y: number;
  z: number;
}

interface ResolvedProjectionOptions {
  domeFieldOfViewDegrees: number;
  perspectiveStrength: number;
  edgeCompression: number;
  minimumAltitudeDegrees: number;
  markerMinimumSizePixels: number;
  markerMaximumSizePixels: number;
  showHorizon: boolean;
  showAltitudeGuides: boolean;
  guideSampleStepDegrees: number;
}

interface ProjectedDirection {
  xPixels: number;
  yPixels: number;
  angularDistanceDegrees: number;
  domeRadius: number;
  inViewport: boolean;
}

export interface SkyDomeEulerOrientation {
  headingDegrees: number;
  pitchDegrees: number;
  rollDegrees: number;
}

/**
 * 将地平坐标投影成适合 AR 预览的鱼眼天穹。
 *
 * 本服务不访问设备或 ArkUI API，既可供 Canvas 实时渲染，也可在单元测试和姿态回放中复用。
 */
export class SkyDomeProjectionService {
  private static readonly DEG_TO_RAD: number = Math.PI / 180.0;
  private static readonly RAD_TO_DEG: number = 180.0 / Math.PI;
  private static readonly EPSILON: number = 0.000001;

  static defaultRenderOptions(): SkyDomeRenderOptions {
    return {
      domeFieldOfViewDegrees: 170.0,
      perspectiveStrength: 0.35,
      edgeCompression: 0.45,
      minimumAltitudeDegrees: 0.0,
      markerMinimumSizePixels: 2.0,
      markerMaximumSizePixels: 10.0,
      showHorizon: true,
      showAltitudeGuides: true,
      guideSampleStepDegrees: 4.0
    };
  }

  /** 生成一个可直接交给批量绘制层的完整帧。 */
  static createFrame(stars: SkyDomeStarInput[], pose: ArPoseSample, viewport: SkyDomeViewport,
    options?: SkyDomeRenderOptions): SkyDomeFrame {
    const resolved: ResolvedProjectionOptions = SkyDomeProjectionService.resolveOptions(options);
    const markers: SkyDomeMarker[] = [];
    for (let index: number = 0; index < stars.length; index++) {
      const star: SkyDomeStarInput = stars[index];
      if (star.altitudeDegrees < resolved.minimumAltitudeDegrees) {
        continue;
      }
      const marker: SkyDomeMarker = SkyDomeProjectionService.projectStarInternal(
        star, pose.orientation, viewport, resolved);
      if (marker.inViewport) {
        markers.push(marker);
      }
    }

    return {
      timestampNs: pose.timestampNs,
      trackingQuality: pose.quality,
      trackingSource: pose.source,
      viewport: viewport,
      markers: markers,
      guideLines: SkyDomeProjectionService.createGuideLinesInternal(pose.orientation, viewport, resolved)
    };
  }

  /** 投影单颗星；即使星体在视口外也返回角距离，便于上层制作目标方向指示。 */
  static projectStar(star: SkyDomeStarInput, pose: ArPoseSample, viewport: SkyDomeViewport,
    options?: SkyDomeRenderOptions): SkyDomeMarker {
    return SkyDomeProjectionService.projectStarInternal(
      star, pose.orientation, viewport, SkyDomeProjectionService.resolveOptions(options));
  }

  /** 单独生成地平线、30 度和 60 度高度弧。 */
  static createGuideLines(pose: ArPoseSample, viewport: SkyDomeViewport,
    options?: SkyDomeRenderOptions): SkyDomePolyline[] {
    return SkyDomeProjectionService.createGuideLinesInternal(
      pose.orientation, viewport, SkyDomeProjectionService.resolveOptions(options));
  }

  /**
   * 查找点击位置附近最近的可见星体。maxDistancePixels 是星点中心的最大命中距离，
   * 渲染层可在 Pad 上传入 24 到 36 像素，保证小星点仍易于选择。
   */
  static findNearestMarker(markers: SkyDomeMarker[], xPixels: number, yPixels: number,
    maxDistancePixels: number): SkyDomeMarker | undefined {
    const safeMaximum: number = Math.max(0.0, maxDistancePixels);
    const maximumSquared: number = safeMaximum * safeMaximum;
    let nearest: SkyDomeMarker | undefined = undefined;
    let nearestSquared: number = maximumSquared;
    let nearestPriority: number = -1;
    for (let index: number = 0; index < markers.length; index++) {
      const marker: SkyDomeMarker = markers[index];
      if (!marker.inViewport) {
        continue;
      }
      const deltaX: number = marker.xPixels - xPixels;
      const deltaY: number = marker.yPixels - yPixels;
      const distanceSquared: number = deltaX * deltaX + deltaY * deltaY;
      const priority: number = SkyDomeProjectionService.markerSelectionPriority(marker);
      const overlapsCurrent: boolean = Math.abs(distanceSquared - nearestSquared) <= 36.0;
      if (distanceSquared <= maximumSquared &&
        (nearest === undefined || distanceSquared + 36.0 < nearestSquared ||
          (overlapsCurrent && priority > nearestPriority))) {
        nearest = marker;
        nearestSquared = distanceSquared;
        nearestPriority = priority;
      }
    }
    return nearest;
  }

  /** 重叠命中时优先返回拥有完整天体资料、规划和拍摄动作的规范目标。 */
  private static markerSelectionPriority(marker: SkyDomeMarker): number {
    if (marker.selected) return 3;
    if (marker.id.startsWith('target:')) return 2;
    if (marker.id.startsWith('catalog:')) return 1;
    return 0;
  }

  static normalizeDegrees(value: number): number {
    let normalized: number = value % 360.0;
    if (normalized < 0.0) {
      normalized += 360.0;
    }
    return normalized;
  }

  static normalizeSignedDegrees(value: number): number {
    return SkyDomeProjectionService.normalizeDegrees(value + 180.0) - 180.0;
  }

  /** 返回从 from 到 to 的最短有符号角差，范围为 [-180, 180)。 */
  static shortestAngleDeltaDegrees(fromDegrees: number, toDegrees: number): number {
    return SkyDomeProjectionService.normalizeDegrees(toDegrees - fromDegrees + 180.0) - 180.0;
  }

  static interpolateAngleDegrees(fromDegrees: number, toDegrees: number, ratio: number): number {
    const safeRatio: number = SkyDomeProjectionService.clamp(ratio, 0.0, 1.0);
    return SkyDomeProjectionService.normalizeDegrees(fromDegrees +
      SkyDomeProjectionService.shortestAngleDeltaDegrees(fromDegrees, toDegrees) * safeRatio);
  }

  static normalizeQuaternion(value: Quaternion): Quaternion {
    const length: number = Math.sqrt(value.x * value.x + value.y * value.y +
      value.z * value.z + value.w * value.w);
    if (length < SkyDomeProjectionService.EPSILON) {
      return { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
    }
    return {
      x: value.x / length,
      y: value.y / length,
      z: value.z / length,
      w: value.w / length
    };
  }

  /** 球面插值会自动翻转终点四元数，保证沿较短旋转路径过渡。 */
  static slerpQuaternion(from: Quaternion, to: Quaternion, ratio: number): Quaternion {
    const safeRatio: number = SkyDomeProjectionService.clamp(ratio, 0.0, 1.0);
    const first: Quaternion = SkyDomeProjectionService.normalizeQuaternion(from);
    let second: Quaternion = SkyDomeProjectionService.normalizeQuaternion(to);
    let dot: number = first.x * second.x + first.y * second.y + first.z * second.z + first.w * second.w;

    if (dot < 0.0) {
      second = { x: -second.x, y: -second.y, z: -second.z, w: -second.w };
      dot = -dot;
    }
    dot = SkyDomeProjectionService.clamp(dot, -1.0, 1.0);

    if (dot > 0.9995) {
      return SkyDomeProjectionService.normalizeQuaternion({
        x: first.x + (second.x - first.x) * safeRatio,
        y: first.y + (second.y - first.y) * safeRatio,
        z: first.z + (second.z - first.z) * safeRatio,
        w: first.w + (second.w - first.w) * safeRatio
      });
    }

    const angle: number = Math.acos(dot);
    const sine: number = Math.sin(angle);
    const firstWeight: number = Math.sin((1.0 - safeRatio) * angle) / sine;
    const secondWeight: number = Math.sin(safeRatio * angle) / sine;
    return SkyDomeProjectionService.normalizeQuaternion({
      x: first.x * firstWeight + second.x * secondWeight,
      y: first.y * firstWeight + second.y * secondWeight,
      z: first.z * firstWeight + second.z * secondWeight,
      w: first.w * firstWeight + second.w * secondWeight
    });
  }

  /**
   * 从后摄中心方位、高度和顺时针横滚生成 orientation。
   * 该方法主要供传感器降级链路与姿态回放使用；AR Engine Provider 应输出同一坐标约定。
   */
  static quaternionFromHeadingPitchRoll(headingDegrees: number, pitchDegrees: number,
    rollDegrees: number): Quaternion {
    const heading: number = SkyDomeProjectionService.normalizeDegrees(headingDegrees) *
      SkyDomeProjectionService.DEG_TO_RAD;
    const pitch: number = SkyDomeProjectionService.clamp(pitchDegrees, -90.0, 90.0) *
      SkyDomeProjectionService.DEG_TO_RAD;
    const roll: number = rollDegrees * SkyDomeProjectionService.DEG_TO_RAD;

    const forward: Vector3 = {
      x: Math.sin(heading) * Math.cos(pitch),
      y: Math.cos(heading) * Math.cos(pitch),
      z: Math.sin(pitch)
    };
    const levelRight: Vector3 = { x: Math.cos(heading), y: -Math.sin(heading), z: 0.0 };
    const levelDown: Vector3 = SkyDomeProjectionService.cross(forward, levelRight);
    const cosine: number = Math.cos(roll);
    const sine: number = Math.sin(roll);
    const right: Vector3 = {
      x: levelRight.x * cosine + levelDown.x * sine,
      y: levelRight.y * cosine + levelDown.y * sine,
      z: levelRight.z * cosine + levelDown.z * sine
    };
    const down: Vector3 = {
      x: -levelRight.x * sine + levelDown.x * cosine,
      y: -levelRight.y * sine + levelDown.y * cosine,
      z: -levelRight.z * sine + levelDown.z * cosine
    };
    return SkyDomeProjectionService.quaternionFromBasis(right, down, forward);
  }

  /** Hamilton 乘法；结果表示先应用 second，再应用 first。 */
  static multiplyQuaternion(first: Quaternion, second: Quaternion): Quaternion {
    const a: Quaternion = SkyDomeProjectionService.normalizeQuaternion(first);
    const b: Quaternion = SkyDomeProjectionService.normalizeQuaternion(second);
    return SkyDomeProjectionService.normalizeQuaternion({
      x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
      w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    });
  }

  /**
   * 把设备自然坐标到磁北 ENU 的旋转向量，转换成当前屏幕后摄坐标到 ENU 的 orientation。
   * displayRotation 取 0/1/2/3，分别对应系统顺时针旋转 0/90/180/270 度。
   */
  static cameraOrientationFromDeviceOrientation(deviceOrientation: Quaternion,
    displayRotation: number): Quaternion {
    const halfSqrt: number = Math.SQRT1_2;
    const normalizedRotation: number = ((Math.round(displayRotation) % 4) + 4) % 4;
    let cameraToDevice: Quaternion = { x: 1.0, y: 0.0, z: 0.0, w: 0.0 };
    if (normalizedRotation === 1) {
      cameraToDevice = { x: halfSqrt, y: halfSqrt, z: 0.0, w: 0.0 };
    } else if (normalizedRotation === 2) {
      cameraToDevice = { x: 0.0, y: 1.0, z: 0.0, w: 0.0 };
    } else if (normalizedRotation === 3) {
      cameraToDevice = { x: halfSqrt, y: -halfSqrt, z: 0.0, w: 0.0 };
    }
    return SkyDomeProjectionService.multiplyQuaternion(deviceOrientation, cameraToDevice);
  }

  /** 把统一 orientation 转回页面状态使用的镜头方位、高度和顺时针横滚。 */
  static headingPitchRollFromQuaternion(orientation: Quaternion,
    fallbackHeadingDegrees: number = 0.0): SkyDomeEulerOrientation {
    const normalized: Quaternion = SkyDomeProjectionService.normalizeQuaternion(orientation);
    const forward: Vector3 = SkyDomeProjectionService.rotateVector(normalized, { x: 0.0, y: 0.0, z: 1.0 });
    const horizontalLength: number = Math.sqrt(forward.x * forward.x + forward.y * forward.y);
    const headingDegrees: number = horizontalLength < 0.0001 ?
      SkyDomeProjectionService.normalizeDegrees(fallbackHeadingDegrees) :
      SkyDomeProjectionService.normalizeDegrees(Math.atan2(forward.x, forward.y) *
        SkyDomeProjectionService.RAD_TO_DEG);
    const pitchDegrees: number = Math.asin(SkyDomeProjectionService.clamp(forward.z, -1.0, 1.0)) *
      SkyDomeProjectionService.RAD_TO_DEG;
    const heading: number = headingDegrees * SkyDomeProjectionService.DEG_TO_RAD;
    const levelRight: Vector3 = { x: Math.cos(heading), y: -Math.sin(heading), z: 0.0 };
    const levelDown: Vector3 = SkyDomeProjectionService.cross(forward, levelRight);
    const actualRight: Vector3 = SkyDomeProjectionService.rotateVector(
      normalized, { x: 1.0, y: 0.0, z: 0.0 });
    const rollDegrees: number = Math.atan2(
      SkyDomeProjectionService.dot(actualRight, levelDown),
      SkyDomeProjectionService.dot(actualRight, levelRight)) * SkyDomeProjectionService.RAD_TO_DEG;
    return {
      headingDegrees: headingDegrees,
      pitchDegrees: pitchDegrees,
      rollDegrees: SkyDomeProjectionService.normalizeSignedDegrees(rollDegrees)
    };
  }

  private static projectStarInternal(star: SkyDomeStarInput, orientation: Quaternion,
    viewport: SkyDomeViewport, options: ResolvedProjectionOptions): SkyDomeMarker {
    const direction: ProjectedDirection = SkyDomeProjectionService.projectDirection(
      star.azimuthDegrees, star.altitudeDegrees, orientation, viewport, options);
    const magnitudeRatio: number = SkyDomeProjectionService.clamp((star.magnitude + 1.5) / 8.5, 0.0, 1.0);
    const baseSize: number = options.markerMaximumSizePixels - magnitudeRatio *
      (options.markerMaximumSizePixels - options.markerMinimumSizePixels);
    const selected: boolean = star.selected === true;
    return {
      id: star.id,
      label: star.label,
      azimuthDegrees: SkyDomeProjectionService.normalizeDegrees(star.azimuthDegrees),
      altitudeDegrees: star.altitudeDegrees,
      magnitude: star.magnitude,
      color: star.color === undefined ? '#EAF3FF' : star.color,
      selected: selected,
      xPixels: direction.xPixels,
      yPixels: direction.yPixels,
      sizePixels: selected ? baseSize * 1.45 : baseSize,
      opacity: selected ? 1.0 : SkyDomeProjectionService.clamp(1.0 - magnitudeRatio * 0.55, 0.3, 1.0),
      angularDistanceDegrees: direction.angularDistanceDegrees,
      domeRadius: direction.domeRadius,
      aboveHorizon: star.altitudeDegrees >= 0.0,
      inViewport: direction.inViewport && star.altitudeDegrees >= options.minimumAltitudeDegrees
    };
  }

  private static projectDirection(azimuthDegrees: number, altitudeDegrees: number,
    orientation: Quaternion, viewport: SkyDomeViewport,
    options: ResolvedProjectionOptions): ProjectedDirection {
    const worldDirection: Vector3 = SkyDomeProjectionService.horizontalVector(
      azimuthDegrees, altitudeDegrees);
    const normalizedOrientation: Quaternion = SkyDomeProjectionService.normalizeQuaternion(orientation);
    const inverse: Quaternion = {
      x: -normalizedOrientation.x,
      y: -normalizedOrientation.y,
      z: -normalizedOrientation.z,
      w: normalizedOrientation.w
    };
    const cameraDirection: Vector3 = SkyDomeProjectionService.rotateVector(inverse, worldDirection);
    const radialSine: number = Math.sqrt(cameraDirection.x * cameraDirection.x +
      cameraDirection.y * cameraDirection.y);
    const angularDistance: number = Math.atan2(radialSine, cameraDirection.z);
    const halfFieldOfView: number = options.domeFieldOfViewDegrees *
      SkyDomeProjectionService.DEG_TO_RAD / 2.0;

    let unitX: number = 0.0;
    let unitY: number = 0.0;
    if (radialSine >= SkyDomeProjectionService.EPSILON) {
      unitX = cameraDirection.x / radialSine;
      unitY = cameraDirection.y / radialSine;
    }

    const equidistantRadius: number = angularDistance / halfFieldOfView;
    const stereoDenominator: number = Math.tan(halfFieldOfView / 2.0);
    const stereographicRadius: number = Math.tan(angularDistance / 2.0) /
      Math.max(stereoDenominator, SkyDomeProjectionService.EPSILON);
    let domeRadius: number = equidistantRadius * (1.0 - options.perspectiveStrength) +
      stereographicRadius * options.perspectiveStrength;

    // 该有理函数保持视场边界仍为 1，同时降低边缘处的径向变化速度，形成穹顶包裹感。
    const compression: number = options.edgeCompression * 1.8;
    domeRadius = domeRadius * (1.0 + compression) / (1.0 + compression * domeRadius);

    const halfWidth: number = Math.max(1.0, viewport.widthPixels) / 2.0;
    const halfHeight: number = Math.max(1.0, viewport.heightPixels) / 2.0;
    const xPixels: number = halfWidth + unitX * domeRadius * halfWidth;
    const yPixels: number = halfHeight + unitY * domeRadius * halfHeight;
    const withinAngularField: boolean = angularDistance <= halfFieldOfView +
      SkyDomeProjectionService.EPSILON;
    const inViewport: boolean = withinAngularField && xPixels >= 0.0 &&
      xPixels <= viewport.widthPixels && yPixels >= 0.0 && yPixels <= viewport.heightPixels;
    return {
      xPixels: xPixels,
      yPixels: yPixels,
      angularDistanceDegrees: angularDistance * SkyDomeProjectionService.RAD_TO_DEG,
      domeRadius: domeRadius,
      inViewport: inViewport
    };
  }

  private static createGuideLinesInternal(orientation: Quaternion, viewport: SkyDomeViewport,
    options: ResolvedProjectionOptions): SkyDomePolyline[] {
    const lines: SkyDomePolyline[] = [];
    if (options.showHorizon) {
      SkyDomeProjectionService.appendAltitudeGuide(lines, 0.0, orientation, viewport, options);
    }
    if (options.showAltitudeGuides) {
      SkyDomeProjectionService.appendAltitudeGuide(lines, 30.0, orientation, viewport, options);
      SkyDomeProjectionService.appendAltitudeGuide(lines, 60.0, orientation, viewport, options);
    }
    return lines;
  }

  private static appendAltitudeGuide(destination: SkyDomePolyline[], altitudeDegrees: number,
    orientation: Quaternion, viewport: SkyDomeViewport, options: ResolvedProjectionOptions): void {
    let currentPoints: SkyDomePoint[] = [];
    let segmentIndex: number = 0;
    const sampleCount: number = Math.ceil(360.0 / options.guideSampleStepDegrees);
    for (let index: number = 0; index <= sampleCount; index++) {
      const azimuth: number = index === sampleCount ? 360.0 : index * 360.0 / sampleCount;
      const projected: ProjectedDirection = SkyDomeProjectionService.projectDirection(
        azimuth, altitudeDegrees, orientation, viewport, options);
      if (projected.inViewport) {
        currentPoints.push({ xPixels: projected.xPixels, yPixels: projected.yPixels });
      } else if (currentPoints.length > 1) {
        SkyDomeProjectionService.pushGuideSegment(
          destination, altitudeDegrees, segmentIndex, currentPoints);
        segmentIndex++;
        currentPoints = [];
      } else {
        currentPoints = [];
      }
    }
    if (currentPoints.length > 1) {
      SkyDomeProjectionService.pushGuideSegment(
        destination, altitudeDegrees, segmentIndex, currentPoints);
    }
  }

  private static pushGuideSegment(destination: SkyDomePolyline[], altitudeDegrees: number,
    segmentIndex: number, points: SkyDomePoint[]): void {
    const roundedAltitude: number = Math.round(altitudeDegrees);
    destination.push({
      id: `altitude-${roundedAltitude}-${segmentIndex}`,
      altitudeDegrees: altitudeDegrees,
      points: points,
      opacity: altitudeDegrees === 0.0 ? 0.72 : 0.36,
      lineWidthPixels: altitudeDegrees === 0.0 ? 1.8 : 1.0
    });
  }

  private static resolveOptions(options?: SkyDomeRenderOptions): ResolvedProjectionOptions {
    const value: SkyDomeRenderOptions = options === undefined ?
      SkyDomeProjectionService.defaultRenderOptions() : options;
    const minimumSize: number = Math.max(0.5, value.markerMinimumSizePixels);
    return {
      domeFieldOfViewDegrees: SkyDomeProjectionService.clamp(value.domeFieldOfViewDegrees, 30.0, 178.0),
      perspectiveStrength: SkyDomeProjectionService.clamp(value.perspectiveStrength, 0.0, 1.0),
      edgeCompression: SkyDomeProjectionService.clamp(value.edgeCompression, 0.0, 1.0),
      minimumAltitudeDegrees: SkyDomeProjectionService.clamp(value.minimumAltitudeDegrees, -90.0, 90.0),
      markerMinimumSizePixels: minimumSize,
      markerMaximumSizePixels: Math.max(minimumSize, value.markerMaximumSizePixels),
      showHorizon: value.showHorizon,
      showAltitudeGuides: value.showAltitudeGuides,
      guideSampleStepDegrees: SkyDomeProjectionService.clamp(value.guideSampleStepDegrees, 1.0, 30.0)
    };
  }

  private static horizontalVector(azimuthDegrees: number, altitudeDegrees: number): Vector3 {
    const azimuth: number = SkyDomeProjectionService.normalizeDegrees(azimuthDegrees) *
      SkyDomeProjectionService.DEG_TO_RAD;
    const altitude: number = SkyDomeProjectionService.clamp(altitudeDegrees, -90.0, 90.0) *
      SkyDomeProjectionService.DEG_TO_RAD;
    return {
      x: Math.sin(azimuth) * Math.cos(altitude),
      y: Math.cos(azimuth) * Math.cos(altitude),
      z: Math.sin(altitude)
    };
  }

  private static rotateVector(rotation: Quaternion, vector: Vector3): Vector3 {
    const twiceCross: Vector3 = {
      x: 2.0 * (rotation.y * vector.z - rotation.z * vector.y),
      y: 2.0 * (rotation.z * vector.x - rotation.x * vector.z),
      z: 2.0 * (rotation.x * vector.y - rotation.y * vector.x)
    };
    const secondCross: Vector3 = SkyDomeProjectionService.cross(
      { x: rotation.x, y: rotation.y, z: rotation.z }, twiceCross);
    return {
      x: vector.x + rotation.w * twiceCross.x + secondCross.x,
      y: vector.y + rotation.w * twiceCross.y + secondCross.y,
      z: vector.z + rotation.w * twiceCross.z + secondCross.z
    };
  }

  private static quaternionFromBasis(right: Vector3, down: Vector3, forward: Vector3): Quaternion {
    const m00: number = right.x;
    const m01: number = down.x;
    const m02: number = forward.x;
    const m10: number = right.y;
    const m11: number = down.y;
    const m12: number = forward.y;
    const m20: number = right.z;
    const m21: number = down.z;
    const m22: number = forward.z;
    const trace: number = m00 + m11 + m22;
    let result: Quaternion;

    if (trace > 0.0) {
      const scale: number = Math.sqrt(trace + 1.0) * 2.0;
      result = {
        x: (m21 - m12) / scale,
        y: (m02 - m20) / scale,
        z: (m10 - m01) / scale,
        w: 0.25 * scale
      };
    } else if (m00 > m11 && m00 > m22) {
      const scale: number = Math.sqrt(1.0 + m00 - m11 - m22) * 2.0;
      result = {
        x: 0.25 * scale,
        y: (m01 + m10) / scale,
        z: (m02 + m20) / scale,
        w: (m21 - m12) / scale
      };
    } else if (m11 > m22) {
      const scale: number = Math.sqrt(1.0 + m11 - m00 - m22) * 2.0;
      result = {
        x: (m01 + m10) / scale,
        y: 0.25 * scale,
        z: (m12 + m21) / scale,
        w: (m02 - m20) / scale
      };
    } else {
      const scale: number = Math.sqrt(1.0 + m22 - m00 - m11) * 2.0;
      result = {
        x: (m02 + m20) / scale,
        y: (m12 + m21) / scale,
        z: 0.25 * scale,
        w: (m10 - m01) / scale
      };
    }
    return SkyDomeProjectionService.normalizeQuaternion(result);
  }

  private static cross(first: Vector3, second: Vector3): Vector3 {
    return {
      x: first.y * second.z - first.z * second.y,
      y: first.z * second.x - first.x * second.z,
      z: first.x * second.y - first.y * second.x
    };
  }

  private static dot(first: Vector3, second: Vector3): number {
    return first.x * second.x + first.y * second.y + first.z * second.z;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

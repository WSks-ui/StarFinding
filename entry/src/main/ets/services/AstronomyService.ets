import {
  ArCalibration,
  CameraViewport,
  CatalogPrecision,
  CelestialObject,
  DevicePose,
  EquatorialCoordinate,
  EquatorialFrame,
  HorizontalCoordinate,
  ObserverState,
  ScreenProjection
} from '../models/DomainModels';

interface Vector3 {
  x: number;
  y: number;
  z: number;
}
interface OrbitalElements {
  ascendingNodeDegrees: number;
  inclinationDegrees: number;
  perihelionDegrees: number;
  semiMajorAxis: number;
  eccentricity: number;
  meanAnomalyDegrees: number;
}

export class AstronomyService {
  private static readonly DEG_TO_RAD: number = Math.PI / 180.0;
  private static readonly RAD_TO_DEG: number = 180.0 / Math.PI;

  static normalizeDegrees(value: number): number {
    let result: number = value % 360.0;
    if (result < 0.0) {
      result += 360.0;
    }
    return result;
  }

  static normalizeSignedDegrees(value: number): number {
    const normalized: number = AstronomyService.normalizeDegrees(value);
    return normalized > 180.0 ? normalized - 360.0 : normalized;
  }

  static normalizeHours(value: number): number {
    let result: number = value % 24.0;
    if (result < 0.0) {
      result += 24.0;
    }
    return result;
  }

  static julianDay(timestampMs: number): number {
    return timestampMs / 86400000.0 + 2440587.5;
  }

  static greenwichSiderealDegrees(timestampMs: number): number {
    const julianDay: number = AstronomyService.julianDay(timestampMs);
    const centuries: number = (julianDay - 2451545.0) / 36525.0;
    const sidereal: number = 280.46061837 + 360.98564736629 * (julianDay - 2451545.0) +
      0.000387933 * centuries * centuries - centuries * centuries * centuries / 38710000.0;
    return AstronomyService.normalizeDegrees(sidereal);
  }

  static localSiderealDegrees(observer: ObserverState): number {
    return AstronomyService.normalizeDegrees(
      AstronomyService.greenwichSiderealDegrees(observer.timestampMs) + observer.longitudeDegrees);
  }

  static equatorialToHorizontal(coordinate: EquatorialCoordinate,
    observer: ObserverState): HorizontalCoordinate {
    const latitudeRad: number = observer.latitudeDegrees * AstronomyService.DEG_TO_RAD;
    const declinationRad: number = coordinate.decDegrees * AstronomyService.DEG_TO_RAD;
    const hourAngleDegrees: number = AstronomyService.normalizeSignedDegrees(
      AstronomyService.localSiderealDegrees(observer) - coordinate.raHours * 15.0);
    const hourAngleRad: number = hourAngleDegrees * AstronomyService.DEG_TO_RAD;

    const altitudeRad: number = Math.asin(Math.sin(declinationRad) * Math.sin(latitudeRad) +
      Math.cos(declinationRad) * Math.cos(latitudeRad) * Math.cos(hourAngleRad));
    const azimuthRad: number = Math.atan2(Math.sin(hourAngleRad),
      Math.cos(hourAngleRad) * Math.sin(latitudeRad) - Math.tan(declinationRad) * Math.cos(latitudeRad));
    const altitudeDegrees: number = altitudeRad * AstronomyService.RAD_TO_DEG;
    return {
      altitudeDegrees: altitudeDegrees,
      azimuthDegrees: AstronomyService.normalizeDegrees(azimuthRad * AstronomyService.RAD_TO_DEG + 180.0),
      aboveHorizon: altitudeDegrees > 0.0
    };
  }

  static horizontalToEquatorial(horizontal: HorizontalCoordinate,
    observer: ObserverState): EquatorialCoordinate {
    const altitudeRad: number = horizontal.altitudeDegrees * AstronomyService.DEG_TO_RAD;
    const azimuthRad: number = horizontal.azimuthDegrees * AstronomyService.DEG_TO_RAD;
    const latitudeRad: number = observer.latitudeDegrees * AstronomyService.DEG_TO_RAD;

    const decRad: number = Math.asin(Math.sin(altitudeRad) * Math.sin(latitudeRad) +
      Math.cos(altitudeRad) * Math.cos(latitudeRad) * Math.cos(azimuthRad));
    const hourAngleRad: number = Math.atan2(-Math.sin(azimuthRad) * Math.cos(altitudeRad),
      Math.sin(altitudeRad) * Math.cos(latitudeRad) -
      Math.cos(altitudeRad) * Math.sin(latitudeRad) * Math.cos(azimuthRad));
    const rightAscensionDegrees: number = AstronomyService.normalizeDegrees(
      AstronomyService.localSiderealDegrees(observer) - hourAngleRad * AstronomyService.RAD_TO_DEG);
    return {
      raHours: rightAscensionDegrees / 15.0,
      decDegrees: decRad * AstronomyService.RAD_TO_DEG,
      frame: EquatorialFrame.TOPOCENTRIC_OF_DATE,
      validAtMs: observer.timestampMs
    };
  }

  /**
   * 将天体方向投影至后摄预览。使用局部东-北-天坐标和透视投影，广角画面边缘不会出现
   * 简单经纬差分导致的明显拉伸。设备姿态须已转换为“方位角/高度角/横滚角”。
   */
  static projectToViewport(horizontal: HorizontalCoordinate, pose: DevicePose,
    viewport: CameraViewport, calibration?: ArCalibration): ScreenProjection {
    const heading: number = AstronomyService.normalizeDegrees(pose.headingDegrees +
      (calibration === undefined ? 0.0 : calibration.headingOffsetDegrees));
    const pitch: number = pose.pitchDegrees +
      (calibration === undefined ? 0.0 : calibration.pitchOffsetDegrees);
    const roll: number = pose.rollDegrees +
      (calibration === undefined ? 0.0 : calibration.rollOffsetDegrees);

    const target: Vector3 = AstronomyService.horizontalVector(
      horizontal.azimuthDegrees, horizontal.altitudeDegrees);
    const forward: Vector3 = AstronomyService.horizontalVector(heading, pitch);
    const headingRad: number = heading * AstronomyService.DEG_TO_RAD;
    const right: Vector3 = {
      x: Math.cos(headingRad),
      y: -Math.sin(headingRad),
      z: 0.0
    };
    const up: Vector3 = AstronomyService.cross(right, forward);
    const forwardDistance: number = AstronomyService.dot(target, forward);
    let normalizedX: number = AstronomyService.dot(target, right);
    let normalizedY: number = AstronomyService.dot(target, up);

    // 横滚只影响屏幕坐标系，不改变镜头中心指向。
    const rollRad: number = roll * AstronomyService.DEG_TO_RAD;
    const rolledX: number = normalizedX * Math.cos(rollRad) + normalizedY * Math.sin(rollRad);
    const rolledY: number = -normalizedX * Math.sin(rollRad) + normalizedY * Math.cos(rollRad);
    normalizedX = rolledX;
    normalizedY = rolledY;

    const horizontalFocal: number = viewport.widthPixels /
      (2.0 * Math.tan(viewport.horizontalFovDegrees * AstronomyService.DEG_TO_RAD / 2.0));
    const verticalFocal: number = viewport.heightPixels /
      (2.0 * Math.tan(viewport.verticalFovDegrees * AstronomyService.DEG_TO_RAD / 2.0));
    const safeForward: number = Math.abs(forwardDistance) < 0.000001 ? 0.000001 : forwardDistance;
    const x: number = viewport.widthPixels / 2.0 + horizontalFocal * normalizedX / safeForward;
    const y: number = viewport.heightPixels / 2.0 - verticalFocal * normalizedY / safeForward;
    const angularDistance: number = Math.acos(AstronomyService.clamp(forwardDistance, -1.0, 1.0)) *
      AstronomyService.RAD_TO_DEG;
    const inFront: boolean = forwardDistance > 0.0;
    return {
      xPixels: x,
      yPixels: y,
      inFront: inFront,
      inViewport: inFront && x >= 0.0 && x <= viewport.widthPixels && y >= 0.0 && y <= viewport.heightPixels,
      angularDistanceDegrees: angularDistance
    };
  }

  static calibrateFromAnchor(target: HorizontalCoordinate, measuredPose: DevicePose,
    anchorObjectId: string, timestampMs: number): ArCalibration {
    return {
      headingOffsetDegrees: AstronomyService.normalizeSignedDegrees(
        target.azimuthDegrees - measuredPose.headingDegrees),
      pitchOffsetDegrees: target.altitudeDegrees - measuredPose.pitchDegrees,
      rollOffsetDegrees: 0.0,
      anchorObjectId: anchorObjectId,
      calibratedAtMs: timestampMs
    };
  }

  static angularSeparation(first: EquatorialCoordinate, second: EquatorialCoordinate): number {
    const firstDec: number = first.decDegrees * AstronomyService.DEG_TO_RAD;
    const secondDec: number = second.decDegrees * AstronomyService.DEG_TO_RAD;
    const raDifference: number = (first.raHours - second.raHours) * 15.0 * AstronomyService.DEG_TO_RAD;
    const cosine: number = Math.sin(firstDec) * Math.sin(secondDec) +
      Math.cos(firstDec) * Math.cos(secondDec) * Math.cos(raDifference);
    return Math.acos(AstronomyService.clamp(cosine, -1.0, 1.0)) * AstronomyService.RAD_TO_DEG;
  }

  /**
   * 把 source 指向 target 的最短球面旋转施加到 value。用于板解析闭环时，三者必须已在
   * 同一 J2000 三维轴系中；该算法不会在 0h 回绕或高赤纬处直接相减赤经赤纬。
   */
  static applyShortestSkyRotation(source: EquatorialCoordinate, target: EquatorialCoordinate,
    value: EquatorialCoordinate): EquatorialCoordinate {
    if (source.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE ||
      target.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE ||
      value.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE) {
      throw new Error('最短球面旋转要求先把坐标统一到 J2000 轴系');
    }
    const from: Vector3 = AstronomyService.equatorialVector(source);
    const to: Vector3 = AstronomyService.equatorialVector(target);
    const input: Vector3 = AstronomyService.equatorialVector(value);
    const axisScaled: Vector3 = AstronomyService.cross(from, to);
    const sine: number = Math.sqrt(AstronomyService.dot(axisScaled, axisScaled));
    const cosine: number = AstronomyService.clamp(AstronomyService.dot(from, to), -1.0, 1.0);
    let rotated: Vector3;
    if (sine < 0.0000000001 && cosine > 0.0) {
      rotated = input;
    } else if (sine < 0.0000000001) {
      // 对跖方向的最短轴不唯一；选择与 source 稳定正交的轴完成 180° 旋转。
      const reference: Vector3 = Math.abs(from.z) < 0.9 ?
        { x: 0.0, y: 0.0, z: 1.0 } : { x: 1.0, y: 0.0, z: 0.0 };
      const axis: Vector3 = AstronomyService.normalizeVector(AstronomyService.cross(from, reference));
      const projection: number = AstronomyService.dot(axis, input);
      rotated = {
        x: 2.0 * axis.x * projection - input.x,
        y: 2.0 * axis.y * projection - input.y,
        z: 2.0 * axis.z * projection - input.z
      };
    } else {
      const firstCross: Vector3 = AstronomyService.cross(axisScaled, input);
      const secondCross: Vector3 = AstronomyService.cross(axisScaled, firstCross);
      const scale: number = (1.0 - cosine) / (sine * sine);
      rotated = {
        x: input.x + firstCross.x + secondCross.x * scale,
        y: input.y + firstCross.y + secondCross.y * scale,
        z: input.z + firstCross.z + secondCross.z * scale
      };
    }
    const result: Vector3 = AstronomyService.normalizeVector(rotated);
    const coordinate: EquatorialCoordinate = {
      raHours: AstronomyService.normalizeHours(Math.atan2(result.y, result.x) * 12.0 / Math.PI),
      decDegrees: Math.asin(AstronomyService.clamp(result.z, -1.0, 1.0)) * AstronomyService.RAD_TO_DEG,
      frame: value.frame
    };
    if (value.validAtMs !== undefined) coordinate.validAtMs = value.validAtMs;
    return coordinate;
  }

  /** 固定天体直接返回 J2000 坐标；太阳、月球和行星按当前时刻计算低精度视位置。 */
  static resolveCoordinate(object: CelestialObject, timestampMs: number): EquatorialCoordinate | undefined {
    if (object.precision === CatalogPrecision.EXACT) {
      return object.coordinate;
    }
    if (object.precision !== CatalogPrecision.DYNAMIC) {
      return undefined;
    }
    if (object.id === 'solar-moon') {
      return AstronomyService.moonCoordinate(timestampMs);
    }
    if (object.id === 'solar-sun') {
      return AstronomyService.sunCoordinate(timestampMs);
    }
    return AstronomyService.planetCoordinate(object.id, timestampMs);
  }

  static sunCoordinate(timestampMs: number): EquatorialCoordinate {
    const days: number = AstronomyService.daysSinceEpoch(timestampMs);
    const sunGeocentric: Vector3 = AstronomyService.orbitalPosition(AstronomyService.sunGeocentricElements(days));
    return AstronomyService.eclipticVectorToEquatorial(sunGeocentric, days);
  }

  static moonCoordinate(timestampMs: number): EquatorialCoordinate {
    const days: number = AstronomyService.daysSinceEpoch(timestampMs);
    const moonElements: OrbitalElements = {
      ascendingNodeDegrees: 125.1228 - 0.0529538083 * days,
      inclinationDegrees: 5.1454,
      perihelionDegrees: 318.0634 + 0.1643573223 * days,
      semiMajorAxis: 60.2666,
      eccentricity: 0.054900,
      meanAnomalyDegrees: 115.3654 + 13.0649929509 * days
    };
    return AstronomyService.eclipticVectorToEquatorial(
      AstronomyService.orbitalPosition(moonElements), days);
  }

  static planetCoordinate(planetId: string, timestampMs: number): EquatorialCoordinate | undefined {
    const days: number = AstronomyService.daysSinceEpoch(timestampMs);
    const planetElements: OrbitalElements | undefined = AstronomyService.elementsForPlanet(planetId, days);
    if (planetElements === undefined) {
      return undefined;
    }
    const planet: Vector3 = AstronomyService.orbitalPosition(planetElements);
    const sunGeocentric: Vector3 = AstronomyService.orbitalPosition(
      AstronomyService.sunGeocentricElements(days));
    // Schlyter 这组“地球”根数实际直接生成地心太阳向量。日心行星向量必须与它相加，
    // 若按日心地球向量相减，会把太阳和行星方向整体用反，并制造虚假的行星聚集。
    return AstronomyService.eclipticVectorToEquatorial({
      x: planet.x + sunGeocentric.x,
      y: planet.y + sunGeocentric.y,
      z: planet.z + sunGeocentric.z
    }, days);
  }

  private static daysSinceEpoch(timestampMs: number): number {
    // 轨道根数使用 2000-01-00 00:00 UT（JD 2451543.5）作为历元。
    return AstronomyService.julianDay(timestampMs) - 2451543.5;
  }

  private static sunGeocentricElements(days: number): OrbitalElements {
    return {
      ascendingNodeDegrees: 0.0,
      inclinationDegrees: 0.0,
      perihelionDegrees: 282.9404 + 4.70935E-5 * days,
      semiMajorAxis: 1.0,
      eccentricity: 0.016709 - 1.151E-9 * days,
      meanAnomalyDegrees: 356.0470 + 0.9856002585 * days
    };
  }

  private static elementsForPlanet(planetId: string, days: number): OrbitalElements | undefined {
    if (planetId === 'planet-mercury') {
      return { ascendingNodeDegrees: 48.3313 + 3.24587E-5 * days, inclinationDegrees: 7.0047 + 5.00E-8 * days,
        perihelionDegrees: 29.1241 + 1.01444E-5 * days, semiMajorAxis: 0.387098,
        eccentricity: 0.205635 + 5.59E-10 * days, meanAnomalyDegrees: 168.6562 + 4.0923344368 * days };
    }
    if (planetId === 'planet-venus') {
      return { ascendingNodeDegrees: 76.6799 + 2.46590E-5 * days, inclinationDegrees: 3.3946 + 2.75E-8 * days,
        perihelionDegrees: 54.8910 + 1.38374E-5 * days, semiMajorAxis: 0.723330,
        eccentricity: 0.006773 - 1.302E-9 * days, meanAnomalyDegrees: 48.0052 + 1.6021302244 * days };
    }
    if (planetId === 'planet-mars') {
      return { ascendingNodeDegrees: 49.5574 + 2.11081E-5 * days, inclinationDegrees: 1.8497 - 1.78E-8 * days,
        perihelionDegrees: 286.5016 + 2.92961E-5 * days, semiMajorAxis: 1.523688,
        eccentricity: 0.093405 + 2.516E-9 * days, meanAnomalyDegrees: 18.6021 + 0.5240207766 * days };
    }
    if (planetId === 'planet-jupiter') {
      return { ascendingNodeDegrees: 100.4542 + 2.76854E-5 * days, inclinationDegrees: 1.3030 - 1.557E-7 * days,
        perihelionDegrees: 273.8777 + 1.64505E-5 * days, semiMajorAxis: 5.20256,
        eccentricity: 0.048498 + 4.469E-9 * days, meanAnomalyDegrees: 19.8950 + 0.0830853001 * days };
    }
    if (planetId === 'planet-saturn') {
      return { ascendingNodeDegrees: 113.6634 + 2.38980E-5 * days, inclinationDegrees: 2.4886 - 1.081E-7 * days,
        perihelionDegrees: 339.3939 + 2.97661E-5 * days, semiMajorAxis: 9.55475,
        eccentricity: 0.055546 - 9.499E-9 * days, meanAnomalyDegrees: 316.9670 + 0.0334442282 * days };
    }
    if (planetId === 'planet-uranus') {
      return { ascendingNodeDegrees: 74.0005 + 1.3978E-5 * days, inclinationDegrees: 0.7733 + 1.9E-8 * days,
        perihelionDegrees: 96.6612 + 3.0565E-5 * days, semiMajorAxis: 19.18171 - 1.55E-8 * days,
        eccentricity: 0.047318 + 7.45E-9 * days, meanAnomalyDegrees: 142.5905 + 0.011725806 * days };
    }
    if (planetId === 'planet-neptune') {
      return { ascendingNodeDegrees: 131.7806 + 3.0173E-5 * days, inclinationDegrees: 1.7700 - 2.55E-7 * days,
        perihelionDegrees: 272.8461 - 6.027E-6 * days, semiMajorAxis: 30.05826 + 3.313E-8 * days,
        eccentricity: 0.008606 + 2.15E-9 * days, meanAnomalyDegrees: 260.2471 + 0.005995147 * days };
    }
    return undefined;
  }

  private static orbitalPosition(elements: OrbitalElements): Vector3 {
    const meanAnomalyRad: number = AstronomyService.normalizeDegrees(elements.meanAnomalyDegrees) *
      AstronomyService.DEG_TO_RAD;
    let eccentricAnomaly: number = meanAnomalyRad + elements.eccentricity * Math.sin(meanAnomalyRad) *
      (1.0 + elements.eccentricity * Math.cos(meanAnomalyRad));
    for (let iteration: number = 0; iteration < 5; iteration++) {
      eccentricAnomaly -= (eccentricAnomaly - elements.eccentricity * Math.sin(eccentricAnomaly) - meanAnomalyRad) /
        (1.0 - elements.eccentricity * Math.cos(eccentricAnomaly));
    }
    const xInPlane: number = elements.semiMajorAxis * (Math.cos(eccentricAnomaly) - elements.eccentricity);
    const yInPlane: number = elements.semiMajorAxis * Math.sqrt(1.0 - elements.eccentricity * elements.eccentricity) *
      Math.sin(eccentricAnomaly);
    const trueAnomaly: number = Math.atan2(yInPlane, xInPlane);
    const radius: number = Math.sqrt(xInPlane * xInPlane + yInPlane * yInPlane);
    const node: number = elements.ascendingNodeDegrees * AstronomyService.DEG_TO_RAD;
    const inclination: number = elements.inclinationDegrees * AstronomyService.DEG_TO_RAD;
    const longitude: number = trueAnomaly + elements.perihelionDegrees * AstronomyService.DEG_TO_RAD;
    return {
      x: radius * (Math.cos(node) * Math.cos(longitude) - Math.sin(node) * Math.sin(longitude) * Math.cos(inclination)),
      y: radius * (Math.sin(node) * Math.cos(longitude) + Math.cos(node) * Math.sin(longitude) * Math.cos(inclination)),
      z: radius * Math.sin(longitude) * Math.sin(inclination)
    };
  }

  private static eclipticVectorToEquatorial(vector: Vector3, days: number): EquatorialCoordinate {
    const obliquity: number = (23.4393 - 3.563E-7 * days) * AstronomyService.DEG_TO_RAD;
    const equatorialX: number = vector.x;
    const equatorialY: number = vector.y * Math.cos(obliquity) - vector.z * Math.sin(obliquity);
    const equatorialZ: number = vector.y * Math.sin(obliquity) + vector.z * Math.cos(obliquity);
    const raDegrees: number = AstronomyService.normalizeDegrees(
      Math.atan2(equatorialY, equatorialX) * AstronomyService.RAD_TO_DEG);
    const declinationDegrees: number = Math.atan2(equatorialZ,
      Math.sqrt(equatorialX * equatorialX + equatorialY * equatorialY)) * AstronomyService.RAD_TO_DEG;
    return {
      raHours: raDegrees / 15.0,
      decDegrees: declinationDegrees,
      frame: EquatorialFrame.APPARENT_EQJ
    };
  }

  private static horizontalVector(azimuthDegrees: number, altitudeDegrees: number): Vector3 {
    const azimuth: number = azimuthDegrees * AstronomyService.DEG_TO_RAD;
    const altitude: number = altitudeDegrees * AstronomyService.DEG_TO_RAD;
    return {
      x: Math.cos(altitude) * Math.sin(azimuth),
      y: Math.cos(altitude) * Math.cos(azimuth),
      z: Math.sin(altitude)
    };
  }

  private static equatorialVector(coordinate: EquatorialCoordinate): Vector3 {
    const rightAscension: number = coordinate.raHours * 15.0 * AstronomyService.DEG_TO_RAD;
    const declination: number = coordinate.decDegrees * AstronomyService.DEG_TO_RAD;
    const cosineDeclination: number = Math.cos(declination);
    return {
      x: cosineDeclination * Math.cos(rightAscension),
      y: cosineDeclination * Math.sin(rightAscension),
      z: Math.sin(declination)
    };
  }

  private static normalizeVector(vector: Vector3): Vector3 {
    const length: number = Math.sqrt(AstronomyService.dot(vector, vector));
    if (!Number.isFinite(length) || length <= 0.0) {
      throw new Error('球面旋转产生无效三维方向');
    }
    return { x: vector.x / length, y: vector.y / length, z: vector.z / length };
  }

  private static dot(first: Vector3, second: Vector3): number {
    return first.x * second.x + first.y * second.y + first.z * second.z;
  }

  private static cross(first: Vector3, second: Vector3): Vector3 {
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

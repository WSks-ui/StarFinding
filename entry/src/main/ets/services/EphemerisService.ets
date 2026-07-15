import {
  ApparentTrajectory,
  ApparentTrajectoryPoint,
  CatalogPrecision,
  CelestialObject,
  EquatorialFrame,
  FramedEquatorialCoordinate,
  HorizontalCoordinate,
  MountTargetCoordinate,
  ObserverState,
  RefractionMode,
  SolarSystemAppearance,
  StellarProperMotion
} from '../models/DomainModels';
import {
  bodyIllumination,
  eqdToEqj,
  eqjFromHorizontal,
  eqjToEqd,
  geocentricEqj,
  horizontalBody,
  horizontalFromEqj,
  moonPhaseDegrees,
  topocentricEqd
} from '../vendor/astronomy-engine/AstronomyEngineBridge';

interface BodyPhysicalData {
  radiusKm: number;
}

/**
 * 项目唯一星历入口。第三方 JavaScript 仅通过数字数组桥接，动态对象不会进入 ArkTS 业务层。
 */
export class EphemerisService {
  private static readonly AU_KM: number = 149597870.7;

  static skyCoordinate(object: CelestialObject,
    timestampMs: number): FramedEquatorialCoordinate | undefined {
    EphemerisService.validateTimestamp(timestampMs);
    if (object.precision === CatalogPrecision.EXACT && object.coordinate !== undefined) {
      if (object.stellarProperMotion !== undefined) {
        return EphemerisService.applyProperMotion(
          object.coordinate, object.stellarProperMotion, timestampMs);
      }
      return {
        raHours: EphemerisService.normalizeHours(object.coordinate.raHours),
        decDegrees: object.coordinate.decDegrees,
        frame: EquatorialFrame.ICRS_J2000
      };
    }
    if (object.precision !== CatalogPrecision.DYNAMIC) {
      return undefined;
    }
    const values: number[] = geocentricEqj(object.id, timestampMs);
    EphemerisService.requireValues(values, 3, `计算 ${object.id} 地心坐标`);
    return {
      raHours: EphemerisService.normalizeHours(values[0]),
      decDegrees: values[1],
      frame: EquatorialFrame.APPARENT_EQJ,
      validAtMs: timestampMs
    };
  }

  static topocentricCoordinate(object: CelestialObject, observer: ObserverState,
    timestampMs: number): MountTargetCoordinate | undefined {
    EphemerisService.validateObserver(observer);
    EphemerisService.validateTimestamp(timestampMs);
    let values: number[];
    if (object.precision === CatalogPrecision.DYNAMIC) {
      values = topocentricEqd(object.id, timestampMs, observer.latitudeDegrees,
        observer.longitudeDegrees, observer.elevationMeters);
    } else if (object.precision === CatalogPrecision.EXACT && object.coordinate !== undefined) {
      const coordinate: FramedEquatorialCoordinate = object.stellarProperMotion === undefined ?
        object.coordinate : EphemerisService.applyProperMotion(
          object.coordinate, object.stellarProperMotion, timestampMs);
      values = eqjToEqd(coordinate.raHours, coordinate.decDegrees, timestampMs);
    } else {
      return undefined;
    }
    EphemerisService.requireValues(values, 2, `计算 ${object.id} 站心当日坐标`);
    return {
      raHours: EphemerisService.normalizeHours(values[0]),
      decDegrees: values[1],
      frame: EquatorialFrame.TOPOCENTRIC_OF_DATE,
      calculatedAtMs: timestampMs,
      observerKey: EphemerisService.observerKey(observer)
    };
  }

  static horizontalCoordinate(object: CelestialObject, observer: ObserverState,
    timestampMs: number, refractionMode: RefractionMode = RefractionMode.NONE): HorizontalCoordinate | undefined {
    EphemerisService.validateObserver(observer);
    EphemerisService.validateTimestamp(timestampMs);
    const applyRefraction: boolean = refractionMode === RefractionMode.NORMAL;
    let values: number[];
    if (object.precision === CatalogPrecision.DYNAMIC) {
      values = horizontalBody(object.id, timestampMs, observer.latitudeDegrees,
        observer.longitudeDegrees, observer.elevationMeters, applyRefraction);
    } else if (object.precision === CatalogPrecision.EXACT && object.coordinate !== undefined) {
      values = horizontalFromEqj(object.coordinate.raHours, object.coordinate.decDegrees,
        timestampMs, observer.latitudeDegrees, observer.longitudeDegrees,
        observer.elevationMeters, applyRefraction);
    } else {
      return undefined;
    }
    EphemerisService.requireValues(values, 2, `计算 ${object.id} 地平坐标`);
    return {
      azimuthDegrees: EphemerisService.normalizeDegrees(values[0]),
      altitudeDegrees: values[1],
      aboveHorizon: values[1] > 0.0
    };
  }

  static horizontalFromEqjCoordinate(coordinate: FramedEquatorialCoordinate,
    observer: ObserverState, timestampMs: number,
    refractionMode: RefractionMode = RefractionMode.NONE): HorizontalCoordinate {
    if (coordinate.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE) {
      throw new Error('站心当日坐标不能作为 J2000 坐标转换地平方向');
    }
    EphemerisService.validateObserver(observer);
    const values: number[] = horizontalFromEqj(coordinate.raHours, coordinate.decDegrees,
      timestampMs, observer.latitudeDegrees, observer.longitudeDegrees,
      observer.elevationMeters, refractionMode === RefractionMode.NORMAL);
    EphemerisService.requireValues(values, 2, '转换 J2000 到地平坐标');
    return {
      azimuthDegrees: EphemerisService.normalizeDegrees(values[0]),
      altitudeDegrees: values[1],
      aboveHorizon: values[1] > 0.0
    };
  }

  static moonIlluminationPercent(timestampMs: number): number {
    const values: number[] = bodyIllumination('solar-moon', timestampMs);
    EphemerisService.requireValues(values, 5, '计算月面亮度');
    return EphemerisService.clamp(values[1] * 100.0, 0.0, 100.0);
  }

  static moonPhaseAngleDegrees(timestampMs: number): number {
    EphemerisService.validateTimestamp(timestampMs);
    return moonPhaseDegrees(timestampMs);
  }

  /**
   * 先在 ICRS 单位球上构造赤经、赤纬切向量，再归一化回球面。
   * 这种写法在赤经回绕和天极附近都不会产生除以 cos(dec) 的数值爆炸。
   */
  static applyProperMotion(coordinate: FramedEquatorialCoordinate,
    motion: StellarProperMotion, timestampMs: number): FramedEquatorialCoordinate {
    if (coordinate.frame !== EquatorialFrame.ICRS_J2000) {
      throw new Error('恒星自行只能应用于 ICRS J2000 星表坐标');
    }
    EphemerisService.validateTimestamp(timestampMs);
    if (!Number.isFinite(motion.pmRaMasPerYear) || !Number.isFinite(motion.pmDecMasPerYear) ||
      !Number.isFinite(motion.sourceEpochYear)) {
      throw new Error('恒星自行或源历元无效');
    }
    const julianDay: number = timestampMs / 86400000.0 + 2440587.5;
    const sourceJulianDay: number = 2451545.0 + (motion.sourceEpochYear - 2000.0) * 365.25;
    const elapsedJulianYears: number = (julianDay - sourceJulianDay) / 365.25;
    const milliarcsecondsToRadians: number = Math.PI / (180.0 * 3600.0 * 1000.0);
    const alpha: number = coordinate.raHours * Math.PI / 12.0;
    const delta: number = coordinate.decDegrees * Math.PI / 180.0;
    const cosineDelta: number = Math.cos(delta);
    const sineDelta: number = Math.sin(delta);
    const cosineAlpha: number = Math.cos(alpha);
    const sineAlpha: number = Math.sin(alpha);
    const muAlpha: number = motion.pmRaMasPerYear * milliarcsecondsToRadians;
    const muDelta: number = motion.pmDecMasPerYear * milliarcsecondsToRadians;
    let x: number = cosineDelta * cosineAlpha + elapsedJulianYears *
      (muAlpha * -sineAlpha + muDelta * -cosineAlpha * sineDelta);
    let y: number = cosineDelta * sineAlpha + elapsedJulianYears *
      (muAlpha * cosineAlpha + muDelta * -sineAlpha * sineDelta);
    let z: number = sineDelta + elapsedJulianYears * muDelta * cosineDelta;
    const length: number = Math.sqrt(x * x + y * y + z * z);
    if (!Number.isFinite(length) || length <= 0.0) {
      throw new Error('恒星自行计算产生无效三维方向');
    }
    x /= length;
    y /= length;
    z /= length;
    return {
      raHours: EphemerisService.normalizeHours(Math.atan2(y, x) * 12.0 / Math.PI),
      decDegrees: Math.asin(EphemerisService.clamp(z, -1.0, 1.0)) * 180.0 / Math.PI,
      frame: EquatorialFrame.ICRS_J2000,
      validAtMs: timestampMs
    };
  }

  static eqjToTopocentricOfDate(coordinate: FramedEquatorialCoordinate,
    observer: ObserverState, timestampMs: number): MountTargetCoordinate {
    if (coordinate.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE) {
      throw new Error('站心当日坐标不能再次执行 J2000 到当日转换');
    }
    EphemerisService.validateObserver(observer);
    const values: number[] = eqjToEqd(coordinate.raHours, coordinate.decDegrees, timestampMs);
    EphemerisService.requireValues(values, 2, '转换 J2000 到站心当日坐标');
    return {
      raHours: EphemerisService.normalizeHours(values[0]),
      decDegrees: values[1],
      frame: EquatorialFrame.TOPOCENTRIC_OF_DATE,
      calculatedAtMs: timestampMs,
      observerKey: EphemerisService.observerKey(observer)
    };
  }

  static topocentricOfDateToEqj(coordinate: MountTargetCoordinate): FramedEquatorialCoordinate {
    EphemerisService.requireMountCoordinate(coordinate);
    const values: number[] = eqdToEqj(
      coordinate.raHours, coordinate.decDegrees, coordinate.calculatedAtMs);
    EphemerisService.requireValues(values, 2, '转换站心当日坐标到 J2000');
    return {
      raHours: EphemerisService.normalizeHours(values[0]),
      decDegrees: values[1],
      frame: EquatorialFrame.APPARENT_EQJ,
      validAtMs: coordinate.calculatedAtMs
    };
  }

  static horizontalToEqj(azimuthDegrees: number, altitudeDegrees: number,
    observer: ObserverState, timestampMs: number,
    refractionMode: RefractionMode = RefractionMode.NONE): FramedEquatorialCoordinate {
    EphemerisService.validateObserver(observer);
    const values: number[] = eqjFromHorizontal(azimuthDegrees, altitudeDegrees, timestampMs,
      observer.latitudeDegrees, observer.longitudeDegrees, observer.elevationMeters,
      refractionMode === RefractionMode.NORMAL);
    EphemerisService.requireValues(values, 2, '转换地平坐标到 J2000');
    return {
      raHours: EphemerisService.normalizeHours(values[0]),
      decDegrees: values[1],
      frame: EquatorialFrame.APPARENT_EQJ,
      validAtMs: timestampMs
    };
  }

  static appearance(object: CelestialObject, timestampMs: number): SolarSystemAppearance | undefined {
    if (object.precision !== CatalogPrecision.DYNAMIC) {
      return undefined;
    }
    const values: number[] = bodyIllumination(object.id, timestampMs);
    EphemerisService.requireValues(values, 5, `计算 ${object.id} 外观`);
    const coordinate: FramedEquatorialCoordinate | undefined =
      EphemerisService.skyCoordinate(object, timestampMs);
    const sunValues: number[] = geocentricEqj('solar-sun', timestampMs);
    EphemerisService.requireValues(sunValues, 3, '计算太阳方向');
    const brightLimbAngle: number = coordinate === undefined ? 0.0 :
      EphemerisService.positionAngle(coordinate.raHours, coordinate.decDegrees,
        sunValues[0], sunValues[1]);
    const appearance: SolarSystemAppearance = {
      objectId: object.id,
      timestampMs: timestampMs,
      magnitude: values[0],
      illuminatedFraction: EphemerisService.clamp(values[1], 0.0, 1.0),
      phaseAngleDegrees: values[2],
      angularDiameterArcSeconds: EphemerisService.angularDiameterArcSeconds(
        object.id, values[3]),
      brightLimbAngleDegrees: brightLimbAngle,
      distanceAu: values[3]
    };
    if (Number.isFinite(values[4])) {
      appearance.ringTiltDegrees = values[4];
    }
    if (object.id === 'solar-moon') {
      appearance.moonPhaseDegrees = moonPhaseDegrees(timestampMs);
    }
    return appearance;
  }

  static trajectory(object: CelestialObject, centerAtMs: number): ApparentTrajectory | undefined {
    if (object.precision !== CatalogPrecision.DYNAMIC) {
      return undefined;
    }
    const timing: number[] = EphemerisService.trajectoryTiming(object.id);
    const halfRangeMs: number = timing[0];
    const stepMs: number = timing[1];
    const startAtMs: number = centerAtMs - halfRangeMs;
    const endAtMs: number = centerAtMs + halfRangeMs;
    const points: ApparentTrajectoryPoint[] = [];
    for (let timestampMs: number = startAtMs; timestampMs <= endAtMs; timestampMs += stepMs) {
      const coordinate: FramedEquatorialCoordinate | undefined =
        EphemerisService.skyCoordinate(object, timestampMs);
      if (coordinate !== undefined) {
        points.push({ timestampMs: timestampMs, coordinate: coordinate });
      }
    }
    return {
      objectId: object.id,
      startAtMs: startAtMs,
      endAtMs: endAtMs,
      stepMs: stepMs,
      points: points
    };
  }

  static observerKey(observer: ObserverState): string {
    return `${observer.latitudeDegrees.toFixed(6)},${observer.longitudeDegrees.toFixed(6)},${
      observer.elevationMeters.toFixed(1)}`;
  }

  static requireMountCoordinate(coordinate: MountTargetCoordinate): void {
    if (coordinate.frame !== EquatorialFrame.TOPOCENTRIC_OF_DATE ||
      !Number.isFinite(coordinate.raHours) || !Number.isFinite(coordinate.decDegrees) ||
      !Number.isFinite(coordinate.calculatedAtMs) || coordinate.observerKey.length === 0) {
      throw new Error('赤道仪只接受带观测地点和计算时刻的站心当日坐标');
    }
  }

  private static trajectoryTiming(objectId: string): number[] {
    const hourMs: number = 3600000.0;
    const dayMs: number = 24.0 * hourMs;
    if (objectId === 'solar-moon') return [48.0 * hourMs, hourMs];
    if (objectId === 'planet-mercury' || objectId === 'planet-venus' || objectId === 'planet-mars') {
      return [45.0 * dayMs, dayMs];
    }
    if (objectId === 'solar-sun') return [15.0 * dayMs, dayMs];
    return [182.0 * dayMs, dayMs];
  }

  private static angularDiameterArcSeconds(objectId: string, distanceAu: number): number {
    const physical: BodyPhysicalData = EphemerisService.physicalData(objectId);
    const distanceKm: number = Math.max(1.0, distanceAu * EphemerisService.AU_KM);
    return 2.0 * Math.atan(physical.radiusKm / distanceKm) * 180.0 / Math.PI * 3600.0;
  }

  private static physicalData(objectId: string): BodyPhysicalData {
    if (objectId === 'solar-sun') return { radiusKm: 695700.0 };
    if (objectId === 'solar-moon') return { radiusKm: 1737.4 };
    if (objectId === 'planet-mercury') return { radiusKm: 2439.7 };
    if (objectId === 'planet-venus') return { radiusKm: 6051.8 };
    if (objectId === 'planet-mars') return { radiusKm: 3389.5 };
    if (objectId === 'planet-jupiter') return { radiusKm: 69911.0 };
    if (objectId === 'planet-saturn') return { radiusKm: 58232.0 };
    if (objectId === 'planet-uranus') return { radiusKm: 25362.0 };
    return { radiusKm: 24622.0 };
  }

  private static positionAngle(sourceRaHours: number, sourceDecDegrees: number,
    targetRaHours: number, targetDecDegrees: number): number {
    const sourceDec: number = sourceDecDegrees * Math.PI / 180.0;
    const targetDec: number = targetDecDegrees * Math.PI / 180.0;
    const raDelta: number = (targetRaHours - sourceRaHours) * Math.PI / 12.0;
    const y: number = Math.cos(targetDec) * Math.sin(raDelta);
    const x: number = Math.sin(targetDec) * Math.cos(sourceDec) -
      Math.cos(targetDec) * Math.sin(sourceDec) * Math.cos(raDelta);
    return EphemerisService.normalizeSignedDegrees(Math.atan2(y, x) * 180.0 / Math.PI);
  }

  private static requireValues(values: number[], minimumLength: number, operation: string): void {
    if (values.length < minimumLength) {
      throw new Error(`${operation}返回的数据长度不足`);
    }
    for (let index: number = 0; index < minimumLength; index++) {
      if (!Number.isFinite(values[index]) && index !== 4) {
        throw new Error(`${operation}返回了无效数值`);
      }
    }
  }

  private static validateObserver(observer: ObserverState): void {
    if (!Number.isFinite(observer.latitudeDegrees) || observer.latitudeDegrees < -90.0 ||
      observer.latitudeDegrees > 90.0 || !Number.isFinite(observer.longitudeDegrees) ||
      observer.longitudeDegrees < -180.0 || observer.longitudeDegrees > 180.0 ||
      !Number.isFinite(observer.elevationMeters)) {
      throw new Error('观测地点经纬度或海拔无效');
    }
  }

  private static validateTimestamp(timestampMs: number): void {
    if (!Number.isFinite(timestampMs)) {
      throw new Error('观测时间必须是有效毫秒时间戳');
    }
    const year: number = new Date(timestampMs).getUTCFullYear();
    if (year < 1900 || year > 2100) {
      throw new Error('星图模拟时间仅支持 1900 至 2100 年');
    }
  }

  private static normalizeHours(value: number): number {
    let result: number = value % 24.0;
    if (result < 0.0) result += 24.0;
    return result;
  }

  private static normalizeDegrees(value: number): number {
    let result: number = value % 360.0;
    if (result < 0.0) result += 360.0;
    return result;
  }

  private static normalizeSignedDegrees(value: number): number {
    const normalized: number = EphemerisService.normalizeDegrees(value);
    return normalized > 180.0 ? normalized - 360.0 : normalized;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

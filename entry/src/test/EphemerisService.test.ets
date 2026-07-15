import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CelestialObject,
  EquatorialCoordinate,
  EquatorialFrame,
  FramedEquatorialCoordinate,
  MountTargetCoordinate,
  ObserverState,
  RefractionMode,
  SolarSystemAppearance,
  StellarProperMotion
} from '../main/ets/models/DomainModels';
import { AstronomyService } from '../main/ets/services/AstronomyService';
import { EphemerisService } from '../main/ets/services/EphemerisService';

function requireTarget(id: string): CelestialObject {
  const target: CelestialObject | undefined = CelestialCatalog.getById(id);
  if (target === undefined) throw new Error(`测试目录缺少 ${id}`);
  return target;
}

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function requireCoordinate(target: CelestialObject, timestampMs: number): FramedEquatorialCoordinate {
  const coordinate: FramedEquatorialCoordinate | undefined =
    EphemerisService.skyCoordinate(target, timestampMs);
  if (coordinate === undefined) throw new Error(`无法计算 ${target.id} 坐标`);
  return coordinate;
}

export default function ephemerisServiceTest(): void {
  describe('离线权威星历', () => {
    it('2026 年行星角距符合 JPL Horizons', 0, () => {
      const timestampMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const mars: FramedEquatorialCoordinate = requireCoordinate(
        requireTarget('planet-mars'), timestampMs);
      const saturn: FramedEquatorialCoordinate = requireCoordinate(
        requireTarget('planet-saturn'), timestampMs);
      const neptune: FramedEquatorialCoordinate = requireCoordinate(
        requireTarget('planet-neptune'), timestampMs);
      const marsLegacy: EquatorialCoordinate = {
        raHours: mars.raHours, decDegrees: mars.decDegrees, frame: EquatorialFrame.APPARENT_EQJ
      };
      const saturnLegacy: EquatorialCoordinate = {
        raHours: saturn.raHours, decDegrees: saturn.decDegrees, frame: EquatorialFrame.APPARENT_EQJ
      };
      const neptuneLegacy: EquatorialCoordinate = {
        raHours: neptune.raHours, decDegrees: neptune.decDegrees, frame: EquatorialFrame.APPARENT_EQJ
      };
      expect(closeTo(AstronomyService.angularSeparation(saturnLegacy, neptuneLegacy), 10.28, 0.1)).assertTrue();
      expect(closeTo(AstronomyService.angularSeparation(marsLegacy, saturnLegacy), 56.81, 0.1)).assertTrue();
      expect(closeTo(AstronomyService.angularSeparation(marsLegacy, neptuneLegacy), 67.01, 0.1)).assertTrue();
    });

    it('固定星表坐标转换为带地点标识的站心当日坐标', 0, () => {
      const timestampMs: number = Date.UTC(2026, 6, 15, 14, 0, 0);
      const observer: ObserverState = {
        latitudeDegrees: 34.75,
        longitudeDegrees: 113.62,
        elevationMeters: 100.0,
        timestampMs: timestampMs
      };
      const target: CelestialObject = requireTarget('star-vega');
      const mount: MountTargetCoordinate | undefined =
        EphemerisService.topocentricCoordinate(target, observer, timestampMs);
      expect(mount !== undefined).assertTrue();
      if (mount === undefined) return;
      expect(mount.frame).assertEqual(EquatorialFrame.TOPOCENTRIC_OF_DATE);
      expect(mount.observerKey).assertEqual(EphemerisService.observerKey(observer));
      const horizontal = EphemerisService.horizontalCoordinate(
        target, observer, timestampMs, RefractionMode.NONE);
      expect(horizontal !== undefined && Number.isFinite(horizontal.altitudeDegrees)).assertTrue();
    });

    it('土星外观包含真实星等和环倾角', 0, () => {
      const appearance: SolarSystemAppearance | undefined = EphemerisService.appearance(
        requireTarget('planet-saturn'), Date.UTC(2026, 6, 15, 0, 0, 0));
      expect(appearance !== undefined).assertTrue();
      if (appearance === undefined) return;
      expect(closeTo(appearance.magnitude, 0.60, 0.1)).assertTrue();
      expect(appearance.ringTiltDegrees !== undefined &&
        closeTo(appearance.ringTiltDegrees, 9.15, 0.1)).assertTrue();
    });

    it('月球轨迹按一小时采样并覆盖前后四十八小时', 0, () => {
      const centerAtMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const trajectory = EphemerisService.trajectory(requireTarget('solar-moon'), centerAtMs);
      expect(trajectory !== undefined).assertTrue();
      if (trajectory === undefined) return;
      expect(trajectory.stepMs).assertEqual(3600000.0);
      expect(trajectory.points.length).assertEqual(97);
      expect(trajectory.startAtMs).assertEqual(centerAtMs - 48.0 * 3600000.0);
      expect(trajectory.endAtMs).assertEqual(centerAtMs + 48.0 * 3600000.0);
    });

    it('高自行恒星通过三维切向量跨越一百年且保持有限', 0, () => {
      const source: FramedEquatorialCoordinate = {
        raHours: 17.963472,
        decDegrees: 4.693388,
        frame: EquatorialFrame.ICRS_J2000
      };
      const motion: StellarProperMotion = {
        pmRaMasPerYear: -797.84,
        pmDecMasPerYear: 9999.99,
        sourceEpochYear: 2000.0
      };
      const moved: FramedEquatorialCoordinate = EphemerisService.applyProperMotion(
        source, motion, Date.UTC(2100, 0, 1, 12, 0, 0));
      const separation: number = AstronomyService.angularSeparation(source, moved);
      expect(Number.isFinite(moved.raHours) && Number.isFinite(moved.decDegrees)).assertTrue();
      expect(moved.frame).assertEqual(EquatorialFrame.ICRS_J2000);
      expect(closeTo(separation, 0.2787, 0.002)).assertTrue();
    });
  });
}

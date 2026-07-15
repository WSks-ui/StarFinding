import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CameraViewport,
  CaptureMode,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  DevicePose,
  EquatorialCoordinate,
  EquatorialFrame,
  HandGesture,
  HandLandmarks,
  HandPoint,
  ImageFormat,
  ObserverState
} from '../main/ets/models/DomainModels';
import { AstronomyService } from '../main/ets/services/AstronomyService';
import { CapturePlanner } from '../main/ets/services/CapturePlanner';
import { GestureInterpreter } from '../main/ets/services/GestureInterpreter';
import { OnStepLX200Client } from '../main/ets/services/OnStepLX200Client';

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function createHand(trackingId: number, centerX: number, openPalm: boolean,
  timestampMs: number): HandLandmarks {
  const points: HandPoint[] = [];
  for (let index: number = 0; index < 21; index++) {
    points.push({ x: centerX, y: 0.65, confidence: 0.95 });
  }
  points[0] = { x: centerX, y: 0.82, confidence: 0.95 };
  const joints: number[] = [6, 10, 14, 18];
  const tips: number[] = [8, 12, 16, 20];
  for (let index: number = 0; index < joints.length; index++) {
    points[joints[index]] = { x: centerX, y: 0.60, confidence: 0.95 };
    points[tips[index]] = {
      x: centerX,
      y: openPalm ? 0.20 : 0.68,
      confidence: 0.95
    };
  }
  points[4] = { x: openPalm ? centerX - 0.18 : centerX + 0.02, y: 0.62, confidence: 0.95 };
  points[9] = { x: centerX, y: 0.62, confidence: 0.95 };
  return { trackingId: trackingId, points: points, confidence: 0.95, timestampMs: timestampMs };
}

export default function starFindingCoreTest(): void {
  describe('StarFinding 核心算法', () => {
    it('赤道坐标与地平坐标往返误差受控', 0, () => {
      const observer: ObserverState = {
        latitudeDegrees: 34.75,
        longitudeDegrees: 113.62,
        elevationMeters: 100,
        timestampMs: Date.UTC(2026, 6, 11, 14, 0, 0)
      };
      const source: EquatorialCoordinate = {
        raHours: 18.6156,
        decDegrees: 38.7837,
        frame: EquatorialFrame.TOPOCENTRIC_OF_DATE
      };
      const horizontal = AstronomyService.equatorialToHorizontal(source, observer);
      const restored = AstronomyService.horizontalToEquatorial(horizontal, observer);
      expect(closeTo(restored.raHours, source.raHours, 0.0001)).assertTrue();
      expect(closeTo(restored.decDegrees, source.decDegrees, 0.001)).assertTrue();
    });

    it('2026 年行星角距与 JPL Horizons 基线一致', 0, () => {
      const timestampMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const mars: EquatorialCoordinate | undefined = AstronomyService.planetCoordinate(
        'planet-mars', timestampMs);
      const saturn: EquatorialCoordinate | undefined = AstronomyService.planetCoordinate(
        'planet-saturn', timestampMs);
      const neptune: EquatorialCoordinate | undefined = AstronomyService.planetCoordinate(
        'planet-neptune', timestampMs);
      expect(mars !== undefined && saturn !== undefined && neptune !== undefined).assertTrue();
      if (mars === undefined || saturn === undefined || neptune === undefined) {
        return;
      }
      // 固定值来自 JPL Horizons。低精度根数阶段允许 0.35 度，后续离线星历接入后收紧到 0.1 度。
      expect(closeTo(AstronomyService.angularSeparation(saturn, neptune), 10.28, 0.35)).assertTrue();
      expect(closeTo(AstronomyService.angularSeparation(mars, saturn), 56.81, 0.35)).assertTrue();
      expect(closeTo(AstronomyService.angularSeparation(mars, neptune), 67.01, 0.35)).assertTrue();
    });

    it('镜头中心方向投影到视口中心', 0, () => {
      const viewport: CameraViewport = {
        widthPixels: 600,
        heightPixels: 500,
        horizontalFovDegrees: 66,
        verticalFovDegrees: 44
      };
      const pose: DevicePose = { headingDegrees: 132, pitchDegrees: 48, rollDegrees: 0 };
      const projection = AstronomyService.projectToViewport({
        azimuthDegrees: 132,
        altitudeDegrees: 48,
        aboveHorizon: true
      }, pose, viewport);
      expect(closeTo(projection.xPixels, 300, 0.001)).assertTrue();
      expect(closeTo(projection.yPixels, 250, 0.001)).assertTrue();
      expect(projection.inViewport).assertTrue();
    });

    it('城市 18mm 计划采用短子曝光与 RAW+JPEG', 0, () => {
      const target: CelestialObject = {
        id: 'm8-test', type: CelestialType.MESSIER, nameZh: '礁湖星云', nameEn: 'Lagoon Nebula',
        designation: 'M8', constellation: '人马座',
        coordinate: {
          raHours: 18.06,
          decDegrees: -24.38,
          frame: EquatorialFrame.ICRS_J2000
        }, magnitude: 6,
        angularSizeDegrees: 1.5, description: '测试目标', tags: ['星云'],
        precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: true
      };
      const plan = CapturePlanner.recommend({
        target: target,
        horizontal: { altitudeDegrees: 45, azimuthDegrees: 180, aboveHorizon: true },
        mode: CaptureMode.SMART_LONG_EXPOSURE,
        bortleClass: 8,
        moonIllumination: 0.2,
        moonSeparationDegrees: 120
      });
      expect(plan.exposureSeconds <= 30).assertTrue();
      expect(plan.frameCount > 1).assertTrue();
      expect(plan.imageFormat).assertEqual(ImageFormat.RAW_JPEG);
      expect(plan.enableLocalStack).assertTrue();
    });

    it('LX200 赤经赤纬格式可往返解析', 0, () => {
      const raText: string = OnStepLX200Client.formatRightAscension(18.6156);
      const decText: string = OnStepLX200Client.formatDeclination(-24.386);
      const ra: number | undefined = OnStepLX200Client.parseRightAscension(raText);
      const dec: number | undefined = OnStepLX200Client.parseDeclination(decText);
      expect(ra !== undefined && closeTo(ra, 18.6156, 0.0002)).assertTrue();
      expect(dec !== undefined && closeTo(dec, -24.386, 0.001)).assertTrue();
      expect(OnStepLX200Client.formatTimezoneOffset(-8)).assertEqual('-08:00');
    });

    it('自动回零使用原点开关搜索命令', 0, () => {
      // :hF# 仅重置坐标且不会运动；这里固定 :hC#，防止机械零位未知时误开放 GOTO。
      expect(OnStepLX200Client.HOME_SEARCH_COMMAND).assertEqual(':hC#');
    });

    it('软件急停同时停止跟踪和运动', 0, () => {
      expect(OnStepLX200Client.EMERGENCY_STOP_COMMAND).assertEqual(':Td#:Q#:Q#');
    });

    it('单掌位移被解释为拖拽', 0, () => {
      const interpreter = new GestureInterpreter();
      interpreter.interpret([createHand(1, 0.40, true, 1000)], 1000);
      const frame = interpreter.interpret([createHand(1, 0.50, true, 1100)], 1100);
      expect(frame.gesture).assertEqual(HandGesture.DRAG);
      expect(frame.deltaX > 0.05).assertTrue();
    });

    it('握拳保持触发一次复位', 0, () => {
      const interpreter = new GestureInterpreter();
      interpreter.interpret([createHand(2, 0.50, false, 1000)], 1000);
      const frame = interpreter.interpret([createHand(2, 0.50, false, 1600)], 1600);
      expect(frame.gesture).assertEqual(HandGesture.FIST_RESET);
    });

    it('离线目录覆盖 88 星座与 110 个精确 Messier 目标', 0, () => {
      const coverage = CelestialCatalog.coverage();
      expect(coverage.constellationIndexCount).assertEqual(88);
      expect(coverage.exactConstellationAnchors).assertEqual(88);
      expect(coverage.messierIndexCount).assertEqual(110);
      expect(coverage.exactMessierTargets).assertEqual(110);
      const messierTwo = CelestialCatalog.getById('messier-2');
      expect(messierTwo !== undefined && messierTwo.gotoAllowed && messierTwo.coordinate !== undefined).assertTrue();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  CaptureMode,
  CapturePlan,
  CatalogPrecision,
  CelestialType,
  EquatorialFrame,
  ImageFormat,
  ObservationNightSelection,
  OutingRecommendation,
  PlanningSnapshot,
  VisibilityStatus,
  WeatherDataStatus
} from '../main/ets/models/DomainModels';
import {
  ObservationSharePayload
} from '../main/ets/models/ObservationShareModels';
import {
  ReplayAssetManifest
} from '../main/ets/models/DigitalTwinModels';
import {
  TaskTargetSnapshot
} from '../main/ets/models/TaskSessionModels';
import { DigitalTwinReplayService } from '../main/ets/services/DigitalTwinReplayService';
import { ObservationShareService } from '../main/ets/services/ObservationShareService';

function planningSnapshot(): PlanningSnapshot {
  const startAtMs: number = Date.UTC(2026, 6, 20, 4, 0, 0);
  const endAtMs: number = startAtMs + 24 * 60 * 60 * 1000;
  return {
    generation: 1,
    dayOffset: 0,
    period: {
      startAtMs: startAtMs,
      endAtMs: endAtMs,
      timezoneOffsetMinutes: 480,
      selection: ObservationNightSelection.TONIGHT
    },
    targetId: 'star-vega',
    observerLatitudeDegrees: 34.75,
    observerLongitudeDegrees: 113.62,
    locationSource: '系统定位',
    locationProvisional: false,
    result: {
      targetId: 'star-vega',
      targetName: '织女星',
      generatedAtMs: startAtMs,
      startAtMs: startAtMs,
      endAtMs: endAtMs,
      constraints: {
        horizonHours: 24,
        sampleMinutes: 10,
        minAltitudeDegrees: 20,
        maxSunAltitudeDegrees: -12
      },
      riseTransitSet: {
        status: VisibilityStatus.NORMAL,
        maxAltitudeDegrees: 80
      },
      moonIlluminationPercent: 35,
      moonPhaseName: '上弦月',
      moonSeparationDegrees: 72,
      samples: [],
      windows: [],
      recommendedCaptureUnavailableReason: '天气不可用，仅按天文条件',
      recommendation: OutingRecommendation.ASTRONOMY_ONLY,
      summary: '仅天文条件',
      warnings: [],
      weatherStatus: WeatherDataStatus.UNAVAILABLE
    }
  };
}

function demoPlan(): CapturePlan {
  return {
    id: 'share-demo-plan',
    mode: CaptureMode.SMART_LONG_EXPOSURE,
    targetId: 'star-vega',
    targetName: '织女星',
    exposureSeconds: 15,
    frameCount: 20,
    intervalSeconds: 2,
    iso: 800,
    aperture: 4,
    imageFormat: ImageFormat.RAW_JPEG,
    outputFps: 25,
    enablePlateSolve: true,
    enableDriftCorrection: true,
    enableLocalStack: true,
    enableCloudEnhancement: true,
    recommendationReason: '分享测试',
    warnings: []
  };
}

function demoTarget(): TaskTargetSnapshot {
  return {
    id: 'star-vega',
    name: '织女星',
    designation: 'Alpha Lyr',
    type: CelestialType.STAR,
    coordinate: {
      raHours: 18.6156,
      decDegrees: 38.7837,
      frame: EquatorialFrame.ICRS_J2000
    },
    precision: CatalogPrecision.EXACT,
    gotoAllowed: true
  };
}

export default function observationShareServiceTest(): void {
  describe('观测计划与任务报告安全分享', () => {
    it('规划分享只使用同一原子快照的数据', 0, () => {
      const payload: ObservationSharePayload = ObservationShareService.createPlanningPayload({
        snapshot: planningSnapshot(),
        targetName: '织女星',
        designation: 'Alpha Lyr'
      });
      expect(payload.content.includes('织女星')).assertTrue();
      expect(payload.content.includes('观测夜')).assertTrue();
      expect(payload.content.includes('设备时间')).assertTrue();
      expect(payload.content.includes('IP')).assertFalse();
      expect(payload.content.includes('token')).assertFalse();
    });

    it('数字孪生报告必须声明模拟素材且不泄露网络配置', 0, () => {
      const manifest: ReplayAssetManifest =
        DigitalTwinReplayService.createSimulatedManifest('织女星');
      const session = DigitalTwinReplayService.createStandardDemo(
        demoPlan(), demoTarget(), manifest)[10].session;
      const payload: ObservationSharePayload = ObservationShareService.createTaskReportPayload({
        session: session,
        replayManifest: manifest
      });
      expect(payload.simulated).assertTrue();
      expect(payload.content.includes('模拟素材 · 非现场实拍')).assertTrue();
      expect(payload.content.includes('192.168.')).assertFalse();
      expect(payload.content.includes('9999')).assertFalse();
      expect(payload.content.includes('token')).assertFalse();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CelestialObject,
  ObservationNightPeriod,
  ObservationPlanningResult,
  ObserverState,
  PlanningSnapshot
} from '../main/ets/models/DomainModels';
import { ObservationPlanningService } from '../main/ets/services/ObservationPlanningService';
import { PlanningPeriodService } from '../main/ets/services/PlanningPeriodService';
import { PlanningSnapshotService } from '../main/ets/services/PlanningSnapshotService';

function requireVega(): CelestialObject {
  const target: CelestialObject | undefined = CelestialCatalog.getById('star-vega');
  if (target === undefined) throw new Error('测试目录缺少织女星');
  return target;
}

function observerAt(timestampMs: number): ObserverState {
  return {
    latitudeDegrees: 34.75,
    longitudeDegrees: 113.62,
    elevationMeters: 100,
    timestampMs: timestampMs
  };
}

export default function planningSnapshotServiceTest(): void {
  describe('规划原子快照', () => {
    it('同一观测夜目标和地点可建立一致快照', 0, () => {
      const period: ObservationNightPeriod = PlanningPeriodService.resolveWithOffset(
        Date.UTC(2026, 6, 18, 8, 0, 0), 0, 480);
      const observer: ObserverState = observerAt(period.startAtMs);
      const target: CelestialObject = requireVega();
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        target, observer, period.startAtMs, undefined, {
          horizonHours: 24,
          sampleMinutes: 10,
          minAltitudeDegrees: 20,
          maxSunAltitudeDegrees: -12
        });
      const snapshot: PlanningSnapshot = PlanningSnapshotService.create(
        1, 0, period, target.id, observer, '系统定位', false, result);
      expect(PlanningSnapshotService.isConsistent(snapshot)).assertTrue();
    });

    it('明晚标题不得复用今晚计算结果', 0, () => {
      const tonightPeriod: ObservationNightPeriod = PlanningPeriodService.resolveWithOffset(
        Date.UTC(2026, 6, 18, 8, 0, 0), 0, 480);
      const tomorrowPeriod: ObservationNightPeriod = PlanningPeriodService.resolveWithOffset(
        Date.UTC(2026, 6, 18, 8, 0, 0), 1, 480);
      const observer: ObserverState = observerAt(tonightPeriod.startAtMs);
      const target: CelestialObject = requireVega();
      const tonightResult: ObservationPlanningResult = ObservationPlanningService.plan(
        target, observer, tonightPeriod.startAtMs);
      const staleSnapshot: PlanningSnapshot = {
        generation: 2,
        dayOffset: 1,
        period: tomorrowPeriod,
        targetId: target.id,
        observerLatitudeDegrees: observer.latitudeDegrees,
        observerLongitudeDegrees: observer.longitudeDegrees,
        locationSource: '系统定位',
        locationProvisional: false,
        result: tonightResult
      };
      expect(PlanningSnapshotService.isConsistent(staleSnapshot)).assertFalse();
    });

    it('天气摘要时间必须与当前推荐拍摄时段一致', 0, () => {
      const period: ObservationNightPeriod = PlanningPeriodService.resolveWithOffset(
        Date.UTC(2026, 6, 18, 8, 0, 0), 0, 480);
      const observer: ObserverState = observerAt(period.startAtMs);
      const target: CelestialObject = requireVega();
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        target, observer, period.startAtMs, undefined, {
          horizonHours: 24,
          sampleMinutes: 10,
          minAltitudeDegrees: 20,
          maxSunAltitudeDegrees: -12
        });
      const snapshot: PlanningSnapshot = PlanningSnapshotService.create(
        3, 0, period, target.id, observer, '系统定位', false, result);
      if (result.recommendedCaptureWindow === undefined) {
        throw new Error('测试目标应生成离线推荐拍摄时段');
      }
      result.planningWeatherSummary = {
        startAtMs: result.recommendedCaptureWindow.startAtMs + 10 * 60 * 1000,
        endAtMs: result.recommendedCaptureWindow.endAtMs,
        sampleCount: 2
      };
      expect(PlanningSnapshotService.isConsistent(snapshot)).assertFalse();
    });
  });
}

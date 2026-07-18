import {
  ObservationNightPeriod,
  ObservationNightSelection,
  ObservationPlanningResult,
  ObserverState,
  PlanningSnapshot
} from '../models/DomainModels';

/** 只负责建立和校验规划原子快照，不读取 UI、网络、设备或系统时钟。 */
export class PlanningSnapshotService {
  static create(generation: number, dayOffset: number, period: ObservationNightPeriod,
    targetId: string, observer: ObserverState, locationSource: string,
    locationProvisional: boolean, result: ObservationPlanningResult): PlanningSnapshot {
    const snapshot: PlanningSnapshot = {
      generation: generation,
      dayOffset: dayOffset,
      period: period,
      targetId: targetId,
      observerLatitudeDegrees: observer.latitudeDegrees,
      observerLongitudeDegrees: observer.longitudeDegrees,
      locationSource: locationSource,
      locationProvisional: locationProvisional,
      result: result
    };
    if (!PlanningSnapshotService.isConsistent(snapshot)) {
      throw new Error('规划快照中的观测夜、目标或地点不一致');
    }
    return snapshot;
  }

  static isConsistent(snapshot: PlanningSnapshot): boolean {
    if (!Number.isInteger(snapshot.generation) || snapshot.generation <= 0 ||
      (snapshot.dayOffset !== 0 && snapshot.dayOffset !== 1) ||
      snapshot.targetId.length === 0 ||
      !Number.isFinite(snapshot.observerLatitudeDegrees) ||
      !Number.isFinite(snapshot.observerLongitudeDegrees)) {
      return false;
    }
    const expectedSelection: ObservationNightSelection = snapshot.dayOffset === 0 ?
      ObservationNightSelection.TONIGHT : ObservationNightSelection.TOMORROW;
    if (snapshot.period.selection !== expectedSelection) {
      return false;
    }
    if (snapshot.result.targetId !== snapshot.targetId ||
      snapshot.result.startAtMs !== snapshot.period.startAtMs ||
      snapshot.result.endAtMs !== snapshot.period.endAtMs) {
      return false;
    }
    if (snapshot.result.recommendedCaptureWindow !== undefined) {
      const recommendedStartAtMs: number = snapshot.result.recommendedCaptureWindow.startAtMs;
      const recommendedEndAtMs: number = snapshot.result.recommendedCaptureWindow.endAtMs;
      if (recommendedStartAtMs < snapshot.period.startAtMs ||
        recommendedEndAtMs > snapshot.period.endAtMs ||
        recommendedStartAtMs >= recommendedEndAtMs) {
        return false;
      }
    }
    if (snapshot.result.planningWeatherSummary !== undefined) {
      const weatherStartAtMs: number = snapshot.result.planningWeatherSummary.startAtMs;
      const weatherEndAtMs: number = snapshot.result.planningWeatherSummary.endAtMs;
      if (weatherStartAtMs < snapshot.period.startAtMs ||
        weatherEndAtMs > snapshot.period.endAtMs ||
        weatherStartAtMs >= weatherEndAtMs) {
        return false;
      }
      // 有正式推荐时，主页面天气摘要必须与该推荐采用完全相同的时间口径。
      if (snapshot.result.recommendedCaptureWindow !== undefined &&
        (weatherStartAtMs !== snapshot.result.recommendedCaptureWindow.startAtMs ||
          weatherEndAtMs !== snapshot.result.recommendedCaptureWindow.endAtMs)) {
        return false;
      }
    }
    return true;
  }
}

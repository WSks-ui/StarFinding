import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  ObservationPlanningResult,
  ObserverState,
  OutingRecommendation,
  VisibilityStatus,
  WeatherDataStatus,
  WeatherForecast,
  WeatherHourlySample
} from '../main/ets/models/DomainModels';
import { ObservationPlanningService } from '../main/ets/services/ObservationPlanningService';
import {
  JPL_RISE_SET_SAMPLES,
  JplRiseSetSample
} from './fixtures/JplHorizonsSamples';

function zhengzhouObserver(timestampMs: number): ObserverState {
  return {
    latitudeDegrees: 34.75,
    longitudeDegrees: 113.62,
    elevationMeters: 100,
    timestampMs: timestampMs
  };
}

function requireTarget(id: string): CelestialObject {
  const target: CelestialObject | undefined = CelestialCatalog.getById(id);
  if (target === undefined) {
    throw new Error(`测试目录中缺少 ${id}`);
  }
  return target;
}

function clearForecast(startAtMs: number): WeatherForecast {
  const hourly: WeatherHourlySample[] = [];
  for (let offsetHours: number = 0; offsetHours <= 48; offsetHours++) {
    hourly.push({
      timestampMs: startAtMs + offsetHours * 3600000,
      cloudCoverPercent: 0,
      precipitationProbabilityPercent: 0,
      precipitationMillimeters: 0,
      humidityPercent: 50,
      visibilityMeters: 20000,
      windSpeedKph: 3.6,
      windGustKph: 7.2
    });
  }
  return {
    status: WeatherDataStatus.LIVE,
    sourceName: '测试预报',
    sourceUrl: 'https://example.test',
    fetchedAtMs: startAtMs,
    latitudeDegrees: 34.75,
    longitudeDegrees: 113.62,
    timezone: 'Asia/Shanghai',
    utcOffsetSeconds: 28800,
    forecastDays: 3,
    hourly: hourly,
    errorMessage: ''
  };
}

function unavailableForecast(startAtMs: number): WeatherForecast {
  return {
    status: WeatherDataStatus.UNAVAILABLE,
    sourceName: '测试离线预报',
    sourceUrl: '',
    fetchedAtMs: startAtMs,
    latitudeDegrees: 34.75,
    longitudeDegrees: 113.62,
    timezone: 'Asia/Shanghai',
    utcOffsetSeconds: 28800,
    forecastDays: 0,
    hourly: [],
    errorMessage: '模拟断网'
  };
}

function assertTargetPlanning(targetId: string, startAtMs: number): void {
  const result: ObservationPlanningResult = ObservationPlanningService.plan(
    requireTarget(targetId), zhengzhouObserver(startAtMs), startAtMs, undefined, {
      horizonHours: 24,
      sampleMinutes: 30,
      minAltitudeDegrees: 20,
      maxSunAltitudeDegrees: -12
    });
  expect(result.samples.length).assertEqual(49);
  expect(result.riseTransitSet.status !== VisibilityStatus.COORDINATE_UNAVAILABLE).assertTrue();
  expect(result.riseTransitSet.riseAtMs !== undefined).assertTrue();
  expect(result.riseTransitSet.transitAtMs !== undefined).assertTrue();
  expect(result.riseTransitSet.setAtMs !== undefined).assertTrue();
  expect(result.windows.length > 0).assertTrue();
  expect(result.bestWindow !== undefined).assertTrue();
  expect(result.moonIlluminationPercent >= 0 && result.moonIlluminationPercent <= 100).assertTrue();
  expect(result.recommendation).assertEqual(OutingRecommendation.ASTRONOMY_ONLY);
}

export default function observationPlanningServiceTest(): void {
  describe('无硬件观测规划', () => {
    it('离线精确星表可生成未来窗口', 0, () => {
      const startAtMs: number = Date.UTC(2026, 6, 12, 8, 0, 0);
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        requireTarget('star-vega'), zhengzhouObserver(startAtMs), startAtMs);
      expect(result.windows.length > 0).assertTrue();
      expect(result.bestWindow !== undefined).assertTrue();
      expect(result.recommendation).assertEqual(OutingRecommendation.ASTRONOMY_ONLY);
      expect(result.overallScore === undefined).assertTrue();
    });

    it('缺少坐标的目录条目只展示资料且不伪造窗口', 0, () => {
      const startAtMs: number = Date.UTC(2026, 6, 12, 8, 0, 0);
      const indexOnlyTarget: CelestialObject = {
        id: 'index-only-test',
        type: CelestialType.MESSIER,
        nameZh: '仅索引测试目标',
        nameEn: 'Index-only target',
        designation: 'TEST',
        constellation: '',
        description: '验证缺少坐标时的规划降级。',
        tags: ['测试'],
        precision: CatalogPrecision.INDEX_ONLY,
        gotoAllowed: false,
        recommendedFor18mm: false
      };
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        indexOnlyTarget, zhengzhouObserver(startAtMs), startAtMs);
      expect(result.riseTransitSet.status).assertEqual(VisibilityStatus.COORDINATE_UNAVAILABLE);
      expect(result.windows.length).assertEqual(0);
      expect(result.overallScore === undefined).assertTrue();
    });

    it('月球在地平线下时不产生月光惩罚', 0, () => {
      const target: CelestialObject = requireTarget('star-vega');
      const darkMoonScore: number = ObservationPlanningService.astronomyScore(
        target, 60, -18, -6, 100, 10);
      const newMoonScore: number = ObservationPlanningService.astronomyScore(
        target, 60, -18, 50, 0, 10);
      expect(darkMoonScore).assertEqual(newMoonScore);
      expect(darkMoonScore).assertEqual(100);
    });

    it('高云量和高降水概率触发天气低分上限', 0, () => {
      const cloudy: number | undefined = ObservationPlanningService.weatherScore({
        timestampMs: 0,
        cloudCoverPercent: 95,
        precipitationProbabilityPercent: 0
      });
      const rainy: number | undefined = ObservationPlanningService.weatherScore({
        timestampMs: 0,
        cloudCoverPercent: 0,
        precipitationProbabilityPercent: 70
      });
      expect(cloudy !== undefined && cloudy <= 20).assertTrue();
      expect(rainy !== undefined && rainy <= 15).assertTrue();
    });

    it('真实天气输入后才生成综合出行评分', 0, () => {
      const startAtMs: number = Date.UTC(2026, 6, 12, 8, 0, 0);
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        requireTarget('star-vega'), zhengzhouObserver(startAtMs), startAtMs, clearForecast(startAtMs));
      expect(result.weatherStatus).assertEqual(WeatherDataStatus.LIVE);
      expect(result.weatherScore !== undefined).assertTrue();
      expect(result.overallScore !== undefined).assertTrue();
    });

    it('亮星月球和行星均可生成完整离线规划', 0, () => {
      // 分别选择目标适合夜间观测的季节，避免把天体本夜不可见误判成规划器故障。
      assertTargetPlanning('star-capella', Date.UTC(2026, 11, 15, 4, 0, 0));
      assertTargetPlanning('star-vega', Date.UTC(2026, 6, 15, 4, 0, 0));
      assertTargetPlanning('solar-moon', Date.UTC(2026, 6, 29, 4, 0, 0));
      assertTargetPlanning('planet-mars', Date.UTC(2027, 0, 15, 4, 0, 0));
    });

    it('天气不可用时仍保留离线天文窗口', 0, () => {
      const startAtMs: number = Date.UTC(2026, 6, 15, 4, 0, 0);
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        requireTarget('star-vega'), zhengzhouObserver(startAtMs), startAtMs,
        unavailableForecast(startAtMs));
      expect(result.weatherStatus).assertEqual(WeatherDataStatus.UNAVAILABLE);
      expect(result.windows.length > 0).assertTrue();
      expect(result.bestWindow !== undefined).assertTrue();
      expect(result.weatherScore === undefined).assertTrue();
      expect(result.overallScore === undefined).assertTrue();
      expect(result.recommendation).assertEqual(OutingRecommendation.ASTRONOMY_ONLY);
    });

    it('动态月球坐标随规划时间变化', 0, () => {
      const target: CelestialObject = requireTarget('solar-moon');
      const first = ObservationPlanningService.horizontalAt(
        target, zhengzhouObserver(Date.UTC(2026, 6, 12, 8, 0, 0)), Date.UTC(2026, 6, 12, 8, 0, 0));
      const second = ObservationPlanningService.horizontalAt(
        target, zhengzhouObserver(Date.UTC(2026, 6, 12, 14, 0, 0)), Date.UTC(2026, 6, 12, 14, 0, 0));
      expect(first !== undefined && second !== undefined &&
        Math.abs(first.azimuthDegrees - second.azimuthDegrees) > 1).assertTrue();
    });

    it('正常大气折射升落时刻与 JPL Horizons 相差不超过五分钟', 0, () => {
      for (let index: number = 0; index < JPL_RISE_SET_SAMPLES.length; index++) {
        const sample: JplRiseSetSample = JPL_RISE_SET_SAMPLES[index];
        const observer: ObserverState = {
          latitudeDegrees: sample.latitudeDegrees,
          longitudeDegrees: sample.longitudeDegrees,
          elevationMeters: sample.elevationMeters,
          timestampMs: sample.startAtMs
        };
        const result: ObservationPlanningResult = ObservationPlanningService.plan(
          requireTarget(sample.objectId), observer, sample.startAtMs, undefined, {
            horizonHours: 24.0,
            sampleMinutes: 10.0,
            minAltitudeDegrees: 0.0,
            maxSunAltitudeDegrees: 0.0
          });
        expect(result.riseTransitSet.riseAtMs !== undefined &&
          result.riseTransitSet.setAtMs !== undefined).assertTrue();
        if (result.riseTransitSet.riseAtMs === undefined ||
          result.riseTransitSet.setAtMs === undefined) continue;
        const toleranceMs: number = sample.toleranceMinutes * 60000.0;
        expect(Math.abs(result.riseTransitSet.riseAtMs - sample.riseAtMs) <= toleranceMs).assertTrue();
        expect(Math.abs(result.riseTransitSet.setAtMs - sample.setAtMs) <= toleranceMs).assertTrue();
      }
    });
  });
}

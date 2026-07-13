import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CelestialObject,
  ObservationPlanningResult,
  ObserverState,
  OutingRecommendation,
  VisibilityStatus,
  WeatherDataStatus,
  WeatherForecast,
  WeatherHourlySample
} from '../main/ets/models/DomainModels';
import { ObservationPlanningService } from '../main/ets/services/ObservationPlanningService';

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
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        requireTarget('messier-2'), zhengzhouObserver(startAtMs), startAtMs);
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

    it('动态月球坐标随规划时间变化', 0, () => {
      const target: CelestialObject = requireTarget('solar-moon');
      const first = ObservationPlanningService.horizontalAt(
        target, zhengzhouObserver(Date.UTC(2026, 6, 12, 8, 0, 0)), Date.UTC(2026, 6, 12, 8, 0, 0));
      const second = ObservationPlanningService.horizontalAt(
        target, zhengzhouObserver(Date.UTC(2026, 6, 12, 14, 0, 0)), Date.UTC(2026, 6, 12, 14, 0, 0));
      expect(first !== undefined && second !== undefined &&
        Math.abs(first.azimuthDegrees - second.azimuthDegrees) > 1).assertTrue();
    });
  });
}

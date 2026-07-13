import {
  CelestialObject,
  CelestialType,
  EquatorialCoordinate,
  HorizontalCoordinate,
  ObservationPlanningConstraints,
  ObservationPlanningResult,
  ObservationSample,
  ObservationWindow,
  ObserverState,
  OutingRecommendation,
  RiseTransitSet,
  VisibilityStatus,
  WeatherDataStatus,
  WeatherForecast,
  WeatherHourlySample
} from '../models/DomainModels';
import { AstronomyService } from './AstronomyService';

interface WindowAccumulator {
  samples: ObservationSample[];
  startAtMs: number;
  endAtMs: number;
}

/**
 * 纯本地观测规划器。这里不得读取赤道仪、相机或网关状态，确保没有外部硬件时仍能完成规划。
 * 当前星历采用项目内的低精度太阳系算法，适合小时级出行与广角构图规划，不应标称为专业测量星历。
 */
export class ObservationPlanningService {
  private static readonly DEFAULT_HORIZON_HOURS: number = 48;
  private static readonly DEFAULT_SAMPLE_MINUTES: number = 10;
  private static readonly DEFAULT_MIN_ALTITUDE: number = 20;
  private static readonly DEFAULT_MAX_SUN_ALTITUDE: number = -12;
  private static readonly SYNODIC_MONTH_DAYS: number = 29.530588853;
  private static readonly REFERENCE_NEW_MOON_JD: number = 2451550.1;

  static defaultConstraints(): ObservationPlanningConstraints {
    return {
      horizonHours: ObservationPlanningService.DEFAULT_HORIZON_HOURS,
      sampleMinutes: ObservationPlanningService.DEFAULT_SAMPLE_MINUTES,
      minAltitudeDegrees: ObservationPlanningService.DEFAULT_MIN_ALTITUDE,
      maxSunAltitudeDegrees: ObservationPlanningService.DEFAULT_MAX_SUN_ALTITUDE
    };
  }

  static horizontalAt(target: CelestialObject, observer: ObserverState,
    timestampMs: number): HorizontalCoordinate | undefined {
    const coordinate: EquatorialCoordinate | undefined = AstronomyService.resolveCoordinate(target, timestampMs);
    if (coordinate === undefined) {
      return undefined;
    }
    return AstronomyService.equatorialToHorizontal(coordinate, {
      latitudeDegrees: observer.latitudeDegrees,
      longitudeDegrees: observer.longitudeDegrees,
      elevationMeters: observer.elevationMeters,
      timestampMs: timestampMs
    });
  }

  /** 由朔望月年龄计算月面亮面比例，返回 0-100。 */
  static moonIlluminationPercent(timestampMs: number): number {
    const julianDay: number = AstronomyService.julianDay(timestampMs);
    let ageDays: number = (julianDay - ObservationPlanningService.REFERENCE_NEW_MOON_JD) %
      ObservationPlanningService.SYNODIC_MONTH_DAYS;
    if (ageDays < 0) {
      ageDays += ObservationPlanningService.SYNODIC_MONTH_DAYS;
    }
    const phaseRadians: number = 2 * Math.PI * ageDays / ObservationPlanningService.SYNODIC_MONTH_DAYS;
    return 50 * (1 - Math.cos(phaseRadians));
  }

  static moonPhaseName(timestampMs: number): string {
    const julianDay: number = AstronomyService.julianDay(timestampMs);
    let ageDays: number = (julianDay - ObservationPlanningService.REFERENCE_NEW_MOON_JD) %
      ObservationPlanningService.SYNODIC_MONTH_DAYS;
    if (ageDays < 0) {
      ageDays += ObservationPlanningService.SYNODIC_MONTH_DAYS;
    }
    const phase: number = ageDays / ObservationPlanningService.SYNODIC_MONTH_DAYS;
    if (phase < 0.03 || phase >= 0.97) return '新月';
    if (phase < 0.22) return '娥眉月';
    if (phase < 0.28) return '上弦月';
    if (phase < 0.47) return '盈凸月';
    if (phase < 0.53) return '满月';
    if (phase < 0.72) return '亏凸月';
    if (phase < 0.78) return '下弦月';
    return '残月';
  }

  static plan(target: CelestialObject, observer: ObserverState, startAtMs: number,
    forecast?: WeatherForecast, suppliedConstraints?: ObservationPlanningConstraints): ObservationPlanningResult {
    const constraints: ObservationPlanningConstraints = suppliedConstraints === undefined ?
      ObservationPlanningService.defaultConstraints() : {
        horizonHours: suppliedConstraints.horizonHours,
        sampleMinutes: suppliedConstraints.sampleMinutes,
        minAltitudeDegrees: suppliedConstraints.minAltitudeDegrees,
        maxSunAltitudeDegrees: suppliedConstraints.maxSunAltitudeDegrees
      };
    ObservationPlanningService.validateInput(observer, startAtMs, constraints);
    const endAtMs: number = startAtMs + constraints.horizonHours * 3600000;
    const weatherStatus: WeatherDataStatus = forecast === undefined ? WeatherDataStatus.NOT_REQUESTED : forecast.status;
    const firstCoordinate: EquatorialCoordinate | undefined = AstronomyService.resolveCoordinate(target, startAtMs);
    if (firstCoordinate === undefined) {
      return ObservationPlanningService.coordinateUnavailableResult(
        target, startAtMs, endAtMs, constraints, weatherStatus);
    }

    const samples: ObservationSample[] = ObservationPlanningService.buildSamples(
      target, observer, startAtMs, endAtMs, constraints.sampleMinutes, forecast);
    if (samples.length === 0) {
      return ObservationPlanningService.coordinateUnavailableResult(
        target, startAtMs, endAtMs, constraints, weatherStatus);
    }
    const windows: ObservationWindow[] = ObservationPlanningService.buildWindows(samples, constraints);
    const riseTransitSet: RiseTransitSet = ObservationPlanningService.buildRiseTransitSet(samples, windows.length);
    const bestWindow: ObservationWindow | undefined = ObservationPlanningService.selectBestWindow(windows);
    const referenceTime: number = bestWindow === undefined ? startAtMs : bestWindow.peakAtMs;
    const moonCoordinate: EquatorialCoordinate = AstronomyService.moonCoordinate(referenceTime);
    const targetCoordinate: EquatorialCoordinate | undefined = AstronomyService.resolveCoordinate(target, referenceTime);
    const moonSeparation: number | undefined = targetCoordinate === undefined ? undefined :
      AstronomyService.angularSeparation(targetCoordinate, moonCoordinate);
    const warnings: string[] = ObservationPlanningService.buildWarnings(target, weatherStatus, windows);
    const recommendation: OutingRecommendation = ObservationPlanningService.recommend(bestWindow, weatherStatus);
    const summary: string = ObservationPlanningService.summary(recommendation, bestWindow, target.nameZh);

    const result: ObservationPlanningResult = {
      targetId: target.id,
      targetName: target.nameZh,
      generatedAtMs: Date.now(),
      startAtMs: startAtMs,
      endAtMs: endAtMs,
      constraints: constraints,
      riseTransitSet: riseTransitSet,
      moonIlluminationPercent: ObservationPlanningService.moonIlluminationPercent(referenceTime),
      moonPhaseName: ObservationPlanningService.moonPhaseName(referenceTime),
      samples: samples,
      windows: windows,
      recommendation: recommendation,
      summary: summary,
      warnings: warnings,
      weatherStatus: weatherStatus
    };
    if (moonSeparation !== undefined) result.moonSeparationDegrees = moonSeparation;
    if (bestWindow !== undefined) {
      result.bestWindow = bestWindow;
      result.astronomyScore = bestWindow.astronomyScore;
      if (bestWindow.weatherScore !== undefined) result.weatherScore = bestWindow.weatherScore;
      if (bestWindow.overallScore !== undefined) result.overallScore = bestWindow.overallScore;
    }
    return result;
  }

  private static buildSamples(target: CelestialObject, observer: ObserverState, startAtMs: number,
    endAtMs: number, sampleMinutes: number, forecast?: WeatherForecast): ObservationSample[] {
    const samples: ObservationSample[] = [];
    const stepMs: number = sampleMinutes * 60000;
    let timestampMs: number = startAtMs;
    while (timestampMs <= endAtMs) {
      const sample: ObservationSample | undefined = ObservationPlanningService.buildSample(
        target, observer, timestampMs, forecast);
      if (sample === undefined) {
        return [];
      }
      samples.push(sample);
      if (timestampMs === endAtMs) break;
      timestampMs = Math.min(endAtMs, timestampMs + stepMs);
    }
    return samples;
  }

  private static buildSample(target: CelestialObject, observer: ObserverState, timestampMs: number,
    forecast?: WeatherForecast): ObservationSample | undefined {
    const coordinate: EquatorialCoordinate | undefined = AstronomyService.resolveCoordinate(target, timestampMs);
    if (coordinate === undefined) return undefined;
    const timedObserver: ObserverState = {
      latitudeDegrees: observer.latitudeDegrees,
      longitudeDegrees: observer.longitudeDegrees,
      elevationMeters: observer.elevationMeters,
      timestampMs: timestampMs
    };
    const horizontal: HorizontalCoordinate = AstronomyService.equatorialToHorizontal(coordinate, timedObserver);
    const sunCoordinate: EquatorialCoordinate = AstronomyService.sunCoordinate(timestampMs);
    const moonCoordinate: EquatorialCoordinate = AstronomyService.moonCoordinate(timestampMs);
    const sunHorizontal: HorizontalCoordinate = AstronomyService.equatorialToHorizontal(sunCoordinate, timedObserver);
    const moonHorizontal: HorizontalCoordinate = AstronomyService.equatorialToHorizontal(moonCoordinate, timedObserver);
    const illumination: number = ObservationPlanningService.moonIlluminationPercent(timestampMs);
    const separation: number = AstronomyService.angularSeparation(coordinate, moonCoordinate);
    const astronomyScore: number = ObservationPlanningService.astronomyScore(
      target, horizontal.altitudeDegrees, sunHorizontal.altitudeDegrees,
      moonHorizontal.altitudeDegrees, illumination, separation);
    const weatherSample: WeatherHourlySample | undefined = ObservationPlanningService.nearestWeather(
      forecast, timestampMs);
    const weatherScore: number | undefined = ObservationPlanningService.weatherScore(weatherSample);
    const result: ObservationSample = {
      timestampMs: timestampMs,
      altitudeDegrees: horizontal.altitudeDegrees,
      azimuthDegrees: horizontal.azimuthDegrees,
      sunAltitudeDegrees: sunHorizontal.altitudeDegrees,
      moonAltitudeDegrees: moonHorizontal.altitudeDegrees,
      moonIlluminationPercent: illumination,
      moonSeparationDegrees: separation,
      astronomyScore: astronomyScore
    };
    if (weatherScore !== undefined) {
      result.weatherScore = weatherScore;
      result.overallScore = ObservationPlanningService.combinedScore(astronomyScore, weatherScore);
    }
    return result;
  }

  /**
   * 天文评分使用乘积结构，使白天或目标过低时不会被其他高分项错误补偿。
   * 月球自身不因自身月光受罚；太阳仍会由暮光项归零，并在结果中给出安全警告。
   */
  static astronomyScore(target: CelestialObject, altitudeDegrees: number, sunAltitudeDegrees: number,
    moonAltitudeDegrees: number, illuminationPercent: number, moonSeparationDegrees: number): number {
    let altitudeScore: number = 0;
    if (altitudeDegrees > 10 && altitudeDegrees < 30) {
      altitudeScore = 0.55 * (altitudeDegrees - 10) / 20;
    } else if (altitudeDegrees >= 30 && altitudeDegrees < 60) {
      altitudeScore = 0.55 + 0.45 * (altitudeDegrees - 30) / 30;
    } else if (altitudeDegrees >= 60) {
      altitudeScore = 1;
    }
    let darknessScore: number = 0;
    if (sunAltitudeDegrees <= -18) {
      darknessScore = 1;
    } else if (sunAltitudeDegrees <= -12) {
      darknessScore = 0.35 + 0.65 * (-sunAltitudeDegrees - 12) / 6;
    } else if (sunAltitudeDegrees <= -6) {
      darknessScore = 0.35 * (-sunAltitudeDegrees - 6) / 6;
    }
    let moonScore: number = 1;
    if (target.type !== CelestialType.MOON) {
      const illumination: number = ObservationPlanningService.clamp(illuminationPercent / 100, 0, 1);
      const moonPresence: number = ObservationPlanningService.clamp((moonAltitudeDegrees + 5) / 35, 0, 1);
      const proximity: number = ObservationPlanningService.clamp((90 - moonSeparationDegrees) / 90, 0, 1);
      const penalty: number = Math.pow(illumination, 1.5) * moonPresence * (0.55 + 0.45 * proximity);
      moonScore = 1 - ObservationPlanningService.clamp(penalty, 0, 1);
    }
    return Math.round(100 * altitudeScore * darknessScore * moonScore);
  }

  static weatherScore(sample?: WeatherHourlySample): number | undefined {
    if (sample === undefined || sample.cloudCoverPercent === undefined ||
      sample.precipitationProbabilityPercent === undefined) {
      return undefined;
    }
    const cloud: number = ObservationPlanningService.clamp(sample.cloudCoverPercent / 100, 0, 1);
    const precipitation: number = ObservationPlanningService.clamp(
      sample.precipitationProbabilityPercent / 100, 0, 1);
    let weighted: number = 0.55 * Math.pow(1 - cloud, 2) + 0.20 * (1 - precipitation);
    let weight: number = 0.75;
    if (sample.humidityPercent !== undefined) {
      weighted += 0.10 * ObservationPlanningService.clamp((98 - sample.humidityPercent) / 28, 0, 1);
      weight += 0.10;
    }
    if (sample.visibilityMeters !== undefined) {
      weighted += 0.08 * ObservationPlanningService.clamp((sample.visibilityMeters / 1000 - 3) / 17, 0, 1);
      weight += 0.08;
    }
    if (sample.windSpeedKph !== undefined) {
      weighted += 0.07 * ObservationPlanningService.clamp((12 - sample.windSpeedKph / 3.6) / 9, 0, 1);
      weight += 0.07;
    }
    let score: number = Math.round(100 * weighted / weight);
    if (cloud >= 0.9) score = Math.min(score, 20);
    if (precipitation >= 0.6 || (sample.precipitationMillimeters !== undefined &&
      sample.precipitationMillimeters >= 0.2)) score = Math.min(score, 15);
    if ((sample.windSpeedKph !== undefined && sample.windSpeedKph >= 43.2) ||
      (sample.windGustKph !== undefined && sample.windGustKph >= 54)) score = Math.min(score, 20);
    return score;
  }

  private static buildWindows(samples: ObservationSample[],
    constraints: ObservationPlanningConstraints): ObservationWindow[] {
    const windows: ObservationWindow[] = [];
    let current: WindowAccumulator | undefined = undefined;
    for (let index: number = 0; index < samples.length; index++) {
      const sample: ObservationSample = samples[index];
      const valid: boolean = ObservationPlanningService.isWindowSample(sample, constraints);
      if (valid && current === undefined) {
        const startAtMs: number = index === 0 ? sample.timestampMs :
          ObservationPlanningService.interpolateBoundary(samples[index - 1], sample, constraints, true);
        current = { samples: [sample], startAtMs: startAtMs, endAtMs: sample.timestampMs };
      } else if (valid && current !== undefined) {
        current.samples.push(sample);
        current.endAtMs = sample.timestampMs;
      } else if (!valid && current !== undefined) {
        current.endAtMs = ObservationPlanningService.interpolateBoundary(
          samples[index - 1], sample, constraints, false);
        windows.push(ObservationPlanningService.finishWindow(current));
        current = undefined;
      }
    }
    if (current !== undefined) {
      current.endAtMs = samples[samples.length - 1].timestampMs;
      windows.push(ObservationPlanningService.finishWindow(current));
    }
    return windows;
  }

  private static isWindowSample(sample: ObservationSample,
    constraints: ObservationPlanningConstraints): boolean {
    return sample.altitudeDegrees >= constraints.minAltitudeDegrees &&
      sample.sunAltitudeDegrees <= constraints.maxSunAltitudeDegrees;
  }

  private static interpolateBoundary(first: ObservationSample, second: ObservationSample,
    constraints: ObservationPlanningConstraints, entering: boolean): number {
    const ratios: number[] = [];
    if ((first.altitudeDegrees < constraints.minAltitudeDegrees) !==
      (second.altitudeDegrees < constraints.minAltitudeDegrees)) {
      ratios.push(ObservationPlanningService.crossingRatio(
        first.altitudeDegrees, second.altitudeDegrees, constraints.minAltitudeDegrees));
    }
    if ((first.sunAltitudeDegrees > constraints.maxSunAltitudeDegrees) !==
      (second.sunAltitudeDegrees > constraints.maxSunAltitudeDegrees)) {
      ratios.push(ObservationPlanningService.crossingRatio(
        first.sunAltitudeDegrees, second.sunAltitudeDegrees, constraints.maxSunAltitudeDegrees));
    }
    let ratio: number = 0.5;
    if (ratios.length > 0) {
      ratio = ratios[0];
      for (let index: number = 1; index < ratios.length; index++) {
        ratio = entering ? Math.max(ratio, ratios[index]) : Math.min(ratio, ratios[index]);
      }
    }
    return Math.round(first.timestampMs + ratio * (second.timestampMs - first.timestampMs));
  }

  private static crossingRatio(firstValue: number, secondValue: number, threshold: number): number {
    const difference: number = secondValue - firstValue;
    if (Math.abs(difference) < 0.000001) return 0.5;
    return ObservationPlanningService.clamp((threshold - firstValue) / difference, 0, 1);
  }

  private static finishWindow(accumulator: WindowAccumulator): ObservationWindow {
    let peak: ObservationSample = accumulator.samples[0];
    let astronomyTotal: number = 0;
    let weatherTotal: number = 0;
    let weatherCount: number = 0;
    let minimumMoonSeparation: number = 180;
    for (let index: number = 0; index < accumulator.samples.length; index++) {
      const sample: ObservationSample = accumulator.samples[index];
      astronomyTotal += sample.astronomyScore;
      minimumMoonSeparation = Math.min(minimumMoonSeparation, sample.moonSeparationDegrees);
      if (sample.weatherScore !== undefined) {
        weatherTotal += sample.weatherScore;
        weatherCount++;
      }
      const sampleRank: number = sample.overallScore === undefined ? sample.astronomyScore : sample.overallScore;
      const peakRank: number = peak.overallScore === undefined ? peak.astronomyScore : peak.overallScore;
      if (sampleRank > peakRank || (sampleRank === peakRank && sample.altitudeDegrees > peak.altitudeDegrees)) {
        peak = sample;
      }
    }
    const astronomyScore: number = Math.round(astronomyTotal / accumulator.samples.length);
    const result: ObservationWindow = {
      startAtMs: accumulator.startAtMs,
      endAtMs: accumulator.endAtMs,
      peakAtMs: peak.timestampMs,
      peakAltitudeDegrees: peak.altitudeDegrees,
      minMoonSeparationDegrees: minimumMoonSeparation,
      astronomyScore: astronomyScore
    };
    if (weatherCount >= Math.ceil(accumulator.samples.length / 2)) {
      const weatherScore: number = Math.round(weatherTotal / weatherCount);
      result.weatherScore = weatherScore;
      result.overallScore = ObservationPlanningService.combinedScore(astronomyScore, weatherScore);
    }
    return result;
  }

  private static buildRiseTransitSet(samples: ObservationSample[], windowCount: number): RiseTransitSet {
    let maximum: ObservationSample = samples[0];
    let riseAtMs: number | undefined = undefined;
    let setAtMs: number | undefined = undefined;
    let allAbove: boolean = true;
    for (let index: number = 0; index < samples.length; index++) {
      const current: ObservationSample = samples[index];
      if (current.altitudeDegrees <= 0) allAbove = false;
      if (current.altitudeDegrees > maximum.altitudeDegrees) maximum = current;
      if (index === 0) continue;
      const previous: ObservationSample = samples[index - 1];
      if (riseAtMs === undefined && previous.altitudeDegrees <= 0 && current.altitudeDegrees > 0) {
        riseAtMs = ObservationPlanningService.interpolateAltitudeCrossing(previous, current, 0);
      }
      if (setAtMs === undefined && previous.altitudeDegrees > 0 && current.altitudeDegrees <= 0) {
        setAtMs = ObservationPlanningService.interpolateAltitudeCrossing(previous, current, 0);
      }
    }
    let status: VisibilityStatus = VisibilityStatus.NORMAL;
    if (allAbove) status = VisibilityStatus.ALWAYS_ABOVE_HORIZON;
    else if (maximum.altitudeDegrees <= 0) status = VisibilityStatus.NEVER_RISE;
    else if (windowCount === 0) status = VisibilityStatus.NO_DARK_WINDOW;
    const result: RiseTransitSet = {
      status: status,
      transitAtMs: maximum.timestampMs,
      maxAltitudeDegrees: maximum.altitudeDegrees
    };
    if (riseAtMs !== undefined) result.riseAtMs = riseAtMs;
    if (setAtMs !== undefined) result.setAtMs = setAtMs;
    return result;
  }

  private static interpolateAltitudeCrossing(first: ObservationSample, second: ObservationSample,
    altitudeDegrees: number): number {
    const ratio: number = ObservationPlanningService.crossingRatio(
      first.altitudeDegrees, second.altitudeDegrees, altitudeDegrees);
    return Math.round(first.timestampMs + ratio * (second.timestampMs - first.timestampMs));
  }

  private static selectBestWindow(windows: ObservationWindow[]): ObservationWindow | undefined {
    if (windows.length === 0) return undefined;
    let best: ObservationWindow = windows[0];
    for (let index: number = 1; index < windows.length; index++) {
      const candidate: ObservationWindow = windows[index];
      const candidateScore: number = candidate.overallScore === undefined ?
        candidate.astronomyScore : candidate.overallScore;
      const bestScore: number = best.overallScore === undefined ? best.astronomyScore : best.overallScore;
      if (candidateScore > bestScore || (candidateScore === bestScore &&
        candidate.peakAltitudeDegrees > best.peakAltitudeDegrees)) {
        best = candidate;
      }
    }
    return best;
  }

  private static nearestWeather(forecast: WeatherForecast | undefined,
    timestampMs: number): WeatherHourlySample | undefined {
    if (forecast === undefined || (forecast.status !== WeatherDataStatus.LIVE &&
      forecast.status !== WeatherDataStatus.CACHED) || forecast.hourly.length === 0) {
      return undefined;
    }
    let nearest: WeatherHourlySample = forecast.hourly[0];
    let distance: number = Math.abs(nearest.timestampMs - timestampMs);
    for (let index: number = 1; index < forecast.hourly.length; index++) {
      const candidate: WeatherHourlySample = forecast.hourly[index];
      const candidateDistance: number = Math.abs(candidate.timestampMs - timestampMs);
      if (candidateDistance < distance) {
        nearest = candidate;
        distance = candidateDistance;
      }
    }
    // 超过 90 分钟不外推，防止把陈旧天气误当成目标时段的预报。
    return distance <= 5400000 ? nearest : undefined;
  }

  private static combinedScore(astronomyScore: number, weatherScore: number): number {
    return Math.round(100 * Math.pow(astronomyScore / 100, 0.45) *
      Math.pow(weatherScore / 100, 0.55));
  }

  private static recommend(bestWindow: ObservationWindow | undefined,
    weatherStatus: WeatherDataStatus): OutingRecommendation {
    if (bestWindow === undefined) return OutingRecommendation.UNAVAILABLE;
    if (weatherStatus !== WeatherDataStatus.LIVE && weatherStatus !== WeatherDataStatus.CACHED) {
      return OutingRecommendation.ASTRONOMY_ONLY;
    }
    if (bestWindow.overallScore === undefined) return OutingRecommendation.ASTRONOMY_ONLY;
    if (bestWindow.overallScore >= 65) return OutingRecommendation.GOOD;
    if (bestWindow.overallScore >= 45) return OutingRecommendation.CAUTION;
    return OutingRecommendation.POOR;
  }

  private static summary(recommendation: OutingRecommendation,
    bestWindow: ObservationWindow | undefined, targetName: string): string {
    if (bestWindow === undefined) return `未来规划范围内没有适合 ${targetName} 的连续暗夜窗口`;
    if (recommendation === OutingRecommendation.GOOD) return '天气与天文条件较好，值得安排出行';
    if (recommendation === OutingRecommendation.CAUTION) return '存在可用窗口，建议出发前复查云量和降水';
    if (recommendation === OutingRecommendation.POOR) return '天气风险较高，不建议为本窗口专程出行';
    return '天文窗口已离线算出，联网获取天气后再决定是否出门';
  }

  private static buildWarnings(target: CelestialObject, weatherStatus: WeatherDataStatus,
    windows: ObservationWindow[]): string[] {
    const warnings: string[] = [];
    if (!target.recommendedFor18mm) {
      warnings.push('目标可观测，但 18mm 镜头不适合作为清晰主体，建议用于环境星野构图');
    }
    if (target.type === CelestialType.SUN) {
      warnings.push('太阳观测必须使用合格的前置太阳滤镜，本应用不会把普通夜间计划用于太阳摄影');
    }
    if (weatherStatus !== WeatherDataStatus.LIVE && weatherStatus !== WeatherDataStatus.CACHED) {
      warnings.push('天气数据不可用；当前结论仅包含本地天文计算，不代表实际晴天');
    }
    if (windows.length === 0) {
      warnings.push('可尝试更换日期、地点或降低最低高度要求');
    }
    warnings.push('升落和月相为规划级近似值，现场请结合实际地平遮挡复核');
    return warnings;
  }

  private static coordinateUnavailableResult(target: CelestialObject, startAtMs: number, endAtMs: number,
    constraints: ObservationPlanningConstraints, weatherStatus: WeatherDataStatus): ObservationPlanningResult {
    return {
      targetId: target.id,
      targetName: target.nameZh,
      generatedAtMs: Date.now(),
      startAtMs: startAtMs,
      endAtMs: endAtMs,
      constraints: constraints,
      riseTransitSet: {
        status: VisibilityStatus.COORDINATE_UNAVAILABLE,
        maxAltitudeDegrees: -90
      },
      moonIlluminationPercent: ObservationPlanningService.moonIlluminationPercent(startAtMs),
      moonPhaseName: ObservationPlanningService.moonPhaseName(startAtMs),
      samples: [],
      windows: [],
      recommendation: OutingRecommendation.UNAVAILABLE,
      summary: '该离线目录条目暂缺可靠坐标，可以查看资料，但不能生成可见时间窗口',
      warnings: ['请选择带精确坐标的亮星、重点星座、梅西耶目标、月球或主要行星'],
      weatherStatus: weatherStatus
    };
  }

  private static validateInput(observer: ObserverState, startAtMs: number,
    constraints: ObservationPlanningConstraints): void {
    if (!Number.isFinite(observer.latitudeDegrees) || observer.latitudeDegrees < -90 ||
      observer.latitudeDegrees > 90) throw new Error('规划纬度必须在 -90 到 90 度之间');
    if (!Number.isFinite(observer.longitudeDegrees) || observer.longitudeDegrees < -180 ||
      observer.longitudeDegrees > 180) throw new Error('规划经度必须在 -180 到 180 度之间');
    if (!Number.isFinite(startAtMs)) throw new Error('规划开始时间无效');
    if (!Number.isFinite(constraints.horizonHours) || constraints.horizonHours <= 0 ||
      constraints.horizonHours > 48) throw new Error('规划范围必须大于 0 小时且不超过 48 小时');
    if (!Number.isFinite(constraints.sampleMinutes) || constraints.sampleMinutes < 5 ||
      constraints.sampleMinutes > 30) throw new Error('规划采样间隔必须在 5 到 30 分钟之间');
    if (!Number.isFinite(constraints.minAltitudeDegrees) || constraints.minAltitudeDegrees < 0 ||
      constraints.minAltitudeDegrees > 90) throw new Error('最低观测高度必须在 0 到 90 度之间');
    if (!Number.isFinite(constraints.maxSunAltitudeDegrees) ||
      constraints.maxSunAltitudeDegrees < -30 || constraints.maxSunAltitudeDegrees > 0) {
      throw new Error('太阳高度边界必须在 -30 到 0 度之间');
    }
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

import { http } from '@kit.NetworkKit';
import {
  ObserverState,
  WeatherDataStatus,
  WeatherForecast,
  WeatherHourlySample
} from '../models/DomainModels';

const OPEN_METEO_FORECAST_ENDPOINT: string = 'https://api.open-meteo.com/v1/forecast';
const OPEN_METEO_FORECAST_DAYS: number = 8;
const OPEN_METEO_MAX_RESPONSE_BYTES: number = 1024 * 1024;
const OPEN_METEO_HOURLY_FIELDS: string[] = [
  'temperature_2m',
  'relative_humidity_2m',
  'dew_point_2m',
  'precipitation_probability',
  'precipitation',
  'weather_code',
  'pressure_msl',
  'cloud_cover',
  'cloud_cover_low',
  'cloud_cover_mid',
  'cloud_cover_high',
  'visibility',
  'wind_speed_10m',
  'wind_gusts_10m'
];

export type NullableWeatherNumber = number | null;

/** Open-Meteo 小时级原始 DTO。字段保持 snake_case，便于发现上游契约变化。 */
export interface OpenMeteoHourlyDto {
  time?: number[];
  temperature_2m?: NullableWeatherNumber[];
  relative_humidity_2m?: NullableWeatherNumber[];
  dew_point_2m?: NullableWeatherNumber[];
  precipitation_probability?: NullableWeatherNumber[];
  precipitation?: NullableWeatherNumber[];
  weather_code?: NullableWeatherNumber[];
  pressure_msl?: NullableWeatherNumber[];
  cloud_cover?: NullableWeatherNumber[];
  cloud_cover_low?: NullableWeatherNumber[];
  cloud_cover_mid?: NullableWeatherNumber[];
  cloud_cover_high?: NullableWeatherNumber[];
  visibility?: NullableWeatherNumber[];
  wind_speed_10m?: NullableWeatherNumber[];
  wind_gusts_10m?: NullableWeatherNumber[];
}

/** Open-Meteo 响应 DTO。可选字段用于在运行时报告缺失项，而不是在属性访问时崩溃。 */
export interface OpenMeteoForecastDto {
  latitude?: number;
  longitude?: number;
  elevation?: number;
  utc_offset_seconds?: number;
  timezone?: string;
  timezone_abbreviation?: string;
  hourly?: OpenMeteoHourlyDto;
}

/**
 * 构造无密钥 Open-Meteo 请求。此函数不读取时钟或系统状态，可由本地单元测试直接验证。
 * timeformat=unixtime 可避免把上游“无时区 ISO 字符串”误当成 Pad 当前时区。
 */
export function buildOpenMeteoForecastUrl(observer: ObserverState): string {
  validateObserver(observer);
  const query: string[] = [
    `latitude=${formatCoordinate(observer.latitudeDegrees)}`,
    `longitude=${formatCoordinate(observer.longitudeDegrees)}`,
    `hourly=${OPEN_METEO_HOURLY_FIELDS.join(',')}`,
    'timezone=auto',
    'timeformat=unixtime',
    `forecast_days=${OPEN_METEO_FORECAST_DAYS}`,
    'temperature_unit=celsius',
    'wind_speed_unit=kmh',
    'precipitation_unit=mm'
  ];
  return `${OPEN_METEO_FORECAST_ENDPOINT}?${query.join('&')}`;
}

/**
 * 将已经反序列化的 DTO 映射为应用模型。所有小时数组必须和 time 严格等长；
 * 上游合法的 null 表示该时次没有数据，必须保留，不能伪装为零云量或零降水。
 */
export function mapOpenMeteoForecastDto(dto: OpenMeteoForecastDto, observer: ObserverState,
  fetchedAtMs: number): WeatherForecast {
  validateObserver(observer);
  requireFinite(fetchedAtMs, '天气获取时间');
  if (fetchedAtMs < 0) {
    throw new Error('天气获取时间不能为负数');
  }

  const gridLatitude: number = requireFinite(dto.latitude, 'latitude');
  const gridLongitude: number = requireFinite(dto.longitude, 'longitude');
  const gridElevation: number = requireFinite(dto.elevation, 'elevation');
  const utcOffsetSeconds: number = requireFinite(dto.utc_offset_seconds, 'utc_offset_seconds');
  const timezone: string = requireNonEmptyString(dto.timezone, 'timezone');
  const timezoneAbbreviation: string = requireNonEmptyString(
    dto.timezone_abbreviation, 'timezone_abbreviation');
  if (gridLatitude < -90 || gridLatitude > 90 || gridLongitude < -180 || gridLongitude > 180) {
    throw new Error('Open-Meteo 返回的网格经纬度超出合法范围');
  }
  if (!Number.isInteger(utcOffsetSeconds) || utcOffsetSeconds < -64800 || utcOffsetSeconds > 64800) {
    throw new Error('Open-Meteo 返回的 utc_offset_seconds 无效');
  }

  const hourly: OpenMeteoHourlyDto | undefined = dto.hourly;
  if (hourly === undefined || hourly === null) {
    throw new Error('Open-Meteo 响应缺少 hourly');
  }
  const times: number[] = requireTimeArray(hourly.time);
  const expectedLength: number = times.length;
  const temperature: NullableWeatherNumber[] = requireWeatherArray(
    hourly.temperature_2m, 'temperature_2m', expectedLength);
  const humidity: NullableWeatherNumber[] = requireWeatherArray(
    hourly.relative_humidity_2m, 'relative_humidity_2m', expectedLength);
  const dewPoint: NullableWeatherNumber[] = requireWeatherArray(
    hourly.dew_point_2m, 'dew_point_2m', expectedLength);
  const precipitationProbability: NullableWeatherNumber[] = requireWeatherArray(
    hourly.precipitation_probability, 'precipitation_probability', expectedLength);
  const precipitation: NullableWeatherNumber[] = requireWeatherArray(
    hourly.precipitation, 'precipitation', expectedLength);
  const weatherCode: NullableWeatherNumber[] = requireWeatherArray(
    hourly.weather_code, 'weather_code', expectedLength);
  const pressure: NullableWeatherNumber[] = requireWeatherArray(
    hourly.pressure_msl, 'pressure_msl', expectedLength);
  const cloudCover: NullableWeatherNumber[] = requireWeatherArray(
    hourly.cloud_cover, 'cloud_cover', expectedLength);
  const cloudCoverLow: NullableWeatherNumber[] = requireWeatherArray(
    hourly.cloud_cover_low, 'cloud_cover_low', expectedLength);
  const cloudCoverMid: NullableWeatherNumber[] = requireWeatherArray(
    hourly.cloud_cover_mid, 'cloud_cover_mid', expectedLength);
  const cloudCoverHigh: NullableWeatherNumber[] = requireWeatherArray(
    hourly.cloud_cover_high, 'cloud_cover_high', expectedLength);
  const visibility: NullableWeatherNumber[] = requireWeatherArray(
    hourly.visibility, 'visibility', expectedLength);
  const windSpeed: NullableWeatherNumber[] = requireWeatherArray(
    hourly.wind_speed_10m, 'wind_speed_10m', expectedLength);
  const windGusts: NullableWeatherNumber[] = requireWeatherArray(
    hourly.wind_gusts_10m, 'wind_gusts_10m', expectedLength);

  const hours: WeatherHourlySample[] = [];
  for (let index: number = 0; index < expectedLength; index += 1) {
    const hour: WeatherHourlySample = { timestampMs: times[index] * 1000 };
    const temperatureValue: NullableWeatherNumber = temperature[index];
    const humidityValue: NullableWeatherNumber = humidity[index];
    const dewPointValue: NullableWeatherNumber = dewPoint[index];
    const precipitationProbabilityValue: NullableWeatherNumber = precipitationProbability[index];
    const precipitationValue: NullableWeatherNumber = precipitation[index];
    const weatherCodeValue: NullableWeatherNumber = weatherCode[index];
    const pressureValue: NullableWeatherNumber = pressure[index];
    const cloudCoverValue: NullableWeatherNumber = cloudCover[index];
    const cloudCoverLowValue: NullableWeatherNumber = cloudCoverLow[index];
    const cloudCoverMidValue: NullableWeatherNumber = cloudCoverMid[index];
    const cloudCoverHighValue: NullableWeatherNumber = cloudCoverHigh[index];
    const visibilityValue: NullableWeatherNumber = visibility[index];
    const windSpeedValue: NullableWeatherNumber = windSpeed[index];
    const windGustsValue: NullableWeatherNumber = windGusts[index];
    if (temperatureValue !== null) hour.temperatureCelsius = temperatureValue;
    if (humidityValue !== null) hour.humidityPercent = humidityValue;
    if (dewPointValue !== null) hour.dewPointCelsius = dewPointValue;
    if (precipitationProbabilityValue !== null) {
      hour.precipitationProbabilityPercent = precipitationProbabilityValue;
    }
    if (precipitationValue !== null) hour.precipitationMillimeters = precipitationValue;
    if (weatherCodeValue !== null) hour.weatherCode = weatherCodeValue;
    if (pressureValue !== null) hour.pressureMslHpa = pressureValue;
    if (cloudCoverValue !== null) hour.cloudCoverPercent = cloudCoverValue;
    if (cloudCoverLowValue !== null) hour.cloudCoverLowPercent = cloudCoverLowValue;
    if (cloudCoverMidValue !== null) hour.cloudCoverMidPercent = cloudCoverMidValue;
    if (cloudCoverHighValue !== null) hour.cloudCoverHighPercent = cloudCoverHighValue;
    if (visibilityValue !== null) hour.visibilityMeters = visibilityValue;
    if (windSpeedValue !== null) hour.windSpeedKph = windSpeedValue;
    if (windGustsValue !== null) hour.windGustKph = windGustsValue;
    hours.push(hour);
  }

  return {
    status: WeatherDataStatus.LIVE,
    sourceName: 'Open-Meteo',
    sourceUrl: buildOpenMeteoForecastUrl(observer),
    fetchedAtMs: fetchedAtMs,
    latitudeDegrees: gridLatitude,
    longitudeDegrees: gridLongitude,
    timezone: timezone,
    utcOffsetSeconds: utcOffsetSeconds,
    forecastDays: OPEN_METEO_FORECAST_DAYS,
    hourly: hours,
    errorMessage: ''
  };
}

/** 解析与映射保持纯函数，测试可直接输入固定 JSON，不依赖 NetworkKit 或真实互联网。 */
export function parseOpenMeteoForecastResponse(body: string, observer: ObserverState,
  fetchedAtMs: number): WeatherForecast {
  if (body.trim().length === 0) {
    throw new Error('Open-Meteo 响应为空');
  }
  let dto: OpenMeteoForecastDto | null;
  try {
    dto = JSON.parse(body) as OpenMeteoForecastDto | null;
  } catch (error) {
    throw new Error(`Open-Meteo 响应不是有效 JSON：${error}`);
  }
  if (dto === null) {
    throw new Error('Open-Meteo 响应不能为 null');
  }
  return mapOpenMeteoForecastDto(dto, observer, fetchedAtMs);
}

/** Pad 直连 Open-Meteo 的天气客户端，不依赖赤道仪、相机或 Linux 网关。 */
export class WeatherForecastService {
  private readonly connectTimeoutMs: number;
  private readonly readTimeoutMs: number;

  constructor(connectTimeoutMs: number = 4000, readTimeoutMs: number = 8000) {
    if (!Number.isInteger(connectTimeoutMs) || connectTimeoutMs < 1000 || connectTimeoutMs > 30000) {
      throw new Error('天气服务连接超时必须是 1000 到 30000 毫秒之间的整数');
    }
    if (!Number.isInteger(readTimeoutMs) || readTimeoutMs < 1000 || readTimeoutMs > 60000) {
      throw new Error('天气服务读取超时必须是 1000 到 60000 毫秒之间的整数');
    }
    this.connectTimeoutMs = connectTimeoutMs;
    this.readTimeoutMs = readTimeoutMs;
  }

  async fetch(observer: ObserverState): Promise<WeatherForecast> {
    const url: string = buildOpenMeteoForecastUrl(observer);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'X-StarFinding-Client': 'HarmonyOS'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.connectTimeoutMs,
        readTimeout: this.readTimeoutMs,
        maxLimit: OPEN_METEO_MAX_RESPONSE_BYTES,
        usingCache: false
      });
      const body: string = typeof response.result === 'string' ? response.result :
        JSON.stringify(response.result);
      const statusCode: number = Number(response.responseCode);
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`Open-Meteo 返回 HTTP ${statusCode}：${summarizeResponse(body)}`);
      }
      return parseOpenMeteoForecastResponse(body, observer, Date.now());
    } catch (error) {
      throw new Error(`获取 Open-Meteo 天气预报失败：${error}`);
    } finally {
      request.destroy();
    }
  }
}

function validateObserver(observer: ObserverState): void {
  if (!Number.isFinite(observer.latitudeDegrees) || observer.latitudeDegrees < -90 ||
    observer.latitudeDegrees > 90) {
    throw new Error('天气查询纬度必须在 -90 到 90 度之间');
  }
  if (!Number.isFinite(observer.longitudeDegrees) || observer.longitudeDegrees < -180 ||
    observer.longitudeDegrees > 180) {
    throw new Error('天气查询经度必须在 -180 到 180 度之间');
  }
  if (!Number.isFinite(observer.elevationMeters)) {
    throw new Error('天气查询海拔必须是有限数值');
  }
  if (!Number.isFinite(observer.timestampMs) || observer.timestampMs < 0) {
    throw new Error('观测时间必须是非负有限数值');
  }
}

function formatCoordinate(value: number): string {
  return value.toFixed(6);
}

function requireFinite(value: number | undefined, label: string): number {
  if (value === undefined || typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`Open-Meteo 响应字段 ${label} 必须是有限数值`);
  }
  return value;
}

function requireNonEmptyString(value: string | undefined, label: string): string {
  if (value === undefined || typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Open-Meteo 响应字段 ${label} 必须是非空字符串`);
  }
  return value;
}

function requireTimeArray(values: number[] | undefined): number[] {
  if (values === undefined || !Array.isArray(values) || values.length === 0) {
    throw new Error('Open-Meteo 响应字段 hourly.time 必须是非空数组');
  }
  const result: number[] = [];
  let previous: number = -1;
  for (let index: number = 0; index < values.length; index += 1) {
    const value: number = values[index];
    if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value) || value < 0) {
      throw new Error(`Open-Meteo 响应字段 hourly.time[${index}] 不是有效 Unix 时间戳`);
    }
    if (index > 0 && value <= previous) {
      throw new Error('Open-Meteo 响应字段 hourly.time 必须严格递增');
    }
    result.push(value);
    previous = value;
  }
  return result;
}

function requireWeatherArray(values: NullableWeatherNumber[] | undefined, label: string,
  expectedLength: number): NullableWeatherNumber[] {
  if (values === undefined || !Array.isArray(values)) {
    throw new Error(`Open-Meteo 响应缺少 hourly.${label} 数组`);
  }
  if (values.length !== expectedLength) {
    throw new Error(`Open-Meteo 响应 hourly.${label} 长度 ${values.length} 与 time 长度 ${expectedLength} 不一致`);
  }
  const result: NullableWeatherNumber[] = [];
  for (let index: number = 0; index < values.length; index += 1) {
    const value: NullableWeatherNumber = values[index];
    if (value !== null && (typeof value !== 'number' || !Number.isFinite(value))) {
      throw new Error(`Open-Meteo 响应字段 hourly.${label}[${index}] 必须是有限数值或 null`);
    }
    result.push(value);
  }
  return result;
}

function summarizeResponse(body: string): string {
  const normalized: string = body.replace(/\s+/g, ' ').trim();
  return normalized.length <= 240 ? normalized : `${normalized.substring(0, 240)}...`;
}

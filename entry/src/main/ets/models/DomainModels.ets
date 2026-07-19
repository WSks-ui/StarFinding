/**
 * StarFinding 核心领域模型。
 *
 * 模型层不依赖 UI、网络或设备 API，页面、真实设备服务和比赛回放服务可共享同一套契约。
 */

export enum CelestialType {
  STAR = 'star',
  CONSTELLATION = 'constellation',
  MESSIER = 'messier',
  SUN = 'sun',
  MOON = 'moon',
  PLANET = 'planet'
}
export enum CatalogPrecision {
  /** 具备可用于投影和 GOTO 的 J2000 坐标。 */
  EXACT = 'exact',
  /** 只有目录索引，允许检索和查看信息，但禁止据此控制赤道仪。 */
  INDEX_ONLY = 'index_only',
  /** 坐标需要按观测时刻动态计算。 */
  DYNAMIC = 'dynamic'
}

/**
 * 赤道坐标必须显式声明参考系。星表、屏幕投影、板解析和 OnStepX 使用的坐标不可互换。
 */
export enum EquatorialFrame {
  ICRS_J2000 = 'icrs_j2000',
  APPARENT_EQJ = 'apparent_eqj',
  TOPOCENTRIC_OF_DATE = 'topocentric_of_date'
}

export interface FramedEquatorialCoordinate {
  raHours: number;
  decDegrees: number;
  frame: EquatorialFrame;
  /** 动态坐标的有效时刻；固定 J2000 目录坐标可省略。 */
  validAtMs?: number;
}

/** 兼容现有投影接口的名称；其实际契约已经要求显式参考系。 */
export type EquatorialCoordinate = FramedEquatorialCoordinate;

/** 仅供赤道仪运动接口消费的当日站心坐标。 */
export interface MountTargetCoordinate {
  targetId: string;
  raHours: number;
  decDegrees: number;
  frame: EquatorialFrame;
  calculatedAtMs: number;
  observerKey: string;
}

export enum RefractionMode {
  NONE = 'none',
  NORMAL = 'normal'
}

/** 太阳系图符和详情面板共用的真实外观参数。 */
export interface SolarSystemAppearance {
  objectId: string;
  timestampMs: number;
  magnitude: number;
  illuminatedFraction: number;
  phaseAngleDegrees: number;
  angularDiameterArcSeconds: number;
  brightLimbAngleDegrees: number;
  distanceAu: number;
  ringTiltDegrees?: number;
  moonPhaseDegrees?: number;
}

export interface ApparentTrajectoryPoint {
  timestampMs: number;
  coordinate: FramedEquatorialCoordinate;
}

export interface ApparentTrajectory {
  objectId: string;
  startAtMs: number;
  endAtMs: number;
  stepMs: number;
  points: ApparentTrajectoryPoint[];
}

export interface HorizontalCoordinate {
  /** 高度角，单位为度。 */
  altitudeDegrees: number;
  /** 方位角，正北为 0 度、向东递增。 */
  azimuthDegrees: number;
  aboveHorizon: boolean;
}

/** 恒星在 ICRS 切平面上的自行；赤经分量遵循星表常用的 mu_alpha*cos(delta)。 */
export interface StellarProperMotion {
  pmRaMasPerYear: number;
  pmDecMasPerYear: number;
  sourceEpochYear: number;
}

export interface CelestialObject {
  id: string;
  type: CelestialType;
  nameZh: string;
  nameEn: string;
  designation: string;
  constellation: string;
  coordinate?: EquatorialCoordinate;
  stellarProperMotion?: StellarProperMotion;
  magnitude?: number;
  angularSizeDegrees?: number;
  description: string;
  tags: string[];
  precision: CatalogPrecision;
  gotoAllowed: boolean;
  recommendedFor18mm: boolean;
}

export interface ObserverState {
  latitudeDegrees: number;
  longitudeDegrees: number;
  elevationMeters: number;
  timestampMs: number;
}

export interface DevicePose {
  /** 后摄镜头中心指向的方位角。 */
  headingDegrees: number;
  /** 后摄镜头中心指向的高度角。 */
  pitchDegrees: number;
  /** 顺时针横滚角。 */
  rollDegrees: number;
}

export interface CameraViewport {
  widthPixels: number;
  heightPixels: number;
  horizontalFovDegrees: number;
  verticalFovDegrees: number;
}

export interface ScreenProjection {
  xPixels: number;
  yPixels: number;
  inFront: boolean;
  inViewport: boolean;
  angularDistanceDegrees: number;
}

export interface ArCalibration {
  headingOffsetDegrees: number;
  pitchOffsetDegrees: number;
  rollOffsetDegrees: number;
  anchorObjectId: string;
  calibratedAtMs: number;
}

export enum ConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  ERROR = 'error',
  SIMULATED = 'simulated'
}

export enum TrackingMode {
  STOPPED = 'stopped',
  SIDEREAL = 'sidereal',
  SOLAR = 'solar',
  LUNAR = 'lunar',
  UNKNOWN = 'unknown'
}

export interface MountState {
  connection: ConnectionState;
  host: string;
  port: number;
  rightAscensionHours: number;
  declinationDegrees: number;
  trackingMode: TrackingMode;
  slewing: boolean;
  homed: boolean;
  parked: boolean;
  lastError: string;
  updatedAtMs: number;
}

export interface CameraCapabilities {
  cameraModel: string;
  bulbSupported: boolean;
  maxExposureSeconds: number;
  rawSupported: boolean;
  liveViewSupported: boolean;
}

export interface CameraState {
  connection: ConnectionState;
  cameraModel: string;
  batteryPercent: number;
  storageFreeBytes: number;
  busy: boolean;
  liveViewActive: boolean;
  lastError: string;
  updatedAtMs: number;
}

export interface CameraPreflightCheck {
  code: string;
  label: string;
  actual: string;
  expected: string;
  passed: boolean;
  blocking: boolean;
  adjustment: string;
}

export interface CameraPreflightResult {
  ready: boolean;
  connected: boolean;
  backend: string;
  simulated: boolean;
  cameraModel: string;
  checks: CameraPreflightCheck[];
  blockers: string[];
  warnings: string[];
  checkedAtMs: number;
}

export enum CaptureMode {
  OBSERVE_ONLY = 'observe_only',
  SMART_LONG_EXPOSURE = 'smart_long_exposure',
  TIMELAPSE = 'timelapse'
}

export enum ImageFormat {
  JPEG = 'jpeg',
  RAW_JPEG = 'raw_jpeg'
}

export interface CapturePlan {
  id: string;
  mode: CaptureMode;
  targetId: string;
  targetName: string;
  exposureSeconds: number;
  frameCount: number;
  intervalSeconds: number;
  iso: number;
  aperture: number;
  imageFormat: ImageFormat;
  outputFps: number;
  enablePlateSolve: boolean;
  enableDriftCorrection: boolean;
  enableLocalStack: boolean;
  enableCloudEnhancement: boolean;
  recommendationReason: string;
  warnings: string[];
}

export enum TaskStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  SUCCEEDED = 'succeeded',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export interface CaptureProduct {
  kind: string;
  fileName: string;
  downloadUrl: string;
  createdAtMs: number;
}

export interface CaptureTask {
  id: string;
  plan: CapturePlan;
  status: TaskStatus;
  progressPercent: number;
  completedFrames: number;
  currentStage: string;
  errorMessage: string;
  products: CaptureProduct[];
  createdAtMs: number;
  updatedAtMs: number;
}

export interface PlateSolveResult {
  taskId: string;
  status: TaskStatus;
  solved: boolean;
  /** astrometry.net 的 WCS 中心固定标记为 ICRS J2000，禁止与赤道仪当日坐标直接相减。 */
  frame: EquatorialFrame;
  centerRaHours: number;
  centerDecDegrees: number;
  fieldWidthDegrees: number;
  fieldHeightDegrees: number;
  rotationDegrees: number;
  residualArcSeconds: number;
  errorMessage: string;
}

export interface EnhancementTask {
  id: string;
  sourceFileUrl: string;
  status: TaskStatus;
  progressPercent: number;
  resultFileUrl: string;
  modelVersion: string;
  preserveStars: boolean;
  errorMessage: string;
  createdAtMs: number;
  updatedAtMs: number;
}

export enum HandGesture {
  NONE = 'none',
  SINGLE_HAND_TRANSFORM = 'single_hand_transform',
  PINCH_SELECT = 'pinch_select',
  FIST_RESET = 'fist_reset'
}

export interface HandPoint {
  x: number;
  y: number;
  /** 模型输出的相对深度；它不代表相机到手部的真实物理距离。 */
  z?: number;
  confidence: number;
}

export interface HandLandmarks {
  trackingId: number;
  points: HandPoint[];
  /**
   * 关键点所在预览坐标的宽高比。x/y 虽同为 0–1，几何距离和角度仍需按该比例还原，
   * 否则长方形预览会把转掌误判成掌面尺寸变化。
   */
  coordinateAspectRatio?: number;
  /** 模型可选输出的三维世界关键点，坐标单位和原点由模型清单定义。 */
  worldPoints?: HandPoint[];
  confidence: number;
  /** 腕部及掌指关节 0、5、9、13、17 的综合可信度。 */
  palmConfidence?: number;
  /** 掌面朝向摄像头的可信度；过低时手掌尺寸不得用于前后移动缩放。 */
  palmFacingConfidence?: number;
  timestampMs: number;
}

/**
 * 单掌一帧产生的统一三轴变换。坐标和位移均为前摄预览中的 0–1 归一化值，
 * 缩放大于 1 表示手靠近摄像头、星图放大。
 */
export interface SingleHandTransform {
  deltaX: number;
  deltaY: number;
  rotationDegrees: number;
  scale: number;
  anchorX: number;
  anchorY: number;
}

export interface GestureFrame {
  gesture: HandGesture;
  transform: SingleHandTransform;
  selectX: number;
  selectY: number;
  confidence: number;
  timestampMs: number;
}

export interface CatalogCoverage {
  exactBrightStars: number;
  constellationIndexCount: number;
  exactConstellationAnchors: number;
  messierIndexCount: number;
  exactMessierTargets: number;
  dynamicSolarSystemCount: number;
  strategy: string;
}

export interface HttpServiceResult {
  statusCode: number;
  body: string;
  succeeded: boolean;
}

export interface GatewayHealth {
  online: boolean;
  serviceVersion: string;
  cameraConnected: boolean;
  astrometryAvailable: boolean;
  ffmpegAvailable: boolean;
  checkedAtMs: number;
}

export interface GatewayEndpointConfig {
  baseUrl: string;
  requestTimeoutMs: number;
  readTimeoutMs: number;
}

export interface AiEndpointConfig {
  baseUrl: string;
  accessToken: string;
  requestTimeoutMs: number;
}

/** 天气数据的可信来源状态。缓存数据必须与实时预报明确区分。 */
export enum WeatherDataStatus {
  NOT_REQUESTED = 'not_requested',
  LOADING = 'loading',
  LIVE = 'live',
  CACHED = 'cached',
  UNAVAILABLE = 'unavailable'
}

/**
 * 单小时天气样本。所有百分比均为 0-100；缺失字段保留 undefined，不能用 0 冒充实测值。
 */
export interface WeatherHourlySample {
  timestampMs: number;
  temperatureCelsius?: number;
  dewPointCelsius?: number;
  weatherCode?: number;
  pressureMslHpa?: number;
  cloudCoverPercent?: number;
  cloudCoverLowPercent?: number;
  cloudCoverMidPercent?: number;
  cloudCoverHighPercent?: number;
  precipitationProbabilityPercent?: number;
  precipitationMillimeters?: number;
  humidityPercent?: number;
  visibilityMeters?: number;
  windSpeedKph?: number;
  windGustKph?: number;
}

/** Open-Meteo 预报在应用内部的统一形式。天文规划算法只依赖此模型，不依赖具体网络客户端。 */
export interface WeatherForecast {
  status: WeatherDataStatus;
  sourceName: string;
  sourceUrl: string;
  fetchedAtMs: number;
  latitudeDegrees: number;
  longitudeDegrees: number;
  timezone: string;
  utcOffsetSeconds: number;
  forecastDays: number;
  hourly: WeatherHourlySample[];
  errorMessage: string;
}

/** 规划算法的可调边界。首版默认适合城市环境与 18mm 广角摄影。 */
export interface ObservationPlanningConstraints {
  horizonHours: number;
  sampleMinutes: number;
  minAltitudeDegrees: number;
  maxSunAltitudeDegrees: number;
}

export enum ObservationNightSelection {
  TONIGHT = 'tonight',
  TOMORROW = 'tomorrow'
}

/**
 * 以设备时区中午为边界的一段观测夜。中午到次日中午可以完整覆盖傍晚、午夜和清晨，
 * 避免“今晚”随打开页面的分钟数滚动，造成同一晚前后两次规划结果不一致。
 */
export interface ObservationNightPeriod {
  startAtMs: number;
  endAtMs: number;
  timezoneOffsetMinutes: number;
  selection: ObservationNightSelection;
}

export enum PlanningPageState {
  NEEDS_LOCATION = 'needs_location',
  ASTRONOMY_ONLY = 'astronomy_only',
  WEATHER_LOADING = 'weather_loading',
  READY = 'ready',
  WEATHER_UNAVAILABLE = 'weather_unavailable'
}

/** 规划目标列表只保存业务结果，颜色和排版由 ArkUI 组件决定。 */
export interface PlanningTargetSummary {
  targetId: string;
  targetName: string;
  designation: string;
  included: boolean;
  bestWindowStartAtMs?: number;
  bestWindowEndAtMs?: number;
  astronomyScore?: number;
  overallScore?: number;
  recommendation: OutingRecommendation;
  unavailableReason: string;
}

/**
 * 规划抽屉的一次原子计算快照。观测夜、地点和结果必须来自同一次计算，
 * 避免 ArkUI 状态提交期间出现“新日期标题 + 旧日期结果”的混合画面。
 */
export interface PlanningSnapshot {
  generation: number;
  dayOffset: number;
  period: ObservationNightPeriod;
  targetId: string;
  observerLatitudeDegrees: number;
  observerLongitudeDegrees: number;
  locationSource: string;
  locationProvisional: boolean;
  result: ObservationPlanningResult;
}

/** 某一时刻的目标、太阳、月球和天气联合状态。 */
export interface ObservationSample {
  timestampMs: number;
  altitudeDegrees: number;
  azimuthDegrees: number;
  sunAltitudeDegrees: number;
  moonAltitudeDegrees: number;
  moonIlluminationPercent: number;
  moonSeparationDegrees: number;
  astronomyScore: number;
  weatherScore?: number;
  overallScore?: number;
}

export enum VisibilityStatus {
  NORMAL = 'normal',
  ALWAYS_ABOVE_HORIZON = 'always_above_horizon',
  NEVER_RISE = 'never_rise',
  COORDINATE_UNAVAILABLE = 'coordinate_unavailable',
  NO_DARK_WINDOW = 'no_dark_window'
}

/** 未来规划范围内的首次升起、最高点和首次落下。undefined 表示范围内没有对应事件。 */
export interface RiseTransitSet {
  status: VisibilityStatus;
  riseAtMs?: number;
  transitAtMs?: number;
  setAtMs?: number;
  maxAltitudeDegrees: number;
}

/** 连续满足目标高度和暮光边界的可用观测窗口。 */
export interface ObservationWindow {
  startAtMs: number;
  endAtMs: number;
  peakAtMs: number;
  peakAltitudeDegrees: number;
  minMoonSeparationDegrees: number;
  astronomyScore: number;
  weatherScore?: number;
  overallScore?: number;
}

/** 推荐拍摄时段内的天气统计，所有字段与推荐时段使用完全相同的采样范围。 */
export interface PlanningWeatherSummary {
  startAtMs: number;
  endAtMs: number;
  sampleCount: number;
  averageCloudCoverPercent?: number;
  maximumCloudCoverPercent?: number;
  maximumPrecipitationProbabilityPercent?: number;
  totalPrecipitationMillimeters?: number;
  averageWindSpeedKph?: number;
  maximumWindSpeedKph?: number;
  maximumWindGustKph?: number;
}

/**
 * 在天文可观测窗口内选出的连续拍摄建议。图像拍摄只消费这个短窗口，
 * 原始 ObservationWindow 继续表达整段目标高度与暮光条件。
 */
export interface RecommendedCaptureWindow {
  startAtMs: number;
  endAtMs: number;
  peakAtMs: number;
  durationMinutes: number;
  peakAltitudeDegrees: number;
  astronomyScore: number;
  weatherScore?: number;
  overallScore?: number;
  astronomyOnly: boolean;
  weatherSummary?: PlanningWeatherSummary;
}

export enum OutingRecommendation {
  GOOD = 'good',
  CAUTION = 'caution',
  POOR = 'poor',
  ASTRONOMY_ONLY = 'astronomy_only',
  UNAVAILABLE = 'unavailable'
}

/**
 * 单个天体的完整软件规划结果。硬件执行层可以消费该结果，但不得反向限制它的生成。
 */
export interface ObservationPlanningResult {
  targetId: string;
  targetName: string;
  generatedAtMs: number;
  startAtMs: number;
  endAtMs: number;
  constraints: ObservationPlanningConstraints;
  riseTransitSet: RiseTransitSet;
  moonIlluminationPercent: number;
  moonPhaseName: string;
  moonSeparationDegrees?: number;
  samples: ObservationSample[];
  windows: ObservationWindow[];
  /** 兼容旧页面的天文可观测窗口；新页面不得再把它称为天气意义上的最佳窗口。 */
  bestWindow?: ObservationWindow;
  recommendedCaptureWindow?: RecommendedCaptureWindow;
  planningWeatherSummary?: PlanningWeatherSummary;
  recommendedCaptureUnavailableReason: string;
  astronomyScore?: number;
  weatherScore?: number;
  overallScore?: number;
  recommendation: OutingRecommendation;
  summary: string;
  warnings: string[];
  weatherStatus: WeatherDataStatus;
}

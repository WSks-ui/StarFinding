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

export interface EquatorialCoordinate {
  /** J2000 或指定历元的赤经，单位为小时，范围 [0, 24)。 */
  raHours: number;
  /** 赤纬，单位为度，范围 [-90, 90]。 */
  decDegrees: number;
  epoch: number;
}

export interface HorizontalCoordinate {
  /** 高度角，单位为度。 */
  altitudeDegrees: number;
  /** 方位角，正北为 0 度、向东递增。 */
  azimuthDegrees: number;
  aboveHorizon: boolean;
}

export interface CelestialObject {
  id: string;
  type: CelestialType;
  nameZh: string;
  nameEn: string;
  designation: string;
  constellation: string;
  coordinate?: EquatorialCoordinate;
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
  DRAG = 'drag',
  ROTATE_SCALE = 'rotate_scale',
  PINCH_SELECT = 'pinch_select',
  FIST_RESET = 'fist_reset'
}

export interface HandPoint {
  x: number;
  y: number;
  confidence: number;
}

export interface HandLandmarks {
  trackingId: number;
  points: HandPoint[];
  confidence: number;
  timestampMs: number;
}

export interface GestureFrame {
  gesture: HandGesture;
  deltaX: number;
  deltaY: number;
  rotationDegrees: number;
  scale: number;
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

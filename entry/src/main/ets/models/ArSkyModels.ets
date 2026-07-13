/**
 * AR 天穹渲染使用的纯数据模型。
 *
 * 四元数约定：orientation 将相机局部坐标转换到 ENU 世界坐标。相机局部坐标的
 * +X 为屏幕右侧、+Y 为屏幕下方、+Z 为镜头前方；ENU 的 +X/+Y/+Z 分别为东、北、天。
 * 该约定可以直接描述屏幕方向，接入 AR Engine 时只需在 Provider 层完成一次坐标系转换。
 */

export interface Quaternion {
  x: number;
  y: number;
  z: number;
  w: number;
}

export enum ArTrackingQuality {
  UNAVAILABLE = 'unavailable',
  INITIALIZING = 'initializing',
  LIMITED = 'limited',
  NORMAL = 'normal',
  HIGH = 'high'
}

export enum ArTrackingSource {
  HUAWEI_AR_ENGINE = 'huawei_ar_engine',
  SENSOR_FUSION = 'sensor_fusion',
  SIMULATION = 'simulation'
}

export interface ArPoseSample {
  orientation: Quaternion;
  /** 单调时钟纳秒时间戳；只用于同一设备会话内的插值和延迟估算。 */
  timestampNs: number;
  quality: ArTrackingQuality;
  source: ArTrackingSource;
}

export interface SkyDomeViewport {
  widthPixels: number;
  heightPixels: number;
}

export interface SkyDomeStarInput {
  id: string;
  label: string;
  /** 正北为 0 度，向东递增。 */
  azimuthDegrees: number;
  /** 地平线为 0 度，天顶为 90 度。 */
  altitudeDegrees: number;
  magnitude: number;
  /** ArkUI 可识别的颜色字符串；未提供时由渲染服务使用冷白色。 */
  color?: string;
  selected?: boolean;
}

export interface SkyDomeMarker {
  id: string;
  label: string;
  azimuthDegrees: number;
  altitudeDegrees: number;
  magnitude: number;
  color: string;
  selected: boolean;
  xPixels: number;
  yPixels: number;
  sizePixels: number;
  opacity: number;
  /** 与镜头中心方向的球面角距离。 */
  angularDistanceDegrees: number;
  /** 归一化天穹半径，0 为画面中心，1 为配置的天穹视场边缘。 */
  domeRadius: number;
  aboveHorizon: boolean;
  inViewport: boolean;
}

export interface SkyDomePoint {
  xPixels: number;
  yPixels: number;
}

export interface SkyDomePolyline {
  id: string;
  /** 0、30 或 60；渲染层可据此区分地平线与高度圈样式。 */
  altitudeDegrees: number;
  points: SkyDomePoint[];
  opacity: number;
  lineWidthPixels: number;
}

export interface SkyDomeFrame {
  timestampNs: number;
  trackingQuality: ArTrackingQuality;
  trackingSource: ArTrackingSource;
  viewport: SkyDomeViewport;
  markers: SkyDomeMarker[];
  guideLines: SkyDomePolyline[];
  /** 银河中心面在当前相机姿态下的可见分段，用于绘制真正随天穹转动的宽弧带。 */
  milkyWayLines?: SkyDomePolyline[];
}

export interface SkyDomeRenderOptions {
  /** 整个鱼眼天穹覆盖的角直径，建议 140 到 178 度。 */
  domeFieldOfViewDegrees: number;
  /** 0 为等距鱼眼，1 为立体投影；中间值兼顾穹顶感和中心区域可读性。 */
  perspectiveStrength: number;
  /** 0 到 1，数值越大，靠近画面边缘的角距离压缩越明显。 */
  edgeCompression: number;
  /** 低于此高度的星体不进入当前渲染帧。 */
  minimumAltitudeDegrees: number;
  markerMinimumSizePixels: number;
  markerMaximumSizePixels: number;
  showHorizon: boolean;
  showAltitudeGuides: boolean;
  /** 高度圈的方位角采样间隔；值越小越平滑，但折线点也越多。 */
  guideSampleStepDegrees: number;
}

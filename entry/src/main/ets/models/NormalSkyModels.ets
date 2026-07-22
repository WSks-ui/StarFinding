import { CelestialType, EquatorialCoordinate, SolarSystemAppearance } from './DomainModels';

/** 普通星图的方向约定。地平视图不跟随设备姿态，只跟随观测位置和时间。 */
export enum SkyMapOrientation {
  EQUATORIAL_NORTH_UP = 'equatorial_north_up',
  HORIZON_ZENITH = 'horizon_zenith'
}

export enum NormalSkyTimeMode {
  REALTIME = 'realtime',
  SIMULATED = 'simulated'
}

export enum NormalSkyPlaybackSpeed {
  HOUR_PER_SECOND = 3600,
  DAY_PER_SECOND = 86400,
  WEEK_PER_SECOND = 604800
}

export interface NormalSkyTimeState {
  mode: NormalSkyTimeMode;
  timestampMs: number;
  playing: boolean;
  speed: NormalSkyPlaybackSpeed;
}

/** 四元数视图状态生成的只读投影快照，供 Canvas、方向辅助和控件显示使用。 */
export interface NormalSkyViewport {
  centerRaHours: number;
  centerDecDegrees: number;
  fieldOfViewDegrees: number;
  rotationDegrees: number;
  orientation: SkyMapOrientation;
}

export interface NormalSkyQuaternion {
  x: number;
  y: number;
  z: number;
  w: number;
}

/**
 * 普通星图唯一长期姿态。四元数把局部“前、东、北”正交基旋转到 ICRS 天球，
 * 因而跨越天极时不会反复把朝向压缩成赤经、赤纬后再恢复。
 */
export interface NormalSkyViewState {
  viewQuaternion: NormalSkyQuaternion;
  fieldOfViewDegrees: number;
  orientation: SkyMapOrientation;
}

export interface SkyMapSize {
  widthPixels: number;
  heightPixels: number;
}

export interface SkyScreenPoint {
  xPixels: number;
  yPixels: number;
}

export interface SkyScreenRect {
  xPixels: number;
  yPixels: number;
  widthPixels: number;
  heightPixels: number;
  opacity: number;
}

export interface SkyGuideInsets {
  leftPixels: number;
  rightPixels: number;
  topPixels: number;
  bottomPixels: number;
}

export interface NormalSkyProjection {
  xPixels: number;
  yPixels: number;
  inViewport: boolean;
  angularDistanceDegrees: number;
}

export interface SkyLayerVisibility {
  /** 仅作为坐标辅助的银河平面细线，不承载真实星云、尘埃或恒星纹理。 */
  galacticPlane: boolean;
  constellationLines: boolean;
  equatorialGrid: boolean;
  ecliptic: boolean;
  horizon: boolean;
  deepSky: boolean;
  solarSystem: boolean;
  directionGuides: boolean;
}

export enum SkyDirectionKind {
  NORTH_CELESTIAL_POLE = 'north_celestial_pole',
  SOUTH_CELESTIAL_POLE = 'south_celestial_pole',
  NORTH = 'north',
  EAST = 'east',
  SOUTH = 'south',
  WEST = 'west',
  ZENITH = 'zenith'
}

export interface SkyDirectionMarker {
  kind: SkyDirectionKind;
  xPixels: number;
  yPixels: number;
  angleDegrees: number;
  inViewport: boolean;
  atEdge: boolean;
}

/** 普通星图当前中心和方向的只读快照，供 Canvas 标记与 ArkUI 状态胶囊共同消费。 */
export interface SkyOrientationSnapshot {
  orientation: SkyMapOrientation;
  centerRaHours: number;
  centerDecDegrees: number;
  centerAzimuthDegrees?: number;
  centerAltitudeDegrees?: number;
  northScreenAngleDegrees: number;
  eastScreenAngleDegrees: number;
  markers: SkyDirectionMarker[];
}

export enum SkyPolylineKind {
  CONSTELLATION = 'constellation',
  GRID = 'grid',
  ECLIPTIC = 'ecliptic',
  GALACTIC = 'galactic',
  HORIZON = 'horizon',
  TRAJECTORY = 'trajectory'
}

/** 天体在普通星图中的语义图符。图符用于辨识，不代表目标的真实角直径。 */
export enum SkyObjectGlyphKind {
  STAR = 'star',
  CONSTELLATION = 'constellation',
  SUN = 'sun',
  MOON = 'moon',
  MERCURY = 'mercury',
  VENUS = 'venus',
  MARS = 'mars',
  JUPITER = 'jupiter',
  SATURN = 'saturn',
  URANUS = 'uranus',
  NEPTUNE = 'neptune',
  SOLAR_SYSTEM_GENERIC = 'solar_system_generic',
  GALAXY = 'galaxy',
  NEBULA = 'nebula',
  DARK_NEBULA = 'dark_nebula',
  OPEN_CLUSTER = 'open_cluster',
  GLOBULAR_CLUSTER = 'globular_cluster',
  PLANETARY_NEBULA = 'planetary_nebula',
  SUPERNOVA_REMNANT = 'supernova_remnant',
  DEEP_SKY_GENERIC = 'deep_sky_generic'
}

export interface SkyPolyline {
  id: string;
  kind: SkyPolylineKind;
  points: SkyScreenPoint[];
}

/** Canvas 绘制和触控/手势命中共用的对象，避免两套坐标产生选择偏差。 */
export interface ProjectedSkyObject {
  id: string;
  type: CelestialType;
  glyphKind: SkyObjectGlyphKind;
  coordinate: EquatorialCoordinate;
  xPixels: number;
  yPixels: number;
  sizePixels: number;
  hitRadiusPixels: number;
  hitPriority: number;
  magnitude?: number;
  /** 动态太阳系目标在当前场景时刻的真实外观；图符仍为非角直径比例的语义绘制。 */
  appearance?: SolarSystemAppearance;
  /** 亮边相对屏幕正上方的顺时针角度，已经包含宽视场投影和视口旋转。 */
  brightLimbScreenAngleDegrees?: number;
  label: string;
  designation: string;
  color: string;
  aboveHorizon?: boolean;
  selected: boolean;
}

export interface NormalSkyScene {
  /** 固定目录层与动态天空层分开保存，Canvas 可独立决定是否重绘。 */
  /** 生成该场景时的精确视口；交互期间 Canvas 使用它计算轻量变换。 */
  viewportSnapshot: NormalSkyViewport;
  staticObjects: ProjectedSkyObject[];
  dynamicObjects: ProjectedSkyObject[];
  /** 命中测试使用的合并视图；顺序固定为目录层在前、动态层在后。 */
  objects: ProjectedSkyObject[];
  constellationLines: SkyPolyline[];
  gridLines: SkyPolyline[];
  eclipticLines: SkyPolyline[];
  galacticPlaneLines: SkyPolyline[];
  horizonLines: SkyPolyline[];
  trajectoryLines: SkyPolyline[];
  horizonMask: SkyScreenRect[];
  orientationSnapshot: SkyOrientationSnapshot;
  staticRevision: number;
  dynamicRevision: number;
  generatedAtMs: number;
}

/**
 * 交互期间直接作用于两个 Canvas 图层的轻量变换。
 *
 * 它不是天球的长期姿态，只是“上一份精确场景 → 当前四元数姿态”的显示近似。
 * 手势结束后会重新构建 NormalSkyScene 并恢复 identity，避免累积投影误差。
 */
export interface InteractiveSkyTransform {
  revision: number;
  active: boolean;
  translateXPixels: number;
  translateYPixels: number;
  scale: number;
  rotationDegrees: number;
  originXPixels: number;
  originYPixels: number;
}

export const DEFAULT_SKY_LAYERS: SkyLayerVisibility = {
  galacticPlane: false,
  constellationLines: true,
  equatorialGrid: false,
  ecliptic: false,
  horizon: true,
  deepSky: true,
  solarSystem: true,
  directionGuides: true
};

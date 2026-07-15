import { CelestialType, EquatorialCoordinate } from './DomainModels';

/** 普通星图的方向约定。地平视图不跟随设备姿态，只跟随观测位置和时间。 */
export enum SkyMapOrientation {
  EQUATORIAL_NORTH_UP = 'equatorial_north_up',
  HORIZON_ZENITH = 'horizon_zenith'
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
  HORIZON = 'horizon'
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
  label: string;
  designation: string;
  color: string;
  aboveHorizon?: boolean;
  selected: boolean;
}

export interface NormalSkyScene {
  objects: ProjectedSkyObject[];
  constellationLines: SkyPolyline[];
  gridLines: SkyPolyline[];
  eclipticLines: SkyPolyline[];
  horizonLines: SkyPolyline[];
  horizonMask: SkyScreenRect[];
  orientationSnapshot: SkyOrientationSnapshot;
  generatedAtMs: number;
}

export const DEFAULT_SKY_LAYERS: SkyLayerVisibility = {
  constellationLines: true,
  equatorialGrid: false,
  ecliptic: false,
  horizon: true,
  deepSky: true,
  solarSystem: true,
  directionGuides: true
};

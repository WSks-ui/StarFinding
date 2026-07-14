import { CelestialType, EquatorialCoordinate } from './DomainModels';

/** 普通星图的方向约定。地平视图不跟随设备姿态，只跟随观测位置和时间。 */
export enum SkyMapOrientation {
  EQUATORIAL_NORTH_UP = 'equatorial_north_up',
  HORIZON_ZENITH = 'horizon_zenith'
}

/**
 * 普通星图唯一持久化的视口状态。拖拽、缩放和旋转必须更新此状态，不能长期保存像素偏移。
 */
export interface NormalSkyViewport {
  centerRaHours: number;
  centerDecDegrees: number;
  fieldOfViewDegrees: number;
  rotationDegrees: number;
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
  generatedAtMs: number;
}

export const DEFAULT_SKY_LAYERS: SkyLayerVisibility = {
  constellationLines: true,
  equatorialGrid: false,
  ecliptic: false,
  horizon: true,
  deepSky: true,
  solarSystem: true
};

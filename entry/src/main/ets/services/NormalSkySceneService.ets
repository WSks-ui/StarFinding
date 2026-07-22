import { CelestialCatalog } from '../data/CelestialCatalog';
import {
  ApparentTrajectory,
  ApparentTrajectoryPoint,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  EquatorialCoordinate,
  EquatorialFrame,
  ObserverState,
  RefractionMode,
  SolarSystemAppearance
} from '../models/DomainModels';
import {
  NormalSkyScene,
  NormalSkyViewport,
  ProjectedSkyObject,
  SkyLayerVisibility,
  SkyGuideInsets,
  SkyMapSize,
  SkyObjectGlyphKind,
  SkyPolyline,
  SkyPolylineKind,
  SkyScreenPoint,
  SkyScreenRect
} from '../models/NormalSkyModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';
import { ConstellationLineGroup, NormalSkyCatalogService } from './NormalSkyCatalogService';
import {
  NormalSkyPreparedProjection,
  NormalSkyProjectionService,
  NormalSkyScreenProjection
} from './NormalSkyProjectionService';
import { NormalSkyOrientationService } from './NormalSkyOrientationService';
import {
  SphericalVisibleStar,
  VisibleStar,
  VisibleStarCatalogService
} from './VisibleStarCatalogService';

export interface NormalSkySceneQuery {
  viewport: NormalSkyViewport;
  size: SkyMapSize;
  layers: SkyLayerVisibility;
  selectedTargetId: string;
  timestampMs: number;
  observer?: ObserverState;
  guideInsets?: SkyGuideInsets;
  showDirectionMarkers?: boolean;
  /** 连续拖动、缩放、惯性和飞行动画期间仅降低标签与地平遮罩细节，恒星集合保持不变。 */
  interactive?: boolean;
}

interface NormalSkyStaticCache {
  key: string;
  revision: number;
  objects: ProjectedSkyObject[];
  galacticPlaneLines: SkyPolyline[];
  constellationLines: SkyPolyline[];
  gridLines: SkyPolyline[];
  eclipticLines: SkyPolyline[];
}

interface NormalSkyTrajectoryCache {
  key: string;
  lines: SkyPolyline[];
}

interface NormalSkyTrajectorySourceCache {
  key: string;
  coordinates: EquatorialCoordinate[];
}

interface NormalSkyDynamicCatalogEntry {
  object: CelestialObject;
  coordinate: EquatorialCoordinate;
  appearance?: SolarSystemAppearance;
}

interface NormalSkyDynamicCatalogCache {
  key: string;
  entries: NormalSkyDynamicCatalogEntry[];
}

interface NormalSkyDirectionVector {
  x: number;
  y: number;
  z: number;
}

export interface NormalSkySceneCacheStats {
  staticBuildCount: number;
  staticCacheHitCount: number;
  dynamicBuildCount: number;
  dynamicCatalogCacheHitCount: number;
  trajectoryBuildCount: number;
  trajectoryCacheHitCount: number;
}

/** 把多个离线目录合成为 Canvas 一次可绘制的场景。 */
export class NormalSkySceneService {
  private static readonly CURATED_DUPLICATE_MINIMUM_DOT: number = 0.9999998629221643;
  private readonly visibleStars: VisibleStarCatalogService;
  private readonly lineCatalog: NormalSkyCatalogService;
  private staticCache: NormalSkyStaticCache | undefined = undefined;
  private trajectoryCache: NormalSkyTrajectoryCache | undefined = undefined;
  private trajectorySourceCache: NormalSkyTrajectorySourceCache | undefined = undefined;
  private dynamicCatalogCache: NormalSkyDynamicCatalogCache | undefined = undefined;
  private staticRevision: number = 0;
  private dynamicRevision: number = 0;
  private staticBuildCount: number = 0;
  private staticCacheHitCount: number = 0;
  private dynamicBuildCount: number = 0;
  private dynamicCatalogCacheHitCount: number = 0;
  private trajectoryBuildCount: number = 0;
  private trajectoryCacheHitCount: number = 0;
  private curatedBrightStarDirections: NormalSkyDirectionVector[] = [];
  private curatedBrightStarDirectionSourceCount: number = -1;

  constructor(visibleStars: VisibleStarCatalogService, lineCatalog: NormalSkyCatalogService) {
    this.visibleStars = visibleStars;
    this.lineCatalog = lineCatalog;
  }

  build(query: NormalSkySceneQuery): NormalSkyScene {
    const prepared: NormalSkyPreparedProjection =
      NormalSkyProjectionService.prepare(query.viewport, query.size);
    const staticLayer: NormalSkyStaticCache = this.resolveStaticLayer(query, prepared);
    const dynamicObjects: ProjectedSkyObject[] = [];
    if (query.layers.solarSystem) {
      this.appendCatalogObjects(
        dynamicObjects, CelestialCatalog.solarSystem(), query, true, prepared);
    }
    const horizonMask: SkyScreenRect[] = query.layers.horizon && query.observer !== undefined ?
      this.buildHorizonMask(query, prepared) : [];
    const objects: ProjectedSkyObject[] = staticLayer.objects.concat(dynamicObjects);
    this.dynamicRevision++;
    this.dynamicBuildCount++;
    return {
      viewportSnapshot: query.viewport,
      staticObjects: staticLayer.objects,
      dynamicObjects: dynamicObjects,
      objects: objects,
      galacticPlaneLines: staticLayer.galacticPlaneLines,
      constellationLines: staticLayer.constellationLines,
      gridLines: staticLayer.gridLines,
      eclipticLines: staticLayer.eclipticLines,
      horizonLines: query.layers.horizon && query.observer !== undefined ?
        this.buildHorizon(query, prepared) : [],
      trajectoryLines: query.layers.solarSystem ?
        this.buildSelectedTrajectoryCached(query, prepared) : [],
      horizonMask: horizonMask,
      orientationSnapshot: NormalSkyOrientationService.build({
        viewport: query.viewport,
        size: query.size,
        directionGuides: query.layers.directionGuides && query.showDirectionMarkers !== false,
        observer: query.observer,
        guideInsets: query.guideInsets
      }),
      staticRevision: staticLayer.revision,
      dynamicRevision: this.dynamicRevision,
      generatedAtMs: query.timestampMs
    };
  }

  getCacheStats(): NormalSkySceneCacheStats {
    return {
      staticBuildCount: this.staticBuildCount,
      staticCacheHitCount: this.staticCacheHitCount,
      dynamicBuildCount: this.dynamicBuildCount,
      dynamicCatalogCacheHitCount: this.dynamicCatalogCacheHitCount,
      trajectoryBuildCount: this.trajectoryBuildCount,
      trajectoryCacheHitCount: this.trajectoryCacheHitCount
    };
  }

  /** 日期选择会改变恒星自行参考时刻；连续播放期间固定层仍保持缓存。 */
  invalidateForTimeSelection(): void {
    this.staticCache = undefined;
    this.trajectoryCache = undefined;
    this.trajectorySourceCache = undefined;
    this.dynamicCatalogCache = undefined;
  }

  private resolveStaticLayer(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): NormalSkyStaticCache {
    const key: string = this.staticCacheKey(query);
    if (this.staticCache !== undefined && this.staticCache.key === key) {
      this.staticCacheHitCount++;
      return this.staticCache;
    }
    const objects: ProjectedSkyObject[] = [];
    const brightStars: CelestialObject[] = CelestialCatalog.brightStars();
    this.prepareCuratedBrightStarDirections(brightStars);
    this.appendCatalogObjects(objects, brightStars, query, false, prepared);
    this.appendVisibleStars(objects, query, false, prepared);
    if (query.layers.constellationLines) {
      this.appendCatalogObjects(
        objects, CelestialCatalog.constellations(), query, false, prepared);
    }
    if (query.layers.deepSky) {
      this.appendCatalogObjects(
        objects, CelestialCatalog.messierObjects(), query, false, prepared);
    }
    this.staticRevision++;
    this.staticBuildCount++;
    const cache: NormalSkyStaticCache = {
      key: key,
      revision: this.staticRevision,
      objects: objects,
      galacticPlaneLines: query.layers.galacticPlane ?
        this.buildGalacticPlaneLines(query, prepared) : [],
      constellationLines: query.layers.constellationLines ?
        this.buildConstellationLines(query, prepared) : [],
      gridLines: query.layers.equatorialGrid ? this.buildEquatorialGrid(query, prepared) : [],
      eclipticLines: query.layers.ecliptic ? this.buildEcliptic(query, prepared) : []
    };
    this.staticCache = cache;
    return cache;
  }

  private appendVisibleStars(result: ProjectedSkyObject[],
    query: NormalSkySceneQuery, includeHorizon: boolean,
    prepared: NormalSkyPreparedProjection): void {
    if (!this.visibleStars.isLoaded()) {
      return;
    }
    const radius: number = this.queryRadius(query.viewport, query.size);
    const candidates: SphericalVisibleStar[] =
      this.visibleStars.filterSphericalViewportCoordinates({
      center: {
        raHours: query.viewport.centerRaHours,
        decDegrees: query.viewport.centerDecDegrees,
        frame: EquatorialFrame.ICRS_J2000
      },
      radiusDegrees: radius,
      maxMagnitude: this.maximumMagnitude(query.viewport.fieldOfViewDegrees),
      maxResults: this.maximumStarCount(query.viewport.fieldOfViewDegrees),
      timestampMs: query.timestampMs
    });
    for (let index: number = 0; index < candidates.length; index++) {
      const candidate: SphericalVisibleStar = candidates[index];
      const star: VisibleStar = candidate.star;
      const coordinate: EquatorialCoordinate = candidate.coordinate;
      if (this.duplicatesCuratedStar(candidate)) {
        continue;
      }
      const projection: NormalSkyScreenProjection =
        NormalSkyProjectionService.projectDirectionScreenPrepared(
          candidate.directionX, candidate.directionY, candidate.directionZ, prepared);
      if (!projection.inViewport) {
        continue;
      }
      const id: string = `hyg-${star.id.toLowerCase()}`;
      const selected: boolean = id === query.selectedTargetId;
      const labelMagnitude: number = query.interactive === true ?
        (query.viewport.fieldOfViewDegrees <= 35.0 ? 2.8 : 1.2) :
        (query.viewport.fieldOfViewDegrees <= 35.0 ? 4.5 : 2.2);
      result.push({
        id: id,
        type: CelestialType.STAR,
        glyphKind: SkyObjectGlyphKind.STAR,
        coordinate: coordinate,
        xPixels: projection.xPixels,
        yPixels: projection.yPixels,
        sizePixels: selected ? 8.0 : Math.max(1.4, 6.2 - star.magnitude * 0.72),
        hitRadiusPixels: 18.0,
        hitPriority: selected ? 100 : 10,
        magnitude: star.magnitude,
        label: star.name.length > 0 && star.magnitude <= labelMagnitude ? star.name : '',
        designation: star.id,
        color: this.starColor(star.spectralType),
        aboveHorizon: includeHorizon ? this.aboveHorizon(coordinate, query.observer) : undefined,
        selected: selected
      });
    }
  }

  private appendCatalogObjects(result: ProjectedSkyObject[], objects: CelestialObject[],
    query: NormalSkySceneQuery, includeHorizon: boolean,
    prepared: NormalSkyPreparedProjection): void {
    if (includeHorizon) {
      const entries: NormalSkyDynamicCatalogEntry[] =
        this.resolveDynamicCatalogEntries(objects, query.timestampMs);
      for (let index: number = 0; index < entries.length; index++) {
        this.appendDynamicCatalogEntry(result, entries[index], query, prepared);
      }
      return;
    }
    for (let index: number = 0; index < objects.length; index++) {
      const object: CelestialObject = objects[index];
      const coordinate: EquatorialCoordinate | undefined = EphemerisService.skyCoordinate(
        object, query.timestampMs);
      if (coordinate === undefined || !this.shouldDisplay(object, query)) {
        continue;
      }
      const projection: NormalSkyScreenProjection =
        NormalSkyProjectionService.projectScreenPrepared(coordinate, prepared);
      if (!projection.inViewport) {
        continue;
      }
      const selected: boolean = object.id === query.selectedTargetId;
      const appearance: SolarSystemAppearance | undefined = EphemerisService.appearance(
        object, query.timestampMs);
      result.push({
        id: object.id,
        type: object.type,
        glyphKind: NormalSkySceneService.glyphKindFor(object),
        coordinate: coordinate,
        xPixels: projection.xPixels,
        yPixels: projection.yPixels,
        sizePixels: this.objectSize(object, selected, query.viewport.fieldOfViewDegrees),
        hitRadiusPixels: object.type === CelestialType.CONSTELLATION ? 24.0 : 20.0,
        hitPriority: selected ? 100 : this.hitPriority(object.type),
        magnitude: appearance === undefined ? object.magnitude : appearance.magnitude,
        appearance: appearance,
        brightLimbScreenAngleDegrees: appearance === undefined ? undefined :
          this.brightLimbScreenAngle(
            coordinate, appearance.brightLimbAngleDegrees, query, prepared),
        label: this.objectLabel(
          object, query.viewport.fieldOfViewDegrees, selected, query.interactive === true),
        designation: object.designation,
        color: this.objectColor(object),
        aboveHorizon: includeHorizon ? this.aboveHorizon(coordinate, query.observer) : undefined,
        selected: selected
      });
    }
  }

  private resolveDynamicCatalogEntries(objects: CelestialObject[],
    timestampMs: number): NormalSkyDynamicCatalogEntry[] {
    const timestampBucket: number = Math.floor(timestampMs / 60000.0);
    const key: string = `${timestampBucket}|${objects.length}`;
    if (this.dynamicCatalogCache !== undefined && this.dynamicCatalogCache.key === key) {
      this.dynamicCatalogCacheHitCount++;
      return this.dynamicCatalogCache.entries;
    }
    const entries: NormalSkyDynamicCatalogEntry[] = [];
    const bucketTimestampMs: number = timestampBucket * 60000.0;
    for (let index: number = 0; index < objects.length; index++) {
      const object: CelestialObject = objects[index];
      const coordinate: EquatorialCoordinate | undefined =
        EphemerisService.skyCoordinate(object, bucketTimestampMs);
      if (coordinate === undefined) continue;
      entries.push({
        object: object,
        coordinate: coordinate,
        appearance: EphemerisService.appearance(object, bucketTimestampMs)
      });
    }
    this.dynamicCatalogCache = { key: key, entries: entries };
    return entries;
  }

  private appendDynamicCatalogEntry(result: ProjectedSkyObject[],
    entry: NormalSkyDynamicCatalogEntry, query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): void {
    const object: CelestialObject = entry.object;
    if (!this.shouldDisplay(object, query)) return;
    const projection: NormalSkyScreenProjection =
      NormalSkyProjectionService.projectScreenPrepared(entry.coordinate, prepared);
    if (!projection.inViewport) return;
    const selected: boolean = object.id === query.selectedTargetId;
    result.push({
      id: object.id,
      type: object.type,
      glyphKind: NormalSkySceneService.glyphKindFor(object),
      coordinate: entry.coordinate,
      xPixels: projection.xPixels,
      yPixels: projection.yPixels,
      sizePixels: this.objectSize(object, selected, query.viewport.fieldOfViewDegrees),
      hitRadiusPixels: 20.0,
      hitPriority: selected ? 100 : this.hitPriority(object.type),
      magnitude: entry.appearance === undefined ? object.magnitude : entry.appearance.magnitude,
      appearance: entry.appearance,
      brightLimbScreenAngleDegrees: entry.appearance === undefined ? undefined :
        this.brightLimbScreenAngle(
          entry.coordinate, entry.appearance.brightLimbAngleDegrees, query, prepared),
      label: this.objectLabel(
        object, query.viewport.fieldOfViewDegrees, selected, query.interactive === true),
      designation: object.designation,
      color: this.objectColor(object),
      aboveHorizon: this.aboveHorizon(entry.coordinate, query.observer),
      selected: selected
    });
  }

  private shouldDisplay(object: CelestialObject, query: NormalSkySceneQuery): boolean {
    if (object.id === query.selectedTargetId) {
      return true;
    }
    if (object.type !== CelestialType.MESSIER) {
      return true;
    }
    const magnitude: number = object.magnitude === undefined ? 99.0 : object.magnitude;
    if (query.viewport.fieldOfViewDegrees >= 90.0) {
      return magnitude <= 5.5 || (object.angularSizeDegrees !== undefined && object.angularSizeDegrees >= 1.0);
    }
    if (query.viewport.fieldOfViewDegrees >= 30.0) {
      return magnitude <= 7.5 || (object.angularSizeDegrees !== undefined && object.angularSizeDegrees >= 0.5);
    }
    return true;
  }

  private buildConstellationLines(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    if (!this.lineCatalog.isLoaded()) {
      return [];
    }
    const result: SkyPolyline[] = [];
    const groups: ConstellationLineGroup[] = this.lineCatalog.getLineGroups();
    const viewportRadiusDegrees: number = this.queryRadius(query.viewport, query.size);
    for (let groupIndex: number = 0; groupIndex < groups.length; groupIndex++) {
      const group: ConstellationLineGroup = groups[groupIndex];
      if (!this.constellationGroupIntersectsViewport(
        group, prepared, viewportRadiusDegrees)) {
        continue;
      }
      for (let lineIndex: number = 0; lineIndex < group.lines.length; lineIndex++) {
        this.appendProjectedLine(result, `${group.designation}-${lineIndex}`,
          SkyPolylineKind.CONSTELLATION, group.lines[lineIndex], query, prepared);
      }
    }
    return result;
  }

  /**
   * 使用离线加载时计算的球面包围帽做整组粗裁剪。
   * 两个球面帽明确不相交时才跳过，180° 标记组始终保留，确保跨 0h、近天极和超大星座不漏线。
   */
  private constellationGroupIntersectsViewport(group: ConstellationLineGroup,
    prepared: NormalSkyPreparedProjection, viewportRadiusDegrees: number): boolean {
    const combinedRadiusDegrees: number =
      viewportRadiusDegrees + group.angularRadiusDegrees;
    if (combinedRadiusDegrees >= 180.0) {
      return true;
    }
    const centerDot: number = prepared.centerX * group.centerDirectionX +
      prepared.centerY * group.centerDirectionY +
      prepared.centerZ * group.centerDirectionZ;
    const minimumDot: number = Math.cos(combinedRadiusDegrees * Math.PI / 180.0);
    return centerDot >= minimumDot;
  }

  private buildEquatorialGrid(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const result: SkyPolyline[] = [];
    const rightAscensionStep: number = query.viewport.fieldOfViewDegrees <= 35.0 ? 1.0 : 2.0;
    for (let ra: number = 0.0; ra < 24.0; ra += rightAscensionStep) {
      const line: EquatorialCoordinate[] = [];
      for (let dec: number = -90.0; dec <= 90.0; dec += 3.0) {
        line.push({ raHours: ra, decDegrees: dec, frame: EquatorialFrame.ICRS_J2000 });
      }
      this.appendProjectedLine(
        result, `ra-${ra}`, SkyPolylineKind.GRID, line, query, prepared);
    }
    for (let dec: number = -75.0; dec <= 75.0; dec += 15.0) {
      const line: EquatorialCoordinate[] = [];
      for (let ra: number = 0.0; ra <= 24.0; ra += 0.25) {
        line.push({ raHours: ra, decDegrees: dec, frame: EquatorialFrame.ICRS_J2000 });
      }
      this.appendProjectedLine(
        result, `dec-${dec}`, SkyPolylineKind.GRID, line, query, prepared);
    }
    return result;
  }

  private buildEcliptic(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const line: EquatorialCoordinate[] = [];
    const obliquity: number = 23.43928 * Math.PI / 180.0;
    for (let longitude: number = 0.0; longitude <= 360.0; longitude += 2.0) {
      const radians: number = longitude * Math.PI / 180.0;
      const x: number = Math.cos(radians);
      const y: number = Math.sin(radians) * Math.cos(obliquity);
      const z: number = Math.sin(radians) * Math.sin(obliquity);
      line.push({
        raHours: AstronomyService.normalizeHours(Math.atan2(y, x) * 12.0 / Math.PI),
        decDegrees: Math.asin(z) * 180.0 / Math.PI,
        frame: EquatorialFrame.ICRS_J2000
      });
    }
    const result: SkyPolyline[] = [];
    this.appendProjectedLine(
      result, 'ecliptic', SkyPolylineKind.ECLIPTIC, line, query, prepared);
    return result;
  }

  /**
   * 使用 IAU J2000 Galactic -> Equatorial 旋转矩阵生成银河平面辅助线。
   *
   * 真实银河纹理由独立摄影底图服务提供；这里故意只保留细线，避免把人为绘制的宽带
   * 误解为星云、尘埃或当前拍摄效果。
   */
  private buildGalacticPlaneLines(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const coordinates: EquatorialCoordinate[] = [];
    // 窄视场下粗采样会让宽笔触显出折线转角，因此固定使用 1° 采样；
    // 361 个投影点相对恒星目录查询开销很小，并且只进入静态场景缓存。
    for (let longitudeDegrees: number = 0.0;
      longitudeDegrees <= 360.0; longitudeDegrees += 1.0) {
      coordinates.push(this.galacticToEquatorial(longitudeDegrees, 0.0));
    }
    const projected: SkyPolyline[] = [];
    this.appendProjectedLine(
      projected, 'galactic-plane', SkyPolylineKind.GALACTIC, coordinates, query, prepared);
    return projected;
  }

  private galacticToEquatorial(longitudeDegrees: number,
    latitudeDegrees: number): EquatorialCoordinate {
    const longitude: number = longitudeDegrees * Math.PI / 180.0;
    const latitude: number = latitudeDegrees * Math.PI / 180.0;
    const latitudeCosine: number = Math.cos(latitude);
    const galacticX: number = latitudeCosine * Math.cos(longitude);
    const galacticY: number = latitudeCosine * Math.sin(longitude);
    const galacticZ: number = Math.sin(latitude);
    // 标准 J2000 Galactic -> Equatorial 旋转矩阵（Equatorial -> Galactic 的转置）。
    const equatorialX: number = -0.0548755604 * galacticX +
      0.4941094279 * galacticY - 0.8676661490 * galacticZ;
    const equatorialY: number = -0.8734370902 * galacticX -
      0.4448296300 * galacticY - 0.1980763734 * galacticZ;
    const equatorialZ: number = -0.4838350155 * galacticX +
      0.7469822445 * galacticY + 0.4559837762 * galacticZ;
    return {
      raHours: AstronomyService.normalizeHours(
        Math.atan2(equatorialY, equatorialX) * 12.0 / Math.PI),
      decDegrees: Math.asin(Math.max(-1.0, Math.min(1.0, equatorialZ))) * 180.0 / Math.PI,
      frame: EquatorialFrame.ICRS_J2000
    };
  }

  private buildHorizon(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const observer: ObserverState | undefined = query.observer;
    if (observer === undefined) {
      return [];
    }
    const line: EquatorialCoordinate[] = [];
    const azimuthStep: number = query.interactive === true ? 8.0 : 4.0;
    for (let azimuth: number = 0.0; azimuth <= 360.0; azimuth += azimuthStep) {
      line.push(EphemerisService.horizontalToEqj(
        azimuth, 0.0, observer, query.timestampMs, RefractionMode.NONE));
    }
    const result: SkyPolyline[] = [];
    this.appendProjectedLine(
      result, 'horizon', SkyPolylineKind.HORIZON, line, query, prepared);
    return result;
  }

  private buildSelectedTrajectoryCached(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const key: string = this.trajectoryCacheKey(query);
    if (this.trajectoryCache !== undefined && this.trajectoryCache.key === key) {
      this.trajectoryCacheHitCount++;
      return this.trajectoryCache.lines;
    }
    const lines: SkyPolyline[] = this.buildSelectedTrajectory(query, prepared);
    this.trajectoryBuildCount++;
    this.trajectoryCache = { key: key, lines: lines };
    return lines;
  }

  private buildSelectedTrajectory(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyPolyline[] {
    const target: CelestialObject | undefined = CelestialCatalog.getById(query.selectedTargetId);
    if (target === undefined || target.precision !== CatalogPrecision.DYNAMIC) return [];
    const coordinates: EquatorialCoordinate[] =
      this.resolveTrajectoryCoordinates(target, query.timestampMs);
    const result: SkyPolyline[] = [];
    this.appendProjectedLine(result, `trajectory-${target.id}`,
      SkyPolylineKind.TRAJECTORY, coordinates, query, prepared);
    return result;
  }

  private resolveTrajectoryCoordinates(target: CelestialObject,
    timestampMs: number): EquatorialCoordinate[] {
    const bucketSize: number = target.id === 'solar-moon' ? 3600000.0 : 86400000.0;
    const timestampBucket: number = Math.floor(timestampMs / bucketSize);
    const key: string = `${target.id}|${timestampBucket}`;
    if (this.trajectorySourceCache !== undefined &&
      this.trajectorySourceCache.key === key) {
      return this.trajectorySourceCache.coordinates;
    }
    const trajectory: ApparentTrajectory | undefined = EphemerisService.trajectory(
      target, timestampBucket * bucketSize);
    if (trajectory === undefined) return [];
    const coordinates: EquatorialCoordinate[] = [];
    for (let index: number = 0; index < trajectory.points.length; index++) {
      const point: ApparentTrajectoryPoint = trajectory.points[index];
      coordinates.push(point.coordinate);
    }
    this.trajectorySourceCache = { key: key, coordinates: coordinates };
    return coordinates;
  }

  private staticCacheKey(query: NormalSkySceneQuery): string {
    const selectedTarget: CelestialObject | undefined = CelestialCatalog.getById(query.selectedTargetId);
    const selectedKey: string = selectedTarget !== undefined &&
      selectedTarget.precision === CatalogPrecision.DYNAMIC ? '' : query.selectedTargetId;
    return `${this.projectionCacheKey(query)}|${selectedKey}|` +
      `${query.layers.galacticPlane ? 1 : 0}${query.layers.constellationLines ? 1 : 0}` +
      `${query.layers.equatorialGrid ? 1 : 0}` +
      `${query.layers.ecliptic ? 1 : 0}${query.layers.deepSky ? 1 : 0}|` +
      `${this.visibleStars.isLoaded() ? 1 : 0}${this.lineCatalog.isLoaded() ? 1 : 0}|` +
      `${query.interactive === true ? 1 : 0}`;
  }

  private trajectoryCacheKey(query: NormalSkySceneQuery): string {
    const target: CelestialObject | undefined = CelestialCatalog.getById(query.selectedTargetId);
    if (target === undefined || target.precision !== CatalogPrecision.DYNAMIC) {
      return `${this.projectionCacheKey(query)}|none`;
    }
    const bucketSize: number = target.id === 'solar-moon' ? 3600000.0 : 86400000.0;
    const timestampBucket: number = Math.floor(query.timestampMs / bucketSize);
    return `${this.projectionCacheKey(query)}|${target.id}|${timestampBucket}`;
  }

  private projectionCacheKey(query: NormalSkySceneQuery): string {
    return `${query.viewport.centerRaHours.toFixed(8)},${query.viewport.centerDecDegrees.toFixed(8)},` +
      `${query.viewport.fieldOfViewDegrees.toFixed(6)},${query.viewport.rotationDegrees.toFixed(6)},` +
      `${query.viewport.orientation}|${query.size.widthPixels.toFixed(2)},${query.size.heightPixels.toFixed(2)}`;
  }

  /** 以屏幕条带近似地平线以下区域；条带随投影重建，不会把不可见区固定在屏幕某一侧。 */
  private buildHorizonMask(query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): SkyScreenRect[] {
    const observer: ObserverState | undefined = query.observer;
    if (observer === undefined) {
      return [];
    }
    const cellSize: number = query.interactive === true ? 96.0 : 48.0;
    const columns: number = Math.ceil(query.size.widthPixels / cellSize);
    const rows: number = Math.ceil(query.size.heightPixels / cellSize);
    const result: SkyScreenRect[] = [];
    for (let row: number = 0; row < rows; row++) {
      let spanStart: number = -1;
      for (let column: number = 0; column <= columns; column++) {
        let belowHorizon: boolean = false;
        if (column < columns) {
          const coordinate: EquatorialCoordinate = NormalSkyProjectionService.unprojectPrepared(
            Math.min(query.size.widthPixels, (column + 0.5) * cellSize),
            Math.min(query.size.heightPixels, (row + 0.5) * cellSize), prepared);
          belowHorizon = EphemerisService.horizontalFromEqjCoordinate(
            coordinate, observer, query.timestampMs, RefractionMode.NONE).altitudeDegrees < 0.0;
        }
        if (belowHorizon && spanStart < 0) {
          spanStart = column;
        } else if (!belowHorizon && spanStart >= 0) {
          result.push({
            xPixels: spanStart * cellSize,
            yPixels: row * cellSize,
            widthPixels: Math.min(query.size.widthPixels, column * cellSize) - spanStart * cellSize,
            heightPixels: Math.min(cellSize, query.size.heightPixels - row * cellSize),
            opacity: 0.26
          });
          spanStart = -1;
        }
      }
    }
    return result;
  }

  private appendProjectedLine(result: SkyPolyline[], baseId: string, kind: SkyPolylineKind,
    coordinates: EquatorialCoordinate[], query: NormalSkySceneQuery,
    prepared: NormalSkyPreparedProjection): void {
    let segment: SkyScreenPoint[] = [];
    let previous: SkyScreenPoint | undefined = undefined;
    let minimumX: number = Number.MAX_VALUE;
    let minimumY: number = Number.MAX_VALUE;
    let maximumX: number = -Number.MAX_VALUE;
    let maximumY: number = -Number.MAX_VALUE;
    const maximumGap: number = Math.max(query.size.widthPixels, query.size.heightPixels) * 1.5;
    let segmentIndex: number = 0;
    for (let index: number = 0; index < coordinates.length; index++) {
      const projection: NormalSkyScreenProjection =
        NormalSkyProjectionService.projectScreenPrepared(coordinates[index], prepared);
      const point: SkyScreenPoint = { xPixels: projection.xPixels, yPixels: projection.yPixels };
      const finite: boolean = Number.isFinite(point.xPixels) && Number.isFinite(point.yPixels) &&
        Math.abs(point.xPixels) < 100000.0 && Math.abs(point.yPixels) < 100000.0;
      const gap: number = previous === undefined ? 0.0 : Math.sqrt(
        (point.xPixels - previous.xPixels) * (point.xPixels - previous.xPixels) +
        (point.yPixels - previous.yPixels) * (point.yPixels - previous.yPixels));
      if (!finite || gap > maximumGap) {
        if (segment.length >= 2 && this.screenBoundsIntersect(
          minimumX, minimumY, maximumX, maximumY, query.size)) {
          result.push({ id: `${baseId}-${segmentIndex}`, kind: kind, points: segment });
          segmentIndex++;
        }
        segment = [];
        previous = undefined;
        minimumX = Number.MAX_VALUE;
        minimumY = Number.MAX_VALUE;
        maximumX = -Number.MAX_VALUE;
        maximumY = -Number.MAX_VALUE;
        continue;
      }
      segment.push(point);
      minimumX = Math.min(minimumX, point.xPixels);
      minimumY = Math.min(minimumY, point.yPixels);
      maximumX = Math.max(maximumX, point.xPixels);
      maximumY = Math.max(maximumY, point.yPixels);
      previous = point;
    }
    if (segment.length >= 2 && this.screenBoundsIntersect(
      minimumX, minimumY, maximumX, maximumY, query.size)) {
      result.push({ id: `${baseId}-${segmentIndex}`, kind: kind, points: segment });
    }
  }

  private screenBoundsIntersect(minimumX: number, minimumY: number,
    maximumX: number, maximumY: number, size: SkyMapSize): boolean {
    const margin: number = 64.0;
    return maximumX >= -margin && minimumX <= size.widthPixels + margin &&
      maximumY >= -margin && minimumY <= size.heightPixels + margin;
  }

  private prepareCuratedBrightStarDirections(brightStars: CelestialObject[]): void {
    if (this.curatedBrightStarDirectionSourceCount === brightStars.length) {
      return;
    }
    const directions: NormalSkyDirectionVector[] = [];
    for (let index: number = 0; index < brightStars.length; index++) {
      const coordinate: EquatorialCoordinate | undefined = brightStars[index].coordinate;
      if (coordinate === undefined) continue;
      const rightAscensionRadians: number = coordinate.raHours * Math.PI / 12.0;
      const declinationRadians: number = coordinate.decDegrees * Math.PI / 180.0;
      const declinationCosine: number = Math.cos(declinationRadians);
      directions.push({
        x: declinationCosine * Math.cos(rightAscensionRadians),
        y: declinationCosine * Math.sin(rightAscensionRadians),
        z: Math.sin(declinationRadians)
      });
    }
    this.curatedBrightStarDirections = directions;
    this.curatedBrightStarDirectionSourceCount = brightStars.length;
  }

  private duplicatesCuratedStar(candidate: SphericalVisibleStar): boolean {
    for (let index: number = 0; index < this.curatedBrightStarDirections.length; index++) {
      const curated: NormalSkyDirectionVector = this.curatedBrightStarDirections[index];
      // 0.03° 阈值与原球面角距判断一致；单位向量点积避免每对恒星重复 sin/cos/acos。
      if (candidate.directionX * curated.x + candidate.directionY * curated.y +
        candidate.directionZ * curated.z >
        NormalSkySceneService.CURATED_DUPLICATE_MINIMUM_DOT) {
        return true;
      }
    }
    return false;
  }

  private queryRadius(viewport: NormalSkyViewport, size: SkyMapSize): number {
    const verticalField: number = Math.min(170.0,
      viewport.fieldOfViewDegrees * Math.max(1.0, size.heightPixels) / Math.max(1.0, size.widthPixels));
    return Math.min(179.0, Math.sqrt(
      viewport.fieldOfViewDegrees * viewport.fieldOfViewDegrees + verticalField * verticalField) / 2.0 + 5.0);
  }

  private maximumMagnitude(fieldOfViewDegrees: number): number {
    if (fieldOfViewDegrees >= 90.0) return 4.7;
    if (fieldOfViewDegrees >= 30.0) return 5.7;
    return 6.5;
  }

  private maximumStarCount(fieldOfViewDegrees: number): number {
    if (fieldOfViewDegrees >= 90.0) return 700;
    if (fieldOfViewDegrees >= 30.0) return 1100;
    return 1600;
  }

  private aboveHorizon(coordinate: EquatorialCoordinate, observer?: ObserverState): boolean | undefined {
    if (observer === undefined) {
      return undefined;
    }
    return EphemerisService.horizontalFromEqjCoordinate(
      coordinate, observer, observer.timestampMs, RefractionMode.NONE).aboveHorizon;
  }

  private objectSize(object: CelestialObject, selected: boolean, fieldOfViewDegrees: number): number {
    const detailScale: number = fieldOfViewDegrees <= 30.0 ? 1.32 :
      (fieldOfViewDegrees < 90.0 ? 1.14 : 1.0);
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON) {
      return (selected ? 17.0 : 14.0) * detailScale;
    }
    if (object.type === CelestialType.PLANET) {
      const baseSize: number = object.id === 'planet-saturn' ? 14.0 : 12.0;
      return (selected ? baseSize + 3.0 : baseSize) * detailScale;
    }
    if (object.type === CelestialType.MESSIER) return (selected ? 13.0 : 9.0) * detailScale;
    if (object.type === CelestialType.CONSTELLATION) return 0.0;
    const magnitude: number = object.magnitude === undefined ? 3.0 : object.magnitude;
    return (selected ? 9.0 : Math.max(2.0, 7.0 - magnitude * 0.8)) *
      (fieldOfViewDegrees <= 30.0 ? 1.12 : 1.0);
  }

  private hitPriority(type: CelestialType): number {
    if (type === CelestialType.SUN || type === CelestialType.MOON || type === CelestialType.PLANET) return 40;
    if (type === CelestialType.MESSIER) return 30;
    if (type === CelestialType.CONSTELLATION) return 20;
    return 15;
  }

  private objectLabel(object: CelestialObject, fieldOfViewDegrees: number,
    selected: boolean, interactive: boolean): string {
    if (selected) return object.nameZh;
    if (object.type === CelestialType.CONSTELLATION) return object.nameZh;
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON ||
      object.type === CelestialType.PLANET) return object.nameZh;
    if (interactive && object.type === CelestialType.MESSIER) return '';
    if (object.type === CelestialType.MESSIER) {
      const magnitude: number = object.magnitude === undefined ? 99.0 : object.magnitude;
      if (fieldOfViewDegrees <= 30.0) return object.designation;
      if (fieldOfViewDegrees < 90.0) {
        return magnitude <= 7.0 || (object.angularSizeDegrees !== undefined && object.angularSizeDegrees >= 0.5) ?
          object.designation : '';
      }
      return magnitude <= 5.0 ? object.designation : '';
    }
    const magnitude: number = object.magnitude === undefined ? 99.0 : object.magnitude;
    if (interactive) return magnitude <= 1.0 ? object.nameZh : '';
    if (fieldOfViewDegrees >= 90.0) return magnitude <= 1.5 ? object.nameZh : '';
    if (fieldOfViewDegrees >= 30.0) return magnitude <= 2.5 ? object.nameZh : '';
    return object.nameZh;
  }

  private objectColor(object: CelestialObject): string {
    if (object.type === CelestialType.SUN) return '#FFD56A';
    if (object.type === CelestialType.MOON) return '#E8EEF7';
    if (object.id === 'planet-mercury') return '#B9B4AB';
    if (object.id === 'planet-venus') return '#F6DB9C';
    if (object.id === 'planet-mars') return '#E7805C';
    if (object.id === 'planet-jupiter') return '#E8C39B';
    if (object.id === 'planet-saturn') return '#E9CF8C';
    if (object.id === 'planet-uranus') return '#8EDDE0';
    if (object.id === 'planet-neptune') return '#739CEC';
    if (object.type === CelestialType.PLANET) return '#F3B75F';
    if (object.type === CelestialType.MESSIER) return '#67D4B1';
    if (object.type === CelestialType.CONSTELLATION) return '#86A9C4';
    return '#FFFFFF';
  }

  /**
   * Astronomy Engine 的亮边角以天球北向为零、向东递增；Canvas 需要屏幕正上方为零。
   * 通过目标附近的球面短弧重新投影，可同时吸收视口旋转和宽视场边缘的局部扭曲。
   */
  private brightLimbScreenAngle(coordinate: EquatorialCoordinate, positionAngleDegrees: number,
    query: NormalSkySceneQuery, prepared: NormalSkyPreparedProjection): number {
    const source: NormalSkyScreenProjection =
      NormalSkyProjectionService.projectScreenPrepared(coordinate, prepared);
    const distanceRadians: number = 0.25 * Math.PI / 180.0;
    const positionRadians: number = positionAngleDegrees * Math.PI / 180.0;
    const sourceRa: number = coordinate.raHours * Math.PI / 12.0;
    const sourceDec: number = coordinate.decDegrees * Math.PI / 180.0;
    const destinationDec: number = Math.asin(
      Math.sin(sourceDec) * Math.cos(distanceRadians) +
      Math.cos(sourceDec) * Math.sin(distanceRadians) * Math.cos(positionRadians));
    const deltaRa: number = Math.atan2(
      Math.sin(positionRadians) * Math.sin(distanceRadians) * Math.cos(sourceDec),
      Math.cos(distanceRadians) - Math.sin(sourceDec) * Math.sin(destinationDec));
    const destination: EquatorialCoordinate = {
      raHours: AstronomyService.normalizeHours((sourceRa + deltaRa) * 12.0 / Math.PI),
      decDegrees: destinationDec * 180.0 / Math.PI,
      frame: coordinate.frame,
      validAtMs: coordinate.validAtMs
    };
    const projectedDestination: NormalSkyScreenProjection =
      NormalSkyProjectionService.projectScreenPrepared(destination, prepared);
    const deltaX: number = projectedDestination.xPixels - source.xPixels;
    const deltaY: number = projectedDestination.yPixels - source.yPixels;
    if (!Number.isFinite(deltaX) || !Number.isFinite(deltaY) ||
      Math.abs(deltaX) + Math.abs(deltaY) < 0.000001) {
      return query.viewport.rotationDegrees - positionAngleDegrees;
    }
    return Math.atan2(deltaX, -deltaY) * 180.0 / Math.PI;
  }

  static glyphKindFor(object: CelestialObject): SkyObjectGlyphKind {
    if (object.type === CelestialType.STAR) return SkyObjectGlyphKind.STAR;
    if (object.type === CelestialType.CONSTELLATION) return SkyObjectGlyphKind.CONSTELLATION;
    if (object.type === CelestialType.SUN) return SkyObjectGlyphKind.SUN;
    if (object.type === CelestialType.MOON) return SkyObjectGlyphKind.MOON;
    if (object.id === 'planet-mercury') return SkyObjectGlyphKind.MERCURY;
    if (object.id === 'planet-venus') return SkyObjectGlyphKind.VENUS;
    if (object.id === 'planet-mars') return SkyObjectGlyphKind.MARS;
    if (object.id === 'planet-jupiter') return SkyObjectGlyphKind.JUPITER;
    if (object.id === 'planet-saturn') return SkyObjectGlyphKind.SATURN;
    if (object.id === 'planet-uranus') return SkyObjectGlyphKind.URANUS;
    if (object.id === 'planet-neptune') return SkyObjectGlyphKind.NEPTUNE;
    if (object.type === CelestialType.PLANET) return SkyObjectGlyphKind.SOLAR_SYSTEM_GENERIC;
    if (NormalSkySceneService.hasTag(object, '星系')) return SkyObjectGlyphKind.GALAXY;
    if (NormalSkySceneService.hasTag(object, '疏散星团')) return SkyObjectGlyphKind.OPEN_CLUSTER;
    if (NormalSkySceneService.hasTag(object, '球状星团')) return SkyObjectGlyphKind.GLOBULAR_CLUSTER;
    if (NormalSkySceneService.hasTag(object, '行星状星云')) return SkyObjectGlyphKind.PLANETARY_NEBULA;
    if (NormalSkySceneService.hasTag(object, '超新星遗迹')) return SkyObjectGlyphKind.SUPERNOVA_REMNANT;
    if (NormalSkySceneService.hasTag(object, '暗星云')) return SkyObjectGlyphKind.DARK_NEBULA;
    if (NormalSkySceneService.hasTag(object, '星云') ||
      NormalSkySceneService.hasTag(object, '反射星云')) return SkyObjectGlyphKind.NEBULA;
    return SkyObjectGlyphKind.DEEP_SKY_GENERIC;
  }

  private static hasTag(object: CelestialObject, expected: string): boolean {
    for (let index: number = 0; index < object.tags.length; index++) {
      if (object.tags[index] === expected) return true;
    }
    return false;
  }

  private starColor(spectralType: string): string {
    if (spectralType.startsWith('O') || spectralType.startsWith('B')) return '#B9D8FF';
    if (spectralType.startsWith('A')) return '#E1ECFF';
    if (spectralType.startsWith('F')) return '#FFF7E1';
    if (spectralType.startsWith('G')) return '#FFE6A8';
    if (spectralType.startsWith('K')) return '#FFC887';
    if (spectralType.startsWith('M')) return '#FF9C7A';
    return '#E8F1FF';
  }
}

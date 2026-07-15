import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  ArCalibration,
  CameraViewport,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  DevicePose,
  EquatorialCoordinate,
  EquatorialFrame,
  HorizontalCoordinate,
  ObserverState,
  RefractionMode,
  ScreenProjection
} from '../models/DomainModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';

interface HygVisibleStarRecord {
  id: string;
  name: string;
  raHours: number;
  decDegrees: number;
  pmra: number;
  pmdec: number;
  magnitude: number;
  constellation: string;
  spectralType: string;
  distanceParsec: number;
}

interface HygVisibleStarDocument {
  source: string;
  sourceUrl: string;
  license: string;
  sourceEpochYear: number;
  magnitudeLimit: number;
  count: number;
  stars: HygVisibleStarRecord[];
}

/** HYG 星表中通过运行时校验、可安全用于投影的恒星记录。 */
export interface VisibleStar {
  id: string;
  name: string;
  raHours: number;
  decDegrees: number;
  pmRaMasPerYear: number;
  pmDecMasPerYear: number;
  sourceEpochYear: number;
  magnitude: number;
  constellation: string;
  spectralType: string;
  distanceParsec: number;
}

export interface VisibleStarCatalogMetadata {
  source: string;
  sourceUrl: string;
  license: string;
  sourceEpochYear: number;
  magnitudeLimit: number;
  declaredCount: number;
  loadedCount: number;
  rejectedCount: number;
}

/**
 * AR 视口查询参数。maxResults 是渲染保护上限，不改变星等筛选结果的顺序；达到上限时优先保留亮星。
 */
export interface VisibleStarViewportQuery {
  observer: ObserverState;
  pose: DevicePose;
  viewport: CameraViewport;
  calibration?: ArCalibration;
  maxMagnitude?: number;
  minAltitudeDegrees?: number;
  viewportMarginPixels?: number;
  maxResults?: number;
}

export interface ProjectedVisibleStar {
  star: VisibleStar;
  coordinate: EquatorialCoordinate;
  horizontal: HorizontalCoordinate;
  projection: ScreenProjection;
}

/** 普通星图的赤经、赤纬矩形窗口；赤经窗口跨越 0h 时会自动处理回绕。 */
export interface EquatorialViewportQuery {
  centerRaHours: number;
  centerDecDegrees: number;
  widthDegrees: number;
  heightDegrees: number;
  maxMagnitude?: number;
  maxResults?: number;
  timestampMs?: number;
}

/** 普通星图球面查询；与矩形窗口不同，它在赤经回绕和天极附近不会漏星。 */
export interface SphericalSkyQuery {
  center: EquatorialCoordinate;
  radiusDegrees: number;
  maxMagnitude?: number;
  maxResults?: number;
  timestampMs?: number;
}

/**
 * 加载并查询 resources/rawfile/visible_stars.json。
 *
 * 服务只缓存解析后的紧凑恒星记录，不把 8921 条记录复制进 CelestialCatalog 的静态业务目录。
 * 页面销毁后可调用 clear() 释放内存；重复 load() 不会再次读取 1.4 MB rawfile。
 */
export class VisibleStarCatalogService {
  private static readonly RAW_FILE_NAME: string = 'visible_stars.json';
  private static readonly DEFAULT_MAX_MAGNITUDE: number = 6.5;
  private static readonly DEFAULT_MAX_RESULTS: number = 1200;
  private static readonly MAX_CATALOG_RESULTS: number = 10000;

  private stars: VisibleStar[] = [];
  private metadata: VisibleStarCatalogMetadata | undefined = undefined;
  private loadingPromise: Promise<VisibleStarCatalogMetadata> | undefined = undefined;

  isLoaded(): boolean {
    return this.metadata !== undefined;
  }

  /** UIAbilityContext、AbilityStageContext 或 ApplicationContext 均可通过其公共 Context 接口加载资源。 */
  async load(context: common.Context): Promise<VisibleStarCatalogMetadata> {
    if (this.metadata !== undefined) {
      return this.copyMetadata(this.metadata);
    }
    if (this.loadingPromise !== undefined) {
      return this.copyMetadata(await this.loadingPromise);
    }

    this.loadingPromise = this.loadInternal(context);
    try {
      const loaded: VisibleStarCatalogMetadata = await this.loadingPromise;
      return this.copyMetadata(loaded);
    } finally {
      this.loadingPromise = undefined;
    }
  }

  clear(): void {
    this.stars = [];
    this.metadata = undefined;
    this.loadingPromise = undefined;
  }

  getMetadata(): VisibleStarCatalogMetadata | undefined {
    return this.metadata === undefined ? undefined : this.copyMetadata(this.metadata);
  }

  getCount(): number {
    return this.stars.length;
  }

  /** Canvas 天穹命中后按稳定目录 ID 取回原始恒星，避免页面为每颗星维护额外点击节点。 */
  getById(id: string): VisibleStar | undefined {
    for (let index: number = 0; index < this.stars.length; index++) {
      if (this.stars[index].id === id) {
        return this.stars[index];
      }
    }
    return undefined;
  }

  /** 按视星等从亮到暗返回恒星，供目录搜索或普通星图分层渲染使用。 */
  filterByMagnitude(maxMagnitude: number = VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE,
    maxResults: number = VisibleStarCatalogService.MAX_CATALOG_RESULTS): VisibleStar[] {
    this.ensureLoaded();
    const safeMagnitude: number = this.normalizeMagnitude(maxMagnitude);
    const safeLimit: number = this.normalizeLimit(maxResults);
    const result: VisibleStar[] = [];
    for (let index: number = 0; index < this.stars.length && result.length < safeLimit; index++) {
      const star: VisibleStar = this.stars[index];
      if (star.magnitude <= safeMagnitude) {
        result.push(star);
      }
    }
    return result;
  }

  /** 按名称、HIP/HYG 标识或星座缩写检索，结果仍按视星等优先。 */
  search(keyword: string, maxResults: number = 20): VisibleStar[] {
    this.ensureLoaded();
    const normalized: string = keyword.trim().toLowerCase();
    if (normalized.length === 0) {
      return [];
    }
    const limit: number = this.normalizeLimit(maxResults);
    const result: VisibleStar[] = [];
    for (let index: number = 0; index < this.stars.length && result.length < limit; index++) {
      const star: VisibleStar = this.stars[index];
      const searchable: string = `${star.id} ${star.name} ${star.constellation}`.toLowerCase();
      if (searchable.includes(normalized)) {
        result.push(star);
      }
    }
    return result;
  }

  /**
   * 普通星图按赤经/赤纬窗口筛选。横向角距离会乘 cos(dec)，使高纬区域的窗口宽度更接近真实视场。
   */
  filterEquatorialViewport(query: EquatorialViewportQuery): VisibleStar[] {
    this.ensureLoaded();
    const maxMagnitude: number = this.normalizeMagnitude(query.maxMagnitude === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE : query.maxMagnitude);
    const maxResults: number = this.normalizeLimit(query.maxResults === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_RESULTS : query.maxResults);
    const halfWidth: number = this.clamp(Math.abs(query.widthDegrees) / 2.0, 0.0, 180.0);
    const halfHeight: number = this.clamp(Math.abs(query.heightDegrees) / 2.0, 0.0, 90.0);
    const centerRaDegrees: number = AstronomyService.normalizeHours(query.centerRaHours) * 15.0;
    const centerDecDegrees: number = this.clamp(query.centerDecDegrees, -90.0, 90.0);
    const declinationScale: number = Math.max(0.01, Math.cos(centerDecDegrees * Math.PI / 180.0));
    const result: VisibleStar[] = [];
    const timestampMs: number = query.timestampMs === undefined ? Date.now() : query.timestampMs;

    for (let index: number = 0; index < this.stars.length && result.length < maxResults; index++) {
      const star: VisibleStar = this.stars[index];
      const coordinate: EquatorialCoordinate = this.coordinateAt(star, timestampMs);
      if (star.magnitude > maxMagnitude || Math.abs(coordinate.decDegrees - centerDecDegrees) > halfHeight) {
        continue;
      }
      const raDifference: number = Math.abs(AstronomyService.normalizeSignedDegrees(
        coordinate.raHours * 15.0 - centerRaDegrees)) * declinationScale;
      if (raDifference <= halfWidth) {
        result.push(star);
      }
    }
    return result;
  }

  filterSphericalViewport(query: SphericalSkyQuery): VisibleStar[] {
    this.ensureLoaded();
    const radius: number = this.clamp(Math.abs(query.radiusDegrees), 0.0, 180.0);
    const maxMagnitude: number = this.normalizeMagnitude(query.maxMagnitude === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE : query.maxMagnitude);
    const maxResults: number = this.normalizeLimit(query.maxResults === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_RESULTS : query.maxResults);
    const center: EquatorialCoordinate = {
      raHours: AstronomyService.normalizeHours(query.center.raHours),
      decDegrees: this.clamp(query.center.decDegrees, -90.0, 90.0),
      frame: query.center.frame
    };
    const timestampMs: number = query.timestampMs === undefined ? Date.now() : query.timestampMs;
    const result: VisibleStar[] = [];
    for (let index: number = 0; index < this.stars.length && result.length < maxResults; index++) {
      const star: VisibleStar = this.stars[index];
      const coordinate: EquatorialCoordinate = this.coordinateAt(star, timestampMs);
      if (star.magnitude > maxMagnitude || !this.passesEquatorialPrefilter(coordinate, center, radius)) {
        continue;
      }
      if (AstronomyService.angularSeparation(coordinate, center) <= radius) {
        result.push(star);
      }
    }
    return result;
  }

  /**
   * 筛选并投影当前 AR 镜头内的恒星。先按赤道坐标角距粗筛，再计算地平坐标与透视坐标，
   * 这样姿态刷新时只会对视场附近的小集合执行完整投影。
   */
  projectViewport(query: VisibleStarViewportQuery): ProjectedVisibleStar[] {
    this.ensureLoaded();
    this.validateViewport(query.viewport);
    const maxMagnitude: number = this.normalizeMagnitude(query.maxMagnitude === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE : query.maxMagnitude);
    const minimumAltitude: number = this.clamp(query.minAltitudeDegrees === undefined ? 0.0 :
      query.minAltitudeDegrees, -90.0, 90.0);
    const marginPixels: number = Math.max(0.0, query.viewportMarginPixels === undefined ? 0.0 :
      query.viewportMarginPixels);
    const maxResults: number = this.normalizeLimit(query.maxResults === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_RESULTS : query.maxResults);

    const calibratedPose: DevicePose = this.calibratedPose(query.pose, query.calibration);
    const cameraCenter: HorizontalCoordinate = {
      altitudeDegrees: calibratedPose.pitchDegrees,
      azimuthDegrees: calibratedPose.headingDegrees,
      aboveHorizon: calibratedPose.pitchDegrees > 0.0
    };
    const cameraCenterEquatorial: EquatorialCoordinate = EphemerisService.horizontalToEqj(
      cameraCenter.azimuthDegrees, cameraCenter.altitudeDegrees, query.observer,
      query.observer.timestampMs, RefractionMode.NORMAL);
    const degreesPerPixel: number = Math.max(
      query.viewport.horizontalFovDegrees / query.viewport.widthPixels,
      query.viewport.verticalFovDegrees / query.viewport.heightPixels);
    const diagonalHalfFov: number = Math.sqrt(
      query.viewport.horizontalFovDegrees * query.viewport.horizontalFovDegrees +
      query.viewport.verticalFovDegrees * query.viewport.verticalFovDegrees) / 2.0;
    // 额外 1 度用于覆盖透视投影边缘和传感器姿态抖动，避免星点在边缘闪烁。
    const prefilterRadius: number = Math.min(100.0, diagonalHalfFov + marginPixels * degreesPerPixel + 1.0);
    const result: ProjectedVisibleStar[] = [];

    for (let index: number = 0; index < this.stars.length && result.length < maxResults; index++) {
      const star: VisibleStar = this.stars[index];
      if (star.magnitude > maxMagnitude) {
        continue;
      }
      const coordinate: EquatorialCoordinate = this.coordinateAt(star, query.observer.timestampMs);
      if (!this.passesEquatorialPrefilter(coordinate, cameraCenterEquatorial, prefilterRadius)) {
        continue;
      }
      if (AstronomyService.angularSeparation(coordinate, cameraCenterEquatorial) > prefilterRadius) {
        continue;
      }
      const horizontal: HorizontalCoordinate = EphemerisService.horizontalFromEqjCoordinate(
        coordinate, query.observer, query.observer.timestampMs, RefractionMode.NORMAL);
      if (horizontal.altitudeDegrees < minimumAltitude) {
        continue;
      }
      const projection: ScreenProjection = AstronomyService.projectToViewport(
        horizontal, query.pose, query.viewport, query.calibration);
      if (projection.inFront && projection.xPixels >= -marginPixels &&
        projection.xPixels <= query.viewport.widthPixels + marginPixels &&
        projection.yPixels >= -marginPixels &&
        projection.yPixels <= query.viewport.heightPixels + marginPixels) {
        result.push({
          star: star,
          coordinate: coordinate,
          horizontal: horizontal,
          projection: projection
        });
      }
    }
    return result;
  }

  /** 将运行时 HYG 记录转换为页面现有的 CelestialObject 契约，便于复用详情弹窗和 GOTO 流程。 */
  toCelestialObject(star: VisibleStar): CelestialObject {
    const displayName: string = star.name.length > 0 ? star.name : star.id;
    const tags: string[] = ['HYG', '恒星'];
    if (star.constellation.length > 0) {
      tags.push(star.constellation);
    }
    if (star.spectralType.length > 0) {
      tags.push(star.spectralType);
    }
    const distanceDescription: string = star.distanceParsec > 0.0 && star.distanceParsec < 100000.0 ?
      `，距离约 ${star.distanceParsec.toFixed(1)} 秒差距` : '';
    return {
      id: `hyg-${star.id.toLowerCase()}`,
      type: CelestialType.STAR,
      nameZh: displayName,
      nameEn: displayName,
      designation: star.id,
      constellation: star.constellation,
      coordinate: this.coordinateOf(star),
      stellarProperMotion: {
        pmRaMasPerYear: star.pmRaMasPerYear,
        pmDecMasPerYear: star.pmDecMasPerYear,
        sourceEpochYear: star.sourceEpochYear
      },
      magnitude: star.magnitude,
      angularSizeDegrees: 0.0,
      description: `HYG 可见星表恒星，光谱型 ${star.spectralType.length > 0 ? star.spectralType : '未知'}${distanceDescription}。`,
      tags: tags,
      precision: CatalogPrecision.EXACT,
      gotoAllowed: true,
      recommendedFor18mm: false
    };
  }

  private async loadInternal(context: common.Context): Promise<VisibleStarCatalogMetadata> {
    let bytes: Uint8Array;
    try {
      bytes = await context.resourceManager.getRawFileContent(VisibleStarCatalogService.RAW_FILE_NAME);
    } catch (error) {
      throw new Error(`读取离线可见星表失败：${error}`);
    }
    let document: HygVisibleStarDocument;
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
      document = JSON.parse(decoder.decodeToString(bytes)) as HygVisibleStarDocument;
      if (document === null || document.stars === undefined || !Array.isArray(document.stars)) {
        throw new Error('缺少 stars 数组');
      }
    } catch (error) {
      throw new Error(`解析离线可见星表失败：${error}`);
    }

    const parsedStars: VisibleStar[] = [];
    let rejectedCount: number = 0;
    const sourceEpochYear: number = this.isFiniteNumber(document.sourceEpochYear) ?
      document.sourceEpochYear : 2000.0;
    for (let index: number = 0; index < document.stars.length; index++) {
      const record: HygVisibleStarRecord | null = document.stars[index];
      if (record === null || !this.isValidRecord(record)) {
        rejectedCount++;
        continue;
      }
      // HYG0 是太阳的占位记录，其 J2000 坐标为 0/0，并非实时太阳位置，不能参与 AR 恒星投影。
      if (record.id === 'HYG0' || record.name === 'Sol') {
        rejectedCount++;
        continue;
      }
      parsedStars.push({
        id: record.id,
        name: record.name,
        raHours: AstronomyService.normalizeHours(record.raHours),
        decDegrees: record.decDegrees,
        pmRaMasPerYear: record.pmra,
        pmDecMasPerYear: record.pmdec,
        sourceEpochYear: sourceEpochYear,
        magnitude: record.magnitude,
        constellation: record.constellation,
        spectralType: record.spectralType,
        distanceParsec: record.distanceParsec
      });
    }

    // 预排序保证所有带结果上限的查询稳定地优先返回亮星，同时避免每次姿态刷新重新排序。
    parsedStars.sort((first: VisibleStar, second: VisibleStar): number => first.magnitude - second.magnitude);
    this.stars = parsedStars;
    this.metadata = {
      source: typeof document.source === 'string' ? document.source : 'HYG Database',
      sourceUrl: typeof document.sourceUrl === 'string' ? document.sourceUrl : '',
      license: typeof document.license === 'string' ? document.license : 'CC BY-SA 4.0',
      sourceEpochYear: sourceEpochYear,
      magnitudeLimit: this.isFiniteNumber(document.magnitudeLimit) ? document.magnitudeLimit :
        VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE,
      declaredCount: this.isFiniteNumber(document.count) ? document.count : document.stars.length,
      loadedCount: parsedStars.length,
      rejectedCount: rejectedCount
    };
    return this.metadata;
  }

  private isValidRecord(record: HygVisibleStarRecord): boolean {
    return record !== undefined && typeof record.id === 'string' && record.id.length > 0 &&
      typeof record.name === 'string' && typeof record.constellation === 'string' &&
      typeof record.spectralType === 'string' && this.isFiniteNumber(record.raHours) &&
      record.raHours >= 0.0 && record.raHours <= 24.0 && this.isFiniteNumber(record.decDegrees) &&
      record.decDegrees >= -90.0 && record.decDegrees <= 90.0 && this.isFiniteNumber(record.magnitude) &&
      this.isFiniteNumber(record.pmra) && this.isFiniteNumber(record.pmdec) &&
      this.isFiniteNumber(record.distanceParsec) && record.distanceParsec >= 0.0;
  }

  /** 球面角距前的保守包围窗口；接近天极时放弃赤经筛选，保证不会误删应显示的恒星。 */
  private passesEquatorialPrefilter(coordinate: EquatorialCoordinate, center: EquatorialCoordinate,
    radiusDegrees: number): boolean {
    if (Math.abs(coordinate.decDegrees - center.decDegrees) > radiusDegrees) {
      return false;
    }
    const furthestDeclination: number = Math.abs(center.decDegrees) + radiusDegrees;
    if (furthestDeclination >= 89.0) {
      return true;
    }
    const minimumCosine: number = Math.max(0.01,
      Math.cos(furthestDeclination * Math.PI / 180.0));
    const maximumRaDifference: number = Math.min(180.0, radiusDegrees / minimumCosine);
    const raDifference: number = Math.abs(AstronomyService.normalizeSignedDegrees(
      coordinate.raHours * 15.0 - center.raHours * 15.0));
    return raDifference <= maximumRaDifference;
  }

  private coordinateOf(star: VisibleStar): EquatorialCoordinate {
    return {
      raHours: star.raHours,
      decDegrees: star.decDegrees,
      frame: EquatorialFrame.ICRS_J2000
    };
  }

  coordinateAt(star: VisibleStar, timestampMs: number): EquatorialCoordinate {
    return EphemerisService.applyProperMotion(this.coordinateOf(star), {
      pmRaMasPerYear: star.pmRaMasPerYear,
      pmDecMasPerYear: star.pmDecMasPerYear,
      sourceEpochYear: star.sourceEpochYear
    }, timestampMs);
  }

  private calibratedPose(pose: DevicePose, calibration?: ArCalibration): DevicePose {
    return {
      headingDegrees: AstronomyService.normalizeDegrees(pose.headingDegrees +
        (calibration === undefined ? 0.0 : calibration.headingOffsetDegrees)),
      pitchDegrees: pose.pitchDegrees + (calibration === undefined ? 0.0 : calibration.pitchOffsetDegrees),
      rollDegrees: pose.rollDegrees + (calibration === undefined ? 0.0 : calibration.rollOffsetDegrees)
    };
  }

  private validateViewport(viewport: CameraViewport): void {
    if (viewport.widthPixels <= 0.0 || viewport.heightPixels <= 0.0 ||
      viewport.horizontalFovDegrees <= 0.0 || viewport.horizontalFovDegrees >= 180.0 ||
      viewport.verticalFovDegrees <= 0.0 || viewport.verticalFovDegrees >= 180.0) {
      throw new Error('相机视口尺寸和视场角必须为有效正数，且视场角应小于 180 度');
    }
  }

  private normalizeMagnitude(value: number): number {
    if (!this.isFiniteNumber(value)) {
      return VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE;
    }
    const catalogLimit: number = this.metadata === undefined ?
      VisibleStarCatalogService.DEFAULT_MAX_MAGNITUDE : this.metadata.magnitudeLimit;
    return Math.min(value, catalogLimit);
  }

  private normalizeLimit(value: number): number {
    if (!this.isFiniteNumber(value)) {
      return VisibleStarCatalogService.DEFAULT_MAX_RESULTS;
    }
    return Math.max(1, Math.floor(value));
  }

  private ensureLoaded(): void {
    if (this.metadata === undefined) {
      throw new Error('离线可见星表尚未加载，请先调用 load(context)');
    }
  }

  private isFiniteNumber(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private copyMetadata(metadata: VisibleStarCatalogMetadata): VisibleStarCatalogMetadata {
    return {
      source: metadata.source,
      sourceUrl: metadata.sourceUrl,
      license: metadata.license,
      sourceEpochYear: metadata.sourceEpochYear,
      magnitudeLimit: metadata.magnitudeLimit,
      declaredCount: metadata.declaredCount,
      loadedCount: metadata.loadedCount,
      rejectedCount: metadata.rejectedCount
    };
  }
}

import {
  ArCalibration,
  CelestialObject,
  CelestialType,
  DevicePose,
  EquatorialCoordinate,
  EquatorialFrame,
  HorizontalCoordinate,
  ObserverState,
  RefractionMode
} from '../models/DomainModels';
import {
  ArPoseSample,
  ArTrackingQuality,
  ArTrackingSource,
  Quaternion,
  SkyDomeFrame,
  SkyDomePoint,
  SkyDomePolyline,
  SkyDomeRenderOptions,
  SkyDomeStarInput,
  SkyDomeViewport
} from '../models/ArSkyModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';
import { SkyDomeProjectionService } from './SkyDomeProjectionService';
import { VisibleStar } from './VisibleStarCatalogService';

export interface SkyDomeSceneQuery {
  observer: ObserverState;
  pose: DevicePose;
  viewport: SkyDomeViewport;
  catalogStars: VisibleStar[];
  featuredTargets: CelestialObject[];
  selectedTargetId: string;
  /** 0=城市肉眼层，1=平衡层，2=完整沉浸天穹。 */
  revealLevel: number;
  calibration?: ArCalibration;
  /** AR Engine 已完成坐标系转换时可直接提供相机 orientation，优先于欧拉角降级姿态。 */
  orientation?: Quaternion;
  trackingQuality?: ArTrackingQuality;
  trackingSource?: ArTrackingSource;
  timestampNs?: number;
}

/**
 * 把业务星表转换成一次 Canvas 可消费的天穹帧。
 *
 * 这里刻意不持有相机或传感器对象：AR Engine、方向传感器和回放数据都只需提供同一份
 * DevicePose，页面无需因为硬件能力不同而维护多套星图。
 */
export class SkyDomeSceneService {
  private cachedCatalogKey: string = '';
  private cachedCatalogInputs: SkyDomeStarInput[] = [];
  private cachedMilkyWayKey: string = '';
  private cachedMilkyWayInputs: SkyDomeStarInput[] = [];

  createFrame(query: SkyDomeSceneQuery): SkyDomeFrame {
    const revealLevel: number = Math.max(0, Math.min(2, Math.round(query.revealLevel)));
    const timestampMs: number = query.observer.timestampMs;
    const inputs: SkyDomeStarInput[] = this.catalogInputs(query, revealLevel).slice();

    for (let index: number = 0; index < query.featuredTargets.length; index++) {
      const target: CelestialObject = query.featuredTargets[index];
      const coordinate: EquatorialCoordinate | undefined = EphemerisService.skyCoordinate(target, timestampMs);
      if (coordinate === undefined) {
        continue;
      }
      const horizontal: HorizontalCoordinate | undefined = EphemerisService.horizontalCoordinate(
        target, query.observer, timestampMs, RefractionMode.NORMAL);
      if (horizontal === undefined) {
        continue;
      }
      inputs.push({
        id: `target:${target.id}`,
        label: target.nameZh,
        azimuthDegrees: horizontal.azimuthDegrees,
        altitudeDegrees: horizontal.altitudeDegrees,
        magnitude: target.magnitude === undefined ? 2.0 : target.magnitude,
        color: this.targetColor(target.type),
        selected: target.id === query.selectedTargetId
      });
    }

    const headingOffset: number = query.calibration === undefined ? 0.0 :
      query.calibration.headingOffsetDegrees;
    const pitchOffset: number = query.calibration === undefined ? 0.0 :
      query.calibration.pitchOffsetDegrees;
    const rollOffset: number = query.calibration === undefined ? 0.0 :
      query.calibration.rollOffsetDegrees;
    let orientation: Quaternion;
    if (query.orientation === undefined) {
      orientation = SkyDomeProjectionService.quaternionFromHeadingPitchRoll(
        query.pose.headingDegrees + headingOffset,
        query.pose.pitchDegrees + pitchOffset,
        query.pose.rollDegrees + rollOffset);
    } else {
      // 原生 AR 四元数也必须消费一星校准。先还原到统一 HPR 语义再加偏移，确保与传感器
      // 降级链保持完全相同的校准定义；预览精度目标下这比维护两套校准矩阵更易验证。
      const nativeEuler = SkyDomeProjectionService.headingPitchRollFromQuaternion(
        query.orientation, query.pose.headingDegrees);
      orientation = SkyDomeProjectionService.quaternionFromHeadingPitchRoll(
        nativeEuler.headingDegrees + headingOffset,
        nativeEuler.pitchDegrees + pitchOffset,
        nativeEuler.rollDegrees + rollOffset);
    }
    const pose: ArPoseSample = {
      orientation: orientation,
      timestampNs: query.timestampNs === undefined ? Date.now() * 1000000.0 : query.timestampNs,
      quality: query.trackingQuality === undefined ? ArTrackingQuality.NORMAL : query.trackingQuality,
      source: query.trackingSource === undefined ? ArTrackingSource.SENSOR_FUSION : query.trackingSource
    };
    const options: SkyDomeRenderOptions = SkyDomeProjectionService.defaultRenderOptions();
    options.domeFieldOfViewDegrees = revealLevel === 2 ? 174.0 : 164.0;
    options.perspectiveStrength = revealLevel === 2 ? 0.46 : 0.30;
    options.edgeCompression = revealLevel === 2 ? 0.58 : 0.42;
    options.minimumAltitudeDegrees = -8.0;
    options.markerMinimumSizePixels = revealLevel === 0 ? 2.2 : 1.6;
    options.markerMaximumSizePixels = revealLevel === 2 ? 9.5 : 8.5;
    const frame: SkyDomeFrame = SkyDomeProjectionService.createFrame(inputs, pose, query.viewport, options);
    frame.milkyWayLines = this.createMilkyWayLines(
      this.milkyWayInputs(query), pose, query.viewport, options);
    return frame;
  }

  /**
   * 恒星相对地平坐标在十几秒内变化远小于预览精度，缓存可避免姿态每帧刷新时重复执行
   * 数百次恒星时和三角函数计算。位置、显星层或星表变化会立即生成不同 key 并重建。
   */
  private catalogInputs(query: SkyDomeSceneQuery, revealLevel: number): SkyDomeStarInput[] {
    const timeBucket: number = Math.floor(query.observer.timestampMs / 15000.0);
    const firstId: string = query.catalogStars.length > 0 ? query.catalogStars[0].id : '';
    const lastId: string = query.catalogStars.length > 0 ? query.catalogStars[query.catalogStars.length - 1].id : '';
    const key: string = `${query.observer.latitudeDegrees.toFixed(3)}:` +
      `${query.observer.longitudeDegrees.toFixed(3)}:${timeBucket}:${revealLevel}:` +
      `${query.catalogStars.length}:${firstId}:${lastId}`;
    if (key === this.cachedCatalogKey) {
      return this.cachedCatalogInputs;
    }

    const magnitudeLimit: number = revealLevel === 0 ? 3.2 : (revealLevel === 1 ? 4.7 : 5.8);
    const catalogLimit: number = revealLevel === 0 ? 260 : (revealLevel === 1 ? 520 : 860);
    const result: SkyDomeStarInput[] = [];
    for (let index: number = 0; index < query.catalogStars.length && result.length < catalogLimit; index++) {
      const star: VisibleStar = query.catalogStars[index];
      if (star.magnitude > magnitudeLimit) {
        continue;
      }
      const coordinate: EquatorialCoordinate = {
        raHours: star.raHours,
        decDegrees: star.decDegrees,
        frame: EquatorialFrame.ICRS_J2000
      };
      const horizontal: HorizontalCoordinate = EphemerisService.horizontalFromEqjCoordinate(
        coordinate, query.observer, query.observer.timestampMs, RefractionMode.NORMAL);
      // 沉浸模式保留地平线下少量星点，使用户转向目标时天穹边缘不会突然出现空洞。
      if (horizontal.altitudeDegrees < -8.0) {
        continue;
      }
      result.push({
        id: `catalog:${star.id}`,
        label: star.name.length > 0 && star.magnitude <= 1.4 ? star.name : '',
        azimuthDegrees: horizontal.azimuthDegrees,
        altitudeDegrees: horizontal.altitudeDegrees,
        magnitude: star.magnitude,
        color: this.starColor(star.spectralType),
        selected: false
      });
    }
    this.cachedCatalogKey = key;
    this.cachedCatalogInputs = result;
    return this.cachedCatalogInputs;
  }

  /**
   * 使用 IAU J2000 银河坐标旋转矩阵采样 b=0° 的银河中心面。这里只生成宽弧带中心线，
   * 不伪造星云细节；渲染层通过多层透明笔触形成银河与中央暗带。
   */
  private milkyWayInputs(query: SkyDomeSceneQuery): SkyDomeStarInput[] {
    const timeBucket: number = Math.floor(query.observer.timestampMs / 15000.0);
    const key: string = `${query.observer.latitudeDegrees.toFixed(3)}:` +
      `${query.observer.longitudeDegrees.toFixed(3)}:${timeBucket}`;
    if (key === this.cachedMilkyWayKey) {
      return this.cachedMilkyWayInputs;
    }

    const result: SkyDomeStarInput[] = [];
    for (let longitudeDegrees: number = 0.0; longitudeDegrees <= 360.0; longitudeDegrees += 5.0) {
      const longitude: number = longitudeDegrees * Math.PI / 180.0;
      const galacticX: number = Math.cos(longitude);
      const galacticY: number = Math.sin(longitude);
      // 标准 J2000 Galactic -> Equatorial 旋转矩阵（Equatorial -> Galactic 的转置）。
      const equatorialX: number = -0.0548755604 * galacticX + 0.4941094279 * galacticY;
      const equatorialY: number = -0.8734370902 * galacticX - 0.4448296300 * galacticY;
      const equatorialZ: number = -0.4838350155 * galacticX + 0.7469822445 * galacticY;
      const raDegrees: number = AstronomyService.normalizeDegrees(
        Math.atan2(equatorialY, equatorialX) * 180.0 / Math.PI);
      const decDegrees: number = Math.asin(Math.max(-1.0, Math.min(1.0, equatorialZ))) * 180.0 / Math.PI;
      const coordinate: EquatorialCoordinate = {
        raHours: raDegrees / 15.0,
        decDegrees: decDegrees,
        frame: EquatorialFrame.ICRS_J2000
      };
      const horizontal: HorizontalCoordinate = EphemerisService.horizontalFromEqjCoordinate(
        coordinate, query.observer, query.observer.timestampMs, RefractionMode.NORMAL);
      result.push({
        id: `milky-way-${Math.round(longitudeDegrees)}`,
        label: '',
        azimuthDegrees: horizontal.azimuthDegrees,
        altitudeDegrees: horizontal.altitudeDegrees,
        magnitude: 0.0,
        selected: false
      });
    }
    this.cachedMilkyWayKey = key;
    this.cachedMilkyWayInputs = result;
    return this.cachedMilkyWayInputs;
  }

  private createMilkyWayLines(inputs: SkyDomeStarInput[], pose: ArPoseSample,
    viewport: SkyDomeViewport, options: SkyDomeRenderOptions): SkyDomePolyline[] {
    const lines: SkyDomePolyline[] = [];
    let current: SkyDomePoint[] = [];
    let segmentIndex: number = 0;
    for (let index: number = 0; index < inputs.length; index++) {
      const marker = SkyDomeProjectionService.projectStar(inputs[index], pose, viewport, options);
      if (marker.inViewport) {
        current.push({ xPixels: marker.xPixels, yPixels: marker.yPixels });
      } else if (current.length > 1) {
        lines.push({
          id: `milky-way-${segmentIndex}`,
          altitudeDegrees: -100.0,
          points: current,
          opacity: 0.20,
          lineWidthPixels: Math.max(52.0, Math.min(viewport.widthPixels, viewport.heightPixels) * 0.18)
        });
        segmentIndex++;
        current = [];
      } else {
        current = [];
      }
    }
    if (current.length > 1) {
      lines.push({
        id: `milky-way-${segmentIndex}`,
        altitudeDegrees: -100.0,
        points: current,
        opacity: 0.20,
        lineWidthPixels: Math.max(52.0, Math.min(viewport.widthPixels, viewport.heightPixels) * 0.18)
      });
    }
    return lines;
  }

  private starColor(spectralType: string): string {
    if (spectralType.startsWith('O') || spectralType.startsWith('B')) return '#B8D8FF';
    if (spectralType.startsWith('A')) return '#E3EEFF';
    if (spectralType.startsWith('F')) return '#FFF8E7';
    if (spectralType.startsWith('G')) return '#FFE6A6';
    if (spectralType.startsWith('K')) return '#FFC27A';
    if (spectralType.startsWith('M')) return '#FF927A';
    return '#EAF3FF';
  }

  private targetColor(type: CelestialType): string {
    if (type === CelestialType.MOON) return '#FFF1C7';
    if (type === CelestialType.SUN) return '#FFD15C';
    if (type === CelestialType.PLANET) return '#F4BA58';
    if (type === CelestialType.MESSIER) return '#72D3F5';
    if (type === CelestialType.CONSTELLATION) return '#89A7D8';
    return '#FFFFFF';
  }
}

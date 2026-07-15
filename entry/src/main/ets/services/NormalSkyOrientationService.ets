import {
  EquatorialCoordinate,
  EquatorialFrame,
  HorizontalCoordinate,
  ObserverState,
  RefractionMode
} from '../models/DomainModels';
import {
  NormalSkyProjection,
  NormalSkyViewport,
  SkyDirectionKind,
  SkyDirectionMarker,
  SkyGuideInsets,
  SkyMapOrientation,
  SkyMapSize,
  SkyOrientationSnapshot
} from '../models/NormalSkyModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';
import { NormalSkyProjectionService } from './NormalSkyProjectionService';

export interface NormalSkyOrientationQuery {
  viewport: NormalSkyViewport;
  size: SkyMapSize;
  directionGuides: boolean;
  observer?: ObserverState;
  guideInsets?: SkyGuideInsets;
}

/** 计算普通星图中心方向、罗盘角度和必要的屏幕边缘方向标记。 */
export class NormalSkyOrientationService {
  static build(query: NormalSkyOrientationQuery): SkyOrientationSnapshot {
    const center: EquatorialCoordinate = {
      raHours: query.viewport.centerRaHours,
      decDegrees: query.viewport.centerDecDegrees,
      frame: EquatorialFrame.ICRS_J2000
    };
    const observer: ObserverState | undefined = query.observer;
    const horizontal: HorizontalCoordinate | undefined = observer === undefined ? undefined :
      EphemerisService.horizontalFromEqjCoordinate(
        center, observer, observer.timestampMs, RefractionMode.NONE);
    let northAngle: number = query.viewport.rotationDegrees;
    let eastAngle: number = query.viewport.rotationDegrees - 90.0;
    const markers: SkyDirectionMarker[] = [];
    if (query.viewport.orientation === SkyMapOrientation.HORIZON_ZENITH && observer !== undefined) {
      const north: EquatorialCoordinate = NormalSkyOrientationService.horizontalCoordinate(0.0, 0.0, observer);
      const east: EquatorialCoordinate = NormalSkyOrientationService.horizontalCoordinate(0.0, 90.0, observer);
      northAngle = NormalSkyProjectionService.screenDirectionAngle(north, query.viewport);
      eastAngle = NormalSkyProjectionService.screenDirectionAngle(east, query.viewport);
      if (query.directionGuides) {
        NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.NORTH, north, query);
        NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.EAST, east, query);
        NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.SOUTH,
          NormalSkyOrientationService.horizontalCoordinate(0.0, 180.0, observer), query);
        NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.WEST,
          NormalSkyOrientationService.horizontalCoordinate(0.0, 270.0, observer), query);
        NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.ZENITH,
          NormalSkyOrientationService.horizontalCoordinate(90.0, 0.0, observer), query);
      }
    } else if (query.directionGuides) {
      NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.NORTH_CELESTIAL_POLE,
        {
          raHours: query.viewport.centerRaHours,
          decDegrees: 90.0,
          frame: EquatorialFrame.ICRS_J2000
        }, query);
      NormalSkyOrientationService.appendMarker(markers, SkyDirectionKind.SOUTH_CELESTIAL_POLE,
        {
          raHours: query.viewport.centerRaHours,
          decDegrees: -90.0,
          frame: EquatorialFrame.ICRS_J2000
        }, query);
    }
    return {
      orientation: query.viewport.orientation,
      centerRaHours: query.viewport.centerRaHours,
      centerDecDegrees: query.viewport.centerDecDegrees,
      centerAzimuthDegrees: horizontal === undefined ? undefined : horizontal.azimuthDegrees,
      centerAltitudeDegrees: horizontal === undefined ? undefined : horizontal.altitudeDegrees,
      northScreenAngleDegrees: NormalSkyOrientationService.normalizeSignedDegrees(northAngle),
      eastScreenAngleDegrees: NormalSkyOrientationService.normalizeSignedDegrees(eastAngle),
      markers: markers
    };
  }

  private static horizontalCoordinate(altitudeDegrees: number, azimuthDegrees: number,
    observer: ObserverState): EquatorialCoordinate {
    return EphemerisService.horizontalToEqj(
      azimuthDegrees, altitudeDegrees, observer, observer.timestampMs, RefractionMode.NONE);
  }

  private static appendMarker(result: SkyDirectionMarker[], kind: SkyDirectionKind,
    coordinate: EquatorialCoordinate, query: NormalSkyOrientationQuery): void {
    const projection: NormalSkyProjection = NormalSkyProjectionService.project(
      coordinate, query.viewport, query.size);
    const angle: number = NormalSkyProjectionService.screenDirectionAngle(coordinate, query.viewport);
    const bounds: SkyGuideInsets = NormalSkyOrientationService.resolveInsets(query);
    const minimumX: number = bounds.leftPixels;
    const maximumX: number = Math.max(minimumX + 1.0, query.size.widthPixels - bounds.rightPixels);
    const minimumY: number = bounds.topPixels;
    const maximumY: number = Math.max(minimumY + 1.0, query.size.heightPixels - bounds.bottomPixels);
    const insideSafeArea: boolean = projection.inViewport && projection.xPixels >= minimumX &&
      projection.xPixels <= maximumX && projection.yPixels >= minimumY && projection.yPixels <= maximumY;
    if (insideSafeArea) {
      result.push({
        kind: kind,
        xPixels: projection.xPixels,
        yPixels: projection.yPixels,
        angleDegrees: angle,
        inViewport: true,
        atEdge: false
      });
      return;
    }
    const radians: number = angle * Math.PI / 180.0;
    const directionX: number = Math.sin(radians);
    const directionY: number = -Math.cos(radians);
    const centerX: number = query.size.widthPixels / 2.0;
    const centerY: number = query.size.heightPixels / 2.0;
    const distance: number = NormalSkyOrientationService.rayDistanceToBounds(
      centerX, centerY, directionX, directionY, minimumX, maximumX, minimumY, maximumY);
    result.push({
      kind: kind,
      xPixels: NormalSkyOrientationService.clamp(centerX + directionX * distance, minimumX, maximumX),
      yPixels: NormalSkyOrientationService.clamp(centerY + directionY * distance, minimumY, maximumY),
      angleDegrees: angle,
      inViewport: projection.inViewport,
      atEdge: true
    });
  }

  private static resolveInsets(query: NormalSkyOrientationQuery): SkyGuideInsets {
    const requested: SkyGuideInsets = query.guideInsets === undefined ? {
      leftPixels: 28.0, rightPixels: 28.0, topPixels: 28.0, bottomPixels: 28.0
    } : query.guideInsets;
    const maximumHorizontal: number = Math.max(12.0, query.size.widthPixels / 2.0 - 24.0);
    const maximumVertical: number = Math.max(12.0, query.size.heightPixels / 2.0 - 24.0);
    return {
      leftPixels: NormalSkyOrientationService.clamp(requested.leftPixels, 12.0, maximumHorizontal),
      rightPixels: NormalSkyOrientationService.clamp(requested.rightPixels, 12.0, maximumHorizontal),
      topPixels: NormalSkyOrientationService.clamp(requested.topPixels, 12.0, maximumVertical),
      bottomPixels: NormalSkyOrientationService.clamp(requested.bottomPixels, 12.0, maximumVertical)
    };
  }

  private static rayDistanceToBounds(centerX: number, centerY: number, directionX: number,
    directionY: number, minimumX: number, maximumX: number, minimumY: number, maximumY: number): number {
    let distance: number = Number.MAX_VALUE;
    if (directionX > 0.000001) distance = Math.min(distance, (maximumX - centerX) / directionX);
    if (directionX < -0.000001) distance = Math.min(distance, (minimumX - centerX) / directionX);
    if (directionY > 0.000001) distance = Math.min(distance, (maximumY - centerY) / directionY);
    if (directionY < -0.000001) distance = Math.min(distance, (minimumY - centerY) / directionY);
    return Number.isFinite(distance) && distance >= 0.0 ? distance : 0.0;
  }

  private static normalizeSignedDegrees(value: number): number {
    const normalized: number = AstronomyService.normalizeDegrees(value);
    return normalized > 180.0 ? normalized - 360.0 : normalized;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

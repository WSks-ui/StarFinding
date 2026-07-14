import { CelestialCatalog } from '../data/CelestialCatalog';
import {
  CelestialObject,
  CelestialType,
  EquatorialCoordinate,
  ObserverState
} from '../models/DomainModels';
import {
  NormalSkyProjection,
  NormalSkyScene,
  NormalSkyViewport,
  ProjectedSkyObject,
  SkyLayerVisibility,
  SkyMapSize,
  SkyPolyline,
  SkyPolylineKind,
  SkyScreenPoint,
  SkyScreenRect
} from '../models/NormalSkyModels';
import { AstronomyService } from './AstronomyService';
import { ConstellationLineGroup, NormalSkyCatalogService } from './NormalSkyCatalogService';
import { NormalSkyProjectionService } from './NormalSkyProjectionService';
import { VisibleStar, VisibleStarCatalogService } from './VisibleStarCatalogService';

export interface NormalSkySceneQuery {
  viewport: NormalSkyViewport;
  size: SkyMapSize;
  layers: SkyLayerVisibility;
  selectedTargetId: string;
  timestampMs: number;
  observer?: ObserverState;
}

/** 把多个离线目录合成为 Canvas 一次可绘制的场景。 */
export class NormalSkySceneService {
  private readonly visibleStars: VisibleStarCatalogService;
  private readonly lineCatalog: NormalSkyCatalogService;

  constructor(visibleStars: VisibleStarCatalogService, lineCatalog: NormalSkyCatalogService) {
    this.visibleStars = visibleStars;
    this.lineCatalog = lineCatalog;
  }

  build(query: NormalSkySceneQuery): NormalSkyScene {
    const objects: ProjectedSkyObject[] = [];
    const brightStars: CelestialObject[] = CelestialCatalog.brightStars();
    this.appendCatalogObjects(objects, brightStars, query);
    this.appendVisibleStars(objects, brightStars, query);
    if (query.layers.constellationLines) {
      this.appendCatalogObjects(objects, CelestialCatalog.constellations(), query);
    }
    if (query.layers.deepSky) {
      this.appendCatalogObjects(objects, CelestialCatalog.messierObjects(), query);
    }
    if (query.layers.solarSystem) {
      this.appendCatalogObjects(objects, CelestialCatalog.solarSystem(), query);
    }

    return {
      objects: objects,
      constellationLines: query.layers.constellationLines ? this.buildConstellationLines(query) : [],
      gridLines: query.layers.equatorialGrid ? this.buildEquatorialGrid(query) : [],
      eclipticLines: query.layers.ecliptic ? this.buildEcliptic(query) : [],
      horizonLines: query.layers.horizon && query.observer !== undefined ? this.buildHorizon(query) : [],
      horizonMask: query.layers.horizon && query.observer !== undefined ? this.buildHorizonMask(query) : [],
      generatedAtMs: query.timestampMs
    };
  }

  private appendVisibleStars(result: ProjectedSkyObject[], brightStars: CelestialObject[],
    query: NormalSkySceneQuery): void {
    if (!this.visibleStars.isLoaded()) {
      return;
    }
    const radius: number = this.queryRadius(query.viewport, query.size);
    const stars: VisibleStar[] = this.visibleStars.filterSphericalViewport({
      center: {
        raHours: query.viewport.centerRaHours,
        decDegrees: query.viewport.centerDecDegrees,
        epoch: 2000.0
      },
      radiusDegrees: radius,
      maxMagnitude: this.maximumMagnitude(query.viewport.fieldOfViewDegrees),
      maxResults: this.maximumStarCount(query.viewport.fieldOfViewDegrees)
    });
    for (let index: number = 0; index < stars.length; index++) {
      const star: VisibleStar = stars[index];
      const coordinate: EquatorialCoordinate = {
        raHours: star.raHours, decDegrees: star.decDegrees, epoch: 2000.0
      };
      if (this.duplicatesCuratedStar(coordinate, brightStars)) {
        continue;
      }
      const projection: NormalSkyProjection = NormalSkyProjectionService.project(
        coordinate, query.viewport, query.size);
      if (!projection.inViewport) {
        continue;
      }
      const id: string = `hyg-${star.id.toLowerCase()}`;
      const selected: boolean = id === query.selectedTargetId;
      const labelMagnitude: number = query.viewport.fieldOfViewDegrees <= 35.0 ? 4.5 : 2.2;
      result.push({
        id: id,
        type: CelestialType.STAR,
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
        aboveHorizon: this.aboveHorizon(coordinate, query.observer),
        selected: selected
      });
    }
  }

  private appendCatalogObjects(result: ProjectedSkyObject[], objects: CelestialObject[],
    query: NormalSkySceneQuery): void {
    for (let index: number = 0; index < objects.length; index++) {
      const object: CelestialObject = objects[index];
      const coordinate: EquatorialCoordinate | undefined = AstronomyService.resolveCoordinate(
        object, query.timestampMs);
      if (coordinate === undefined || !this.shouldDisplay(object, query)) {
        continue;
      }
      const projection: NormalSkyProjection = NormalSkyProjectionService.project(
        coordinate, query.viewport, query.size);
      if (!projection.inViewport) {
        continue;
      }
      const selected: boolean = object.id === query.selectedTargetId;
      result.push({
        id: object.id,
        type: object.type,
        coordinate: coordinate,
        xPixels: projection.xPixels,
        yPixels: projection.yPixels,
        sizePixels: this.objectSize(object, selected),
        hitRadiusPixels: object.type === CelestialType.CONSTELLATION ? 24.0 : 20.0,
        hitPriority: selected ? 100 : this.hitPriority(object.type),
        magnitude: object.magnitude,
        label: this.objectLabel(object, query.viewport.fieldOfViewDegrees),
        designation: object.designation,
        color: this.objectColor(object.type),
        aboveHorizon: this.aboveHorizon(coordinate, query.observer),
        selected: selected
      });
    }
  }

  private shouldDisplay(object: CelestialObject, query: NormalSkySceneQuery): boolean {
    if (object.id === query.selectedTargetId) {
      return true;
    }
    if (object.type !== CelestialType.MESSIER) {
      return true;
    }
    const magnitude: number = object.magnitude === undefined ? 99.0 : object.magnitude;
    if (query.viewport.fieldOfViewDegrees >= 100.0) {
      return magnitude <= 5.5 || (object.angularSizeDegrees !== undefined && object.angularSizeDegrees >= 1.0);
    }
    if (query.viewport.fieldOfViewDegrees >= 55.0) {
      return magnitude <= 7.5 || (object.angularSizeDegrees !== undefined && object.angularSizeDegrees >= 0.5);
    }
    return true;
  }

  private buildConstellationLines(query: NormalSkySceneQuery): SkyPolyline[] {
    if (!this.lineCatalog.isLoaded()) {
      return [];
    }
    const result: SkyPolyline[] = [];
    const groups: ConstellationLineGroup[] = this.lineCatalog.getLineGroups();
    for (let groupIndex: number = 0; groupIndex < groups.length; groupIndex++) {
      const group: ConstellationLineGroup = groups[groupIndex];
      for (let lineIndex: number = 0; lineIndex < group.lines.length; lineIndex++) {
        this.appendProjectedLine(result, `${group.designation}-${lineIndex}`,
          SkyPolylineKind.CONSTELLATION, group.lines[lineIndex], query);
      }
    }
    return result;
  }

  private buildEquatorialGrid(query: NormalSkySceneQuery): SkyPolyline[] {
    const result: SkyPolyline[] = [];
    const rightAscensionStep: number = query.viewport.fieldOfViewDegrees <= 35.0 ? 1.0 : 2.0;
    for (let ra: number = 0.0; ra < 24.0; ra += rightAscensionStep) {
      const line: EquatorialCoordinate[] = [];
      for (let dec: number = -90.0; dec <= 90.0; dec += 3.0) {
        line.push({ raHours: ra, decDegrees: dec, epoch: 2000.0 });
      }
      this.appendProjectedLine(result, `ra-${ra}`, SkyPolylineKind.GRID, line, query);
    }
    for (let dec: number = -75.0; dec <= 75.0; dec += 15.0) {
      const line: EquatorialCoordinate[] = [];
      for (let ra: number = 0.0; ra <= 24.0; ra += 0.25) {
        line.push({ raHours: ra, decDegrees: dec, epoch: 2000.0 });
      }
      this.appendProjectedLine(result, `dec-${dec}`, SkyPolylineKind.GRID, line, query);
    }
    return result;
  }

  private buildEcliptic(query: NormalSkySceneQuery): SkyPolyline[] {
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
        epoch: 2000.0
      });
    }
    const result: SkyPolyline[] = [];
    this.appendProjectedLine(result, 'ecliptic', SkyPolylineKind.ECLIPTIC, line, query);
    return result;
  }

  private buildHorizon(query: NormalSkySceneQuery): SkyPolyline[] {
    const observer: ObserverState | undefined = query.observer;
    if (observer === undefined) {
      return [];
    }
    const line: EquatorialCoordinate[] = [];
    for (let azimuth: number = 0.0; azimuth <= 360.0; azimuth += 3.0) {
      line.push(AstronomyService.horizontalToEquatorial({
        altitudeDegrees: 0.0, azimuthDegrees: azimuth, aboveHorizon: false
      }, observer));
    }
    const result: SkyPolyline[] = [];
    this.appendProjectedLine(result, 'horizon', SkyPolylineKind.HORIZON, line, query);
    return result;
  }

  /** 以屏幕条带近似地平线以下区域；条带随投影重建，不会把不可见区固定在屏幕某一侧。 */
  private buildHorizonMask(query: NormalSkySceneQuery): SkyScreenRect[] {
    const observer: ObserverState | undefined = query.observer;
    if (observer === undefined) {
      return [];
    }
    const cellSize: number = 32.0;
    const columns: number = Math.ceil(query.size.widthPixels / cellSize);
    const rows: number = Math.ceil(query.size.heightPixels / cellSize);
    const result: SkyScreenRect[] = [];
    for (let row: number = 0; row < rows; row++) {
      let spanStart: number = -1;
      for (let column: number = 0; column <= columns; column++) {
        let belowHorizon: boolean = false;
        if (column < columns) {
          const coordinate: EquatorialCoordinate = NormalSkyProjectionService.unproject(
            Math.min(query.size.widthPixels, (column + 0.5) * cellSize),
            Math.min(query.size.heightPixels, (row + 0.5) * cellSize), query.viewport, query.size);
          belowHorizon = AstronomyService.equatorialToHorizontal(coordinate, observer).altitudeDegrees < 0.0;
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
    coordinates: EquatorialCoordinate[], query: NormalSkySceneQuery): void {
    let segment: SkyScreenPoint[] = [];
    let previous: SkyScreenPoint | undefined = undefined;
    const maximumGap: number = Math.max(query.size.widthPixels, query.size.heightPixels) * 1.5;
    let segmentIndex: number = 0;
    for (let index: number = 0; index < coordinates.length; index++) {
      const projection: NormalSkyProjection = NormalSkyProjectionService.project(
        coordinates[index], query.viewport, query.size);
      const point: SkyScreenPoint = { xPixels: projection.xPixels, yPixels: projection.yPixels };
      const finite: boolean = Number.isFinite(point.xPixels) && Number.isFinite(point.yPixels) &&
        Math.abs(point.xPixels) < 100000.0 && Math.abs(point.yPixels) < 100000.0;
      const gap: number = previous === undefined ? 0.0 : Math.sqrt(
        (point.xPixels - previous.xPixels) * (point.xPixels - previous.xPixels) +
        (point.yPixels - previous.yPixels) * (point.yPixels - previous.yPixels));
      if (!finite || gap > maximumGap) {
        if (segment.length >= 2) {
          result.push({ id: `${baseId}-${segmentIndex}`, kind: kind, points: segment });
          segmentIndex++;
        }
        segment = [];
        previous = undefined;
        continue;
      }
      segment.push(point);
      previous = point;
    }
    if (segment.length >= 2) {
      result.push({ id: `${baseId}-${segmentIndex}`, kind: kind, points: segment });
    }
  }

  private duplicatesCuratedStar(coordinate: EquatorialCoordinate, brightStars: CelestialObject[]): boolean {
    for (let index: number = 0; index < brightStars.length; index++) {
      const curated: EquatorialCoordinate | undefined = brightStars[index].coordinate;
      if (curated !== undefined && AstronomyService.angularSeparation(coordinate, curated) < 0.03) {
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
    if (fieldOfViewDegrees >= 120.0) return 4.5;
    if (fieldOfViewDegrees >= 70.0) return 5.2;
    if (fieldOfViewDegrees >= 35.0) return 5.8;
    return 6.5;
  }

  private maximumStarCount(fieldOfViewDegrees: number): number {
    if (fieldOfViewDegrees >= 120.0) return 700;
    if (fieldOfViewDegrees >= 70.0) return 1000;
    return 1600;
  }

  private aboveHorizon(coordinate: EquatorialCoordinate, observer?: ObserverState): boolean | undefined {
    if (observer === undefined) {
      return undefined;
    }
    return AstronomyService.equatorialToHorizontal(coordinate, observer).aboveHorizon;
  }

  private objectSize(object: CelestialObject, selected: boolean): number {
    if (selected) return 12.0;
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON) return 12.0;
    if (object.type === CelestialType.PLANET) return 9.0;
    if (object.type === CelestialType.MESSIER) return 7.0;
    if (object.type === CelestialType.CONSTELLATION) return 0.0;
    const magnitude: number = object.magnitude === undefined ? 3.0 : object.magnitude;
    return Math.max(2.0, 7.0 - magnitude * 0.8);
  }

  private hitPriority(type: CelestialType): number {
    if (type === CelestialType.SUN || type === CelestialType.MOON || type === CelestialType.PLANET) return 40;
    if (type === CelestialType.MESSIER) return 30;
    if (type === CelestialType.CONSTELLATION) return 20;
    return 15;
  }

  private objectLabel(object: CelestialObject, fieldOfViewDegrees: number): string {
    if (object.type === CelestialType.CONSTELLATION) return object.nameZh;
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON ||
      object.type === CelestialType.PLANET) return object.nameZh;
    if (object.type === CelestialType.MESSIER) {
      const magnitude: number = object.magnitude === undefined ? 99.0 : object.magnitude;
      return fieldOfViewDegrees <= 70.0 || magnitude <= 5.0 ? object.designation : '';
    }
    return object.nameZh;
  }

  private objectColor(type: CelestialType): string {
    if (type === CelestialType.SUN) return '#FFD56A';
    if (type === CelestialType.MOON) return '#E8EEF7';
    if (type === CelestialType.PLANET) return '#F3B75F';
    if (type === CelestialType.MESSIER) return '#67D4B1';
    if (type === CelestialType.CONSTELLATION) return '#86A9C4';
    return '#FFFFFF';
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

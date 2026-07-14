import { describe, expect, it } from '@ohos/hypium';
import {
  CelestialType,
  EquatorialCoordinate
} from '../main/ets/models/DomainModels';
import {
  NormalSkyViewport,
  ProjectedSkyObject,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import { AstronomyService } from '../main/ets/services/AstronomyService';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';

const TEST_SIZE: SkyMapSize = { widthPixels: 1000.0, heightPixels: 700.0 };

function viewport(raHours: number, decDegrees: number, fieldOfViewDegrees: number = 100.0): NormalSkyViewport {
  return {
    centerRaHours: raHours,
    centerDecDegrees: decDegrees,
    fieldOfViewDegrees: fieldOfViewDegrees,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
}

function coordinate(raHours: number, decDegrees: number): EquatorialCoordinate {
  return { raHours: raHours, decDegrees: decDegrees, epoch: 2000.0 };
}

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function object(id: string, x: number, y: number, priority: number): ProjectedSkyObject {
  return {
    id: id,
    type: CelestialType.STAR,
    coordinate: coordinate(0.0, 0.0),
    xPixels: x,
    yPixels: y,
    sizePixels: 4.0,
    hitRadiusPixels: 18.0,
    hitPriority: priority,
    label: id,
    designation: id,
    color: '#FFFFFF',
    selected: false
  };
}

export default function normalSkyProjectionServiceTest(): void {
  describe('普通星图球面投影', () => {
    it('视口中心投影到画面中心', 0, () => {
      const projection = NormalSkyProjectionService.project(coordinate(18.0, 38.0),
        viewport(18.0, 38.0), TEST_SIZE);
      expect(closeTo(projection.xPixels, 500.0, 0.001)).assertTrue();
      expect(closeTo(projection.yPixels, 350.0, 0.001)).assertTrue();
      expect(projection.inViewport).assertTrue();
    });

    it('跨越赤经零点仍按最短方向投影并可反算', 0, () => {
      const source: EquatorialCoordinate = coordinate(0.1, 12.0);
      const current: NormalSkyViewport = viewport(23.9, 10.0, 40.0);
      const projection = NormalSkyProjectionService.project(source, current, TEST_SIZE);
      const restored = NormalSkyProjectionService.unproject(
        projection.xPixels, projection.yPixels, current, TEST_SIZE);
      expect(projection.inViewport).assertTrue();
      expect(AstronomyService.angularSeparation(source, restored) < 0.0001).assertTrue();
    });

    it('天极附近正反投影保持稳定', 0, () => {
      const source: EquatorialCoordinate = coordinate(21.0, 88.7);
      const current: NormalSkyViewport = viewport(2.0, 87.5, 35.0);
      const projection = NormalSkyProjectionService.project(source, current, TEST_SIZE);
      const restored = NormalSkyProjectionService.unproject(
        projection.xPixels, projection.yPixels, current, TEST_SIZE);
      expect(projection.inViewport).assertTrue();
      expect(AstronomyService.angularSeparation(source, restored) < 0.0001).assertTrue();
    });

    it('视场角被限制在安全范围', 0, () => {
      expect(NormalSkyProjectionService.normalizeViewport(viewport(0.0, 0.0, 2.0)).fieldOfViewDegrees)
        .assertEqual(8.0);
      expect(NormalSkyProjectionService.normalizeViewport(viewport(0.0, 0.0, 200.0)).fieldOfViewDegrees)
        .assertEqual(160.0);
    });

    it('缩放保持双指中心下方天体位置', 0, () => {
      const current: NormalSkyViewport = viewport(8.0, 25.0, 90.0);
      const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(720.0, 260.0, current, TEST_SIZE);
      const zoomed: NormalSkyViewport = NormalSkyProjectionService.zoomAt(
        current, TEST_SIZE, 1.8, 720.0, 260.0);
      const projection = NormalSkyProjectionService.project(anchor, zoomed, TEST_SIZE);
      expect(closeTo(projection.xPixels, 720.0, 0.2)).assertTrue();
      expect(closeTo(projection.yPixels, 260.0, 0.2)).assertTrue();
    });

    it('旋转保持双指中心下方天体位置', 0, () => {
      const current: NormalSkyViewport = viewport(8.0, 25.0, 90.0);
      const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(680.0, 310.0, current, TEST_SIZE);
      const rotated: NormalSkyViewport = NormalSkyProjectionService.rotateAt(
        current, TEST_SIZE, 37.0, 680.0, 310.0);
      const projection = NormalSkyProjectionService.project(anchor, rotated, TEST_SIZE);
      expect(closeTo(projection.xPixels, 680.0, 0.2)).assertTrue();
      expect(closeTo(projection.yPixels, 310.0, 0.2)).assertTrue();
    });

    it('飞行插值跨赤经零点不绕远路', 0, () => {
      const first: NormalSkyViewport = viewport(23.8, 0.0, 80.0);
      const second: NormalSkyViewport = NormalSkyProjectionService.flyTo(first, coordinate(0.2, 0.0), 30.0);
      const middle: NormalSkyViewport = NormalSkyProjectionService.interpolate(first, second, 0.5);
      expect(middle.centerRaHours < 0.1 || middle.centerRaHours > 23.9).assertTrue();
      expect(closeTo(middle.fieldOfViewDegrees, 55.0, 0.001)).assertTrue();
    });

    it('重叠目标优先选择高价值对象', 0, () => {
      const selected: ProjectedSkyObject | undefined = NormalSkyProjectionService.hitTest([
        object('普通恒星', 500.0, 350.0, 10),
        object('行星', 504.0, 352.0, 40)
      ], 500.0, 350.0);
      expect(selected !== undefined && selected.id === '行星').assertTrue();
    });
  });
}

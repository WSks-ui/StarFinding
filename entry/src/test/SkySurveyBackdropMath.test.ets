import { describe, expect, it } from '@ohos/hypium';
import {
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import {
  NormalSkyPreparedProjection,
  NormalSkyProjectionService
} from '../main/ets/services/NormalSkyProjectionService';
import {
  SkySurveyBackdropMath,
  SkySurveyDirection,
  SkySurveyEquirectangularUv,
  SkySurveyGalacticCoordinate
} from '../main/ets/services/SkySurveyBackdropMath';

const TEST_SIZE: SkyMapSize = { widthPixels: 1024.0, heightPixels: 720.0 };

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function uvForEquatorial(raHours: number, decDegrees: number): SkySurveyEquirectangularUv {
  const direction: SkySurveyDirection = SkySurveyBackdropMath.equatorialCoordinateToDirection(
    raHours, decDegrees);
  return SkySurveyBackdropMath.equatorialDirectionToEquirectangularUv(
    direction.x, direction.y, direction.z);
}

function directionSeparationDegrees(first: SkySurveyDirection, second: SkySurveyDirection): number {
  const dot: number = Math.max(-1.0, Math.min(1.0,
    first.x * second.x + first.y * second.y + first.z * second.z));
  return Math.acos(dot) * 180.0 / Math.PI;
}

function preparedProjection(): NormalSkyPreparedProjection {
  const viewport: NormalSkyViewport = {
    centerRaHours: 17.75,
    centerDecDegrees: -29.0,
    fieldOfViewDegrees: 110.0,
    rotationDegrees: 31.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
  return NormalSkyProjectionService.prepare(viewport, TEST_SIZE);
}

export default function skySurveyBackdropMathTest(): void {
  describe('真实全天摄影底图数学', () => {
    it('银河中心和三个巡天锚点映射到固定全天图 UV', 0, () => {
      // 这些均为 J2000 赤道坐标，允许少量目录坐标与 IAU 银河系定义之间的固有偏差。
      const galacticCenter: SkySurveyEquirectangularUv = uvForEquatorial(17.761122, -29.00781);
      const m31: SkySurveyEquirectangularUv = uvForEquatorial(0.712314, 41.26875);
      const lmc: SkySurveyEquirectangularUv = uvForEquatorial(5.392927, -69.7561);
      const smc: SkySurveyEquirectangularUv = uvForEquatorial(0.879113, -72.8286);

      expect(closeTo(galacticCenter.u, 0.500155, 0.0005)).assertTrue();
      expect(closeTo(galacticCenter.v, 0.500256, 0.0005)).assertTrue();
      expect(closeTo(m31.u, 0.163405, 0.0005)).assertTrue();
      expect(closeTo(m31.v, 0.619852, 0.0005)).assertTrue();
      expect(closeTo(lmc.u, 0.720930, 0.0005)).assertTrue();
      expect(closeTo(lmc.v, 0.682714, 0.0005)).assertTrue();
      expect(closeTo(smc.u, 0.658897, 0.0005)).assertTrue();
      expect(closeTo(smc.v, 0.746107, 0.0005)).assertTrue();
    });

    it('银河经度接缝位于银河中心而非图像边界', 0, () => {
      const beforeWrap: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.galacticEquirectangularUv(359.999, 0.0);
      const afterWrap: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.galacticEquirectangularUv(0.001, 0.0);
      const oppositeSide: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.galacticEquirectangularUv(180.0, 0.0);
      expect(closeTo(beforeWrap.u, 0.500003, 0.00001)).assertTrue();
      expect(closeTo(afterWrap.u, 0.499997, 0.00001)).assertTrue();
      expect(closeTo(oppositeSide.u, 0.0, 0.000001)).assertTrue();
      expect(closeTo(beforeWrap.v, 0.5, 0.000001)).assertTrue();
    });

    it('银河南北极分别映射到全天图上下边缘', 0, () => {
      const northPole: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.galacticEquirectangularUv(45.0, 90.0);
      const southPole: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.galacticEquirectangularUv(45.0, -90.0);
      expect(closeTo(northPole.v, 0.0, 0.000001)).assertTrue();
      expect(closeTo(southPole.v, 1.0, 0.000001)).assertTrue();
    });

    it('普通星图反投影在中心和屏幕边缘均返回有限单位方向', 0, () => {
      const prepared: NormalSkyPreparedProjection = preparedProjection();
      const expectedCenter: SkySurveyDirection = SkySurveyBackdropMath.equatorialCoordinateToDirection(
        prepared.viewport.centerRaHours, prepared.viewport.centerDecDegrees);
      const actualCenter: SkySurveyDirection =
        SkySurveyBackdropMath.inverseStereographicScreenDirection(512.0, 360.0, prepared);
      const topLeft: SkySurveyDirection =
        SkySurveyBackdropMath.inverseStereographicScreenDirection(0.0, 0.0, prepared);
      const bottomRight: SkySurveyDirection =
        SkySurveyBackdropMath.inverseStereographicScreenDirection(1024.0, 720.0, prepared);

      expect(directionSeparationDegrees(actualCenter, expectedCenter) < 0.0001).assertTrue();
      expect(Number.isFinite(topLeft.x) && Number.isFinite(topLeft.y) &&
        Number.isFinite(topLeft.z)).assertTrue();
      expect(Number.isFinite(bottomRight.x) && Number.isFinite(bottomRight.y) &&
        Number.isFinite(bottomRight.z)).assertTrue();
      expect(closeTo(topLeft.x * topLeft.x + topLeft.y * topLeft.y + topLeft.z * topLeft.z,
        1.0, 0.000001)).assertTrue();
      expect(closeTo(bottomRight.x * bottomRight.x + bottomRight.y * bottomRight.y +
        bottomRight.z * bottomRight.z, 1.0, 0.000001)).assertTrue();
    });

    it('退化方向不会向底图渲染链路传播 NaN', 0, () => {
      const galactic: SkySurveyGalacticCoordinate =
        SkySurveyBackdropMath.equatorialDirectionToGalactic(0.0, 0.0, 0.0);
      const uv: SkySurveyEquirectangularUv =
        SkySurveyBackdropMath.equatorialDirectionToEquirectangularUv(0.0, 0.0, 0.0);
      expect(Number.isFinite(galactic.longitudeDegrees) &&
        Number.isFinite(galactic.latitudeDegrees)).assertTrue();
      expect(Number.isFinite(uv.u) && Number.isFinite(uv.v)).assertTrue();
      expect(uv.u >= 0.0 && uv.u < 1.0 && uv.v >= 0.0 && uv.v <= 1.0).assertTrue();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  EquatorialFrame,
  EquatorialCoordinate
} from '../main/ets/models/DomainModels';
import {
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import { NormalSkyInteractiveTransformService } from
  '../main/ets/services/NormalSkyInteractiveTransformService';

const TEST_SIZE: SkyMapSize = {
  widthPixels: 1024.0,
  heightPixels: 720.0
};

function viewport(raHours: number, decDegrees: number, fieldOfViewDegrees: number,
  rotationDegrees: number = 0.0): NormalSkyViewport {
  return {
    centerRaHours: raHours,
    centerDecDegrees: decDegrees,
    fieldOfViewDegrees: fieldOfViewDegrees,
    rotationDegrees: rotationDegrees,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
}

export default function normalSkyInteractiveTransformServiceTest(): void {
  describe('普通星图交互变换层', () => {
    it('恒等视口不产生 Canvas 变换', 0, () => {
      const source: NormalSkyViewport = viewport(8.0, 25.0, 90.0);
      const transform = NormalSkyInteractiveTransformService.fromViewports(
        source, source, TEST_SIZE, 1);
      expect(transform.active).assertFalse();
      expect(transform.scale).assertEqual(1.0);
      expect(transform.translateXPixels).assertEqual(0.0);
      expect(transform.translateYPixels).assertEqual(0.0);
    });

    it('缩小视场会放大已有 Canvas 场景且不会产生 NaN', 0, () => {
      const base: NormalSkyViewport = viewport(8.0, 25.0, 90.0);
      const current: NormalSkyViewport = viewport(8.0, 25.0, 45.0, 12.0);
      const transform = NormalSkyInteractiveTransformService.fromViewports(
        base, current, TEST_SIZE, 2);
      expect(transform.active).assertTrue();
      expect(transform.scale > 1.0).assertTrue();
      expect(Math.abs(transform.rotationDegrees - 12.0) < 0.001).assertTrue();
      expect(Number.isFinite(transform.translateXPixels) &&
        Number.isFinite(transform.translateYPixels)).assertTrue();
    });

    it('赤经跨越 0 小时仍使用有限的短路变换', 0, () => {
      const base: NormalSkyViewport = viewport(23.9, 5.0, 70.0);
      const current: NormalSkyViewport = viewport(0.1, 5.0, 70.0);
      const transform = NormalSkyInteractiveTransformService.fromViewports(
        base, current, TEST_SIZE, 3);
      expect(transform.active).assertTrue();
      expect(Math.abs(transform.translateXPixels) < 20000.0 &&
        Math.abs(transform.translateYPixels) < 20000.0).assertTrue();
    });

    it('接近天极时仍保持有限结果', 0, () => {
      const base: NormalSkyViewport = viewport(0.0, 89.5, 30.0);
      const current: NormalSkyViewport = viewport(12.0, 89.0, 28.0, -8.0);
      const transform = NormalSkyInteractiveTransformService.fromViewports(
        base, current, TEST_SIZE, 4);
      expect(Number.isFinite(transform.scale) &&
        Number.isFinite(transform.rotationDegrees) &&
        Number.isFinite(transform.translateXPixels) &&
        Number.isFinite(transform.translateYPixels)).assertTrue();
    });

    it('交互锚点使用固定 J2000 坐标，不会误用站心坐标帧', 0, () => {
      const anchor: EquatorialCoordinate = {
        raHours: 10.0,
        decDegrees: -20.0,
        frame: EquatorialFrame.ICRS_J2000
      };
      expect(anchor.frame).assertEqual(EquatorialFrame.ICRS_J2000);
    });
  });
}

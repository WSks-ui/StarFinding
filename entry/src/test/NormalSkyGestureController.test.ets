import { describe, expect, it } from '@ohos/hypium';
import {
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import {
  NormalSkyGestureController,
  NormalSkyGestureUpdate
} from '../main/ets/services/NormalSkyGestureController';

const GESTURE_TEST_SIZE: SkyMapSize = { widthPixels: 1000.0, heightPixels: 700.0 };

function gestureViewport(): NormalSkyViewport {
  return {
    centerRaHours: 8.0,
    centerDecDegrees: 25.0,
    fieldOfViewDegrees: 90.0,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
}

export default function normalSkyGestureControllerTest(): void {
  describe('普通星图变换事务', () => {
    it('指针缩放超过百分之二后才激活', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.beginPointerScale();
      const ignored: NormalSkyGestureUpdate = controller.updatePointerScale(
        gestureViewport(), GESTURE_TEST_SIZE, 1.01, 600.0, 300.0);
      const accepted: NormalSkyGestureUpdate = controller.updatePointerScale(
        ignored.viewport, GESTURE_TEST_SIZE, 1.03, 600.0, 300.0);
      expect(ignored.changed).assertFalse();
      expect(accepted.changed && accepted.scaleChanged).assertTrue();
      expect(accepted.viewport.fieldOfViewDegrees < 90.0).assertTrue();
    });

    it('指针旋转超过三度后才激活', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.beginPointerRotation();
      const ignored: NormalSkyGestureUpdate = controller.updatePointerRotation(
        gestureViewport(), GESTURE_TEST_SIZE, 2.0, 500.0, 350.0);
      const accepted: NormalSkyGestureUpdate = controller.updatePointerRotation(
        ignored.viewport, GESTURE_TEST_SIZE, 4.0, 500.0, 350.0);
      expect(ignored.changed).assertFalse();
      expect(accepted.changed && accepted.rotationChanged).assertTrue();
      expect(Math.abs(accepted.viewport.rotationDegrees - 4.0) < 0.01).assertTrue();
    });

    it('双掌的小幅连续变化会累计到激活阈值', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const first: NormalSkyGestureUpdate = controller.updateHandTransform(
        gestureViewport(), GESTURE_TEST_SIZE, 1.01, 1.5, 500.0, 350.0);
      const second: NormalSkyGestureUpdate = controller.updateHandTransform(
        first.viewport, GESTURE_TEST_SIZE, 1.01, 1.5, 500.0, 350.0);
      expect(first.changed).assertFalse();
      expect(second.changed).assertTrue();
      expect(second.scaleChanged && second.rotationChanged).assertTrue();
    });

    it('结束事务会清除尚未达到阈值的残留量', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.updateHandTransform(gestureViewport(), GESTURE_TEST_SIZE, 1.01, 2.0, 500.0, 350.0);
      controller.endHandTransform();
      const next: NormalSkyGestureUpdate = controller.updateHandTransform(
        gestureViewport(), GESTURE_TEST_SIZE, 1.01, 2.0, 500.0, 350.0);
      expect(next.changed).assertFalse();
    });
  });
}

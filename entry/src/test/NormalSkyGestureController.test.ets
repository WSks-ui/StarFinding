import { describe, expect, it } from '@ohos/hypium';
import {
  NormalSkyViewState,
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import {
  NormalSkyGestureController,
  NormalSkyGestureUpdate
} from '../main/ets/services/NormalSkyGestureController';
import { NormalSkyViewStateService } from '../main/ets/services/NormalSkyViewStateService';

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

function gestureViewState(): NormalSkyViewState {
  return NormalSkyViewStateService.fromViewport(gestureViewport());
}

export default function normalSkyGestureControllerTest(): void {
  describe('普通星图变换事务', () => {
    it('指针缩放超过百分之二后才激活', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.beginPointerScale();
      const ignored: NormalSkyGestureUpdate = controller.updatePointerScale(
        gestureViewState(), GESTURE_TEST_SIZE, 1.01, 600.0, 300.0);
      const accepted: NormalSkyGestureUpdate = controller.updatePointerScale(
        ignored.viewState, GESTURE_TEST_SIZE, 1.03, 600.0, 300.0);
      expect(ignored.changed).assertFalse();
      expect(accepted.changed && accepted.scaleChanged).assertTrue();
      expect(accepted.viewState.fieldOfViewDegrees < 90.0).assertTrue();
    });

    it('指针旋转超过三度后才激活', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.beginPointerRotation();
      const ignored: NormalSkyGestureUpdate = controller.updatePointerRotation(
        gestureViewState(), GESTURE_TEST_SIZE, 2.0, 500.0, 350.0);
      const accepted: NormalSkyGestureUpdate = controller.updatePointerRotation(
        ignored.viewState, GESTURE_TEST_SIZE, 4.0, 500.0, 350.0);
      expect(ignored.changed).assertFalse();
      expect(accepted.changed && accepted.rotationChanged).assertTrue();
      expect(Math.abs(NormalSkyViewStateService.snapshot(
        accepted.viewState).rotationDegrees - 4.0) < 0.01).assertTrue();
    });

    it('双掌的小幅连续变化会累计到激活阈值', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const first: NormalSkyGestureUpdate = controller.updateHandTransform(
        gestureViewState(), GESTURE_TEST_SIZE, 1.01, 1.5, 500.0, 350.0);
      const second: NormalSkyGestureUpdate = controller.updateHandTransform(
        first.viewState, GESTURE_TEST_SIZE, 1.01, 1.5, 500.0, 350.0);
      expect(first.changed).assertFalse();
      expect(second.changed).assertTrue();
      expect(second.scaleChanged && second.rotationChanged).assertTrue();
    });

    it('结束事务会清除尚未达到阈值的残留量', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      controller.updateHandTransform(gestureViewState(), GESTURE_TEST_SIZE, 1.01, 2.0, 500.0, 350.0);
      controller.endHandTransform();
      const next: NormalSkyGestureUpdate = controller.updateHandTransform(
        gestureViewState(), GESTURE_TEST_SIZE, 1.01, 2.0, 500.0, 350.0);
      expect(next.changed).assertFalse();
    });
  });
}

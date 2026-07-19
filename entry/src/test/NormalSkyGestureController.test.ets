import { describe, expect, it } from '@ohos/hypium';
import { SingleHandTransform } from '../main/ets/models/DomainModels';
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

    it('单掌三轴变换在一次事务中更新视口', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const transform: SingleHandTransform = {
        deltaX: 0.05,
        deltaY: -0.03,
        rotationDegrees: 5.0,
        scale: 1.06,
        anchorX: 0.58,
        anchorY: 0.42
      };
      const update: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        gestureViewState(), GESTURE_TEST_SIZE, transform);
      expect(update.changed).assertTrue();
      expect(update.translationChanged && update.scaleChanged && update.rotationChanged).assertTrue();
      expect(update.viewState.fieldOfViewDegrees < 90.0).assertTrue();
      expect(Number.isFinite(NormalSkyViewStateService.snapshot(
        update.viewState).rotationDegrees)).assertTrue();
    });

    it('没有达到算法层死区的恒等变换不会改变视口', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const transform: SingleHandTransform = {
        deltaX: 0.0,
        deltaY: 0.0,
        rotationDegrees: 0.0,
        scale: 1.0,
        anchorX: 0.5,
        anchorY: 0.5
      };
      const update: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        gestureViewState(), GESTURE_TEST_SIZE, transform);
      expect(update.changed).assertFalse();
      expect(update.translationChanged || update.scaleChanged || update.rotationChanged).assertFalse();
    });

    it('控制器再次限制单帧旋转缩放和异常位移', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const transform: SingleHandTransform = {
        deltaX: 1.0,
        deltaY: -1.0,
        rotationDegrees: 40.0,
        scale: 2.0,
        anchorX: 0.5,
        anchorY: 0.5
      };
      const update: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        gestureViewState(), GESTURE_TEST_SIZE, transform);
      const snapshot: NormalSkyViewport = NormalSkyViewStateService.snapshot(update.viewState);
      expect(update.changed && update.translationChanged).assertTrue();
      expect(update.scaleChanged && update.rotationChanged).assertTrue();
      expect(snapshot.fieldOfViewDegrees >= 8.0 && snapshot.fieldOfViewDegrees <= 160.0).assertTrue();
      expect(Number.isFinite(snapshot.centerRaHours) &&
        Number.isFinite(snapshot.centerDecDegrees) &&
        Number.isFinite(snapshot.rotationDegrees)).assertTrue();
    });
  });
}

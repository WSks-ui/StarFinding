import { describe, expect, it } from '@ohos/hypium';
import {
  EquatorialCoordinate,
  EquatorialFrame
} from '../main/ets/models/DomainModels';
import {
  NormalSkyProjection,
  NormalSkyViewState,
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import { AstronomyService } from '../main/ets/services/AstronomyService';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';
import { NormalSkyViewStateService } from '../main/ets/services/NormalSkyViewStateService';

const VIEW_STATE_TEST_SIZE: SkyMapSize = { widthPixels: 1000.0, heightPixels: 700.0 };

function viewStateViewport(raHours: number, decDegrees: number, fieldOfViewDegrees: number,
  rotationDegrees: number = 0.0): NormalSkyViewport {
  return {
    centerRaHours: raHours,
    centerDecDegrees: decDegrees,
    fieldOfViewDegrees: fieldOfViewDegrees,
    rotationDegrees: rotationDegrees,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
}

function viewStateCoordinate(raHours: number, decDegrees: number): EquatorialCoordinate {
  return {
    raHours: raHours,
    decDegrees: decDegrees,
    frame: EquatorialFrame.ICRS_J2000
  };
}

function closeViewStateValue(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function quaternionLength(state: NormalSkyViewState): number {
  return Math.sqrt(
    state.viewQuaternion.x * state.viewQuaternion.x +
    state.viewQuaternion.y * state.viewQuaternion.y +
    state.viewQuaternion.z * state.viewQuaternion.z +
    state.viewQuaternion.w * state.viewQuaternion.w);
}

export default function normalSkyViewStateServiceTest(): void {
  describe('普通星图四元数视图状态', () => {
    it('视口转换往返保持中心视场和屏幕旋转', 0, () => {
      const source: NormalSkyViewport = viewStateViewport(18.4, 72.0, 42.0, 37.0);
      const restored: NormalSkyViewport = NormalSkyViewStateService.snapshot(
        NormalSkyViewStateService.fromViewport(source));
      const sourceCenter: EquatorialCoordinate = viewStateCoordinate(
        source.centerRaHours, source.centerDecDegrees);
      const restoredCenter: EquatorialCoordinate = viewStateCoordinate(
        restored.centerRaHours, restored.centerDecDegrees);
      expect(AstronomyService.angularSeparation(sourceCenter, restoredCenter) < 0.000001).assertTrue();
      expect(closeViewStateValue(restored.fieldOfViewDegrees, 42.0, 0.000001)).assertTrue();
      expect(closeViewStateValue(restored.rotationDegrees, 37.0, 0.000001)).assertTrue();
      expect(closeViewStateValue(quaternionLength(
        NormalSkyViewStateService.fromViewport(source)), 1.0, 0.000001)).assertTrue();
    });

    it('轨迹球连续跨越南北天极不产生跳变或非有限状态', 0, () => {
      let state: NormalSkyViewState = NormalSkyViewStateService.fromViewport(
        viewStateViewport(2.0, 87.0, 35.0));
      const reference: EquatorialCoordinate = viewStateCoordinate(8.0, 86.0);
      let previous: NormalSkyProjection = NormalSkyProjectionService.project(
        reference, NormalSkyViewStateService.snapshot(state), VIEW_STATE_TEST_SIZE);
      for (let index: number = 0; index < 30; index++) {
        state = NormalSkyViewStateService.pan(state, VIEW_STATE_TEST_SIZE, 0.0, 28.0);
        const viewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
        const current: NormalSkyProjection = NormalSkyProjectionService.project(
          reference, viewport, VIEW_STATE_TEST_SIZE);
        const deltaX: number = current.xPixels - previous.xPixels;
        const deltaY: number = current.yPixels - previous.yPixels;
        expect(Number.isFinite(viewport.centerRaHours) && Number.isFinite(viewport.centerDecDegrees) &&
          Number.isFinite(viewport.rotationDegrees)).assertTrue();
        expect(Math.sqrt(deltaX * deltaX + deltaY * deltaY) < 120.0).assertTrue();
        expect(closeViewStateValue(quaternionLength(state), 1.0, 0.000001)).assertTrue();
        previous = current;
      }
      for (let index: number = 0; index < 60; index++) {
        state = NormalSkyViewStateService.pan(state, VIEW_STATE_TEST_SIZE, 0.0, -28.0);
        const viewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
        expect(Number.isFinite(viewport.centerRaHours) && Number.isFinite(viewport.centerDecDegrees) &&
          Number.isFinite(viewport.rotationDegrees)).assertTrue();
      }
    });

    it('四元数缩放保持双指锚点天体位置', 0, () => {
      const state: NormalSkyViewState = NormalSkyViewStateService.fromViewport(
        viewStateViewport(8.0, 25.0, 90.0));
      const before: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
      const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(
        720.0, 260.0, before, VIEW_STATE_TEST_SIZE);
      const zoomed: NormalSkyViewState = NormalSkyViewStateService.zoomAt(
        state, VIEW_STATE_TEST_SIZE, 1.8, 720.0, 260.0);
      const projection: NormalSkyProjection = NormalSkyProjectionService.project(
        anchor, NormalSkyViewStateService.snapshot(zoomed), VIEW_STATE_TEST_SIZE);
      expect(closeViewStateValue(projection.xPixels, 720.0, 0.2)).assertTrue();
      expect(closeViewStateValue(projection.yPixels, 260.0, 0.2)).assertTrue();
    });

    it('四元数旋转保持双指锚点天体位置', 0, () => {
      const state: NormalSkyViewState = NormalSkyViewStateService.fromViewport(
        viewStateViewport(8.0, 25.0, 90.0));
      const before: NormalSkyViewport = NormalSkyViewStateService.snapshot(state);
      const anchor: EquatorialCoordinate = NormalSkyProjectionService.unproject(
        680.0, 310.0, before, VIEW_STATE_TEST_SIZE);
      const rotated: NormalSkyViewState = NormalSkyViewStateService.rotateAt(
        state, VIEW_STATE_TEST_SIZE, 37.0, 680.0, 310.0);
      const projection: NormalSkyProjection = NormalSkyProjectionService.project(
        anchor, NormalSkyViewStateService.snapshot(rotated), VIEW_STATE_TEST_SIZE);
      expect(closeViewStateValue(projection.xPixels, 680.0, 0.2)).assertTrue();
      expect(closeViewStateValue(projection.yPixels, 310.0, 0.2)).assertTrue();
    });

    it('搜索飞行使用最短四元数插值跨越 0h', 0, () => {
      const source: NormalSkyViewState = NormalSkyViewStateService.fromViewport(
        viewStateViewport(23.8, 0.0, 80.0));
      const destination: NormalSkyViewState = NormalSkyViewStateService.flyTo(
        source, viewStateCoordinate(0.2, 0.0), 30.0);
      const middle: NormalSkyViewport = NormalSkyViewStateService.snapshot(
        NormalSkyViewStateService.interpolate(source, destination, 0.5));
      expect(middle.centerRaHours < 0.1 || middle.centerRaHours > 23.9).assertTrue();
      expect(closeViewStateValue(middle.fieldOfViewDegrees, 55.0, 0.001)).assertTrue();
    });

    it('惯性角速度限制为每秒九十度', 0, () => {
      const source: NormalSkyViewState = NormalSkyViewStateService.fromViewport(
        viewStateViewport(8.0, 0.0, 100.0));
      const moved: NormalSkyViewState = NormalSkyViewStateService.panWithVelocity(
        source, VIEW_STATE_TEST_SIZE, 100000.0, 0.0, 0.05);
      const first: NormalSkyViewport = NormalSkyViewStateService.snapshot(source);
      const second: NormalSkyViewport = NormalSkyViewStateService.snapshot(moved);
      const separation: number = AstronomyService.angularSeparation(
        viewStateCoordinate(first.centerRaHours, first.centerDecDegrees),
        viewStateCoordinate(second.centerRaHours, second.centerDecDegrees));
      expect(separation <= 4.6).assertTrue();
    });
  });
}

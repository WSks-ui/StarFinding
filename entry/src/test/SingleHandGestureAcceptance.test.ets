import { describe, expect, it } from '@ohos/hypium';
import {
  HandGesture,
  HandLandmarks,
  HandPoint,
  SingleHandTransform
} from '../main/ets/models/DomainModels';
import {
  HandLandmarkCoordinateMapper,
  HandLandmarkPreviewTransform
} from '../main/ets/services/HandLandmarkAnalyzer';
import { GestureInterpreter } from '../main/ets/services/GestureInterpreter';
import {
  NormalSkyGestureController,
  NormalSkyGestureUpdate
} from '../main/ets/services/NormalSkyGestureController';
import {
  NormalSkyViewState,
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';
import { NormalSkyViewStateService } from '../main/ets/services/NormalSkyViewStateService';

const TEST_SIZE: SkyMapSize = {
  widthPixels: 1024.0,
  heightPixels: 720.0
};

function point(x: number, y: number, confidence: number = 0.95): HandPoint {
  return {
    x: x,
    y: y,
    z: 0.0,
    confidence: confidence
  };
}

function put(points: HandPoint[], index: number, centerX: number, centerY: number,
  localX: number, localY: number, scale: number): void {
  points[index] = point(centerX + localX * scale, centerY + localY * scale);
}

/**
 * 构造测试用的稳定张掌。掌面几何严格使用 0、5、9、13、17，指尖只用于
 * 解释器的张掌/握拳分类，避免回归测试把两套职责混在一起。
 */
function openHand(trackingId: number, centerX: number, timestampMs: number,
  scale: number = 1.0): HandLandmarks {
  const points: HandPoint[] = [];
  for (let index: number = 0; index < 21; index++) {
    points.push(point(centerX, 0.58));
  }
  put(points, 0, centerX, 0.58, 0.0, 0.16, scale);
  put(points, 5, centerX, 0.58, -0.12, 0.0, scale);
  put(points, 9, centerX, 0.58, 0.0, -0.08, scale);
  put(points, 13, centerX, 0.58, 0.04, -0.04, scale);
  put(points, 17, centerX, 0.58, 0.08, -0.04, scale);
  const joints: number[] = [6, 10, 14, 18];
  const tips: number[] = [8, 12, 16, 20];
  const fingerX: number[] = [-0.10, -0.03, 0.04, 0.10];
  for (let index: number = 0; index < joints.length; index++) {
    put(points, joints[index], centerX, 0.58, fingerX[index], -0.14, scale);
    put(points, tips[index], centerX, 0.58, fingerX[index], -0.36, scale);
  }
  put(points, 4, centerX, 0.58, -0.20, -0.05, scale);
  return {
    trackingId: trackingId,
    points: points,
    confidence: 0.95,
    palmConfidence: 0.95,
    palmFacingConfidence: 0.95,
    timestampMs: timestampMs
  };
}

function pinchHand(trackingId: number, centerX: number, timestampMs: number): HandLandmarks {
  const hand: HandLandmarks = openHand(trackingId, centerX, timestampMs);
  hand.points[4] = point(centerX - 0.008, 0.30);
  hand.points[8] = point(centerX + 0.008, 0.30);
  return hand;
}

function fistHand(trackingId: number, centerX: number, timestampMs: number): HandLandmarks {
  const hand: HandLandmarks = openHand(trackingId, centerX, timestampMs);
  const joints: number[] = [6, 10, 14, 18];
  const tips: number[] = [8, 12, 16, 20];
  for (let index: number = 0; index < joints.length; index++) {
    hand.points[joints[index]] = point(centerX, 0.56);
    hand.points[tips[index]] = point(centerX, 0.68);
  }
  // 握拳同时满足“拇指靠近中指掌指关节”，用于验证握拳优先于捏合。
  hand.points[4] = point(centerX + 0.01, 0.57);
  hand.points[8] = point(centerX + 0.02, 0.58);
  hand.points[9] = point(centerX, 0.58);
  return hand;
}

function normalViewState(): NormalSkyViewState {
  const viewport: NormalSkyViewport = {
    centerRaHours: 8.0,
    centerDecDegrees: 25.0,
    fieldOfViewDegrees: 90.0,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
  return NormalSkyViewStateService.fromViewport(viewport);
}

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function mappedPoint(rotationDegrees: number, mirrored: boolean): HandPoint {
  const transform: HandLandmarkPreviewTransform = {
    mirrored: mirrored,
    rotationDegrees: rotationDegrees,
    cropLeft: 0.0,
    cropTop: 0.0,
    cropWidth: 1.0,
    cropHeight: 1.0,
    previewAspectRatio: 16.0 / 9.0
  };
  return HandLandmarkCoordinateMapper.mapPointToPreview(
    { x: 0.2, y: 0.3, z: -0.1, confidence: 0.91 }, transform);
}

export default function singleHandGestureAcceptanceTest(): void {
  describe('普通星图单掌三轴验收回归', () => {
    it('四方向旋转和镜像映射保持前摄坐标方向', 0, () => {
      const zero: HandPoint = mappedPoint(0.0, false);
      const quarter: HandPoint = mappedPoint(90.0, false);
      const half: HandPoint = mappedPoint(180.0, false);
      const threeQuarter: HandPoint = mappedPoint(270.0, false);
      const mirrored: HandPoint = mappedPoint(90.0, true);
      expect(closeTo(zero.x, 0.2, 0.000001) && closeTo(zero.y, 0.3, 0.000001)).assertTrue();
      expect(closeTo(quarter.x, 0.7, 0.000001) && closeTo(quarter.y, 0.2, 0.000001)).assertTrue();
      expect(closeTo(half.x, 0.8, 0.000001) && closeTo(half.y, 0.7, 0.000001)).assertTrue();
      expect(closeTo(threeQuarter.x, 0.3, 0.000001) &&
        closeTo(threeQuarter.y, 0.8, 0.000001)).assertTrue();
      expect(closeTo(mirrored.x, 0.3, 0.000001) && closeTo(mirrored.y, 0.2, 0.000001) &&
        closeTo(mirrored.z === undefined ? 0.0 : mirrored.z, -0.1, 0.000001)).assertTrue();
    });

    it('裁剪映射不会把 ROI 外的关键点伪装为有效坐标', 0, () => {
      const transform: HandLandmarkPreviewTransform = {
        mirrored: false,
        rotationDegrees: 0.0,
        cropLeft: 0.25,
        cropTop: 0.10,
        cropWidth: 0.50,
        cropHeight: 0.60,
        previewAspectRatio: 4.0 / 3.0
      };
      const mapped: HandPoint = HandLandmarkCoordinateMapper.mapPointToPreview(
        { x: 0.50, y: 0.40, z: 0.25, confidence: 0.88 }, transform);
      expect(closeTo(mapped.x, 0.50, 0.000001) && closeTo(mapped.y, 0.50, 0.000001) &&
        closeTo(mapped.z === undefined ? 0.0 : mapped.z, 0.25, 0.000001)).assertTrue();
      const outside: HandPoint = HandLandmarkCoordinateMapper.mapPointToPreview(
        { x: 0.0, y: 1.0, z: 0.1, confidence: 0.88 }, transform);
      expect(outside.x === 0.0 && outside.y === 1.0).assertTrue();
    });

    it('纯平移、纯旋转和纯缩放不会串扰其他轴', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const source: NormalSkyViewState = normalViewState();
      const translation: SingleHandTransform = {
        deltaX: 0.04,
        deltaY: -0.02,
        rotationDegrees: 0.0,
        scale: 1.0,
        anchorX: 0.55,
        anchorY: 0.45
      };
      const translated: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        source, TEST_SIZE, translation);
      const translatedViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(
        translated.viewState);
      expect(translated.translationChanged && !translated.rotationChanged &&
        !translated.scaleChanged).assertTrue();
      // 球面轨迹球平移会带来极小的局部滚转；验收门槛按计划限定在 2° 内。
      expect(Math.abs(translatedViewport.rotationDegrees) <= 2.0).assertTrue();
      expect(closeTo(translatedViewport.fieldOfViewDegrees, 90.0, 0.0001)).assertTrue();

      const rotated: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        source, TEST_SIZE, {
          deltaX: 0.0,
          deltaY: 0.0,
          rotationDegrees: 6.0,
          scale: 1.0,
          anchorX: 0.55,
          anchorY: 0.45
        });
      const rotatedViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(
        rotated.viewState);
      expect(!rotated.translationChanged && rotated.rotationChanged &&
        !rotated.scaleChanged).assertTrue();
      expect(closeTo(rotatedViewport.fieldOfViewDegrees, 90.0, 0.0001)).assertTrue();

      const scaled: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        source, TEST_SIZE, {
          deltaX: 0.0,
          deltaY: 0.0,
          rotationDegrees: 0.0,
          scale: 1.06,
          anchorX: 0.55,
          anchorY: 0.45
        });
      const scaledViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(
        scaled.viewState);
      expect(!scaled.translationChanged && !scaled.rotationChanged &&
        scaled.scaleChanged).assertTrue();
      expect(scaledViewport.fieldOfViewDegrees < 90.0).assertTrue();
      expect(Number.isFinite(scaledViewport.centerRaHours) &&
        Number.isFinite(scaledViewport.centerDecDegrees)).assertTrue();
    });

    it('纯旋转和缩放均保持掌心锚点天体位置', 0, () => {
      const controller: NormalSkyGestureController = new NormalSkyGestureController();
      const source: NormalSkyViewState = normalViewState();
      const anchorX: number = 690.0;
      const anchorY: number = 260.0;
      const sourceViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(source);
      const anchor = NormalSkyProjectionService.unproject(
        anchorX, anchorY, sourceViewport, TEST_SIZE);
      const rotated: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        source, TEST_SIZE, {
          deltaX: 0.0,
          deltaY: 0.0,
          rotationDegrees: 7.0,
          scale: 1.0,
          anchorX: anchorX / TEST_SIZE.widthPixels,
          anchorY: anchorY / TEST_SIZE.heightPixels
        });
      const rotatedProjection = NormalSkyProjectionService.project(
        anchor, NormalSkyViewStateService.snapshot(rotated.viewState), TEST_SIZE);
      expect(Math.sqrt(
        (rotatedProjection.xPixels - anchorX) * (rotatedProjection.xPixels - anchorX) +
        (rotatedProjection.yPixels - anchorY) * (rotatedProjection.yPixels - anchorY)) < 0.5).assertTrue();

      const scaled: NormalSkyGestureUpdate = controller.updateSingleHandTransform(
        source, TEST_SIZE, {
          deltaX: 0.0,
          deltaY: 0.0,
          rotationDegrees: 0.0,
          scale: 1.06,
          anchorX: anchorX / TEST_SIZE.widthPixels,
          anchorY: anchorY / TEST_SIZE.heightPixels
        });
      const scaledProjection = NormalSkyProjectionService.project(
        anchor, NormalSkyViewStateService.snapshot(scaled.viewState), TEST_SIZE);
      expect(Math.sqrt(
        (scaledProjection.xPixels - anchorX) * (scaledProjection.xPixels - anchorX) +
        (scaledProjection.yPixels - anchorY) * (scaledProjection.yPixels - anchorY)) < 0.5).assertTrue();
    });

    it('连续 20 次捏合每次闭合只选择一次', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      let selections: number = 0;
      for (let cycle: number = 0; cycle < 20; cycle++) {
        const base: number = 1000.0 + cycle * 1000.0;
        interpreter.interpret([openHand(1, 0.5, base)], base);
        const selected = interpreter.interpret([pinchHand(1, 0.5, base + 100.0)], base + 100.0);
        const held = interpreter.interpret([pinchHand(1, 0.5, base + 150.0)], base + 150.0);
        interpreter.interpret([openHand(1, 0.5, base + 250.0)], base + 250.0);
        if (selected.gesture === HandGesture.PINCH_SELECT) selections++;
        expect(held.gesture).assertEqual(HandGesture.NONE);
      }
      expect(selections).assertEqual(20);
    });

    it('连续 20 次握拳每次保持只复位一次', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      let resets: number = 0;
      for (let cycle: number = 0; cycle < 20; cycle++) {
        const base: number = 2000.0 + cycle * 1200.0;
        interpreter.interpret([openHand(2, 0.5, base)], base);
        interpreter.interpret([fistHand(2, 0.5, base + 100.0)], base + 100.0);
        const reset = interpreter.interpret([fistHand(2, 0.5, base + 650.0)], base + 650.0);
        const held = interpreter.interpret([fistHand(2, 0.5, base + 750.0)], base + 750.0);
        interpreter.interpret([openHand(2, 0.5, base + 850.0)], base + 850.0);
        if (reset.gesture === HandGesture.FIST_RESET) resets++;
        expect(held.gesture).assertEqual(HandGesture.NONE);
      }
      expect(resets).assertEqual(20);
    });
  });
}

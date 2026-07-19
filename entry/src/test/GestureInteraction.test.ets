import { describe, expect, it } from '@ohos/hypium';
import {
  HandGesture,
  HandLandmarks,
  HandPoint
} from '../main/ets/models/DomainModels';
import { GestureInterpreter } from '../main/ets/services/GestureInterpreter';
import { HandLandmarkCoordinateMapper } from '../main/ets/services/HandLandmarkAnalyzer';

function makePoint(x: number, y: number, confidence: number, z: number = 0.0): HandPoint {
  return { x: x, y: y, z: z, confidence: confidence };
}

function placePoint(points: HandPoint[], index: number, centerX: number, centerY: number,
  localX: number, localY: number, size: number, rotationDegrees: number,
  confidence: number): void {
  const radians: number = rotationDegrees * Math.PI / 180.0;
  const scaledX: number = localX * size;
  const scaledY: number = localY * size;
  points[index] = makePoint(
    centerX + scaledX * Math.cos(radians) - scaledY * Math.sin(radians),
    centerY + scaledX * Math.sin(radians) + scaledY * Math.cos(radians),
    confidence);
}

function createOpenHand(trackingId: number, centerX: number, centerY: number,
  palmSize: number, rotationDegrees: number, confidence: number,
  timestampMs: number): HandLandmarks {
  const points: HandPoint[] = [];
  for (let index: number = 0; index < 21; index++) {
    points.push(makePoint(centerX, centerY, confidence));
  }

  // 掌心基准点 0、5、9、13、17 的局部坐标总和为零，便于精确构造平移测试。
  placePoint(points, 0, centerX, centerY, 0.0, 0.16, palmSize, rotationDegrees, confidence);
  placePoint(points, 5, centerX, centerY, -0.12, 0.0, palmSize, rotationDegrees, confidence);
  placePoint(points, 9, centerX, centerY, 0.0, -0.08, palmSize, rotationDegrees, confidence);
  placePoint(points, 13, centerX, centerY, 0.04, -0.04, palmSize, rotationDegrees, confidence);
  placePoint(points, 17, centerX, centerY, 0.08, -0.04, palmSize, rotationDegrees, confidence);

  const jointIndices: number[] = [6, 10, 14, 18];
  const tipIndices: number[] = [8, 12, 16, 20];
  const fingerX: number[] = [-0.10, -0.03, 0.04, 0.10];
  for (let index: number = 0; index < jointIndices.length; index++) {
    placePoint(points, jointIndices[index], centerX, centerY,
      fingerX[index], -0.14, palmSize, rotationDegrees, confidence);
    placePoint(points, tipIndices[index], centerX, centerY,
      fingerX[index], -0.36, palmSize, rotationDegrees, confidence);
  }
  placePoint(points, 4, centerX, centerY, -0.20, -0.05,
    palmSize, rotationDegrees, confidence);
  return {
    trackingId: trackingId,
    points: points,
    confidence: confidence,
    palmConfidence: confidence,
    palmFacingConfidence: 0.95,
    timestampMs: timestampMs
  };
}

function createOpenHandInPreview(trackingId: number, centerX: number, centerY: number,
  palmSize: number, rotationDegrees: number, confidence: number,
  timestampMs: number, previewAspectRatio: number): HandLandmarks {
  const hand: HandLandmarks = createOpenHand(
    trackingId, centerX, centerY, palmSize, rotationDegrees, confidence, timestampMs);
  for (let index: number = 0; index < hand.points.length; index++) {
    hand.points[index].x =
      centerX + (hand.points[index].x - centerX) / previewAspectRatio;
  }
  hand.coordinateAspectRatio = previewAspectRatio;
  return hand;
}

function createPinchHand(trackingId: number, centerX: number,
  timestampMs: number, palmSize: number = 1.0,
  pinchRatio: number = 0.10): HandLandmarks {
  const hand: HandLandmarks = createOpenHand(
    trackingId, centerX, 0.58, palmSize, 0.0, 0.95, timestampMs);
  const palmWidth: number = pointDistance(hand.points[5], hand.points[17]);
  const palmLength: number = pointDistance(hand.points[0], hand.points[9]);
  const normalizedPalmSize: number = Math.sqrt(palmWidth * palmLength);
  const halfPinchDistance: number = normalizedPalmSize * pinchRatio / 2.0;
  hand.points[4] = makePoint(centerX - halfPinchDistance, 0.30, 0.95);
  hand.points[8] = makePoint(centerX + halfPinchDistance, 0.30, 0.95);
  return hand;
}

function pointDistance(first: HandPoint, second: HandPoint): number {
  const deltaX: number = first.x - second.x;
  const deltaY: number = first.y - second.y;
  return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
}

function createFistHand(trackingId: number, centerX: number,
  timestampMs: number): HandLandmarks {
  const hand: HandLandmarks = createOpenHand(
    trackingId, centerX, 0.58, 1.0, 0.0, 0.95, timestampMs);
  const joints: number[] = [6, 10, 14, 18];
  const tips: number[] = [8, 12, 16, 20];
  for (let index: number = 0; index < joints.length; index++) {
    hand.points[joints[index]] = makePoint(centerX, 0.56, 0.95);
    hand.points[tips[index]] = makePoint(centerX, 0.68, 0.95);
  }
  // 握拳时拇指靠近中指掌指关节，同时也满足“捏合距离近”，用于验证握拳优先级。
  hand.points[4] = makePoint(centerX + 0.01, 0.57, 0.95);
  hand.points[8] = makePoint(centerX + 0.02, 0.58, 0.95);
  hand.points[9] = makePoint(centerX, 0.58, 0.95);
  return hand;
}

export default function gestureInteractionTest(): void {
  describe('普通星图单掌手势接口', () => {
    it('张掌连续两帧后同时输出平移旋转和前后缩放', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const first = interpreter.interpret([
        createOpenHand(1, 0.42, 0.58, 1.0, 0.0, 0.95, 1000)
      ], 1000);
      const second = interpreter.interpret([
        createOpenHand(1, 0.49, 0.54, 1.25, 12.0, 0.95, 1080)
      ], 1080);
      expect(first.gesture).assertEqual(HandGesture.NONE);
      expect(second.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(second.transform.deltaX > 0.02).assertTrue();
      expect(second.transform.deltaY < -0.01).assertTrue();
      expect(second.transform.rotationDegrees > 2.0).assertTrue();
      expect(second.transform.rotationDegrees <= 8.0).assertTrue();
      expect(second.transform.scale > 1.02 && second.transform.scale <= 1.08).assertTrue();
      expect(Math.abs(second.transform.anchorX - 0.49) < 0.001).assertTrue();
    });

    it('只采用置信度最高的一只手', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHand(10, 0.20, 0.58, 1.0, 0.0, 0.70, 1000),
        createOpenHand(20, 0.60, 0.58, 1.0, 0.0, 0.96, 1000)
      ], 1000);
      const frame = interpreter.interpret([
        createOpenHand(10, 0.80, 0.58, 1.0, 0.0, 0.70, 1080),
        createOpenHand(20, 0.64, 0.58, 1.0, 0.0, 0.96, 1080)
      ], 1080);
      expect(frame.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(frame.transform.deltaX > 0.015 && frame.transform.deltaX < 0.05).assertTrue();
    });

    it('三轴分别应用死区且不会互相阻塞', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHand(11, 0.40, 0.58, 1.0, 0.0, 0.95, 1000)
      ], 1000);
      const frame = interpreter.interpret([
        createOpenHand(11, 0.405, 0.58, 1.02, 1.0, 0.95, 1080)
      ], 1080);
      expect(frame.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(frame.transform.deltaX).assertEqual(0.0);
      expect(frame.transform.rotationDegrees).assertEqual(0.0);
      expect(frame.transform.scale).assertEqual(1.0);
    });

    it('掌面角度跨正负一百八十度时采用最短旋转', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHand(12, 0.50, 0.58, 1.0, 175.0, 0.95, 1000)
      ], 1000);
      const frame = interpreter.interpret([
        createOpenHand(12, 0.50, 0.58, 1.0, -175.0, 0.95, 1080)
      ], 1080);
      expect(frame.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(frame.transform.rotationDegrees > 0.0 &&
        frame.transform.rotationDegrees <= 8.0).assertTrue();
    });

    it('长方形前摄预览中纯转掌不会被误判成缩放', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHandInPreview(13, 0.50, 0.58, 1.0, 0.0, 0.95, 1000, 1.6)
      ], 1000);
      const frame = interpreter.interpret([
        createOpenHandInPreview(13, 0.50, 0.58, 1.0, 20.0, 0.95, 1080, 1.6)
      ], 1080);
      expect(frame.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(frame.transform.rotationDegrees > 2.0).assertTrue();
      expect(frame.transform.scale).assertEqual(1.0);
      expect(frame.transform.deltaX).assertEqual(0.0);
      expect(frame.transform.deltaY).assertEqual(0.0);
    });

    it('握拳优先于捏合并且保持只复位一次', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const first = interpreter.interpret([createFistHand(2, 0.50, 1000)], 1000);
      const reset = interpreter.interpret([createFistHand(2, 0.50, 1550)], 1550);
      const held = interpreter.interpret([createFistHand(2, 0.50, 1700)], 1700);
      expect(first.gesture).assertEqual(HandGesture.NONE);
      expect(reset.gesture).assertEqual(HandGesture.FIST_RESET);
      expect(held.gesture).assertEqual(HandGesture.NONE);
    });

    it('手部远近变化不会改变握拳判定', 0, () => {
      const smallHandInterpreter: GestureInterpreter = new GestureInterpreter();
      const largeHandInterpreter: GestureInterpreter = new GestureInterpreter();
      const smallFist: HandLandmarks = createFistHand(21, 0.50, 1000);
      const largeFist: HandLandmarks = createFistHand(22, 0.50, 1000);
      const smallCenterX: number = 0.50;
      const smallCenterY: number = 0.58;
      for (let index: number = 0; index < smallFist.points.length; index++) {
        smallFist.points[index].x =
          smallCenterX + (smallFist.points[index].x - smallCenterX) * 0.45;
        smallFist.points[index].y =
          smallCenterY + (smallFist.points[index].y - smallCenterY) * 0.45;
        largeFist.points[index].x =
          smallCenterX + (largeFist.points[index].x - smallCenterX) * 1.80;
        largeFist.points[index].y =
          smallCenterY + (largeFist.points[index].y - smallCenterY) * 1.80;
      }
      smallHandInterpreter.interpret([smallFist], 1000);
      largeHandInterpreter.interpret([largeFist], 1000);
      const smallReset = smallHandInterpreter.interpret([smallFist], 1550);
      const largeReset = largeHandInterpreter.interpret([largeFist], 1550);
      expect(smallReset.gesture).assertEqual(HandGesture.FIST_RESET);
      expect(largeReset.gesture).assertEqual(HandGesture.FIST_RESET);
    });

    it('捏合只在闭合边沿触发并遵守冷却时间', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const first = interpreter.interpret([createPinchHand(3, 0.5, 1000)], 1000);
      const held = interpreter.interpret([createPinchHand(3, 0.5, 1050)], 1050);
      interpreter.interpret([
        createOpenHand(3, 0.5, 0.58, 1.0, 0.0, 0.95, 1100)
      ], 1100);
      const cooldown = interpreter.interpret([createPinchHand(3, 0.5, 1200)], 1200);
      expect(first.gesture).assertEqual(HandGesture.PINCH_SELECT);
      expect(held.gesture).assertEqual(HandGesture.NONE);
      expect(cooldown.gesture).assertEqual(HandGesture.NONE);
    });

    it('小手和大手使用相同掌面比例都能触发捏合', 0, () => {
      const smallHandInterpreter: GestureInterpreter = new GestureInterpreter();
      const largeHandInterpreter: GestureInterpreter = new GestureInterpreter();
      const smallHand = smallHandInterpreter.interpret([
        createPinchHand(31, 0.5, 1000, 0.45, 0.28)
      ], 1000);
      const largeHand = largeHandInterpreter.interpret([
        createPinchHand(32, 0.5, 1000, 1.80, 0.28)
      ], 1000);
      expect(smallHand.gesture).assertEqual(HandGesture.PINCH_SELECT);
      expect(largeHand.gesture).assertEqual(HandGesture.PINCH_SELECT);
    });

    it('捏合阈值附近抖动不会重复触发选择', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const closed = interpreter.interpret([
        createPinchHand(33, 0.5, 1000, 1.0, 0.30)
      ], 1000);
      const jitterWhileClosed = interpreter.interpret([
        createPinchHand(33, 0.5, 1050, 1.0, 0.37)
      ], 1050);
      interpreter.interpret([
        createPinchHand(33, 0.5, 1100, 1.0, 0.45)
      ], 1100);
      const jitterAfterRelease = interpreter.interpret([
        createPinchHand(33, 0.5, 1500, 1.0, 0.37)
      ], 1500);
      const closedAgain = interpreter.interpret([
        createPinchHand(33, 0.5, 1600, 1.0, 0.30)
      ], 1600);
      expect(closed.gesture).assertEqual(HandGesture.PINCH_SELECT);
      expect(jitterWhileClosed.gesture).assertEqual(HandGesture.NONE);
      expect(jitterAfterRelease.gesture).assertEqual(HandGesture.NONE);
      expect(closedAgain.gesture).assertEqual(HandGesture.PINCH_SELECT);
    });

    it('短时丢手保留事务而超时丢手会重建基准', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHand(4, 0.35, 0.58, 1.0, 0.0, 0.95, 1000)
      ], 1000);
      interpreter.interpret([], 1080);
      const shortRecovery = interpreter.interpret([
        createOpenHand(4, 0.42, 0.58, 1.0, 0.0, 0.95, 1120)
      ], 1120);
      interpreter.interpret([], 1300);
      const longRecovery = interpreter.interpret([
        createOpenHand(4, 0.70, 0.58, 1.0, 0.0, 0.95, 1310)
      ], 1310);
      expect(shortRecovery.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(shortRecovery.transform.deltaX > 0.02).assertTrue();
      expect(longRecovery.gesture).assertEqual(HandGesture.NONE);
    });

    it('跟踪 ID 变化不会继承上一只手的位置', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createOpenHand(5, 0.30, 0.58, 1.0, 0.0, 0.95, 1000)
      ], 1000);
      const changed = interpreter.interpret([
        createOpenHand(6, 0.75, 0.58, 1.0, 0.0, 0.95, 1080)
      ], 1080);
      expect(changed.gesture).assertEqual(HandGesture.NONE);
    });

    it('掌面侧转时暂停尺寸缩放但保留平移', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const first: HandLandmarks = createOpenHand(
        7, 0.40, 0.58, 1.0, 0.0, 0.95, 1000);
      const second: HandLandmarks = createOpenHand(
        7, 0.45, 0.58, 1.4, 0.0, 0.95, 1080);
      first.palmFacingConfidence = 0.1;
      second.palmFacingConfidence = 0.1;
      interpreter.interpret([first], 1000);
      const frame = interpreter.interpret([second], 1080);
      expect(frame.gesture).assertEqual(HandGesture.SINGLE_HAND_TRANSFORM);
      expect(frame.transform.deltaX > 0.01).assertTrue();
      expect(frame.transform.scale).assertEqual(1.0);
    });

    it('前摄旋转与镜像统一转换到预览坐标', 0, () => {
      const mapped: HandPoint = HandLandmarkCoordinateMapper.mapPoint(
        { x: 0.2, y: 0.3, z: -0.1, confidence: 0.9 }, true, 90);
      expect(Math.abs(mapped.x - 0.3) < 0.0001).assertTrue();
      expect(Math.abs(mapped.y - 0.2) < 0.0001).assertTrue();
      expect(mapped.confidence).assertEqual(0.9);
    });
  });
}

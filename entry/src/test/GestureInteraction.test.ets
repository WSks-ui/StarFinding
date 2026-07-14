import { describe, expect, it } from '@ohos/hypium';
import {
  HandGesture,
  HandLandmarks,
  HandPoint
} from '../main/ets/models/DomainModels';
import { GestureInterpreter } from '../main/ets/services/GestureInterpreter';
import { HandLandmarkCoordinateMapper } from '../main/ets/services/HandLandmarkAnalyzer';

function createHand(trackingId: number, centerX: number, centerY: number,
  openPalm: boolean, timestampMs: number): HandLandmarks {
  const points: HandPoint[] = [];
  for (let index: number = 0; index < 21; index++) {
    points.push({ x: centerX, y: centerY, confidence: 0.95 });
  }
  points[0] = { x: centerX, y: centerY + 0.20, confidence: 0.95 };
  const joints: number[] = [6, 10, 14, 18];
  const tips: number[] = [8, 12, 16, 20];
  for (let index: number = 0; index < joints.length; index++) {
    points[joints[index]] = { x: centerX, y: centerY, confidence: 0.95 };
    points[tips[index]] = {
      x: centerX,
      y: openPalm ? centerY - 0.28 : centerY + 0.08,
      confidence: 0.95
    };
  }
  points[4] = {
    x: openPalm ? centerX - 0.18 : centerX + 0.02,
    y: centerY,
    confidence: 0.95
  };
  points[9] = { x: centerX, y: centerY, confidence: 0.95 };
  return { trackingId: trackingId, points: points, confidence: 0.95, timestampMs: timestampMs };
}

function createPinchHand(trackingId: number, centerX: number, timestampMs: number): HandLandmarks {
  const hand: HandLandmarks = createHand(trackingId, centerX, 0.58, true, timestampMs);
  hand.points[4] = { x: centerX - 0.01, y: 0.30, confidence: 0.95 };
  hand.points[8] = { x: centerX + 0.01, y: 0.30, confidence: 0.95 };
  return hand;
}

export default function gestureInteractionTest(): void {
  describe('普通星图手势接口', () => {
    it('双掌距离变化解释为锚点缩放', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([
        createHand(1, 0.38, 0.58, true, 1000),
        createHand(2, 0.62, 0.58, true, 1000)
      ], 1000);
      const frame = interpreter.interpret([
        createHand(1, 0.28, 0.58, true, 1100),
        createHand(2, 0.72, 0.58, true, 1100)
      ], 1100);
      expect(frame.gesture).assertEqual(HandGesture.ROTATE_SCALE);
      expect(frame.scale > 1.2).assertTrue();
      expect(Math.abs(frame.selectX - 0.5) < 0.01).assertTrue();
    });

    it('捏合只在闭合边沿触发并遵守冷却时间', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      const first = interpreter.interpret([createPinchHand(3, 0.5, 1000)], 1000);
      const held = interpreter.interpret([createPinchHand(3, 0.5, 1050)], 1050);
      interpreter.interpret([createHand(3, 0.5, 0.58, true, 1100)], 1100);
      const cooldown = interpreter.interpret([createPinchHand(3, 0.5, 1200)], 1200);
      expect(first.gesture).assertEqual(HandGesture.PINCH_SELECT);
      expect(held.gesture).assertEqual(HandGesture.NONE);
      expect(cooldown.gesture).assertEqual(HandGesture.NONE);
    });

    it('跟踪 ID 变化或丢帧后不会产生跳跃拖拽', 0, () => {
      const interpreter: GestureInterpreter = new GestureInterpreter();
      interpreter.interpret([createHand(4, 0.35, 0.58, true, 1000)], 1000);
      const changed = interpreter.interpret([createHand(5, 0.70, 0.58, true, 1100)], 1100);
      interpreter.interpret([], 1200);
      const recovered = interpreter.interpret([createHand(5, 0.25, 0.58, true, 1300)], 1300);
      expect(changed.gesture).assertEqual(HandGesture.NONE);
      expect(recovered.gesture).assertEqual(HandGesture.NONE);
    });

    it('前摄旋转与镜像统一转换到预览坐标', 0, () => {
      const mapped: HandPoint = HandLandmarkCoordinateMapper.mapPoint(
        { x: 0.2, y: 0.3, confidence: 0.9 }, true, 90);
      expect(Math.abs(mapped.x - 0.3) < 0.0001).assertTrue();
      expect(Math.abs(mapped.y - 0.2) < 0.0001).assertTrue();
      expect(mapped.confidence).assertEqual(0.9);
    });
  });
}

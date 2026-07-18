import { describe, expect, it } from '@ohos/hypium';
import { ObserverLocationPolicy } from '../main/ets/services/ObserverLocationPolicy';

export default function observerLocationPolicyTest(): void {
  describe('最近位置快速路径', () => {
    const nowMs: number = Date.UTC(2026, 6, 18, 5, 0, 0);

    it('二十四小时内且精度合格的位置可以立即使用', 0, () => {
      expect(ObserverLocationPolicy.isUsable(
        nowMs, nowMs - 23 * 60 * 60 * 1000, 4999)).assertTrue();
    });

    it('超过二十四小时或精度差于五公里时拒绝快速使用', 0, () => {
      expect(ObserverLocationPolicy.isUsable(
        nowMs, nowMs - 24 * 60 * 60 * 1000 - 1, 100)).assertFalse();
      expect(ObserverLocationPolicy.isUsable(
        nowMs, nowMs - 60 * 1000, 5001)).assertFalse();
    });

    it('明显来自未来或包含非有限数值的位置被拒绝', 0, () => {
      expect(ObserverLocationPolicy.isUsable(
        nowMs, nowMs + 6 * 60 * 1000, 20)).assertFalse();
      expect(ObserverLocationPolicy.isUsable(
        nowMs, Number.NaN, 20)).assertFalse();
    });
  });
}

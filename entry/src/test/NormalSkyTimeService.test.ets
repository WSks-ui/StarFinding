import { describe, expect, it } from '@ohos/hypium';
import {
  NormalSkyPlaybackSpeed,
  NormalSkyTimeMode,
  NormalSkyTimeState
} from '../main/ets/models/NormalSkyModels';
import { NormalSkyTimeService } from '../main/ets/services/NormalSkyTimeService';

export default function normalSkyTimeServiceTest(): void {
  describe('普通星图时间状态机', () => {
    it('实时状态始终跟随真实当前时间', 0, () => {
      const nowMs: number = Date.UTC(2026, 6, 15, 12, 0, 0);
      const state: NormalSkyTimeState = NormalSkyTimeService.tick(
        NormalSkyTimeService.realtime(nowMs - 5000), 5000, nowMs);
      expect(state.mode).assertEqual(NormalSkyTimeMode.REALTIME);
      expect(state.timestampMs).assertEqual(nowMs);
      expect(state.playing).assertFalse();
    });

    it('一小时每秒播放按真实间隔推进', 0, () => {
      const startMs: number = Date.UTC(2026, 6, 15, 12, 0, 0);
      const state: NormalSkyTimeState = NormalSkyTimeService.tick(
        NormalSkyTimeService.simulated(
          startMs, NormalSkyPlaybackSpeed.HOUR_PER_SECOND, true), 500, startMs);
      expect(state.timestampMs).assertEqual(startMs + 30 * 60 * 1000);
      expect(state.mode).assertEqual(NormalSkyTimeMode.SIMULATED);
      expect(state.playing).assertTrue();
    });

    it('模拟时间限制在 1900 至 2100 并在上限暂停', 0, () => {
      const state: NormalSkyTimeState = NormalSkyTimeService.tick(
        NormalSkyTimeService.simulated(
          NormalSkyTimeService.MAX_TIMESTAMP_MS - 1000,
          NormalSkyPlaybackSpeed.WEEK_PER_SECOND, true), 1000,
        NormalSkyTimeService.MAX_TIMESTAMP_MS);
      expect(state.timestampMs).assertEqual(NormalSkyTimeService.MAX_TIMESTAMP_MS);
      expect(state.playing).assertFalse();
      expect(NormalSkyTimeService.selectTime(state, Date.UTC(1800, 0, 1)).timestampMs)
        .assertEqual(NormalSkyTimeService.MIN_TIMESTAMP_MS);
    });
  });
}

import {
  NormalSkyPlaybackSpeed,
  NormalSkyTimeMode,
  NormalSkyTimeState
} from '../models/NormalSkyModels';

/** 普通星图独立时间状态机。AR 和设备链路不得消费 SIMULATED 时间。 */
export class NormalSkyTimeService {
  static readonly MIN_TIMESTAMP_MS: number = Date.UTC(1900, 0, 1, 0, 0, 0);
  static readonly MAX_TIMESTAMP_MS: number = Date.UTC(2100, 11, 31, 23, 59, 59);

  static realtime(nowMs: number = Date.now()): NormalSkyTimeState {
    return {
      mode: NormalSkyTimeMode.REALTIME,
      timestampMs: NormalSkyTimeService.clampTimestamp(nowMs),
      playing: false,
      speed: NormalSkyPlaybackSpeed.HOUR_PER_SECOND
    };
  }

  static simulated(timestampMs: number,
    speed: NormalSkyPlaybackSpeed = NormalSkyPlaybackSpeed.HOUR_PER_SECOND,
    playing: boolean = false): NormalSkyTimeState {
    return {
      mode: NormalSkyTimeMode.SIMULATED,
      timestampMs: NormalSkyTimeService.clampTimestamp(timestampMs),
      playing: playing,
      speed: speed
    };
  }

  static tick(state: NormalSkyTimeState, elapsedRealMs: number,
    nowMs: number = Date.now()): NormalSkyTimeState {
    if (state.mode === NormalSkyTimeMode.REALTIME) {
      return NormalSkyTimeService.realtime(nowMs);
    }
    if (!state.playing || !Number.isFinite(elapsedRealMs) || elapsedRealMs <= 0.0) {
      return NormalSkyTimeService.simulated(state.timestampMs, state.speed, state.playing);
    }
    const candidate: number = state.timestampMs + elapsedRealMs * Number(state.speed);
    const clamped: number = NormalSkyTimeService.clampTimestamp(candidate);
    return NormalSkyTimeService.simulated(clamped, state.speed,
      clamped < NormalSkyTimeService.MAX_TIMESTAMP_MS);
  }

  static selectTime(state: NormalSkyTimeState, timestampMs: number): NormalSkyTimeState {
    return NormalSkyTimeService.simulated(timestampMs, state.speed, false);
  }

  static togglePlayback(state: NormalSkyTimeState): NormalSkyTimeState {
    if (state.mode === NormalSkyTimeMode.REALTIME) {
      return NormalSkyTimeService.simulated(state.timestampMs, state.speed, true);
    }
    return NormalSkyTimeService.simulated(state.timestampMs, state.speed, !state.playing);
  }

  static setSpeed(state: NormalSkyTimeState,
    speed: NormalSkyPlaybackSpeed): NormalSkyTimeState {
    return NormalSkyTimeService.simulated(state.timestampMs, speed, state.playing);
  }

  private static clampTimestamp(timestampMs: number): number {
    if (!Number.isFinite(timestampMs)) return Date.now();
    return Math.max(NormalSkyTimeService.MIN_TIMESTAMP_MS,
      Math.min(NormalSkyTimeService.MAX_TIMESTAMP_MS, timestampMs));
  }
}

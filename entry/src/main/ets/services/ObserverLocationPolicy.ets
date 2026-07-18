/** 最近位置快速路径的纯规则，独立测试时间边界和精度边界。 */
export class ObserverLocationPolicy {
  static readonly MAX_AGE_MS: number = 24 * 60 * 60 * 1000;
  static readonly MAX_ACCURACY_METERS: number = 5000;
  private static readonly MAX_FUTURE_OFFSET_MS: number = 5 * 60 * 1000;

  static isUsable(nowMs: number, locationTimestampMs: number, accuracyMeters: number): boolean {
    if (!Number.isFinite(nowMs) || !Number.isFinite(locationTimestampMs) ||
      !Number.isFinite(accuracyMeters) || accuracyMeters < 0 ||
      accuracyMeters > ObserverLocationPolicy.MAX_ACCURACY_METERS) {
      return false;
    }
    const ageMs: number = nowMs - locationTimestampMs;
    return ageMs >= -ObserverLocationPolicy.MAX_FUTURE_OFFSET_MS &&
      ageMs <= ObserverLocationPolicy.MAX_AGE_MS;
  }
}

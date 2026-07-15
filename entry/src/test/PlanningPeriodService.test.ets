import { describe, expect, it } from '@ohos/hypium';
import {
  ObservationNightPeriod,
  ObservationNightSelection
} from '../main/ets/models/DomainModels';
import { PlanningPeriodService } from '../main/ets/services/PlanningPeriodService';

const CHINA_TIMEZONE_OFFSET_MINUTES: number = 480;
const ONE_DAY_MS: number = 24 * 60 * 60 * 1000;

function resolveChinaPeriod(localYear: number, localMonth: number, localDay: number,
  localHour: number, localMinute: number, dayOffset: number): ObservationNightPeriod {
  const utcTimestampMs: number = Date.UTC(
    localYear, localMonth, localDay, localHour - 8, localMinute, 0, 0);
  return PlanningPeriodService.resolveWithOffset(
    utcTimestampMs, dayOffset, CHINA_TIMEZONE_OFFSET_MINUTES);
}

export default function planningPeriodServiceTest(): void {
  describe('设备时区观测夜', () => {
    it('中午前仍归入前一日开始的今晚', 0, () => {
      const period: ObservationNightPeriod = resolveChinaPeriod(2026, 6, 16, 11, 59, 0);
      expect(period.startAtMs).assertEqual(Date.UTC(2026, 6, 15, 4, 0, 0));
      expect(period.endAtMs).assertEqual(Date.UTC(2026, 6, 16, 4, 0, 0));
      expect(period.selection).assertEqual(ObservationNightSelection.TONIGHT);
    });

    it('中午整点切换到当日开始的今晚', 0, () => {
      const period: ObservationNightPeriod = resolveChinaPeriod(2026, 6, 16, 12, 0, 0);
      expect(period.startAtMs).assertEqual(Date.UTC(2026, 6, 16, 4, 0, 0));
      expect(period.endAtMs).assertEqual(Date.UTC(2026, 6, 17, 4, 0, 0));
    });

    it('中午后保持当日中午至次日中午', 0, () => {
      const period: ObservationNightPeriod = resolveChinaPeriod(2026, 6, 16, 23, 30, 0);
      expect(period.startAtMs).assertEqual(Date.UTC(2026, 6, 16, 4, 0, 0));
      expect(period.endAtMs - period.startAtMs).assertEqual(ONE_DAY_MS);
      expect(period.timezoneOffsetMinutes).assertEqual(CHINA_TIMEZONE_OFFSET_MINUTES);
    });

    it('明晚相对今晚整体顺延二十四小时', 0, () => {
      const tonight: ObservationNightPeriod = resolveChinaPeriod(2026, 6, 16, 18, 0, 0);
      const tomorrow: ObservationNightPeriod = resolveChinaPeriod(2026, 6, 16, 18, 0, 1);
      expect(tomorrow.startAtMs - tonight.startAtMs).assertEqual(ONE_DAY_MS);
      expect(tomorrow.endAtMs - tonight.endAtMs).assertEqual(ONE_DAY_MS);
      expect(tomorrow.selection).assertEqual(ObservationNightSelection.TOMORROW);
    });

    it('跨月时仍保持连续观测夜', 0, () => {
      const tomorrow: ObservationNightPeriod = resolveChinaPeriod(2026, 0, 31, 20, 0, 1);
      expect(tomorrow.startAtMs).assertEqual(Date.UTC(2026, 1, 1, 4, 0, 0));
      expect(tomorrow.endAtMs).assertEqual(Date.UTC(2026, 1, 2, 4, 0, 0));
    });

    it('跨年时仍保持连续观测夜', 0, () => {
      const tomorrow: ObservationNightPeriod = resolveChinaPeriod(2026, 11, 31, 20, 0, 1);
      expect(tomorrow.startAtMs).assertEqual(Date.UTC(2027, 0, 1, 4, 0, 0));
      expect(tomorrow.endAtMs).assertEqual(Date.UTC(2027, 0, 2, 4, 0, 0));
    });
  });
}

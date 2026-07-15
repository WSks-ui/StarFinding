import {
  ObservationNightPeriod,
  ObservationNightSelection
} from '../models/DomainModels';

const MIN_TIMEZONE_OFFSET_MINUTES: number = -18 * 60;
const MAX_TIMEZONE_OFFSET_MINUTES: number = 18 * 60;
const MINUTES_PER_DAY: number = 24 * 60;
const MILLISECONDS_PER_MINUTE: number = 60000;

/** 生成与硬件、网络和 UI 无关的观测夜时间范围。 */
export class PlanningPeriodService {
  static resolve(nowMs: number, dayOffset: number): ObservationNightPeriod {
    const deviceOffsetMinutes: number = -new Date(nowMs).getTimezoneOffset();
    return PlanningPeriodService.resolveWithOffset(nowMs, dayOffset, deviceOffsetMinutes);
  }

  /**
   * 显式时区偏移版本用于固定输入测试。比赛主场景在中国，不跨夏令时；若未来支持跨时区城市搜索，
   * 应由地点时区数据库提供每个边界时刻的实际偏移，不能继续复用设备当前偏移。
   */
  static resolveWithOffset(nowMs: number, dayOffset: number,
    timezoneOffsetMinutes: number): ObservationNightPeriod {
    PlanningPeriodService.validateInput(nowMs, dayOffset, timezoneOffsetMinutes);
    const localNowMs: number = nowMs + timezoneOffsetMinutes * MILLISECONDS_PER_MINUTE;
    const localNow: Date = new Date(localNowMs);
    let localDayStartUtcMs: number = Date.UTC(
      localNow.getUTCFullYear(), localNow.getUTCMonth(), localNow.getUTCDate(), 12, 0, 0, 0);
    if (localNow.getUTCHours() < 12) {
      localDayStartUtcMs -= MINUTES_PER_DAY * MILLISECONDS_PER_MINUTE;
    }
    localDayStartUtcMs += dayOffset * MINUTES_PER_DAY * MILLISECONDS_PER_MINUTE;
    const startAtMs: number = localDayStartUtcMs - timezoneOffsetMinutes * MILLISECONDS_PER_MINUTE;
    return {
      startAtMs: startAtMs,
      endAtMs: startAtMs + MINUTES_PER_DAY * MILLISECONDS_PER_MINUTE,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      selection: dayOffset === 0 ? ObservationNightSelection.TONIGHT : ObservationNightSelection.TOMORROW
    };
  }

  private static validateInput(nowMs: number, dayOffset: number, timezoneOffsetMinutes: number): void {
    if (!Number.isFinite(nowMs)) throw new Error('规划当前时间必须是有限数值');
    if (!Number.isInteger(dayOffset) || dayOffset < 0 || dayOffset > 1) {
      throw new Error('规划日期仅支持今晚或明晚');
    }
    if (!Number.isInteger(timezoneOffsetMinutes) ||
      timezoneOffsetMinutes < MIN_TIMEZONE_OFFSET_MINUTES ||
      timezoneOffsetMinutes > MAX_TIMEZONE_OFFSET_MINUTES) {
      throw new Error('设备时区偏移超出合法范围');
    }
  }
}

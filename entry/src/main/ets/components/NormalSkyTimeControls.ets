import {
  NormalSkyPlaybackSpeed,
  NormalSkyTimeMode,
  NormalSkyTimeState
} from '../models/NormalSkyModels';
import { NormalSkyTimeService } from '../services/NormalSkyTimeService';
import { MotionTokens } from '../utils/MotionTokens';

/** 普通星图时间胶囊；日期时间选择使用 API 22 的 UIContext DatePickerDialog。 */
@Component
export struct NormalSkyTimeControls {
  @Prop timeState: NormalSkyTimeState = NormalSkyTimeService.realtime();
  @Prop viewportWidth: number = 600.0;
  @Prop viewportHeight: number = 500.0;
  @Prop compact: boolean = false;
  @State private expanded: boolean = false;

  onReturnNow: () => void = (): void => {};
  onTogglePlayback: () => void = (): void => {};
  onTimeSelected: (timestampMs: number) => void = (_timestampMs: number): void => {};
  onSpeedSelected: (speed: NormalSkyPlaybackSpeed) => void =
    (_speed: NormalSkyPlaybackSpeed): void => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Button() {
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.calendar')).fontSize(18)
              .fontColor([$r('app.color.app_brand')])
            Text(this.timeText()).fontSize(12).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.sky_text_primary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1).height(40).padding({ left: 10, right: 10 })
        .backgroundColor('transparent').borderRadius($r('app.float.corner_control'))
        .onClick(() => { this.openDateTimePicker(); })

        Button() {
          SymbolGlyph(this.timeState.playing ?
            $r('sys.symbol.pause_circle') : $r('sys.symbol.play_circle'))
            .fontSize(21).fontColor([$r('app.color.sky_text_primary')])
        }
        .width(40).height(40).backgroundColor($r('app.color.sky_surface_soft')).borderRadius(20)
        .onClick(this.onTogglePlayback)

        Button() {
          SymbolGlyph($r('sys.symbol.adjustment')).fontSize(19)
            .fontColor([this.expanded ? $r('app.color.app_brand') : $r('app.color.sky_text_secondary')])
        }
        .width(40).height(40).backgroundColor('transparent').borderRadius(20)
        .onClick(() => { this.expanded = !this.expanded; })
      }.width('100%').height(40)

      if (this.expanded) {
        Row({ space: 5 }) {
          this.SpeedButton($r('app.string.normal_sky_time_hour_speed'),
            NormalSkyPlaybackSpeed.HOUR_PER_SECOND)
          this.SpeedButton($r('app.string.normal_sky_time_day_speed'),
            NormalSkyPlaybackSpeed.DAY_PER_SECOND)
          this.SpeedButton($r('app.string.normal_sky_time_week_speed'),
            NormalSkyPlaybackSpeed.WEEK_PER_SECOND)
        }.width('100%').height(34)

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.house')).fontSize(17)
              .fontColor([$r('app.color.app_brand')])
            Text($r('app.string.normal_sky_time_now')).fontSize(12)
              .fontColor($r('app.color.sky_text_primary'))
          }
        }
        .width('100%').height(34).backgroundColor($r('app.color.sky_surface_soft'))
        .borderRadius($r('app.float.corner_control')).onClick(this.onReturnNow)
      }
    }
    .width(this.controlWidth()).height(this.expanded ? 132 : 52)
    .padding(this.expanded ? 8 : 6)
    .backgroundColor($r('app.color.sky_surface')).backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: this.timeState.mode === NormalSkyTimeMode.SIMULATED ?
      $r('app.color.app_brand') : $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_card'))
    .position({ x: this.controlX(), y: this.controlY() })
    .transition(MotionTokens.capsule())
  }

  @Builder
  private SpeedButton(label: ResourceStr, speed: NormalSkyPlaybackSpeed) {
    Button(label).layoutWeight(1).height(34).fontSize(10)
      .fontWeight(this.timeState.speed === speed ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.timeState.speed === speed ?
        $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary'))
      .backgroundColor(this.timeState.speed === speed ?
        $r('app.color.app_brand') : $r('app.color.sky_surface_soft'))
      .borderRadius($r('app.float.corner_control'))
      .onClick(() => { this.onSpeedSelected(speed); })
  }

  private openDateTimePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(1900, 0, 1, 0, 0, 0),
      end: new Date(2100, 11, 31, 23, 59, 59),
      selected: new Date(this.timeState.timestampMs),
      lunar: false,
      showTime: true,
      useMilitaryTime: true,
      onDateAccept: (value: Date): void => {
        this.onTimeSelected(value.getTime());
      }
    });
  }

  private timeText(): string {
    const date: Date = new Date(this.timeState.timestampMs);
    const prefix: string = this.timeState.mode === NormalSkyTimeMode.REALTIME ? '实时' : '模拟';
    return `${prefix} ${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private controlWidth(): number {
    return Math.max(0.0, Math.min(360.0, this.viewportWidth - 24.0));
  }

  private controlX(): number {
    return this.compact ? 12.0 : 96.0;
  }

  private controlY(): number {
    const bottomReserved: number = this.compact ? 156.0 : 76.0;
    const gap: number = this.expanded ? 148.0 : 68.0;
    return Math.max(108.0, this.viewportHeight - bottomReserved - gap);
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}

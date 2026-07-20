import {
  ObservationNightPeriod,
  ObservationNightSelection,
  ObservationPlanningResult,
  ObservationSample,
  ObservationWindow,
  OutingRecommendation,
  PlanningPageState,
  PlanningSnapshot,
  PlanningTargetSummary,
  PlanningWeatherSummary,
  RecommendedCaptureWindow,
  VisibilityStatus
} from '../models';
import { MotionTokens } from '../utils/MotionTokens';
import { PlanningSnapshotService } from '../services/PlanningSnapshotService';

interface PlanningHeightBar {
  id: string;
  label: string;
  height: number;
  color: ResourceColor;
  recommended: boolean;
}

interface PlanningRenderFrame {
  id: string;
  pageState: PlanningPageState;
}

@Component
export struct PlanningDrawer {
  @Prop drawerWidth: number = 420;
  @Prop drawerHeight: number = 620;
  @Prop drawerX: number = 0;
  @Prop drawerY: number = 0;
  @Prop bottomSheet: boolean = false;
  @Prop pageState: PlanningPageState = PlanningPageState.NEEDS_LOCATION;
  @Prop period: ObservationNightPeriod = {
    startAtMs: 0,
    endAtMs: 86400000,
    timezoneOffsetMinutes: 0,
    selection: ObservationNightSelection.TONIGHT
  };
  @Prop dayOffset: number = 0;
  @Prop activeTargetId: string = '';
  @Prop activeTargetName: string = '';
  @Prop activeDesignation: string = '';
  @Prop activeTargetIncluded: boolean = false;
  @Prop targetCount: number = 0;
  @Prop snapshot: PlanningSnapshot | undefined = undefined;
  @Prop targetSummaries: PlanningTargetSummary[] = [];
  @Prop weatherMessage: string = '';
  @Prop weatherDetailsText: string = '';
  @Prop locationText: string = '';
  @Prop locationSource: string = '';
  @Prop locationEditorOpen: boolean = false;
  @Prop manualLatitudeText: string = '';
  @Prop manualLongitudeText: string = '';
  @Prop busy: boolean = false;
  @State private weatherDetailsVisible: boolean = false;

  onClose: () => void = (): void => {};
  onDayChange: (dayOffset: number) => void = (_dayOffset: number): void => {};
  onToggleLocationEditor: () => void = (): void => {};
  onLatitudeChange: (value: string) => void = (_value: string): void => {};
  onLongitudeChange: (value: string) => void = (_value: string): void => {};
  onApplyManualLocation: () => void = (): void => {};
  onUseCurrentLocation: () => void = (): void => {};
  onRefreshWeather: () => void = (): void => {};
  onSharePlan: () => void = (): void => {};
  onAddActiveTarget: () => void = (): void => {};
  onSelectTarget: (targetId: string) => void = (_targetId: string): void => {};
  onRemoveTarget: (targetId: string) => void = (_targetId: string): void => {};

  build() {
    Column({ space: 0 }) {
      if (this.bottomSheet) {
        Rect().width(44).height(4).fill($r('app.color.sky_text_tertiary'))
          .borderRadius(2).margin({ top: 10, bottom: 8 })
      }
      this.Header()
      this.PeriodToolbar()
      if (this.locationEditorOpen) {
        this.LocationEditor()
      }
      Scroll() {
        Column({ space: 10 }) {
          // ArkUI 局部更新不会可靠追踪嵌套 @Prop 对象中每个计算字符串的依赖。
          // 使用快照生成序号作为 ForEach 键，在日期、地点或天气重算后原子替换整个结果区，
          // 防止标题已经切到明晚，而分数、月光或天气仍保留今晚节点的混合画面。
          ForEach(this.renderFrames(), (frame: PlanningRenderFrame) => {
            if (frame.pageState === PlanningPageState.NEEDS_LOCATION) {
              this.LocationEmptyState()
            } else if (frame.pageState === PlanningPageState.WEATHER_LOADING) {
              this.ResultContent(PlanningPageState.WEATHER_LOADING)
            } else if (frame.pageState === PlanningPageState.READY) {
              this.ResultContent(PlanningPageState.READY)
            } else if (frame.pageState === PlanningPageState.WEATHER_UNAVAILABLE) {
              this.ResultContent(PlanningPageState.WEATHER_UNAVAILABLE)
            } else {
              this.ResultContent(PlanningPageState.ASTRONOMY_ONLY)
            }
            this.TargetList()
          }, (frame: PlanningRenderFrame) => frame.id)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 14 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width(this.drawerWidth)
    .height(this.drawerHeight)
    .backgroundColor($r('app.color.sky_surface_strong'))
    .backgroundBlurStyle(BlurStyle.Thick)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_modal'))
    .position({ x: this.drawerX, y: this.drawerY })
    .transition(MotionTokens.drawer(this.bottomSheet))
  }

  @Builder
  private Header() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.activeDayOffset() === 0 ? $r('app.string.planning_title_tonight') :
          $r('app.string.planning_title_tomorrow'))
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        Row({ space: 6 }) {
          Text(`${this.targetCount} 个目标 · ${this.formatDate(this.activePeriod().startAtMs)}`)
            .fontSize(11).fontColor($r('app.color.sky_text_secondary'))
          Text($r('app.string.planning_device_time'))
            .fontSize(10).fontColor($r('app.color.sky_text_tertiary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.busy) {
        LoadingProgress().width(18).height(18).color($r('app.color.app_brand'))
      }
      Button($r('app.string.observation_share'))
        .height(40)
        .padding({ left: 14, right: 14 })
        .fontSize(11)
        .fontColor($r('app.color.sky_text_primary'))
        .backgroundColor($r('app.color.app_surface_primary'))
        .borderRadius(20)
        .enabled(this.canSharePlan())
        .onClick(this.onSharePlan)
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20).fontColor([$r('app.color.sky_text_secondary')])
      }
      .width(48).height(48)
      .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
      .accessibilityText('关闭规划')
      .onClick(this.onClose)
    }
    .width('100%')
    .padding({ left: 20, right: 14, top: 10, bottom: 8 })
  }

  @Builder
  private PeriodToolbar() {
    Row({ space: 6 }) {
      this.DayButton($r('app.string.planning_tonight'), 0)
      this.DayButton($r('app.string.planning_tomorrow'), 1)
      Blank()
      Button($r('app.string.planning_location'))
        .height(40).padding({ left: 14, right: 14 }).fontSize(12)
        .fontColor($r('app.color.sky_text_primary'))
        .backgroundColor($r('app.color.app_surface_primary')).borderRadius(20)
        .onClick(this.onToggleLocationEditor)
      if (this.pageState !== PlanningPageState.NEEDS_LOCATION) {
        Button($r('app.string.planning_refresh'))
          .height(40).padding({ left: 14, right: 14 }).fontSize(12)
          .enabled(!this.busy)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(20)
          .onClick(this.onRefreshWeather)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    if (this.locationText.length > 0 && !this.locationEditorOpen) {
      Text(`${this.locationSource} · ${this.locationText}`)
        .fontSize(9).fontColor($r('app.color.sky_text_tertiary'))
        .width('100%').padding({ left: 16, right: 16, bottom: 7 }).maxLines(1)
    }
  }

  @Builder
  private DayButton(label: Resource, offset: number) {
    Button(label)
      .height(40).padding({ left: 16, right: 16 }).fontSize(13)
      .fontWeight(this.activeDayOffset() === offset ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeDayOffset() === offset ?
        $r('app.color.app_on_brand') : $r('app.color.app_text_secondary'))
      .backgroundColor(this.activeDayOffset() === offset ?
        $r('app.color.app_brand') : $r('app.color.app_surface_primary'))
      .borderRadius(20)
      .onClick(() => { this.onDayChange(offset); })
  }

  @Builder
  private LocationEditor() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.planning_latitude'), text: this.manualLatitudeText })
          .layoutWeight(1).height(44).fontSize(13).fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
          .onChange(this.onLatitudeChange)
        TextInput({ placeholder: $r('app.string.planning_longitude'), text: this.manualLongitudeText })
          .layoutWeight(1).height(44).fontSize(13).fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
          .onChange(this.onLongitudeChange)
      }
      Row({ space: 8 }) {
        Button($r('app.string.planning_apply_coordinates'))
          .layoutWeight(1).height(44).fontSize(13)
          .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(22)
          .onClick(this.onApplyManualLocation)
        Button($r('app.string.planning_use_current_location'))
          .layoutWeight(1).height(44).fontSize(13)
          .enabled(!this.busy)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(22)
          .onClick(this.onUseCurrentLocation)
      }
      if (this.locationText.length > 0) {
        Text(`${this.locationSource} · ${this.locationText}`)
          .fontSize(10).fontColor($r('app.color.sky_text_tertiary')).width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 10 })
    .backgroundColor($r('app.color.sky_surface_soft'))
    .transition(MotionTokens.drawer(true))
  }

  @Builder
  private LocationEmptyState() {
    Column({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.scope'))
        .fontSize(34).fontColor([$r('app.color.app_brand')])
      Column({ space: 5 }) {
        Text($r('app.string.planning_location_required'))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        Text($r('app.string.planning_location_required_detail'))
          .fontSize(12).fontColor($r('app.color.sky_text_secondary')).textAlign(TextAlign.Center)
      }
      Row({ space: 8 }) {
        Button($r('app.string.planning_use_current_location'))
          .layoutWeight(1).height(46).fontSize(13).fontWeight(FontWeight.Bold)
          .enabled(!this.busy)
          .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(23)
          .onClick(this.onUseCurrentLocation)
        Button($r('app.string.planning_enter_coordinates'))
          .layoutWeight(1).height(46).fontSize(13)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(23)
          .onClick(this.onToggleLocationEditor)
      }
      .width('100%')
      this.ActiveTargetAction()
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.sky_surface_soft'))
    .borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private ResultContent(pageState: PlanningPageState) {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(this.activeTargetName)
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
            Text(this.activeDesignation)
              .fontSize(11).fontColor($r('app.color.sky_text_tertiary'))
          }
          .layoutWeight(1)
          this.TargetActionButton()
        }
        if (this.planningResult() !== undefined) {
          Text(this.planningSummaryText())
            .fontSize(12).lineHeight(18).fontColor($r('app.color.sky_text_secondary')).width('100%').maxLines(2)
        }
      }
      .width('100%').padding(14)
      .backgroundColor($r('app.color.sky_surface_soft'))
      .borderRadius($r('app.float.corner_card'))

      Column({ space: 6 }) {
        this.InfoLine($r('app.string.planning_recommended_capture_window'), this.recommendedCaptureText())
        this.InfoLine($r('app.string.planning_astronomical_window'), this.astronomicalWindowText())
      }
      .width('100%').padding(11)
      .backgroundColor($r('app.color.sky_background'))
      .borderRadius($r('app.float.corner_card'))

      Row({ space: 6 }) {
        this.ScoreMetric($r('app.string.planning_astronomy_score'), this.astronomyScoreText())
        this.ScoreMetric($r('app.string.planning_weather_score'), this.weatherScoreText())
        this.ScoreMetric($r('app.string.planning_overall_score'), this.overallScoreText())
      }
      .width('100%')

      Row({ space: 6 }) {
        this.EventMetric($r('app.string.planning_rise'), this.eventText('rise'))
        this.EventMetric($r('app.string.planning_transit'), this.eventText('transit'))
        this.EventMetric($r('app.string.planning_set'), this.eventText('set'))
      }
      .width('100%')

      if (this.hasPlanningSamples()) {
        this.HeightTrend()
      }

      Column({ space: 6 }) {
        this.InfoLine($r('app.string.planning_moonlight'), this.moonText())
        if (pageState === PlanningPageState.WEATHER_LOADING) {
          this.InfoLine($r('app.string.planning_weather_period'), $r('app.string.planning_weather_loading'))
        } else if (pageState === PlanningPageState.WEATHER_UNAVAILABLE ||
          pageState === PlanningPageState.ASTRONOMY_ONLY) {
          this.InfoLine($r('app.string.planning_weather_period'), $r('app.string.planning_weather_unavailable'))
        } else {
          Column({ space: 3 }) {
            Text($r('app.string.planning_weather_period'))
              .fontSize(11).fontColor($r('app.color.sky_text_tertiary')).width('100%')
            Text(this.weatherMetricsText())
              .fontSize(10).lineHeight(15).fontColor($r('app.color.sky_text_secondary'))
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }
        Row({ space: 8 }) {
          Text(this.weatherMessage)
            .fontSize(9).fontColor($r('app.color.sky_text_tertiary')).layoutWeight(1).maxLines(1)
          if (this.weatherDetailsText.length > 0) {
            Button(this.weatherDetailsVisible ? $r('app.string.planning_weather_details_hide') :
              $r('app.string.planning_weather_details'))
              .height(28).padding({ left: 10, right: 10 }).fontSize(9)
              .fontColor($r('app.color.sky_text_secondary'))
              .backgroundColor($r('app.color.app_surface_primary')).borderRadius(14)
              .onClick(() => { this.weatherDetailsVisible = !this.weatherDetailsVisible; })
          }
        }
        .width('100%')
        if (this.weatherDetailsVisible && this.weatherDetailsText.length > 0) {
          Text(this.weatherDetailsText)
            .fontSize(9).lineHeight(14).fontColor($r('app.color.sky_text_tertiary'))
            .width('100%').maxLines(3)
        }
      }
      .width('100%').padding(11)
      .backgroundColor($r('app.color.sky_background'))
      .borderRadius($r('app.float.corner_card'))

      if (this.hasPlanningWarning()) {
        Text(this.planningWarningText())
          .fontSize(10).lineHeight(15).fontColor($r('app.color.app_warning')).width('100%').maxLines(2)
      }
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
  }

  @Builder
  private ActiveTargetAction() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.activeTargetName)
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        Text(this.activeDesignation)
          .fontSize(11).fontColor($r('app.color.sky_text_tertiary'))
      }
      .layoutWeight(1)
      this.TargetActionButton()
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.sky_background'))
    .borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private TargetActionButton() {
    Button(this.activeTargetIncluded ? $r('app.string.planning_target_added') :
      $r('app.string.planning_add_target'))
      .height(38).padding({ left: 13, right: 13 }).fontSize(11)
      .enabled(!this.activeTargetIncluded)
      .fontColor(this.activeTargetIncluded ?
        $r('app.color.app_success') : $r('app.color.app_on_brand'))
      .backgroundColor(this.activeTargetIncluded ?
        $r('app.color.app_surface_primary') : $r('app.color.app_brand'))
      .borderRadius(19)
      .onClick(this.onAddActiveTarget)
  }

  @Builder
  private ScoreMetric(label: Resource, value: string) {
    Column({ space: 3 }) {
      Text(value).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
      Text(label).fontSize(10).fontColor($r('app.color.sky_text_tertiary'))
    }
    .layoutWeight(1).height(56).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private EventMetric(label: Resource, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(11).fontColor($r('app.color.sky_text_tertiary'))
      Text(value).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1).height(58).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private HeightTrend() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.planning_altitude_trend'))
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        Blank()
        Text(`${this.formatDate(this.activePeriod().startAtMs)}–${this.formatDate(this.activePeriod().endAtMs)}`)
          .fontSize(9).fontColor($r('app.color.sky_text_tertiary'))
      }
      .width('100%')
      Row({ space: 3 }) {
        ForEach(this.heightBars(), (bar: PlanningHeightBar) => {
          Column({ space: 2 }) {
            Blank()
            Rect().width('100%').height(bar.height).fill(bar.color).borderRadius(1)
            Text(bar.label).fontSize(7).fontColor($r('app.color.sky_text_tertiary')).height(10)
          }
          .layoutWeight(1).height(70)
        }, (bar: PlanningHeightBar) => bar.id)
      }
      .width('100%').height(70)
    }
    .width('100%').height(100).padding(10)
    .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private InfoLine(label: Resource, value: ResourceStr) {
    Row({ space: 8 }) {
      Text(label).fontSize(11).fontColor($r('app.color.sky_text_tertiary')).flexShrink(0)
      Text(value).fontSize(11).fontColor($r('app.color.sky_text_secondary'))
        .textAlign(TextAlign.End).maxLines(2).layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private TargetList() {
    Column({ space: 7 }) {
      Row() {
        Text($r('app.string.planning_target_list'))
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        Blank()
        Text(`${this.targetCount} / 8`)
          .fontSize(10).fontColor($r('app.color.sky_text_tertiary'))
      }
      .width('100%')
      if (this.targetSummaries.length === 0) {
        Text($r('app.string.planning_empty_targets'))
          .width('100%').height(48).fontSize(11).textAlign(TextAlign.Center)
          .fontColor($r('app.color.sky_text_tertiary'))
          .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
      } else {
        ForEach(this.targetSummaries, (summary: PlanningTargetSummary) => {
          Row({ space: 8 }) {
            Circle().width(7).height(7).fill(this.recommendationColor(summary.recommendation))
            Column({ space: 2 }) {
              Text(`${summary.targetName} · ${summary.designation}`)
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary')).width('100%')
              Text(this.targetWindowText(summary))
                .fontSize(9).fontColor($r('app.color.sky_text_tertiary')).width('100%')
            }
            .layoutWeight(1)
            Text(this.targetScoreText(summary))
              .fontSize(10).fontColor(this.recommendationColor(summary.recommendation))
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(14).fontColor([$r('app.color.sky_text_secondary')])
            }
            .width(32).height(32).backgroundColor($r('app.color.app_surface_primary')).borderRadius(16)
            .accessibilityText(`移除 ${summary.targetName}`)
            .onClick(() => { this.onRemoveTarget(summary.targetId); })
          }
          .width('100%').height(50).padding({ left: 10, right: 6 })
          .backgroundColor(summary.targetId === this.activeTargetId ?
            $r('app.color.sky_surface_soft') : $r('app.color.sky_background'))
          .border({ width: summary.targetId === this.activeTargetId ? 1 : 0,
            color: $r('app.color.sky_border') })
          .borderRadius($r('app.float.corner_card'))
          .onClick(() => { this.onSelectTarget(summary.targetId); })
        }, (summary: PlanningTargetSummary) => summary.targetId)
      }
    }
    .width('100%')
  }

  private astronomyScoreText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.astronomyScore === undefined) return '暂无';
    return result.astronomyScore.toFixed(0);
  }

  private weatherScoreText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.weatherScore === undefined) return '待获取';
    return result.weatherScore.toFixed(0);
  }

  private overallScoreText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.overallScore === undefined) return '仅天文';
    return result.overallScore.toFixed(0);
  }

  private eventText(kind: string): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.samples.length === 0) return '暂无';
    const first: ObservationSample = result.samples[0];
    const last: ObservationSample = result.samples[result.samples.length - 1];
    if (result.riseTransitSet.status === VisibilityStatus.NEVER_RISE) return '本夜不升';
    if (kind === 'transit') {
      const transitAtMs: number | undefined = result.riseTransitSet.transitAtMs;
      return transitAtMs === undefined ? '暂无' :
        `${this.formatClock(transitAtMs)} · ${result.riseTransitSet.maxAltitudeDegrees.toFixed(0)}°`;
    }
    if (result.riseTransitSet.status === VisibilityStatus.ALWAYS_ABOVE_HORIZON) return '整夜可见';
    if (kind === 'rise') {
      if (result.riseTransitSet.riseAtMs !== undefined) {
        return this.formatClock(result.riseTransitSet.riseAtMs);
      }
      return first.altitudeDegrees > 0 ? '夜初已升' : '本夜未升';
    }
    if (result.riseTransitSet.setAtMs !== undefined) {
      return this.formatClock(result.riseTransitSet.setAtMs);
    }
    return last.altitudeDegrees > 0 ? '夜末仍在' : '本夜未落';
  }

  private astronomicalWindowText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.bestWindow === undefined) return '本夜无可用窗口';
    const window: ObservationWindow = result.bestWindow;
    return `${this.formatClock(window.startAtMs)}–${this.formatClock(window.endAtMs)} · ` +
      `峰值 ${window.peakAltitudeDegrees.toFixed(0)}°`;
  }

  private recommendedCaptureText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined) return '暂无';
    const window: RecommendedCaptureWindow | undefined = result.recommendedCaptureWindow;
    if (window === undefined) return result.recommendedCaptureUnavailableReason;
    const mode: string = window.astronomyOnly ? ' · 仅天文' : '';
    return `${this.formatClock(window.startAtMs)}–${this.formatClock(window.endAtMs)} · ` +
      `${window.durationMinutes}分钟${mode}`;
  }

  private moonText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined) return '暂无';
    const separation: string = result.moonSeparationDegrees === undefined ? '' :
      ` · 月距 ${result.moonSeparationDegrees.toFixed(0)}°`;
    return `${result.moonPhaseName} ${result.moonIlluminationPercent.toFixed(0)}%${separation}`;
  }

  private weatherMetricsText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.planningWeatherSummary === undefined) return '待获取';
    const summary: PlanningWeatherSummary = result.planningWeatherSummary;
    const metrics: string[] = [];
    if (summary.averageCloudCoverPercent !== undefined && summary.maximumCloudCoverPercent !== undefined) {
      metrics.push(`云均 ${summary.averageCloudCoverPercent.toFixed(0)}% / 最高 ` +
        `${summary.maximumCloudCoverPercent.toFixed(0)}%`);
    }
    if (summary.maximumPrecipitationProbabilityPercent !== undefined) {
      metrics.push(`降水最高 ${summary.maximumPrecipitationProbabilityPercent.toFixed(0)}%`);
    }
    if (summary.averageWindSpeedKph !== undefined && summary.maximumWindSpeedKph !== undefined) {
      metrics.push(`风均 ${summary.averageWindSpeedKph.toFixed(0)} / 最高 ` +
        `${summary.maximumWindSpeedKph.toFixed(0)}km/h`);
    }
    if (summary.maximumWindGustKph !== undefined) {
      metrics.push(`阵风 ${summary.maximumWindGustKph.toFixed(0)}km/h`);
    }
    return metrics.length === 0 ? '暂无逐小时数据' : metrics.join(' · ');
  }

  private heightBars(): PlanningHeightBar[] {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.samples.length === 0) return [];
    const bars: PlanningHeightBar[] = [];
    const count: number = 12;
    for (let index: number = 0; index < count; index++) {
      const sampleIndex: number = Math.round(index * (result.samples.length - 1) / (count - 1));
      const sample: ObservationSample = result.samples[sampleIndex];
      const height: number = Math.max(3, Math.min(50, (sample.altitudeDegrees + 10) / 90 * 50));
      const recommended: boolean = this.isRecommendedTimestamp(sample.timestampMs);
      let color: ResourceColor = $r('app.color.app_text_tertiary');
      if (recommended) {
        color = $r('app.color.app_brand');
      } else if (sample.altitudeDegrees >= 20 && sample.sunAltitudeDegrees <= -12) {
        color = $r('app.color.app_success');
      } else if (sample.altitudeDegrees >= 0) {
        color = $r('app.color.app_warning');
      }
      bars.push({
        id: sample.timestampMs.toString(),
        label: this.pad2(new Date(sample.timestampMs).getHours()),
        height: height,
        color: color,
        recommended: recommended
      });
    }
    return bars;
  }

  /** 抽屉只从一个原子快照读取结果，避免日期、地点与结果分别更新。 */
  private planningResult(): ObservationPlanningResult | undefined {
    if (this.snapshot === undefined) return undefined;
    if (!PlanningSnapshotService.isConsistent(this.snapshot)) return undefined;
    return this.snapshot.result;
  }

  /** 只有当前原子快照通过日期、目标和天气时间范围校验时才允许调起系统分享。 */
  private canSharePlan(): boolean {
    return !this.busy && this.snapshot !== undefined &&
      PlanningSnapshotService.isConsistent(this.snapshot);
  }

  private renderFrames(): PlanningRenderFrame[] {
    const generation: number = this.snapshot === undefined ? 0 : this.snapshot.generation;
    const frame: PlanningRenderFrame = {
      id: `${generation}:${this.pageState}`,
      pageState: this.pageState
    };
    return [frame];
  }

  private activePeriod(): ObservationNightPeriod {
    return this.snapshot === undefined ? this.period : this.snapshot.period;
  }

  private activeDayOffset(): number {
    return this.snapshot === undefined ? this.dayOffset : this.snapshot.dayOffset;
  }

  private isRecommendedTimestamp(timestampMs: number): boolean {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    if (result === undefined || result.recommendedCaptureWindow === undefined) return false;
    // 高度图只有 12 根柱，每根代表约两小时；适度扩展命中范围，避免短晴窗完全没有高亮。
    return timestampMs >= result.recommendedCaptureWindow.startAtMs - 60 * 60 * 1000 &&
      timestampMs <= result.recommendedCaptureWindow.endAtMs + 60 * 60 * 1000;
  }

  private planningSummaryText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    return result === undefined ? '' : result.summary;
  }

  private hasPlanningSamples(): boolean {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    return result !== undefined && result.samples.length > 0;
  }

  private hasPlanningWarning(): boolean {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    return result !== undefined && result.warnings.length > 0;
  }

  private planningWarningText(): string {
    const result: ObservationPlanningResult | undefined = this.planningResult();
    return result === undefined || result.warnings.length === 0 ? '' : result.warnings[0];
  }

  private targetWindowText(summary: PlanningTargetSummary): string {
    if (summary.bestWindowStartAtMs !== undefined && summary.bestWindowEndAtMs !== undefined) {
      return `${this.formatClock(summary.bestWindowStartAtMs)}–${this.formatClock(summary.bestWindowEndAtMs)}`;
    }
    return summary.unavailableReason;
  }

  private targetScoreText(summary: PlanningTargetSummary): string {
    const score: number | undefined = summary.overallScore === undefined ?
      summary.astronomyScore : summary.overallScore;
    return score === undefined ? '待计算' : `${score.toFixed(0)} 分`;
  }

  private recommendationColor(recommendation: OutingRecommendation): ResourceColor {
    if (recommendation === OutingRecommendation.GOOD) return $r('app.color.app_success');
    if (recommendation === OutingRecommendation.CAUTION ||
      recommendation === OutingRecommendation.ASTRONOMY_ONLY) return $r('app.color.app_warning');
    if (recommendation === OutingRecommendation.POOR) return $r('app.color.app_error');
    return $r('app.color.app_text_tertiary');
  }

  private formatDate(timestampMs: number): string {
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.formatClock(timestampMs)}`;
  }

  private formatClock(timestampMs: number): string {
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}

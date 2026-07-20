import {
  CameraPreflightCheck,
  CameraPreflightResult,
  ConnectionState
} from '../models/DomainModels';
import {
  SessionKind,
  SessionStatus,
  TaskSession,
  WorkflowStage,
  WorkflowStepState
} from '../models/TaskSessionModels';
import {
  ObservationRunMode,
  ReplayAsset,
  ReplayAssetManifest,
  ReplayAssetSource
} from '../models/DigitalTwinModels';
import { LiveObservationState } from '../models/LiveObservationModels';
import { MotionTokens } from '../utils/MotionTokens';
import { TaskSessionPresentationService } from '../services/TaskSessionPresentationService';

interface TaskPipelineStep {
  stage: WorkflowStage;
  title: ResourceStr;
  state: WorkflowStepState;
}

@Component
export struct TaskWorkspace {
  @Prop compact: boolean = false;
  @Prop pageMargin: number = 18;
  @Prop runMode: ObservationRunMode = ObservationRunMode.REAL;
  @Prop replayManifest: ReplayAssetManifest | undefined = undefined;
  @Prop digitalTwinPlaying: boolean = false;
  @Prop activeSession: TaskSession | undefined = undefined;
  @Prop history: TaskSession[] = [];
  @Prop storeReady: boolean = false;
  @Prop storeWarning: string = '';
  @Prop stopRequested: boolean = false;
  @Prop mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop cameraConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop mountHomed: boolean = false;
  @Prop coordinateModeCompatible: boolean = false;
  @Prop locationSynced: boolean = false;
  @Prop preflight: CameraPreflightResult | undefined = undefined;
  @Prop liveObservation: LiveObservationState | undefined = undefined;
  @State private inspectedHistoryId: string = '';

  onGoToSky: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onContinue: () => void = (): void => {};
  onArchive: () => void = (): void => {};
  onEndObservation: () => void = (): void => {};
  onOpenProducts: () => void = (): void => {};
  onToggleSimulationPlayback: () => void = (): void => {};
  onRestartSimulation: () => void = (): void => {};
  onExitSimulation: () => void = (): void => {};
  onShareReport: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 18 }) {
        if (this.simulationActive()) {
          this.SimulationBanner()
        }
        if (this.liveObservation !== undefined) {
          this.LiveObservationBanner(this.liveObservation)
        }
        if (this.storeWarning.length > 0) {
          this.WarningBanner(this.storeWarning)
        }
        if (this.activeSession === undefined) {
          this.EmptyState()
        } else {
          this.ActiveSession(this.activeSession)
        }
        this.HistorySection()
      }
      .width('100%')
      .padding({ left: this.pageMargin, right: this.pageMargin, top: 18, bottom: 28 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private SimulationBanner() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.play_circle'))
        .fontSize(22)
        .fontColor([$r('app.color.app_brand')])
      Column({ space: 3 }) {
        Text($r('app.string.digital_twin_watermark'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_brand'))
        Text(this.replaySourceText())
          .fontSize(10)
          .fontColor($r('app.color.app_warning'))
      }.layoutWeight(1)
      Button($r('app.string.digital_twin_exit'))
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(11)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_surface_secondary'))
        .borderRadius(18)
        .onClick(this.onExitSimulation)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_surface_primary'))
    .border({ width: 1, color: $r('app.color.app_brand') })
    .borderRadius($r('app.float.corner_control'))
  }

  @Builder
  private LiveObservationBanner(state: LiveObservationState) {
    Row({ space: 10 }) {
      Circle()
        .width(9)
        .height(9)
        .fill(this.liveObservationColor(state.status))
      Column({ space: 3 }) {
        Text($r('app.string.live_observation_in_app'))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Text(state.statusText)
          .fontSize(10)
          .fontColor($r('app.color.app_text_secondary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      Text(this.liveObservationTail(state))
        .fontSize(10)
        .fontColor($r('app.color.app_brand'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_control'))
  }

  @Builder
  private EmptyState() {
    Column({ space: 18 }) {
      SymbolGlyph($r('sys.symbol.scope'))
        .fontSize(42)
        .fontColor([$r('app.color.app_brand')])
      Text(this.storeReady ? $r('app.string.task_empty_title') : $r('app.string.task_loading_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
      Text(this.storeReady ? $r('app.string.task_empty_detail') : $r('app.string.task_loading_detail'))
        .fontSize(13)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.app_text_secondary'))
        .constraintSize({ maxWidth: 520 })
      if (this.preflight !== undefined && !this.preflight.ready) {
        Column({ space: 10 }) {
          this.SideSectionTitle($r('app.string.task_preflight_title'))
          this.PreflightSummary(this.preflight)
        }
        .width('100%')
        .constraintSize({ maxWidth: 620 })
        .padding(16)
        .backgroundColor($r('app.color.app_surface_secondary'))
        .borderRadius($r('app.float.corner_control'))
      }
      this.ReadinessSummary(true)
      Button($r('app.string.task_go_to_sky'))
        .height(48)
        .padding({ left: 24, right: 24 })
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_on_brand'))
        .backgroundColor($r('app.color.app_brand'))
        .borderRadius(24)
        .enabled(this.storeReady)
        .onClick(this.onGoToSky)
    }
    .width('100%')
    .constraintSize({ minHeight: this.compact ? 300 : 360 })
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
    .transition(MotionTokens.modal())
  }

  @Builder
  private ActiveSession(session: TaskSession) {
    Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap,
      justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
      Column({ space: 16 }) {
        this.SessionHeader(session)
        this.ProgressSection(session)
        this.PipelineSection(session)
        this.SessionActions(session)
      }
      .layoutWeight(1)
      .width(this.compact ? '100%' : undefined)
      .margin({ right: this.compact ? 0 : 12, bottom: this.compact ? 12 : 0 })

      Column({ space: 14 }) {
        this.SideSectionTitle($r('app.string.task_safety_title'))
        this.ReadinessSummary(false)
        this.SideSectionTitle($r('app.string.task_stage_detail_title'))
        this.StageDetail(session)
        if (this.preflight !== undefined) {
          this.SideSectionTitle($r('app.string.task_preflight_title'))
          this.PreflightSummary(this.preflight)
        }
        if (session.warnings.length > 0) {
          this.SideSectionTitle($r('app.string.task_warnings_title'))
          this.WarningList(session.warnings)
        }
        if (session.products.length > 0) {
          if (this.simulationActive() && this.replayManifest !== undefined) {
            this.ReplayAssetSection(this.replayManifest)
          } else {
            this.ProductEntrance(session)
          }
        }
      }
      .width(this.compact ? '100%' : 320)
      .padding(16)
      .backgroundColor($r('app.color.app_background_secondary'))
      .borderRadius($r('app.float.corner_card'))
      .border({ width: 1, color: $r('app.color.app_divider') })
    }
    .width('100%')
  }

  @Builder
  private SessionHeader(session: TaskSession) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(session.target.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .width('100%')
          Row({ space: 5 }) {
            Text(session.target.designation).fontSize(13).fontColor($r('app.color.app_text_secondary'))
            Text('·').fontSize(13).fontColor($r('app.color.app_text_tertiary'))
            Text(this.kindText(session.kind)).fontSize(13).fontColor($r('app.color.app_text_secondary'))
          }.width('100%')
        }
        .layoutWeight(1)
        this.StatusBadge(this.statusText(session.status), this.statusColor(session.status))
      }
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        if (this.simulationActive()) {
          this.InfoCapsule($r('app.string.digital_twin_data_source'), this.replaySourceText())
        }
        this.InfoCapsule($r('app.string.task_device_time'), this.timeText(session.startedAtMs))
        this.InfoCapsule($r('app.string.task_completed_frames'),
          session.kind === SessionKind.OBSERVATION ? $r('app.string.task_not_applicable') :
            `${session.completedFrames} / ${session.plan.frameCount}`)
        this.ConnectionBadge($r('app.string.task_mount_short'),
          this.mountConnection === ConnectionState.CONNECTED ||
            (this.simulationActive() && this.mountConnection === ConnectionState.SIMULATED))
        if (session.kind !== SessionKind.OBSERVATION) {
          this.ConnectionBadge($r('app.string.task_camera_short'),
            this.cameraConnection === ConnectionState.CONNECTED ||
              (this.simulationActive() && this.cameraConnection === ConnectionState.SIMULATED))
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private ProgressSection(session: TaskSession) {
    Column({ space: 9 }) {
      Row() {
        Text(this.stageTitle(session.stage))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Blank()
        Text(`${Math.round(session.progressPercent)}%`)
          .fontSize(12)
          .fontColor($r('app.color.app_success'))
      }
      .width('100%')
      Progress({ value: session.progressPercent, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(8)
        .color($r('app.color.app_success'))
        .backgroundColor($r('app.color.app_surface_primary'))
        .animation(MotionTokens.standard())
      Text(session.statusDetail.length > 0 ? session.statusDetail : session.checkpoint.detail)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  private PipelineSection(session: TaskSession) {
    Column({ space: 10 }) {
      this.SectionTitle($r('app.string.task_pipeline_title'), this.pipelineSubtitle(session.kind))
      ForEach(this.pipeline(session), (step: TaskPipelineStep) => {
        this.PipelineStep(step)
      }, (step: TaskPipelineStep): string => `${step.stage}-${step.state}`)
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private PipelineStep(step: TaskPipelineStep) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(32)
          .height(32)
          .fill(this.stepColor(step.state))
        if (step.state === WorkflowStepState.ACTIVE) {
          LoadingProgress().width(17).height(17).color($r('app.color.app_on_brand'))
        } else {
          SymbolGlyph(this.stepSymbol(step.state))
            .fontSize(16)
            .fontColor([step.state === WorkflowStepState.WAITING ?
              $r('app.color.app_text_secondary') : $r('app.color.app_on_brand')])
        }
      }
      .width(32)
      .height(32)
      Text(step.title)
        .layoutWeight(1)
        .fontSize(13)
        .fontWeight(step.state === WorkflowStepState.ACTIVE ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(step.state === WorkflowStepState.WAITING || step.state === WorkflowStepState.SKIPPED ?
          $r('app.color.app_text_secondary') : $r('app.color.app_text_primary'))
      Text(this.stepStateText(step.state))
        .fontSize(11)
        .fontColor(this.stepColor(step.state))
    }
    .width('100%')
    .height(42)
  }

  @Builder
  private SessionActions(session: TaskSession) {
    Column({ space: 8 }) {
      if (this.simulationActive()) {
        Row({ space: 10 }) {
          Button(this.digitalTwinPlaying ? $r('app.string.digital_twin_pause') :
            $r('app.string.digital_twin_play'))
            .layoutWeight(1)
            .height(48)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_on_brand'))
            .backgroundColor($r('app.color.app_brand'))
            .borderRadius(24)
            .onClick(this.onToggleSimulationPlayback)
          Button($r('app.string.digital_twin_restart'))
            .layoutWeight(1)
            .height(48)
            .fontSize(14)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_surface_primary'))
            .borderRadius(24)
            .onClick(this.onRestartSimulation)
        }.width('100%')
        Text($r('app.string.digital_twin_task_not_persisted'))
          .fontSize(11)
          .lineHeight(17)
          .fontColor($r('app.color.app_warning'))
          .width('100%')
      } else {
        Row({ space: 10 }) {
          if (this.canRefresh(session)) {
            Button($r('app.string.task_refresh'))
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_surface_primary'))
              .borderRadius(24)
              .onClick(this.onRefresh)
          }
          if (session.status === SessionStatus.WAITING_FOR_USER ||
            session.status === SessionStatus.INTERRUPTED) {
            Button($r('app.string.task_continue'))
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_on_brand'))
              .backgroundColor($r('app.color.app_brand'))
              .borderRadius(24)
              .onClick(this.onContinue)
            Button($r('app.string.task_archive_failed'))
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_surface_primary'))
              .borderRadius(24)
              .onClick(this.onArchive)
          }
          if (session.kind === SessionKind.OBSERVATION && session.status === SessionStatus.RUNNING) {
            Button($r('app.string.task_end_observation'))
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_surface_primary'))
              .borderRadius(24)
              .onClick(this.onEndObservation)
          } else if (session.kind !== SessionKind.OBSERVATION && !this.stopRequested &&
            (session.status === SessionStatus.PREPARING || session.status === SessionStatus.RUNNING)) {
            Button($r('app.string.task_stop_later_frames'))
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.sky_text_primary'))
              .backgroundColor($r('app.color.app_error_container'))
              .borderRadius(24)
              .onClick(this.onStop)
          }
        }
        .width('100%')
        if (session.status === SessionStatus.INTERRUPTED) {
          Text($r('app.string.task_continue_safety_note'))
            .fontSize(11)
            .lineHeight(17)
            .fontColor($r('app.color.app_warning'))
            .width('100%')
        }
        if (this.stopRequested) {
          Text($r('app.string.task_soft_cancel_pending'))
            .fontSize(11)
            .lineHeight(17)
            .fontColor($r('app.color.app_warning'))
            .width('100%')
        }
      }
      Button($r('app.string.observation_share_report'))
        .width('100%')
        .height(44)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_text_primary'))
        .backgroundColor($r('app.color.app_surface_primary'))
        .borderRadius(22)
        .onClick(this.onShareReport)
    }
    .width('100%')
  }

  @Builder
  private ReadinessSummary(short: boolean) {
    Flex({ direction: short && !this.compact ? FlexDirection.Row : FlexDirection.Column,
      wrap: FlexWrap.Wrap }) {
      this.ReadinessItem(this.simulationActive() ? $r('app.string.digital_twin_ready_script') :
        $r('app.string.task_ready_mount'), this.simulationActive() ||
          this.mountConnection === ConnectionState.CONNECTED)
      this.ReadinessItem($r('app.string.task_ready_home'), this.mountHomed)
      this.ReadinessItem($r('app.string.task_ready_coordinate'), this.coordinateModeCompatible)
      this.ReadinessItem($r('app.string.task_ready_location'), this.locationSynced)
      this.ReadinessItem($r('app.string.task_ready_camera'), this.cameraConnection === ConnectionState.CONNECTED ||
        (this.simulationActive() && this.cameraConnection === ConnectionState.SIMULATED))
    }
    .width('100%')
  }

  @Builder
  private ReadinessItem(label: ResourceStr, ready: boolean) {
    Row({ space: 7 }) {
      Circle().width(7).height(7).fill(ready ? $r('app.color.app_success') : $r('app.color.app_warning'))
      Text(label).fontSize(11).fontColor($r('app.color.app_text_secondary'))
    }
    .height(30)
    .padding({ left: 11, right: 11 })
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius(15)
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private StageDetail(session: TaskSession) {
    Column({ space: 8 }) {
      this.DetailRow($r('app.string.task_stage'), this.stageTitle(session.stage))
      if (this.simulationActive()) {
        this.DetailRow($r('app.string.digital_twin_data_source'), this.replaySourceText())
        this.DetailRow($r('app.string.task_child_task'), $r('app.string.digital_twin_no_gateway_request'))
      } else {
        this.DetailRow($r('app.string.task_child_task'),
          session.checkpoint.childTaskId.length > 0 ? session.checkpoint.childTaskId.substring(0, 8) :
            $r('app.string.task_no_child_task'))
      }
      this.DetailRow($r('app.string.task_real_device_time'), this.timeText(Date.now()))
      if (session.errorMessage.length > 0) {
        Text(session.errorMessage)
          .fontSize(11)
          .lineHeight(17)
          .fontColor($r('app.color.app_error'))
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private PreflightSummary(result: CameraPreflightResult) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Circle().width(8).height(8).fill(result.ready ? $r('app.color.app_success') : $r('app.color.app_error'))
        Text(result.ready ? $r('app.string.task_preflight_passed') : $r('app.string.task_preflight_blocked'))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(result.ready ? $r('app.color.app_success') : $r('app.color.app_error'))
      }
      ForEach(result.checks, (check: CameraPreflightCheck) => {
        Row({ space: 8 }) {
          SymbolGlyph(check.passed ? $r('sys.symbol.checkmark_circle_fill') :
            $r('sys.symbol.exclamationmark_circle_fill'))
            .fontSize(15)
            .fontColor([check.passed ? $r('app.color.app_success') :
              (check.blocking ? $r('app.color.app_error') : $r('app.color.app_warning'))])
          Column({ space: 2 }) {
            Text(check.label).fontSize(11).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary')).width('100%')
            Text(`${check.actual} → ${check.expected}`).fontSize(10)
              .fontColor($r('app.color.app_text_secondary')).width('100%').maxLines(2)
            if (!check.passed) {
              Text(check.adjustment).fontSize(10).lineHeight(15)
                .fontColor($r('app.color.app_warning')).width('100%')
            }
          }.layoutWeight(1)
        }.width('100%')
      }, (check: CameraPreflightCheck): string => check.code)
    }
    .width('100%')
  }

  @Builder
  private WarningList(warnings: string[]) {
    Column({ space: 7 }) {
      ForEach(warnings, (warning: string, index: number) => {
        Row({ space: 8 }) {
          Text('!').fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_on_brand'))
            .width(20).height(20).textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.app_warning')).borderRadius(10)
          Text(warning).layoutWeight(1).fontSize(11).lineHeight(17)
            .fontColor($r('app.color.app_text_secondary'))
        }.width('100%')
      }, (_warning: string, index: number): string => `${index}`)
    }.width('100%')
  }

  @Builder
  private ProductEntrance(session: TaskSession) {
    Button() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.list_bullet_square'))
          .fontSize(18)
          .fontColor([$r('app.color.app_brand')])
        Column({ space: 2 }) {
          Text($r('app.string.task_products_title')).fontSize(12).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary')).width('100%')
          Row({ space: 4 }) {
            Text(`${session.products.length}`).fontSize(10).fontColor($r('app.color.app_text_secondary'))
            Text(this.productCountUnit()).fontSize(10).fontColor($r('app.color.app_text_secondary'))
          }.width('100%')
        }.layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14)
          .fontColor([$r('app.color.app_text_secondary')])
      }.width('100%')
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius($r('app.float.corner_control'))
    .onClick(this.onOpenProducts)
  }

  @Builder
  private ReplayAssetSection(manifest: ReplayAssetManifest) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.list_bullet_square'))
          .fontSize(17)
          .fontColor([$r('app.color.app_brand')])
        Text($r('app.string.digital_twin_assets_title'))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .layoutWeight(1)
        Text(this.replaySourceText())
          .fontSize(10)
          .fontColor($r('app.color.app_warning'))
      }.width('100%')
      ForEach(manifest.files, (asset: ReplayAsset) => {
        Row({ space: 8 }) {
          Circle().width(6).height(6).fill($r('app.color.app_brand'))
          Column({ space: 2 }) {
            Text(asset.fileName)
              .fontSize(10)
              .fontColor($r('app.color.app_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(asset.description)
              .fontSize(9)
              .fontColor($r('app.color.app_text_tertiary'))
              .maxLines(1)
          }.layoutWeight(1)
        }.width('100%')
      }, (asset: ReplayAsset): string => asset.id)
      Text(manifest.note)
        .fontSize(9)
        .lineHeight(14)
        .fontColor($r('app.color.app_warning'))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius($r('app.float.corner_control'))
  }

  @Builder
  private HistorySection() {
    Column({ space: 12 }) {
      this.SectionTitle($r('app.string.task_history_title'), this.simulationActive() ?
        $r('app.string.digital_twin_real_history_note') : $r('app.string.task_history_subtitle'))
      if (this.history.length === 0) {
        Text($r('app.string.task_history_empty'))
          .fontSize(12)
          .fontColor($r('app.color.app_text_secondary'))
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else {
        ForEach(this.history, (session: TaskSession) => {
          this.HistoryItem(session)
        }, (session: TaskSession): string => session.id)
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private HistoryItem(session: TaskSession) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Row({ space: 5 }) {
            Text(session.target.name).fontSize(13).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
            Text('·').fontSize(12).fontColor($r('app.color.app_text_tertiary'))
            Text(this.kindText(session.kind)).fontSize(13).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
          }.width('100%')
          Row({ space: 5 }) {
            Text(this.timeText(session.completedAtMs > 0 ? session.completedAtMs : session.updatedAtMs))
              .fontSize(11).fontColor($r('app.color.app_text_secondary'))
            Text('·').fontSize(11).fontColor($r('app.color.app_text_tertiary'))
            if (session.kind === SessionKind.OBSERVATION) {
              Text(this.observationHistoryText()).fontSize(11).fontColor($r('app.color.app_text_secondary'))
            } else {
              Text(`${session.completedFrames}/${session.plan.frameCount}`)
                .fontSize(11).fontColor($r('app.color.app_text_secondary'))
            }
          }.width('100%')
        }.layoutWeight(1)
        this.StatusBadge(this.statusText(session.status), this.statusColor(session.status))
        SymbolGlyph(this.inspectedHistoryId === session.id ? $r('sys.symbol.chevron_up') :
          $r('sys.symbol.chevron_down'))
          .fontSize(14).fontColor([$r('app.color.app_text_secondary')])
      }
      .width('100%')
      .onClick(() => {
        this.inspectedHistoryId = this.inspectedHistoryId === session.id ? '' : session.id;
      })
      if (this.inspectedHistoryId === session.id) {
        Column({ space: 7 }) {
          this.DetailRow($r('app.string.task_stage'), this.stageTitle(session.stage))
          this.DetailRow($r('app.string.task_completed_frames'),
            session.kind === SessionKind.OBSERVATION ? $r('app.string.task_not_applicable') :
              `${session.completedFrames} / ${session.plan.frameCount}`)
          this.DetailRow($r('app.string.task_products_title'), `${session.products.length}`)
          if (session.statusDetail.length > 0) {
            Text(session.statusDetail).fontSize(11).lineHeight(17)
              .fontColor($r('app.color.app_text_secondary')).width('100%')
          }
          if (session.products.length > 0) {
            Button($r('app.string.task_open_post'))
              .height(40).fontSize(12).fontColor($r('app.color.app_on_brand'))
              .backgroundColor($r('app.color.app_brand')).borderRadius(20)
              .onClick(this.onOpenProducts)
          }
        }
        .width('100%')
        .padding({ top: 10 })
        .border({ width: { top: 1 }, color: $r('app.color.app_divider') })
        .transition(MotionTokens.capsule())
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_control'))
  }

  @Builder
  private WarningBanner(message: string) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(18).fontColor([$r('app.color.app_warning')])
      Text(message).layoutWeight(1).fontSize(12).lineHeight(18).fontColor($r('app.color.app_text_secondary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius($r('app.float.corner_control'))
  }

  @Builder
  private SectionTitle(title: ResourceStr, subtitle: ResourceStr) {
    Column({ space: 3 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
      Text(subtitle).fontSize(11).fontColor($r('app.color.app_text_secondary')).width('100%')
    }.width('100%')
  }

  @Builder
  private SideSectionTitle(title: ResourceStr) {
    Text(title).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
  }

  @Builder
  private DetailRow(label: ResourceStr, value: ResourceStr) {
    Row({ space: 8 }) {
      Text(label).fontSize(11).fontColor($r('app.color.app_text_secondary'))
      Blank()
      Text(value).fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_text_primary'))
        .textAlign(TextAlign.End).maxLines(2)
    }.width('100%')
  }

  @Builder
  private StatusBadge(label: ResourceStr, color: ResourceColor) {
    Text(label)
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(color)
      .height(28)
      .padding({ left: 10, right: 10 })
      .textAlign(TextAlign.Center)
      .backgroundColor($r('app.color.app_surface_primary'))
      .borderRadius(14)
  }

  @Builder
  private InfoCapsule(label: ResourceStr, value: ResourceStr) {
    Column({ space: 2 }) {
      Text(label).fontSize(9).fontColor($r('app.color.app_text_tertiary'))
      Text(value).fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_text_primary'))
    }
    .height(42)
    .padding({ left: 11, right: 11, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius($r('app.float.corner_control'))
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private ConnectionBadge(label: ResourceStr, connected: boolean) {
    Row({ space: 6 }) {
      Circle().width(6).height(6).fill(connected ? $r('app.color.app_success') : $r('app.color.app_warning'))
      Text(label).fontSize(10).fontColor($r('app.color.app_text_secondary'))
    }
    .height(30)
    .padding({ left: 9, right: 9 })
    .backgroundColor($r('app.color.app_surface_primary'))
    .borderRadius(15)
    .margin({ right: 8, bottom: 8 })
  }

  private pipeline(session: TaskSession): TaskPipelineStep[] {
    const stages: WorkflowStage[] = TaskSessionPresentationService.pipelineStages(session);
    const result: TaskPipelineStep[] = [];
    for (let index: number = 0; index < stages.length; index++) {
      const stage: WorkflowStage = stages[index];
      result.push({
        stage: stage,
        title: stage === WorkflowStage.COMPLETE && session.kind === SessionKind.OBSERVATION ?
          $r('app.string.task_step_observation_end') : this.stageTitle(stage),
        state: TaskSessionPresentationService.stepState(session, stage)
      });
    }
    return result;
  }

  private stageTitle(stage: WorkflowStage): ResourceStr {
    if (stage === WorkflowStage.SAFETY_CHECK) return $r('app.string.task_step_safety');
    if (stage === WorkflowStage.CAMERA_PREFLIGHT) return $r('app.string.task_preflight_title');
    if (stage === WorkflowStage.GOTO) return $r('app.string.task_step_goto');
    if (stage === WorkflowStage.TRACKING) return $r('app.string.task_step_tracking');
    if (stage === WorkflowStage.CAPTURE) return $r('app.string.task_step_capture');
    if (stage === WorkflowStage.PLATE_SOLVE) return $r('app.string.task_step_plate');
    if (stage === WorkflowStage.DRIFT_CORRECTION) return $r('app.string.task_step_correction');
    if (stage === WorkflowStage.STACK) return $r('app.string.task_step_stack');
    if (stage === WorkflowStage.TIMELAPSE) return $r('app.string.task_step_timelapse');
    if (stage === WorkflowStage.CLOUD_ENHANCEMENT) return $r('app.string.task_step_cloud');
    return $r('app.string.task_step_complete');
  }

  private kindText(kind: SessionKind): ResourceStr {
    if (kind === SessionKind.OBSERVATION) return $r('app.string.task_kind_observation');
    if (kind === SessionKind.SMART_LONG_EXPOSURE) return $r('app.string.task_kind_smart');
    return $r('app.string.task_kind_timelapse');
  }

  private statusText(status: SessionStatus): ResourceStr {
    if (status === SessionStatus.PREPARING) return $r('app.string.task_status_preparing');
    if (status === SessionStatus.RUNNING) return $r('app.string.task_status_running');
    if (status === SessionStatus.WAITING_FOR_USER) return $r('app.string.task_status_waiting_user');
    if (status === SessionStatus.INTERRUPTED) return $r('app.string.task_status_interrupted');
    if (status === SessionStatus.SUCCEEDED) return $r('app.string.task_status_succeeded');
    if (status === SessionStatus.FAILED) return $r('app.string.task_status_failed');
    return $r('app.string.task_status_cancelled');
  }

  private statusColor(status: SessionStatus): ResourceColor {
    if (status === SessionStatus.SUCCEEDED) return $r('app.color.app_success');
    if (status === SessionStatus.FAILED) return $r('app.color.app_error');
    if (status === SessionStatus.CANCELLED || status === SessionStatus.INTERRUPTED ||
      status === SessionStatus.WAITING_FOR_USER) return $r('app.color.app_warning');
    return $r('app.color.app_brand');
  }

  private liveObservationColor(status: SessionStatus): ResourceColor {
    if (status === SessionStatus.SUCCEEDED) return $r('app.color.app_success');
    if (status === SessionStatus.FAILED) return $r('app.color.app_error');
    if (status === SessionStatus.CANCELLED || status === SessionStatus.INTERRUPTED ||
      status === SessionStatus.WAITING_FOR_USER) return $r('app.color.app_warning');
    return $r('app.color.app_brand');
  }

  private liveObservationTail(state: LiveObservationState): string {
    if (state.runMode === ObservationRunMode.SIMULATION) {
      return `${Math.round(state.progressPercent)}% · #${state.sequence}`;
    }
    return `${Math.round(state.progressPercent)}% · ${this.timeText(state.updatedAtMs)}`;
  }

  private stepColor(state: WorkflowStepState): ResourceColor {
    if (state === WorkflowStepState.SUCCEEDED) return $r('app.color.app_success');
    if (state === WorkflowStepState.FAILED) return $r('app.color.app_error');
    if (state === WorkflowStepState.CANCELLED) return $r('app.color.app_warning');
    if (state === WorkflowStepState.ACTIVE) return $r('app.color.app_brand');
    return $r('app.color.app_surface_tertiary');
  }

  private stepSymbol(state: WorkflowStepState): Resource {
    if (state === WorkflowStepState.SUCCEEDED) return $r('sys.symbol.checkmark');
    if (state === WorkflowStepState.FAILED) return $r('sys.symbol.xmark');
    if (state === WorkflowStepState.CANCELLED) return $r('sys.symbol.pause_circle');
    if (state === WorkflowStepState.SKIPPED) return $r('sys.symbol.chevron_right');
    return $r('sys.symbol.circle');
  }

  private stepStateText(state: WorkflowStepState): ResourceStr {
    if (state === WorkflowStepState.ACTIVE) return $r('app.string.task_step_active');
    if (state === WorkflowStepState.SUCCEEDED) return $r('app.string.task_step_succeeded');
    if (state === WorkflowStepState.SKIPPED) return $r('app.string.task_step_skipped');
    if (state === WorkflowStepState.FAILED) return $r('app.string.task_step_failed');
    if (state === WorkflowStepState.CANCELLED) return $r('app.string.task_step_cancelled');
    return $r('app.string.task_step_waiting');
  }

  private pipelineSubtitle(kind: SessionKind): ResourceStr {
    return kind === SessionKind.OBSERVATION ? $r('app.string.task_pipeline_observation') :
      $r('app.string.task_pipeline_camera');
  }

  private canRefresh(session: TaskSession): boolean {
    return session.checkpoint.childTaskId.length > 0 &&
      (session.status === SessionStatus.RUNNING || session.status === SessionStatus.INTERRUPTED ||
        session.status === SessionStatus.WAITING_FOR_USER);
  }

  private timeText(timestampMs: number): string {
    if (timestampMs <= 0) return '--';
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ${
      this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private productCountUnit(): ResourceStr {
    return $r('app.string.task_product_count_unit');
  }

  private observationHistoryText(): ResourceStr {
    return $r('app.string.task_observation_history');
  }

  private replaySourceText(): ResourceStr {
    if (this.replayManifest !== undefined &&
      this.replayManifest.source === ReplayAssetSource.REAL_CAPTURE_REPLAY) {
      return $r('app.string.digital_twin_source_real_history');
    }
    return $r('app.string.digital_twin_source_simulated');
  }

  private simulationActive(): boolean {
    return this.runMode === ObservationRunMode.SIMULATION;
  }
}

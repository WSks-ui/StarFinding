import { TaskStatus } from '../models';

@Component
export struct TaskWorkspace {
  @Prop compact: boolean = false;
  @Prop pageMargin: number = 18;
  @Prop taskStage: string = '等待创建';
  @Prop targetName: string = '';
  @Prop captureMode: number = 0;
  @Prop exposureSeconds: number = 15;
  @Prop frameCount: number = 20;
  @Prop iso: number = 800;
  @Prop taskStatus: TaskStatus = TaskStatus.PENDING;
  @Prop taskProgress: number = 0;
  @Prop completedFrames: number = 0;
  @Prop workflowWarningText: string = '';
  @Prop plateSolveCount: number = 0;
  @Prop correctionCount: number = 0;
  @Prop stackFileUrl: string = '';
  @Prop timelapseFileUrl: string = '';
  @Prop aiFileUrl: string = '';

  onRefresh: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  build() {
    Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
      Column({ space: 14 }) {
        this.PanelTitle('当前拍摄任务', this.taskStage)
        Row() {
          Column({ space: 4 }) {
            Text(`${this.targetName} · ${this.captureModeText()}`)
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
            Text(`${this.exposureSeconds}s × ${this.frameCount} · ISO ${this.iso}`)
              .fontSize(13).fontColor($r('app.color.app_text_secondary')).width('100%')
          }.layoutWeight(1)
          Text(this.taskStatusText()).fontSize(12).fontColor(this.taskStatusColor())
        }.width('100%')

        Progress({ value: this.taskProgress, total: 100, type: ProgressType.Linear })
          .width('100%').height(8).color($r('app.color.app_success'))
          .backgroundColor($r('app.color.app_surface_primary'))
        Row() {
          Text(`${this.completedFrames} / ${this.frameCount} 帧`)
            .fontSize(12).fontColor($r('app.color.app_text_secondary'))
          Blank()
          Text(`${this.taskProgress.toFixed(0)}%`).fontSize(11).fontColor('#57C995')
        }.width('100%')

        if (this.workflowWarningText.length > 0) {
          Text(this.workflowWarningText)
            .fontSize(12).fontColor($r('app.color.app_warning')).lineHeight(18).width('100%').maxLines(2)
        }

        Row({ space: 10 }) {
          Button('刷新状态').layoutWeight(1).height(48).fontSize(14)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
            .onClick(this.onRefresh)
          Button('取消任务').layoutWeight(1).height(48).fontSize(14)
            .fontColor($r('app.color.sky_text_primary'))
            .backgroundColor($r('app.color.app_error_container')).borderRadius(24)
            .onClick(this.onCancel)
        }.width('100%')
      }
      .layoutWeight(1)
      .height(280)
      .padding(20)
      .backgroundColor($r('app.color.app_background_secondary'))
      .borderRadius($r('app.float.corner_card'))
      .border({ width: 1, color: $r('app.color.app_divider') })

      Column({ space: 12 }) {
        this.PanelTitle('处理流水线', 'RAW 原片始终保留在相机存储卡')
        this.PipelineStep('1', '拍摄与下载', this.taskProgress > 0)
        this.PipelineStep('2', `板解析 ${this.plateSolveCount} 次 · 修正 ${this.correctionCount} 次`,
          this.plateSolveCount > 0)
        this.PipelineStep('3', this.captureMode === 2 ? '1080p 延时制片' : '星点配准、坏帧剔除与堆栈',
          this.stackFileUrl.length > 0 || this.timelapseFileUrl.length > 0)
        this.PipelineStep('4', '华为云受约束增强（可选）', this.aiFileUrl.length > 0)
      }
      .width(this.compact ? '100%' : 340)
      .padding(20)
      .backgroundColor($r('app.color.app_background_secondary'))
      .borderRadius($r('app.float.corner_card'))
      .border({ width: 1, color: $r('app.color.app_divider') })
    }
    .layoutWeight(1)
    .width('100%')
    .padding(this.pageMargin)
  }

  @Builder
  private PanelTitle(title: string, subtitle: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
      Text(subtitle).fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
    }.width('100%')
  }

  @Builder
  private PipelineStep(number: string, label: string, active: boolean) {
    Row({ space: 10 }) {
      Text(active ? '✓' : number)
        .fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(active ? $r('app.color.app_on_brand') : $r('app.color.app_text_secondary'))
        .width(28).height(28).textAlign(TextAlign.Center)
        .backgroundColor(active ? $r('app.color.app_success') : $r('app.color.app_surface_primary'))
        .borderRadius(14)
      Text(label).fontSize(13)
        .fontColor(active ? $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
    }.width('100%').height(40)
  }

  private taskStatusText(): string {
    if (this.taskStatus === TaskStatus.RUNNING) return '运行中';
    if (this.taskStatus === TaskStatus.SUCCEEDED) return '已完成';
    if (this.taskStatus === TaskStatus.FAILED) return '失败';
    if (this.taskStatus === TaskStatus.CANCELLED) return '已取消';
    return '等待创建';
  }

  private captureModeText(): string {
    if (this.captureMode === 0) return '仅观测';
    if (this.captureMode === 1) return '智能长曝光';
    return '延时摄影';
  }

  private taskStatusColor(): ResourceColor {
    if (this.taskStatus === TaskStatus.SUCCEEDED) return $r('app.color.app_success');
    if (this.taskStatus === TaskStatus.FAILED) return $r('app.color.app_error');
    if (this.taskStatus === TaskStatus.CANCELLED) return $r('app.color.app_warning');
    if (this.taskStatus === TaskStatus.RUNNING) return $r('app.color.app_brand');
    return $r('app.color.app_text_secondary');
  }
}

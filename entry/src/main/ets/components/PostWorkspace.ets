import { MotionTokens } from '../utils/MotionTokens';

@Component
export struct PostWorkspace {
  @Prop compact: boolean = false;
  @Prop pageMargin: number = 18;
  @Prop aiEndpoint: string = '';
  @Prop aiToken: string = '';
  @Prop aiStatus: string = '未配置';
  @Prop aiConfigured: boolean = false;
  @Prop stackFileUrl: string = '';
  @Prop aiFileUrl: string = '';
  @Prop aiModelVersion: string = '';
  @Prop timelapseFileUrl: string = '';
  @Prop plateSolveCount: number = 0;
  @Prop correctionCount: number = 0;
  @Prop completedFrames: number = 0;

  onEndpointChange: (value: string) => void = (_value: string): void => {};
  onTokenChange: (value: string) => void = (_value: string): void => {};
  onApplyConfiguration: () => void = (): void => {};

  build() {
    Column({ space: 14 }) {
      Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
        this.PanelTitle('可信图像后期', 'AI 只处理背景噪声与光污染，不生成、删除或移动星体')
        if (!this.compact) Blank()
        Button('导出处理记录')
          .height(48).padding({ left: 20, right: 20 }).fontSize(14)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
      }.width('100%')

      Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
        TextInput({ placeholder: '云增强服务地址，例如 https://example.com', text: this.aiEndpoint })
          .layoutWeight(1).height(48).fontSize(13).fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_surface_secondary'))
          .borderRadius($r('app.float.corner_card'))
          .onChange(this.onEndpointChange)
        TextInput({ placeholder: '访问令牌（服务未启用鉴权时可空）', text: this.aiToken })
          .width(this.compact ? '100%' : 250).height(48).fontSize(13)
          .fontColor($r('app.color.app_text_primary'))
          .type(InputType.Password)
          .backgroundColor($r('app.color.app_surface_secondary'))
          .borderRadius($r('app.float.corner_card'))
          .onChange(this.onTokenChange)
        Button('应用云配置')
          .height(48).padding({ left: 20, right: 20 }).fontSize(14)
          .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(24)
          .onClick(this.onApplyConfiguration)
        Text(this.aiStatus).width(this.compact ? '100%' : 92)
          .fontSize(12).fontColor(this.aiConfigured ? $r('app.color.app_success') : $r('app.color.app_warning'))
      }.width('100%')

      Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
        this.ImageResultPanel('本地堆栈', this.stackFileUrl.length > 0 ? '树莓派处理结果' : '等待真实任务文件',
          '#17202A', this.stackFileUrl)
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(24).fontColor([$r('app.color.app_brand')])
          Text('拖动对比').fontSize(12).fontColor($r('app.color.app_text_secondary'))
        }.width(58).alignItems(HorizontalAlign.Center)
        this.ImageResultPanel('AI 增强', this.aiFileUrl.length > 0 ?
          `模型 ${this.aiModelVersion.length > 0 ? this.aiModelVersion : '已记录'}` : '等待云端处理记录',
          '#101D1A', this.aiFileUrl)
      }
      .layoutWeight(1)
      .width('100%')

      if (this.timelapseFileUrl.length > 0) {
        Video({ src: this.timelapseFileUrl })
          .width('100%').height(180).controls(true).autoPlay(false)
          .objectFit(ImageFit.Contain).backgroundColor($r('app.color.sky_background'))
          .borderRadius($r('app.float.corner_card'))
          .transition(MotionTokens.modal())
      }

      Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
        this.PostMetric('板解析', `${this.plateSolveCount} 次`, '#57C995')
        this.PostMetric('漂移修正', `${this.correctionCount} 次`, '#72D3F5')
        this.PostMetric('光污染梯度', this.stackFileUrl.length > 0 ? '已校正' : '待处理', '#F4BA58')
        this.PostMetric('原片证据', this.completedFrames > 0 ? `${this.completedFrames} 帧 + 日志` : '等待任务', '#E5E9F0')
      }.width('100%')
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
  private ImageResultPanel(title: string, subtitle: string, fillColor: string, sourceUrl: string) {
    Column() {
      if (sourceUrl.length > 0) {
        Image(sourceUrl).layoutWeight(1).width('100%').objectFit(ImageFit.Contain).backgroundColor('#05070B')
          .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
      } else {
        Stack() {
          Rect().width('100%').height('100%').fill(fillColor)
          Text('等待真实图像').fontSize(14).fontColor($r('app.color.app_text_secondary'))
        }.layoutWeight(1).width('100%')
          .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
      }
      Row() {
        Column({ space: 3 }) {
          Text(title).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary')).width('100%')
          Text(subtitle).fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
        }.layoutWeight(1)
        Text('4K JPEG').fontSize(12).fontColor($r('app.color.app_brand'))
      }.width('100%').height(58).padding({ left: 14, right: 14 })
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .clip(true)
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private PostMetric(label: string, value: string, color: string) {
    Row() {
      Column({ space: 3 }) {
        Text(label).fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
        Text(value).fontSize(13).fontWeight(FontWeight.Bold).fontColor(color).width('100%')
      }.layoutWeight(1)
    }
    .layoutWeight(1)
    .height(58)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }
}

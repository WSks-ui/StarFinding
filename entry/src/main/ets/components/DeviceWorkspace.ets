import { ConnectionState } from '../models';

interface DeviceStatusLine {
  name: string;
  detail: string;
  state: string;
  color: ResourceColor;
}

@Component
export struct DeviceWorkspace {
  @Prop compact: boolean = false;
  @Prop pageMargin: number = 18;
  @Prop mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop gatewayConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop gatewayDetail: string = '';
  @Prop mountHomed: boolean = false;
  @Prop tracking: boolean = false;
  @Prop locationSynced: boolean = false;
  @Prop observerAvailable: boolean = false;
  @Prop locationText: string = '等待定位';
  @Prop mountRaHours: number = 0;
  @Prop mountDecDegrees: number = 0;
  @Prop mountSlewing: boolean = false;

  onToggleMount: () => void = (): void => {};
  onToggleGateway: () => void = (): void => {};
  onHomeMount: () => void = (): void => {};
  onSyncObserver: () => void = (): void => {};
  onToggleTracking: () => void = (): void => {};
  onParkMount: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row,
          wrap: FlexWrap.NoWrap }) {
          this.ConnectionPanel('赤道仪', 'OnStepX · TCP 9999', this.mountConnection, this.onToggleMount)
          this.ConnectionPanel('相机网关', this.gatewayDetail, this.gatewayConnection, this.onToggleGateway)
        }.width('100%')

        Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row,
          wrap: FlexWrap.NoWrap }) {
          Column({ space: 14 }) {
            this.PanelTitle('赤道仪操作', '自动运动前必须完成两轴回零和位置时间同步')
            Row({ space: 10 }) {
              this.ActionButton($r('sys.symbol.house'), '两轴回零',
                this.mountConnection === ConnectionState.CONNECTED, this.onHomeMount)
              this.ActionButton($r('sys.symbol.scope'), '同步位置',
                this.mountConnection === ConnectionState.CONNECTED && this.observerAvailable, this.onSyncObserver)
              this.ActionButton($r('sys.symbol.play_circle'), this.tracking ? '停止跟踪' : '恒星跟踪',
                this.mountHomed && this.locationSynced, this.onToggleTracking)
              this.ActionButton($r('sys.symbol.pause_circle'), '停放设备', this.mountHomed, this.onParkMount)
            }.width('100%')

            Column({ space: 9 }) {
              ForEach(this.deviceLines(), (line: DeviceStatusLine) => {
                Row({ space: 10 }) {
                  Circle().width(8).height(8).fill(line.color)
                  Text(line.name).fontSize(13).fontColor($r('app.color.app_text_secondary')).width(108)
                  Text(line.detail).fontSize(13).fontColor($r('app.color.app_text_primary')).layoutWeight(1)
                  Text(line.state).fontSize(12).fontColor(line.color)
                }.width('100%').height(40)
              }, (line: DeviceStatusLine) => line.name)
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.app_background_primary'))
            .borderRadius($r('app.float.corner_card'))
          }
          .layoutWeight(1)
          .height(300)
          .padding(20)
          .backgroundColor($r('app.color.app_background_secondary'))
          .borderRadius($r('app.float.corner_card'))
          .border({ width: 1, color: $r('app.color.app_divider') })

          Column({ space: 14 }) {
            this.PanelTitle('实时遥测', '软件软限位不会替代物理急停')
            this.TelemetryLine('赤经', this.formatRa(this.mountRaHours))
            this.TelemetryLine('赤纬', this.formatDec(this.mountDecDegrees))
            this.TelemetryLine('运动状态', this.mountSlewing ? '转动中' : '静止')
            this.TelemetryLine('位置同步', this.locationSynced ? '已同步' : '未同步')
            this.TelemetryLine('跟踪模式', this.tracking ? '恒星时' : '已停止')
            this.TelemetryLine('安全状态', this.mountHomed ? '软限位有效' : '等待回零')
          }
          .width(this.compact ? '100%' : 330)
          .height(300)
          .padding(20)
          .backgroundColor($r('app.color.app_background_secondary'))
          .borderRadius($r('app.float.corner_card'))
          .border({ width: 1, color: $r('app.color.app_divider') })
        }
      }
      .width('100%')
      .padding(this.pageMargin)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ConnectionPanel(title: string, subtitle: string, state: ConnectionState, action: () => void) {
    Flex({ direction: this.compact ? FlexDirection.Column : FlexDirection.Row, wrap: FlexWrap.NoWrap }) {
      Circle().width(14).height(14).fill(this.connectionColor(state))
      Column({ space: 4 }) {
        Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
        Text(subtitle).fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
      }.layoutWeight(1)
      Text(this.connectionText(state)).fontSize(13).fontColor(this.connectionColor(state))
      Button(state === ConnectionState.CONNECTED || state === ConnectionState.SIMULATED ? '断开' : '连接')
        .height(48).padding({ left: 20, right: 20 }).fontSize(14)
        .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(24)
        .onClick(action)
    }
    .layoutWeight(1)
    .height(96)
    .padding({ left: 20, right: 16 })
    .backgroundColor($r('app.color.app_background_secondary'))
    .border({ width: 1, color: $r('app.color.app_divider') })
    .borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private PanelTitle(title: string, subtitle: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_text_primary')).width('100%')
      Text(subtitle).fontSize(12).fontColor($r('app.color.app_text_secondary')).width('100%')
    }.width('100%')
  }

  @Builder
  private ActionButton(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Column({ space: 6 }) {
      SymbolGlyph(icon).fontSize(26)
        .fontColor([enabled ? $r('app.color.app_brand') : $r('app.color.app_text_tertiary')])
      Text(label).fontSize(13)
        .fontColor(enabled ? $r('app.color.app_text_primary') : $r('app.color.app_text_tertiary'))
    }
    .layoutWeight(1)
    .height(84)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .opacity(enabled ? 1 : 0.65)
    .onClick(() => {
      if (enabled) action();
    })
  }

  @Builder
  private TelemetryLine(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.app_text_secondary'))
      Blank()
      Text(value).fontSize(13).fontColor($r('app.color.app_text_primary'))
    }.width('100%').height(32)
  }

  private connectionText(state: ConnectionState): string {
    if (state === ConnectionState.CONNECTED) return '已连接';
    if (state === ConnectionState.CONNECTING) return '连接中';
    if (state === ConnectionState.ERROR) return '异常';
    if (state === ConnectionState.SIMULATED) return '模拟';
    return '未连接';
  }

  private connectionColor(state: ConnectionState): ResourceColor {
    if (state === ConnectionState.CONNECTED) return $r('app.color.app_success');
    if (state === ConnectionState.CONNECTING) return $r('app.color.app_warning');
    if (state === ConnectionState.ERROR) return $r('app.color.app_error');
    if (state === ConnectionState.SIMULATED) return $r('app.color.app_brand');
    return $r('app.color.app_text_tertiary');
  }

  private deviceLines(): DeviceStatusLine[] {
    return [
      { name: '网络', detail: 'StarScope · 10.42.0.20:9999', state: this.connectionText(this.mountConnection),
        color: this.connectionColor(this.mountConnection) },
      { name: '机械零位', detail: 'AUX3 / AUX4 常闭原点开关', state: this.mountHomed ? '已回零' : '未回零',
        color: this.mountHomed ? $r('app.color.app_success') : $r('app.color.app_warning') },
      { name: '位置时间', detail: this.locationText, state: this.locationSynced ? '已同步' : '待同步',
        color: this.locationSynced ? $r('app.color.app_success') : $r('app.color.app_warning') },
      { name: '物理急停', detail: '独立切断电机电源', state: '需人工确认', color: '#E05B64' }
    ];
  }

  private formatRa(raHours: number): string {
    const normalized: number = ((raHours % 24) + 24) % 24;
    const totalSeconds: number = Math.round(normalized * 3600.0);
    const hours: number = Math.floor(totalSeconds / 3600) % 24;
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    return `${this.pad2(hours)}h ${this.pad2(minutes)}m ${this.pad2(seconds)}s`;
  }

  private formatDec(decDegrees: number): string {
    const sign: string = decDegrees >= 0 ? '+' : '-';
    const absolute: number = Math.abs(decDegrees);
    const degrees: number = Math.floor(absolute);
    const minutes: number = Math.floor((absolute - degrees) * 60.0);
    const seconds: number = Math.round((((absolute - degrees) * 60.0) - minutes) * 60.0);
    return `${sign}${degrees.toString()}° ${this.pad2(minutes)}′ ${this.pad2(seconds)}″`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}

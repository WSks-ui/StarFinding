import { MotionTokens } from '../utils/MotionTokens';

@Component
export struct WorkspaceNavigationDock {
  @Prop compact: boolean = false;
  @Prop veryNarrow: boolean = false;
  @Prop activeSection: number = 0;
  @Prop activeSkyPanel: number = 0;
  @Prop showEmergency: boolean = false;
  @State private pressedLabel: string = '';

  onTarget: () => void = (): void => {};
  onPlanning: () => void = (): void => {};
  onDevice: () => void = (): void => {};
  onTask: () => void = (): void => {};
  onPost: () => void = (): void => {};
  onImmersive: () => void = (): void => {};
  onEmergency: () => void = (): void => {};

  build() {
    if (this.compact) {
      Row({ space: 4 }) {
        this.DockButton($r('sys.symbol.star'), '天体',
          this.activeSection === 0 && this.activeSkyPanel === 1, true, this.onTarget)
        this.DockButton($r('sys.symbol.calendar'), '规划',
          this.activeSection === 0 && this.activeSkyPanel === 2, true, this.onPlanning)
        this.DockButton($r('sys.symbol.device_2'), '设备', this.activeSection === 1, true, this.onDevice)
        this.DockButton($r('sys.symbol.list_bullet_square'), '任务', this.activeSection === 2, true, this.onTask)
        this.DockButton($r('sys.symbol.adjustment'), '后期', this.activeSection === 3, true, this.onPost)
      }
      .width('100%')
      .height(72)
      .padding(6)
      .backgroundColor($r('app.color.sky_surface'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius($r('app.float.corner_modal'))
    } else {
      Column({ space: 4 }) {
        this.DockButton($r('sys.symbol.star'), '天体',
          this.activeSection === 0 && this.activeSkyPanel === 1, false, this.onTarget)
        this.DockButton($r('sys.symbol.calendar'), '规划',
          this.activeSection === 0 && this.activeSkyPanel === 2, false, this.onPlanning)
        this.DockButton($r('sys.symbol.device_2'), '设备', this.activeSection === 1, false, this.onDevice)
        this.DockButton($r('sys.symbol.list_bullet_square'), '任务', this.activeSection === 2, false, this.onTask)
        this.DockButton($r('sys.symbol.adjustment'), '后期', this.activeSection === 3, false, this.onPost)
        this.DockButton($r('sys.symbol.fullscreen'), '沉浸', false, false, this.onImmersive)

        if (this.showEmergency) {
          Button() {
            SymbolGlyph($r('sys.symbol.stop_circle_fill'))
              .fontSize(24)
              .fontColor([$r('app.color.sky_text_primary')])
          }
            .width(48)
            .height(48)
            .backgroundColor($r('app.color.app_error_container'))
            .borderRadius(24)
            .accessibilityText('全局急停')
            .onClick(this.onEmergency)
        }
      }
      .width(72)
      .padding(8)
      .backgroundColor($r('app.color.sky_surface'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius($r('app.float.corner_modal'))
    }
  }

  @Builder
  private DockButton(icon: Resource, label: string, active: boolean, compact: boolean,
    action: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      if (active) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.app_brand'))
          .borderRadius($r('app.float.corner_control'))
          .geometryTransition('workspace-navigation-indicator', { follow: true })
          .transition(TransitionEffect.OPACITY.animation(MotionTokens.quick()))
      }

      Column({ space: 3 }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([active ? $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary')])
        if (!this.veryNarrow) {
          Text(label)
            .fontSize(12)
            .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(active ? $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary'))
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(compact ? 1 : 0)
    .width(compact ? '100%' : 56)
    .height(compact ? 58 : 56)
    .borderRadius($r('app.float.corner_control'))
    .scale({
      x: this.pressedLabel === label ? 0.96 : (active ? 1.04 : 1),
      y: this.pressedLabel === label ? 0.96 : (active ? 1.04 : 1)
    })
    .animation(MotionTokens.quick())
    .accessibilityText(label)
    .accessibilitySelected(active)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedLabel = label;
      } else if (this.pressedLabel === label) {
        this.pressedLabel = '';
      }
    })
    .onClick(action)
  }
}

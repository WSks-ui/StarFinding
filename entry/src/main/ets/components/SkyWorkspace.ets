import { ConnectionState, TaskStatus } from '../models';
import {
  NormalSkyViewport,
  SkyMapOrientation,
  SkyOrientationSnapshot
} from '../models/NormalSkyModels';
import { MotionTokens } from '../utils/MotionTokens';
import { WorkspaceNavigationDock } from './WorkspaceNavigationDock';

@Component
export struct SkyWorkspace {
  @Prop skyMode: number = 0;
  @Prop chromeVisible: boolean = true;
  @Prop overlayPanel: number = 0;
  @Prop viewportWidth: number = 600;
  @Prop viewportHeight: number = 500;
  @Prop targetSearch: string = '';
  @Prop observerAvailable: boolean = false;
  @Prop locationText: string = '等待定位';
  @Prop currentTimeText: string = '--:--';
  @Prop mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop gatewayConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop taskStatus: TaskStatus = TaskStatus.PENDING;
  @Prop emergencyMessage: string = '';
  @Prop operationMessage: string = '';
  @Prop targetName: string = '';
  @Prop recommendationTitle: string = '';
  @Prop recommendationColor: ResourceColor = '#72D3F5';
  @Prop planningWindowText: string = '';
  @Prop weatherSourceText: string = '';
  @Prop poseReady: boolean = false;
  @Prop poseHeading: number = 0;
  @Prop posePitch: number = 0;
  @Prop calibrationText: string = '未校准';
  @Prop calibrationEnabled: boolean = false;
  @Prop calibrationFeedbackActive: boolean = false;
  @Prop arTrackingText: string = '';
  @Prop domeRevealLevel: number = 2;
  @Prop gestureEnabled: boolean = false;
  @Prop normalViewport: NormalSkyViewport = {
    centerRaHours: 0.0,
    centerDecDegrees: 0.0,
    fieldOfViewDegrees: 100.0,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
  @Prop normalOrientationSnapshot: SkyOrientationSnapshot = {
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP,
    centerRaHours: 0.0,
    centerDecDegrees: 0.0,
    northScreenAngleDegrees: 0.0,
    eastScreenAngleDegrees: -90.0,
    markers: []
  };

  @BuilderParam skyCanvas: () => void = this.EmptyBuilder;
  @BuilderParam gesturePreview: () => void = this.EmptyBuilder;
  @BuilderParam normalControls: () => void = this.EmptyBuilder;
  @BuilderParam normalTimeControls: () => void = this.EmptyBuilder;
  @BuilderParam normalOrientation: () => void = this.EmptyBuilder;
  @BuilderParam targetDrawer: () => void = this.EmptyBuilder;
  @BuilderParam planningDrawer: () => void = this.EmptyBuilder;

  onViewportChange: (width: number, height: number) => void = (_width: number, _height: number): void => {};
  onSearchChange: (value: string) => void = (_value: string): void => {};
  onSearchSubmit: (value: string) => void = (_value: string): void => {};
  onOpenPanel: (panel: number) => void = (_panel: number): void => {};
  onNavigate: (section: number) => void = (_section: number): void => {};
  onChromeVisibleChange: (visible: boolean) => void = (_visible: boolean): void => {};
  onNoticeDismiss: () => void = (): void => {};
  onModeChange: (mode: number) => void = (_mode: number): void => {};
  onDomeRevealChange: (level: number) => void = (_level: number): void => {};
  onEmergencyStop: () => void = (): void => {};
  onOpenPlanningLocation: () => void = (): void => {};

  @Builder
  private EmptyBuilder() {}

  build() {
    Stack() {
      this.skyCanvas()

      if (this.skyMode === 1) {
        this.normalOrientation()
      }

      if (this.chromeVisible) {
        this.SkyBrandPill()
        this.SkySearchCapsule()
        if (!this.useBottomSheet()) this.SkyTopStatusCapsule()
        if (this.hasNotice() && !(this.useBottomSheet() && this.overlayPanel > 0)) this.SkyNoticeCapsule()
        if (this.overlayPanel === 0 && !(this.useBottomSheet() && this.hasNotice())) this.SkyTargetPeekCapsule()
        if (this.skyMode === 0 && this.overlayPanel === 0 && this.viewportHeight >= 480) {
          this.SkyDomeRevealCapsule()
        }
        this.SkyNavigationDock()
        if (!(this.useBottomSheet() && this.overlayPanel > 0)) this.SkyBottomControlCapsule()

        if (this.skyMode === 1 && this.overlayPanel === 0) {
          this.normalControls()
          this.normalTimeControls()
        }

        if (this.skyMode === 1 && this.gestureEnabled &&
          (!this.useBottomSheet() || (this.viewportWidth >= 360 && this.viewportHeight >= 360)) &&
          !(this.useBottomSheet() && this.overlayPanel > 0)) {
          this.gesturePreview()
        }

        if (this.overlayPanel === 1) {
          this.targetDrawer()
        } else if (this.overlayPanel === 2) {
          this.planningDrawer()
        }
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(24).fontColor([$r('app.color.sky_text_primary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.sky_surface')).borderRadius(24)
          .backgroundBlurStyle(BlurStyle.Thin)
          .position({ x: 16, y: this.topChromeY() })
          .transition(MotionTokens.capsule())
          .onClick(() => { this.onChromeVisibleChange(true); })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.sky_background'))
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      const height: number = Number(newValue.height);
      if (!Number.isFinite(width) || !Number.isFinite(height) || width < 1 || height < 1) return;
      if (Math.abs(width - this.viewportWidth) < 0.5 && Math.abs(height - this.viewportHeight) < 0.5) return;
      // 抽屉始终悬浮在完整视口之上，避免开合时改变天球投影坐标。
      this.onViewportChange(width, height);
    })
  }

  @Builder
  private SkyBrandPill() {
    Column({ space: 1 }) {
      Text('探星').fontSize(this.useBottomSheet() ? 18 : 20)
        .fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary')).width('100%')
      if (!this.isVeryNarrow()) {
        Text('StarFinding').fontSize(12).fontColor($r('app.color.sky_text_tertiary')).width('100%')
      }
    }
    .width(this.isVeryNarrow() ? 72 : (this.useBottomSheet() ? 108 : 148))
    .height(52)
    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .backgroundColor($r('app.color.sky_surface_soft'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_card'))
    .position({ x: 16, y: this.topChromeY() })
    .transition(MotionTokens.capsule())
  }

  @Builder
  private SkySearchCapsule() {
    Search({ value: this.targetSearch, placeholder: '搜索天体、星座或编号' })
      .width(this.searchWidth()).height(52).textFont({ size: 14 })
      .fontColor($r('app.color.sky_text_primary'))
      .placeholderColor($r('app.color.sky_text_tertiary'))
      .searchButton('搜索', { fontSize: 14, fontColor: $r('app.color.app_brand') })
      .backgroundColor($r('app.color.sky_surface_soft'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius($r('app.float.corner_control'))
      .onChange(this.onSearchChange)
      .onSubmit(this.onSearchSubmit)
      .position({ x: this.searchX(), y: this.topChromeY() })
      .transition(MotionTokens.capsule())
  }

  @Builder
  private SkyTopStatusCapsule() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        Circle().width(7).height(7).fill(this.observerAvailable ? '#57C995' : '#F4BA58')
        Text(this.observerAvailable ? this.locationText : '位置待定')
          .fontSize(12).fontColor($r('app.color.sky_text_secondary')).maxLines(1)
      }.layoutWeight(1).onClick(this.onOpenPlanningLocation)
      Text(this.currentTimeText).fontSize(13).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.sky_text_primary'))
      Row({ space: 5 }) {
        Circle().width(7).height(7).fill(this.connectionColor(this.mountConnection))
        Circle().width(7).height(7).fill(this.connectionColor(this.gatewayConnection))
      }
    }
    .width(280).height(52).padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.sky_surface_soft')).backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_card'))
    .position({ x: Math.max(16, this.viewportWidth - 296), y: this.topChromeY() })
    .transition(MotionTokens.capsule())
  }

  @Builder
  private SkyNoticeCapsule() {
    Row({ space: 8 }) {
      Circle().width(8).height(8).fill(this.emergencyMessage.length > 0 ? '#E05B64' : '#72D3F5')
      Text(this.emergencyMessage.length > 0 ? this.emergencyMessage : this.operationMessage)
        .layoutWeight(1).fontSize(12).lineHeight(18).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor(this.emergencyMessage.length > 0 ? '#FFD6D9' : '#C7D1DE')
      Button() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('app.color.sky_text_secondary')])
      }
        .width(40).height(40).backgroundColor('transparent').borderRadius(20)
        .onClick(this.onNoticeDismiss)
    }
    .width(Math.min(480, this.bottomControlWidth()))
    .padding({ left: 14, right: 6, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.sky_surface')).backgroundBlurStyle(BlurStyle.Regular)
    .border({ width: 1, color: this.emergencyMessage.length > 0 ?
      $r('app.color.app_error') : $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_card'))
    .position({ x: this.bottomControlX(), y: this.topChromeY() + 60 })
    .transition(MotionTokens.capsule())
  }

  @Builder
  private SkyTargetPeekCapsule() {
    Row({ space: 9 }) {
      Circle().width(9).height(9).fill(this.recommendationColor)
      Column({ space: 2 }) {
        Text(`${this.targetName} · ${this.recommendationTitle}`)
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary')).width('100%')
        Text(`${this.planningWindowText} · ${this.weatherSourceText}`)
          .fontSize(12).fontColor($r('app.color.sky_text_tertiary')).width('100%')
      }.layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([$r('app.color.app_brand')])
    }
    .width(this.useBottomSheet() ? Math.max(0, Math.min(228, this.viewportWidth - 24)) : 252).height(56)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.sky_surface_soft')).backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_card'))
    .position({ x: Math.max(16, this.viewportWidth - (this.useBottomSheet() ? 244 : 268)), y: this.topChromeY() + 60 })
    .transition(MotionTokens.capsule())
    .onClick(() => { this.onOpenPanel(2); })
  }

  @Builder
  private SkyNavigationDock() {
    if (this.useBottomSheet()) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.overlayPanel === 1) {
          this.SharedNavigationDock(true, 1)
        } else if (this.overlayPanel === 2) {
          this.SharedNavigationDock(true, 2)
        } else {
          this.SharedNavigationDock(true, 0)
        }
      }
        .width(Math.max(0, this.viewportWidth - 32))
        .height(72)
        .position({ x: 16, y: Math.max(16, this.viewportHeight - 96) })
        .transition(MotionTokens.capsule())
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.overlayPanel === 1) {
          this.SharedNavigationDock(false, 1)
        } else if (this.overlayPanel === 2) {
          this.SharedNavigationDock(false, 2)
        } else {
          this.SharedNavigationDock(false, 0)
        }
      }
        .width(72)
        .position({ x: 16, y: this.topChromeY() + 64 })
        .transition(MotionTokens.capsule())
    }
  }

  @Builder
  private SharedNavigationDock(compact: boolean, activeSkyPanel: number) {
    WorkspaceNavigationDock({
      compact: compact,
      veryNarrow: compact && this.isVeryNarrow(),
      activeSection: 0,
      activeSkyPanel: activeSkyPanel,
      showEmergency: this.mountConnection !== ConnectionState.DISCONNECTED ||
        this.gatewayConnection !== ConnectionState.DISCONNECTED || this.taskStatus === TaskStatus.RUNNING,
      onTarget: (): void => { this.onOpenPanel(1); },
      onPlanning: (): void => { this.onOpenPanel(2); },
      onDevice: (): void => { this.onNavigate(1); },
      onTask: (): void => { this.onNavigate(2); },
      onPost: (): void => { this.onNavigate(3); },
      onImmersive: (): void => {
        this.onOpenPanel(0);
        this.onChromeVisibleChange(false);
      },
      onEmergency: this.onEmergencyStop
    })
  }

  @Builder
  private SkyBottomControlCapsule() {
    Row({ space: 8 }) {
      this.ModeTab('AR', 0)
      this.ModeTab('星图', 1)
      if (this.skyMode === 1) {
        Rect().width(1).height(22).fill($r('app.color.sky_border'))
        Text(this.normalViewport.orientation === SkyMapOrientation.EQUATORIAL_NORTH_UP ?
          $r('app.string.normal_sky_equatorial_mode') : $r('app.string.normal_sky_horizon_mode'))
          .fontSize(12).fontColor($r('app.color.sky_text_secondary'))
        if (!this.isVeryNarrow()) {
          Text(this.normalCenterDirectionText()).fontSize(12)
            .fontColor($r('app.color.sky_text_secondary')).maxLines(1)
        }
        Text(`${this.normalViewport.fieldOfViewDegrees.toFixed(0)}°`)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_brand'))
      } else if (this.isVeryNarrow()) {
        Text(this.poseReady ? `${this.poseHeading.toFixed(0)}°` : '姿态 --')
          .fontSize(12).fontColor($r('app.color.sky_text_secondary'))
      } else {
        Rect().width(1).height(22).fill($r('app.color.sky_border'))
        Text(this.poseReady ? `方位 ${this.poseHeading.toFixed(0)}°` : '方位 --')
          .fontSize(12).fontColor($r('app.color.sky_text_secondary'))
        Text(this.poseReady ? `高度 ${this.posePitch.toFixed(0)}°` : '高度 --')
          .fontSize(12).fontColor($r('app.color.sky_text_secondary'))
        Text(this.calibrationText).fontSize(12)
          .fontColor(this.calibrationEnabled ? $r('app.color.app_success') : $r('app.color.app_warning'))
          .scale({
            x: this.calibrationFeedbackActive ? 1.08 : 1,
            y: this.calibrationFeedbackActive ? 1.08 : 1
          })
          .animation(MotionTokens.spring())
        if (!this.useBottomSheet()) {
          Text(this.arTrackingText).fontSize(12).fontColor($r('app.color.sky_text_tertiary'))
        }
      }
    }
    .width(this.bottomControlWidth()).height(52).padding({ left: 8, right: 14 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.sky_surface')).backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_control'))
    .position({ x: this.bottomControlX(), y: this.bottomControlY() })
    .transition(MotionTokens.capsule())
  }

  private normalCenterDirectionText(): string {
    if (this.normalViewport.orientation === SkyMapOrientation.HORIZON_ZENITH &&
      this.normalOrientationSnapshot.centerAzimuthDegrees !== undefined &&
      this.normalOrientationSnapshot.centerAltitudeDegrees !== undefined) {
      return `${this.normalOrientationSnapshot.centerAzimuthDegrees.toFixed(0)}° / ` +
        `${this.normalOrientationSnapshot.centerAltitudeDegrees.toFixed(0)}°`;
    }
    const sign: string = this.normalOrientationSnapshot.centerDecDegrees >= 0.0 ? '+' : '';
    return `${this.normalOrientationSnapshot.centerRaHours.toFixed(2)}h / ` +
      `${sign}${this.normalOrientationSnapshot.centerDecDegrees.toFixed(1)}°`;
  }

  @Builder
  private SkyDomeRevealCapsule() {
    Row({ space: 2 }) {
      this.DomeRevealButton('肉眼', 0)
      this.DomeRevealButton('平衡', 1)
      this.DomeRevealButton('天穹', 2)
    }
    .width(216).height(44).padding(4)
    .backgroundColor($r('app.color.sky_surface')).backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_control'))
    .position({ x: Math.max(12, this.viewportWidth / 2 - 108),
      y: Math.max(this.topChromeY() + 60, this.bottomControlY() - 52) })
    .transition(MotionTokens.capsule())
  }

  @Builder
  private DomeRevealButton(label: string, level: number) {
    Button(label).layoutWeight(1).height(36).fontSize(12)
      .fontWeight(this.domeRevealLevel === level ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.domeRevealLevel === level ? $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary'))
      .backgroundColor(this.domeRevealLevel === level ? $r('app.color.app_brand') : 'transparent')
      .borderRadius(18).animation(MotionTokens.quick())
      .onClick(() => { this.onDomeRevealChange(level); })
  }

  @Builder
  private ModeTab(label: string, mode: number) {
    Button(label).height(40).padding({ left: 16, right: 16 }).fontSize(14)
      .fontWeight(this.skyMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.skyMode === mode ? $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary'))
      .backgroundColor(this.skyMode === mode ? $r('app.color.app_brand') : 'transparent')
      .borderRadius(20).animation(MotionTokens.quick())
      .onClick(() => { this.onModeChange(mode); })
  }

  private useBottomSheet(): boolean {
    return this.viewportWidth < 840 || this.viewportHeight < 600;
  }

  private isVeryNarrow(): boolean {
    return this.useBottomSheet() && this.viewportWidth < 360;
  }

  private topChromeY(): number {
    return this.viewportHeight < 420 ? 28 : 40;
  }

  private searchWidth(): number {
    if (this.isVeryNarrow()) return Math.max(120, this.viewportWidth - 112);
    if (this.useBottomSheet()) return Math.max(170, this.viewportWidth - 154);
    return Math.min(390, Math.max(260, this.viewportWidth - 640));
  }

  private searchX(): number {
    const width: number = this.searchWidth();
    if (this.isVeryNarrow()) return 96;
    if (this.useBottomSheet()) return Math.max(132, this.viewportWidth - width - 16);
    return Math.max(180, (this.viewportWidth - width) / 2);
  }

  private drawerWidth(): number {
    if (this.useBottomSheet()) {
      return this.viewportWidth < 260 ? Math.max(0, this.viewportWidth - 16) : Math.max(240, this.viewportWidth - 24);
    }
    return this.overlayPanel === 2 ? 420 : 350;
  }

  private drawerX(): number {
    if (this.useBottomSheet()) return 12;
    return Math.max(90, this.viewportWidth - this.drawerWidth() - 16);
  }

  private bottomControlWidth(): number {
    if (this.useBottomSheet()) {
      return this.viewportWidth < 260 ? Math.max(0, this.viewportWidth - 16) : Math.max(240, this.viewportWidth - 24);
    }
    const reserved: number = this.overlayPanel > 0 ? this.drawerWidth() + 150 : 300;
    return Math.min(500, Math.max(340, this.viewportWidth - reserved));
  }

  private bottomControlX(): number {
    if (this.useBottomSheet()) return 12;
    const left: number = 90;
    const right: number = this.overlayPanel > 0 ? this.drawerX() - 12 : this.viewportWidth - 16;
    return Math.max(left, left + (right - left - this.bottomControlWidth()) / 2);
  }

  private bottomControlY(): number {
    return Math.max(this.topChromeY() + 60, this.viewportHeight - (this.useBottomSheet() ? 156 : 76));
  }

  private hasNotice(): boolean {
    return this.emergencyMessage.length > 0 || this.operationMessage.length > 0;
  }

  private connectionColor(state: ConnectionState): ResourceColor {
    if (state === ConnectionState.CONNECTED) return $r('app.color.app_success');
    if (state === ConnectionState.CONNECTING) return $r('app.color.app_warning');
    if (state === ConnectionState.ERROR) return $r('app.color.app_error');
    if (state === ConnectionState.SIMULATED) return $r('app.color.app_brand');
    return $r('app.color.app_text_tertiary');
  }
}

import {
  NormalSkyViewport,
  SkyLayerVisibility,
  SkyMapOrientation
} from '../models/NormalSkyModels';
import { MotionTokens } from '../utils/MotionTokens';
import { NormalSkyLayoutService } from '../services/NormalSkyLayoutService';

/** 普通星图控制坞只负责呈现，所有天球状态变更由页面控制器处理。 */
@Component
export struct NormalSkyControls {
  @Prop viewport: NormalSkyViewport;
  @Prop layers: SkyLayerVisibility;
  @Prop panelOpen: boolean = false;
  @Prop viewportWidth: number = 600.0;
  @Prop viewportHeight: number = 500.0;
  @Prop catalogStatus: string = '';
  @Prop lineCatalogStatus: string = '';

  onHome: () => void = (): void => {};
  onResetNorth: () => void = (): void => {};
  onZoomIn: () => void = (): void => {};
  onZoomOut: () => void = (): void => {};
  onToggleOrientation: () => void = (): void => {};
  onTogglePanel: () => void = (): void => {};
  onFieldOfViewChange: (fieldOfViewDegrees: number) => void =
    (_fieldOfViewDegrees: number): void => {};
  onLayerChange: (layer: number, enabled: boolean) => void =
    (_layer: number, _enabled: boolean): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.panelOpen) {
        Column({ space: 7 }) {
          Row() {
            Text('星图图层').fontSize(14).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.sky_text_primary'))
            Blank()
            Text(`${this.viewport.fieldOfViewDegrees.toFixed(0)}°`)
              .fontSize(12).fontColor($r('app.color.app_brand'))
          }.width('100%')
          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.normal_sky_field_of_view')).fontSize(11)
                .fontColor($r('app.color.sky_text_secondary'))
              Blank()
              Text(`${this.viewport.fieldOfViewDegrees.toFixed(0)}°`).fontSize(11)
                .fontWeight(FontWeight.Bold).fontColor($r('app.color.app_brand'))
            }.width('100%')
            Slider({ value: this.viewport.fieldOfViewDegrees, min: 8.0, max: 160.0, step: 2.0 })
              .width('100%')
              .selectedColor($r('app.color.app_brand'))
              .trackColor($r('app.color.sky_border'))
              .onChange((value: number) => { this.onFieldOfViewChange(value); })
          }.width('100%')
          Scroll() {
            Column({ space: 3 }) {
              this.LayerToggle('星座连线', 0, this.layers.constellationLines)
              this.LayerToggle('赤道网格', 1, this.layers.equatorialGrid)
              this.LayerToggle('黄道', 2, this.layers.ecliptic)
              this.LayerToggle('地平线', 3, this.layers.horizon)
              this.LayerToggle('深空天体', 4, this.layers.deepSky)
              this.LayerToggle('太阳系', 5, this.layers.solarSystem)
              this.LayerToggle($r('app.string.normal_sky_direction_guides'), 6, this.layers.directionGuides)
              Text(`${this.catalogStatus} · ${this.lineCatalogStatus}`)
                .fontSize(10).fontColor($r('app.color.sky_text_tertiary')).maxLines(2)
                .width('100%').padding({ top: 4, bottom: 4 })
            }.width('100%')
          }
          .layoutWeight(1).width('100%')
        }
        .width(this.panelWidth()).height(this.panelHeight())
        .padding(12).backgroundColor($r('app.color.sky_surface_strong'))
        .backgroundBlurStyle(BlurStyle.Regular)
        .border({ width: 1, color: $r('app.color.sky_border') })
        .borderRadius($r('app.float.corner_card'))
        .position({ x: 0, y: 34 })
        .transition(MotionTokens.capsule())
      }

      Column({ space: 6 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.house')).fontSize(20)
            .fontColor([$r('app.color.sky_text_primary')])
        }
          .width(44).height(44).backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onHome)
        Button('N')
          .width(44).height(44).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onResetNorth)
        Button('+')
          .width(44).height(44).fontSize(22).fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onZoomIn)
        Button('-')
          .width(44).height(44).fontSize(22).fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onZoomOut)
        Button(this.viewport.orientation === SkyMapOrientation.EQUATORIAL_NORTH_UP ? '地平' : '赤道')
          .width(52).height(44).fontSize(11).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onToggleOrientation)
        Button() {
          SymbolGlyph($r('sys.symbol.adjustment')).fontSize(20)
            .fontColor([this.panelOpen ? $r('app.color.app_brand') : $r('app.color.sky_text_primary')])
        }
          .width(44).height(44).backgroundColor($r('app.color.sky_surface')).borderRadius(22)
          .onClick(this.onTogglePanel)
      }
      .padding(4).backgroundColor($r('app.color.sky_surface_soft')).backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') }).borderRadius(26)
      .position({ x: this.controlWidth() - 56, y: 0 })
    }
    .width(this.controlWidth()).height(this.rootHeight())
    .position({
      x: Math.max(8, this.viewportWidth - this.controlWidth() - 8),
      y: Math.max(72, (this.viewportHeight - this.rootHeight()) / 2.0)
    })
  }

  @Builder
  private LayerToggle(label: ResourceStr, layer: number, enabled: boolean) {
    Row() {
      Text(label).fontSize(12).fontColor($r('app.color.sky_text_secondary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .selectedColor($r('app.color.app_brand'))
        .onChange((value: boolean) => { this.onLayerChange(layer, value); })
    }.width('100%').height(34)
  }

  private controlWidth(): number {
    // 面板关闭时只保留按钮热区，避免透明根容器吞掉右侧大块星图拖拽事件。
    return this.panelOpen ? Math.min(278.0, Math.max(228.0, this.viewportWidth - 16.0)) : 56.0;
  }

  private panelWidth(): number {
    return Math.min(206.0, Math.max(160.0, this.controlWidth() - 68.0));
  }

  private panelHeight(): number {
    return NormalSkyLayoutService.panelHeight(this.viewportHeight);
  }

  private rootHeight(): number {
    return NormalSkyLayoutService.panelRootHeight(this.viewportHeight, this.panelOpen);
  }
}

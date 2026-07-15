import {
  SkyGuideInsets,
  SkyOrientationSnapshot
} from '../models/NormalSkyModels';
import {
  NormalSkyCompassLayout,
  NormalSkyLayoutService
} from '../services/NormalSkyLayoutService';

/** 普通星图常驻紧凑罗盘；N/E 指针随当前天球或地平方向实时旋转。 */
@Component
export struct NormalSkyOrientationOverlay {
  @Prop @Watch('onSnapshotChanged') snapshot: SkyOrientationSnapshot;
  @Prop @Watch('onSnapshotChanged') viewportWidth: number = 600.0;
  @Prop @Watch('onSnapshotChanged') viewportHeight: number = 500.0;
  @Prop @Watch('onSnapshotChanged') guideInsets: SkyGuideInsets;
  @Prop @Watch('onSnapshotChanged') compactDrawerOpen: boolean = false;
  onResetNorth: () => void = (): void => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;

  aboutToDisappear(): void {
    this.canvasReady = false;
  }

  build() {
    Canvas(this.context)
      .width(this.compassLayout().sizePixels).height(this.compassLayout().sizePixels)
      .backgroundColor($r('app.color.sky_surface'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius(this.compassLayout().sizePixels / 2.0)
      .position({ x: this.compassX(), y: this.compassY() })
      .onReady(() => {
        this.canvasReady = true;
        this.drawCompass();
      })
      .onClick(this.onResetNorth)
  }

  private onSnapshotChanged(): void {
    this.drawCompass();
  }

  private drawCompass(): void {
    if (!this.canvasReady) return;
    const size: number = this.compassLayout().sizePixels;
    const scale: number = size / 64.0;
    const center: number = size / 2.0;
    this.context.clearRect(0.0, 0.0, size, size);
    this.context.globalAlpha = 0.72;
    this.context.strokeStyle = '#6F8292';
    this.context.lineWidth = 1.0;
    this.context.beginPath();
    this.context.arc(center, center, 21.0 * scale, 0.0, Math.PI * 2.0);
    this.context.stroke();
    this.drawDirection(this.snapshot.eastScreenAngleDegrees, 'E', '#83C9D9', 16.0 * scale, 0.70);
    this.drawDirection(this.snapshot.northScreenAngleDegrees, 'N', '#72D3F5', 22.0 * scale, 1.0);
    this.context.globalAlpha = 1.0;
    this.context.fillStyle = '#D9F7FF';
    this.context.beginPath();
    this.context.arc(center, center, 2.2 * scale, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private drawDirection(angleDegrees: number, label: string, color: string,
    length: number, opacity: number): void {
    const radians: number = angleDegrees * Math.PI / 180.0;
    const directionX: number = Math.sin(radians);
    const directionY: number = -Math.cos(radians);
    const size: number = this.compassLayout().sizePixels;
    const scale: number = size / 64.0;
    const center: number = size / 2.0;
    const tipX: number = center + directionX * length;
    const tipY: number = center + directionY * length;
    this.context.globalAlpha = opacity;
    this.context.strokeStyle = color;
    this.context.fillStyle = color;
    this.context.lineWidth = (label === 'N' ? 2.0 : 1.2) * scale;
    this.context.beginPath();
    this.context.moveTo(center, center);
    this.context.lineTo(tipX, tipY);
    this.context.stroke();
    const normalX: number = -directionY;
    const normalY: number = directionX;
    this.context.beginPath();
    this.context.moveTo(tipX + directionX * 3.0 * scale, tipY + directionY * 3.0 * scale);
    this.context.lineTo(tipX - directionX * 3.0 * scale + normalX * 2.5 * scale,
      tipY - directionY * 3.0 * scale + normalY * 2.5 * scale);
    this.context.lineTo(tipX - directionX * 3.0 * scale - normalX * 2.5 * scale,
      tipY - directionY * 3.0 * scale - normalY * 2.5 * scale);
    this.context.closePath();
    this.context.fill();
    this.context.font = label === 'N' ? `700 ${10.0 * scale}px sans-serif` :
      `600 ${9.0 * scale}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(label, center + directionX * (length + 8.0 * scale),
      center + directionY * (length + 8.0 * scale));
  }

  private compassX(): number {
    return this.compassLayout().xPixels;
  }

  private compassY(): number {
    return this.compassLayout().yPixels;
  }

  private compassLayout(): NormalSkyCompassLayout {
    return NormalSkyLayoutService.compassLayout(this.viewportWidth, this.viewportHeight,
      this.guideInsets, this.compactDrawerOpen);
  }
}

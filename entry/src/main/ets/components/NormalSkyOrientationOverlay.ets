import {
  SkyGuideInsets,
  SkyOrientationSnapshot
} from '../models/NormalSkyModels';

/** 普通星图常驻紧凑罗盘；N/E 指针随当前天球或地平方向实时旋转。 */
@Component
export struct NormalSkyOrientationOverlay {
  @Prop @Watch('onSnapshotChanged') snapshot: SkyOrientationSnapshot;
  @Prop @Watch('onSnapshotChanged') viewportWidth: number = 600.0;
  @Prop @Watch('onSnapshotChanged') viewportHeight: number = 500.0;
  @Prop @Watch('onSnapshotChanged') guideInsets: SkyGuideInsets;
  onResetNorth: () => void = (): void => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;

  aboutToDisappear(): void {
    this.canvasReady = false;
  }

  build() {
    Canvas(this.context)
      .width(64).height(64)
      .backgroundColor($r('app.color.sky_surface'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius(32)
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
    const center: number = 32.0;
    this.context.clearRect(0.0, 0.0, 64.0, 64.0);
    this.context.globalAlpha = 0.72;
    this.context.strokeStyle = '#6F8292';
    this.context.lineWidth = 1.0;
    this.context.beginPath();
    this.context.arc(center, center, 21.0, 0.0, Math.PI * 2.0);
    this.context.stroke();
    this.drawDirection(this.snapshot.eastScreenAngleDegrees, 'E', '#83C9D9', 16.0, 0.70);
    this.drawDirection(this.snapshot.northScreenAngleDegrees, 'N', '#72D3F5', 22.0, 1.0);
    this.context.globalAlpha = 1.0;
    this.context.fillStyle = '#D9F7FF';
    this.context.beginPath();
    this.context.arc(center, center, 2.2, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private drawDirection(angleDegrees: number, label: string, color: string,
    length: number, opacity: number): void {
    const radians: number = angleDegrees * Math.PI / 180.0;
    const directionX: number = Math.sin(radians);
    const directionY: number = -Math.cos(radians);
    const center: number = 32.0;
    const tipX: number = center + directionX * length;
    const tipY: number = center + directionY * length;
    this.context.globalAlpha = opacity;
    this.context.strokeStyle = color;
    this.context.fillStyle = color;
    this.context.lineWidth = label === 'N' ? 2.0 : 1.2;
    this.context.beginPath();
    this.context.moveTo(center, center);
    this.context.lineTo(tipX, tipY);
    this.context.stroke();
    const normalX: number = -directionY;
    const normalY: number = directionX;
    this.context.beginPath();
    this.context.moveTo(tipX + directionX * 3.0, tipY + directionY * 3.0);
    this.context.lineTo(tipX - directionX * 3.0 + normalX * 2.5,
      tipY - directionY * 3.0 + normalY * 2.5);
    this.context.lineTo(tipX - directionX * 3.0 - normalX * 2.5,
      tipY - directionY * 3.0 - normalY * 2.5);
    this.context.closePath();
    this.context.fill();
    this.context.font = label === 'N' ? '700 10px sans-serif' : '600 9px sans-serif';
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(label, center + directionX * (length + 8.0),
      center + directionY * (length + 8.0));
  }

  private compassX(): number {
    const minimum: number = Math.max(8.0, this.guideInsets.leftPixels + 4.0);
    const desired: number = this.viewportWidth - this.guideInsets.rightPixels - 72.0;
    return Math.max(minimum, Math.min(desired, Math.max(minimum, this.viewportWidth - 72.0)));
  }

  private compassY(): number {
    const minimum: number = Math.max(8.0, this.guideInsets.topPixels + 4.0);
    const desired: number = this.viewportHeight - this.guideInsets.bottomPixels - 72.0;
    return Math.max(minimum, Math.min(desired, Math.max(minimum, this.viewportHeight - 72.0)));
  }
}

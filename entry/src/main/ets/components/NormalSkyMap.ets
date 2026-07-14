import { CelestialType } from '../models/DomainModels';
import {
  NormalSkyScene,
  ProjectedSkyObject,
  SkyPolyline,
  SkyScreenPoint,
  SkyScreenRect
} from '../models/NormalSkyModels';
import { NormalSkyProjectionService } from '../services/NormalSkyProjectionService';

interface SkyLabelBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

const TAP_MOVE_TOLERANCE_PIXELS: number = 14.0;

/** 普通星图单 Canvas 渲染器；绘制对象与命中对象来自同一 NormalSkyScene。 */
@Component
export struct NormalSkyMap {
  @Prop @Watch('onRenderInputChanged') scene: NormalSkyScene;
  @Prop @Watch('onRenderInputChanged') widthPixels: number = 1.0;
  @Prop @Watch('onRenderInputChanged') heightPixels: number = 1.0;
  onObjectSelected: (objectId: string) => void = (_objectId: string): void => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private touchTracking: boolean = false;
  private touchStartX: number = 0.0;
  private touchStartY: number = 0.0;

  aboutToDisappear(): void {
    this.canvasReady = false;
  }

  build() {
    Canvas(this.context)
      .width(Math.max(1.0, this.widthPixels))
      .height(Math.max(1.0, this.heightPixels))
      .clip(true)
      .onReady(() => {
        this.canvasReady = true;
        this.drawScene();
      })
      .onAreaChange((_oldArea: Area, _newArea: Area) => {
        this.drawScene();
      })
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
  }

  private onRenderInputChanged(): void {
    this.drawScene();
  }

  private drawScene(): void {
    if (!this.canvasReady) {
      return;
    }
    const width: number = Math.max(1.0, this.widthPixels);
    const height: number = Math.max(1.0, this.heightPixels);
    this.context.clearRect(0.0, 0.0, width, height);
    this.context.fillStyle = '#050A10';
    this.context.globalAlpha = 1.0;
    this.context.fillRect(0.0, 0.0, width, height);
    this.drawPolylines(this.scene.gridLines, '#29404E', 0.48, 0.7);
    this.drawPolylines(this.scene.eclipticLines, '#B69955', 0.68, 1.0);
    this.drawPolylines(this.scene.constellationLines, '#426B82', 0.76, 1.1);
    this.drawHorizonMask(this.scene.horizonMask);
    this.drawPolylines(this.scene.horizonLines, '#78C9C5', 0.88, 1.4);
    this.drawObjects(this.scene.objects, width, height);
    this.resetContextState();
  }

  private drawPolylines(lines: SkyPolyline[], color: string, opacity: number, lineWidth: number): void {
    this.context.save();
    this.context.strokeStyle = color;
    this.context.globalAlpha = opacity;
    this.context.lineWidth = lineWidth;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    for (let index: number = 0; index < lines.length; index++) {
      const points: SkyScreenPoint[] = lines[index].points;
      if (points.length < 2) {
        continue;
      }
      this.context.beginPath();
      this.context.moveTo(points[0].xPixels, points[0].yPixels);
      for (let pointIndex: number = 1; pointIndex < points.length; pointIndex++) {
        this.context.lineTo(points[pointIndex].xPixels, points[pointIndex].yPixels);
      }
      this.context.stroke();
    }
    this.context.restore();
  }

  private drawHorizonMask(rectangles: SkyScreenRect[]): void {
    this.context.save();
    this.context.fillStyle = '#020407';
    for (let index: number = 0; index < rectangles.length; index++) {
      const rectangle: SkyScreenRect = rectangles[index];
      this.context.globalAlpha = rectangle.opacity;
      this.context.fillRect(rectangle.xPixels, rectangle.yPixels,
        rectangle.widthPixels + 0.5, rectangle.heightPixels + 0.5);
    }
    this.context.restore();
  }

  private drawObjects(objects: ProjectedSkyObject[], width: number, height: number): void {
    const occupied: SkyLabelBox[] = [];
    this.context.save();
    for (let index: number = 0; index < objects.length; index++) {
      const object: ProjectedSkyObject = objects[index];
      if (!this.inDrawingBounds(object, width, height) || object.type === CelestialType.CONSTELLATION) {
        continue;
      }
      const opacity: number = object.aboveHorizon === false ? 0.42 : 1.0;
      this.context.globalAlpha = opacity;
      this.context.fillStyle = object.color;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, Math.max(0.7, object.sizePixels / 2.0),
        0.0, Math.PI * 2.0);
      this.context.fill();
      if (object.type === CelestialType.MESSIER) {
        this.context.globalAlpha = opacity * 0.82;
        this.context.strokeStyle = object.color;
        this.context.lineWidth = 1.0;
        this.context.beginPath();
        this.context.arc(object.xPixels, object.yPixels, Math.max(5.0, object.sizePixels),
          0.0, Math.PI * 2.0);
        this.context.stroke();
      }
    }

    // 标签按业务优先级分批绘制，避免普通暗星占据行星和已选目标的位置。
    for (let priority: number = 100; priority >= 10; priority -= 10) {
      for (let index: number = 0; index < objects.length; index++) {
        const object: ProjectedSkyObject = objects[index];
        if (object.label.length === 0 || !this.inDrawingBounds(object, width, height) ||
          this.labelBucket(object) !== priority) {
          continue;
        }
        this.drawLabel(object, occupied, width, height);
      }
    }
    this.drawSelectedObject(objects, width, height);
    this.context.restore();
  }

  private drawLabel(object: ProjectedSkyObject, occupied: SkyLabelBox[], width: number, height: number): void {
    const constellation: boolean = object.type === CelestialType.CONSTELLATION;
    const fontSize: number = constellation ? 13.0 : (object.selected ? 14.0 : 11.0);
    this.context.font = `${object.selected ? '600' : '500'} ${fontSize}px sans-serif`;
    const textWidth: number = Math.min(190.0, this.context.measureText(object.label).width);
    const boxWidth: number = textWidth + (constellation ? 8.0 : 12.0);
    const boxHeight: number = constellation ? 22.0 : 20.0;
    let boxX: number = object.xPixels + Math.max(6.0, object.sizePixels / 2.0 + 5.0);
    let boxY: number = object.yPixels - boxHeight / 2.0;
    if (boxX + boxWidth > width - 6.0) {
      boxX = object.xPixels - boxWidth - Math.max(6.0, object.sizePixels / 2.0 + 5.0);
    }
    boxX = this.clamp(boxX, 4.0, Math.max(4.0, width - boxWidth - 4.0));
    boxY = this.clamp(boxY, 4.0, Math.max(4.0, height - boxHeight - 4.0));
    const candidate: SkyLabelBox = { x: boxX, y: boxY, width: boxWidth, height: boxHeight };
    if (!object.selected && this.overlaps(candidate, occupied)) {
      return;
    }
    occupied.push(candidate);

    this.context.globalAlpha = object.aboveHorizon === false ? 0.48 :
      (constellation ? 0.74 : 0.94);
    if (!constellation) {
      this.roundedRectPath(boxX, boxY, boxWidth, boxHeight, 4.0);
      this.context.fillStyle = object.selected ? 'rgba(14, 40, 49, 0.94)' : 'rgba(5, 12, 19, 0.78)';
      this.context.fill();
    }
    this.context.fillStyle = object.selected ? '#8CE8E5' :
      (constellation ? '#86A9C4' : '#D8E3EC');
    this.context.textAlign = 'left';
    this.context.textBaseline = 'middle';
    this.context.fillText(object.label, boxX + (constellation ? 4.0 : 6.0),
      boxY + boxHeight / 2.0, Math.max(1.0, boxWidth - 8.0));
  }

  private drawSelectedObject(objects: ProjectedSkyObject[], width: number, height: number): void {
    for (let index: number = 0; index < objects.length; index++) {
      const object: ProjectedSkyObject = objects[index];
      if (!object.selected || !this.inDrawingBounds(object, width, height)) {
        continue;
      }
      this.context.globalAlpha = 0.92;
      this.context.strokeStyle = '#7DE5EA';
      this.context.lineWidth = 1.8;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, Math.max(12.0, object.sizePixels + 7.0),
        0.0, Math.PI * 2.0);
      this.context.stroke();
      return;
    }
  }

  private labelBucket(object: ProjectedSkyObject): number {
    if (object.selected) return 100;
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON ||
      object.type === CelestialType.PLANET) return 90;
    if (object.type === CelestialType.MESSIER) return 80;
    if (object.type === CelestialType.CONSTELLATION) return 70;
    if (object.magnitude !== undefined && object.magnitude <= 1.5) return 60;
    return 50;
  }

  private overlaps(candidate: SkyLabelBox, occupied: SkyLabelBox[]): boolean {
    for (let index: number = 0; index < occupied.length; index++) {
      const current: SkyLabelBox = occupied[index];
      if (candidate.x < current.x + current.width + 3.0 && candidate.x + candidate.width + 3.0 > current.x &&
        candidate.y < current.y + current.height + 3.0 && candidate.y + candidate.height + 3.0 > current.y) {
        return true;
      }
    }
    return false;
  }

  private inDrawingBounds(object: ProjectedSkyObject, width: number, height: number): boolean {
    return object.xPixels >= -30.0 && object.xPixels <= width + 30.0 &&
      object.yPixels >= -30.0 && object.yPixels <= height + 30.0;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.changedTouches.length === 0) {
      return;
    }
    const touch: TouchObject = event.changedTouches[0];
    if (event.type === TouchType.Down) {
      this.touchTracking = true;
      this.touchStartX = touch.x;
      this.touchStartY = touch.y;
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.touchTracking = false;
      return;
    }
    if (event.type !== TouchType.Up || !this.touchTracking) {
      return;
    }
    this.touchTracking = false;
    const deltaX: number = touch.x - this.touchStartX;
    const deltaY: number = touch.y - this.touchStartY;
    if (deltaX * deltaX + deltaY * deltaY >
      TAP_MOVE_TOLERANCE_PIXELS * TAP_MOVE_TOLERANCE_PIXELS) {
      return;
    }
    const selected: ProjectedSkyObject | undefined = NormalSkyProjectionService.hitTest(
      this.scene.objects, touch.x, touch.y, 18.0);
    if (selected !== undefined) {
      this.onObjectSelected(selected.id);
    }
  }

  private roundedRectPath(x: number, y: number, width: number, height: number, radius: number): void {
    const safeRadius: number = Math.min(radius, Math.min(width, height) / 2.0);
    this.context.beginPath();
    this.context.moveTo(x + safeRadius, y);
    this.context.lineTo(x + width - safeRadius, y);
    this.context.quadraticCurveTo(x + width, y, x + width, y + safeRadius);
    this.context.lineTo(x + width, y + height - safeRadius);
    this.context.quadraticCurveTo(x + width, y + height, x + width - safeRadius, y + height);
    this.context.lineTo(x + safeRadius, y + height);
    this.context.quadraticCurveTo(x, y + height, x, y + height - safeRadius);
    this.context.lineTo(x, y + safeRadius);
    this.context.quadraticCurveTo(x, y, x + safeRadius, y);
    this.context.closePath();
  }

  private resetContextState(): void {
    this.context.globalAlpha = 1.0;
    this.context.shadowBlur = 0.0;
    this.context.setLineDash([]);
    this.context.textAlign = 'left';
    this.context.textBaseline = 'alphabetic';
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

import { CelestialType } from '../models/DomainModels';
import {
  NormalSkyScene,
  ProjectedSkyObject,
  SkyDirectionKind,
  SkyDirectionMarker,
  SkyObjectGlyphKind,
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
    this.drawDirectionMarkers(this.scene.orientationSnapshot.markers);
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
      if (object.glyphKind === SkyObjectGlyphKind.STAR) {
        this.drawStarGlyph(object, opacity);
      } else if (this.isSolarSystemGlyph(object.glyphKind)) {
        this.drawSolarSystemGlyph(object, opacity);
      } else {
        this.drawDeepSkyGlyph(object, opacity);
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

  private drawStarGlyph(object: ProjectedSkyObject, opacity: number): void {
    const radius: number = Math.max(0.7, object.sizePixels / 2.0);
    const magnitude: number = object.magnitude === undefined ? 9.0 : object.magnitude;
    if (magnitude <= 1.5 || object.selected) {
      this.context.globalAlpha = opacity * (object.selected ? 0.24 : 0.14);
      this.context.fillStyle = object.color;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius * (object.selected ? 2.8 : 2.15),
        0.0, Math.PI * 2.0);
      this.context.fill();
    }
    if (magnitude <= 0.5) {
      const ray: number = Math.max(4.0, radius * 2.4);
      this.context.globalAlpha = opacity * 0.58;
      this.context.strokeStyle = object.color;
      this.context.lineWidth = 0.7;
      this.context.beginPath();
      this.context.moveTo(object.xPixels - ray, object.yPixels);
      this.context.lineTo(object.xPixels + ray, object.yPixels);
      this.context.moveTo(object.xPixels, object.yPixels - ray);
      this.context.lineTo(object.xPixels, object.yPixels + ray);
      this.context.stroke();
    }
    this.context.globalAlpha = opacity;
    this.context.fillStyle = object.color;
    this.context.beginPath();
    this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private isSolarSystemGlyph(kind: SkyObjectGlyphKind): boolean {
    return kind === SkyObjectGlyphKind.SUN || kind === SkyObjectGlyphKind.MOON ||
      kind === SkyObjectGlyphKind.MERCURY || kind === SkyObjectGlyphKind.VENUS ||
      kind === SkyObjectGlyphKind.MARS || kind === SkyObjectGlyphKind.JUPITER ||
      kind === SkyObjectGlyphKind.SATURN || kind === SkyObjectGlyphKind.URANUS ||
      kind === SkyObjectGlyphKind.NEPTUNE || kind === SkyObjectGlyphKind.SOLAR_SYSTEM_GENERIC;
  }

  private drawSolarSystemGlyph(object: ProjectedSkyObject, opacity: number): void {
    const radius: number = Math.max(4.0, object.sizePixels / 2.0);
    if (object.glyphKind === SkyObjectGlyphKind.SUN) {
      this.drawHalo(object.xPixels, object.yPixels, radius * 1.65, object.color, opacity * 0.20);
      this.drawDisc(object.xPixels, object.yPixels, radius, object.color, opacity);
      this.drawSolarRays(object.xPixels, object.yPixels, radius, object.color, opacity);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.MOON) {
      this.drawDisc(object.xPixels, object.yPixels, radius, object.color, opacity);
      this.context.globalAlpha = opacity * 0.72;
      this.context.fillStyle = '#66717D';
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius, -Math.PI / 2.0, Math.PI / 2.0);
      this.context.lineTo(object.xPixels, object.yPixels - radius);
      this.context.closePath();
      this.context.fill();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.SATURN) {
      this.context.globalAlpha = opacity * 0.92;
      this.context.strokeStyle = object.color;
      this.context.lineWidth = Math.max(1.1, radius * 0.16);
      this.ellipsePath(object.xPixels, object.yPixels, radius * 1.72, radius * 0.58);
      this.context.stroke();
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.72, object.color, opacity);
      this.context.globalAlpha = opacity * 0.42;
      this.context.strokeStyle = '#8B7446';
      this.context.lineWidth = 0.8;
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.62, object.yPixels - radius * 0.12);
      this.context.lineTo(object.xPixels + radius * 0.62, object.yPixels + radius * 0.12);
      this.context.stroke();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.JUPITER) {
      this.drawDisc(object.xPixels, object.yPixels, radius, object.color, opacity);
      this.context.globalAlpha = opacity * 0.72;
      this.context.strokeStyle = '#9E674E';
      this.context.lineWidth = Math.max(0.8, radius * 0.12);
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.78, object.yPixels - radius * 0.27);
      this.context.lineTo(object.xPixels + radius * 0.78, object.yPixels - radius * 0.27);
      this.context.moveTo(object.xPixels - radius * 0.86, object.yPixels + radius * 0.22);
      this.context.lineTo(object.xPixels + radius * 0.86, object.yPixels + radius * 0.22);
      this.context.stroke();
      this.context.fillStyle = '#B95F45';
      this.context.beginPath();
      this.context.arc(object.xPixels + radius * 0.42, object.yPixels + radius * 0.12,
        Math.max(0.9, radius * 0.16), 0.0, Math.PI * 2.0);
      this.context.fill();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.URANUS) {
      this.context.globalAlpha = opacity * 0.72;
      this.context.strokeStyle = '#C4F4F0';
      this.context.lineWidth = 0.9;
      this.ellipsePath(object.xPixels, object.yPixels, radius * 0.52, radius * 1.35);
      this.context.stroke();
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.82, object.color, opacity);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.VENUS) {
      this.drawHalo(object.xPixels, object.yPixels, radius * 1.45, object.color, opacity * 0.15);
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.88, object.color, opacity);
      return;
    }
    this.drawDisc(object.xPixels, object.yPixels,
      object.glyphKind === SkyObjectGlyphKind.MERCURY ? radius * 0.72 : radius * 0.86,
      object.color, opacity);
    if (object.glyphKind === SkyObjectGlyphKind.MARS) {
      this.context.globalAlpha = opacity * 0.72;
      this.context.strokeStyle = '#FFE0C4';
      this.context.lineWidth = 0.8;
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.42, object.yPixels - radius * 0.42);
      this.context.lineTo(object.xPixels + radius * 0.30, object.yPixels - radius * 0.55);
      this.context.stroke();
    }
  }

  private drawDeepSkyGlyph(object: ProjectedSkyObject, opacity: number): void {
    const radius: number = Math.max(4.5, object.sizePixels / 2.0);
    this.context.strokeStyle = object.color;
    this.context.fillStyle = object.color;
    this.context.lineWidth = object.selected ? 1.5 : 1.0;
    if (object.glyphKind === SkyObjectGlyphKind.GALAXY) {
      this.context.globalAlpha = opacity * 0.17;
      this.ellipsePath(object.xPixels, object.yPixels, radius * 1.55, radius * 0.64);
      this.context.fill();
      this.context.globalAlpha = opacity * 0.92;
      this.ellipsePath(object.xPixels, object.yPixels, radius * 1.55, radius * 0.64);
      this.context.stroke();
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, Math.max(1.0, radius * 0.22), 0.0, Math.PI * 2.0);
      this.context.fill();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.OPEN_CLUSTER) {
      this.context.globalAlpha = opacity * 0.72;
      this.context.setLineDash([2.0, 2.5]);
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius * 1.15, 0.0, Math.PI * 2.0);
      this.context.stroke();
      this.context.setLineDash([]);
      this.drawClusterPoint(object.xPixels - radius * 0.42, object.yPixels - radius * 0.28, opacity);
      this.drawClusterPoint(object.xPixels + radius * 0.35, object.yPixels - radius * 0.43, opacity);
      this.drawClusterPoint(object.xPixels - radius * 0.18, object.yPixels + radius * 0.38, opacity);
      this.drawClusterPoint(object.xPixels + radius * 0.52, object.yPixels + radius * 0.24, opacity);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.GLOBULAR_CLUSTER) {
      this.context.globalAlpha = opacity * 0.28;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
      this.context.fill();
      this.context.globalAlpha = opacity * 0.92;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
      this.context.moveTo(object.xPixels - radius, object.yPixels);
      this.context.lineTo(object.xPixels + radius, object.yPixels);
      this.context.moveTo(object.xPixels, object.yPixels - radius);
      this.context.lineTo(object.xPixels, object.yPixels + radius);
      this.context.stroke();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.PLANETARY_NEBULA) {
      this.context.globalAlpha = opacity * 0.88;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
      this.context.stroke();
      this.context.globalAlpha = opacity * 0.48;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius * 0.43, 0.0, Math.PI * 2.0);
      this.context.stroke();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.SUPERNOVA_REMNANT) {
      this.context.globalAlpha = opacity * 0.88;
      this.context.setLineDash([4.0, 2.0]);
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius * 1.08, 0.0, Math.PI * 2.0);
      this.context.stroke();
      this.context.setLineDash([]);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.NEBULA ||
      object.glyphKind === SkyObjectGlyphKind.DARK_NEBULA) {
      this.context.globalAlpha = object.glyphKind === SkyObjectGlyphKind.DARK_NEBULA ? opacity * 0.20 : opacity * 0.16;
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius, object.yPixels + radius * 0.18);
      this.context.bezierCurveTo(object.xPixels - radius * 0.72, object.yPixels - radius,
        object.xPixels + radius * 0.20, object.yPixels - radius * 0.76,
        object.xPixels + radius, object.yPixels - radius * 0.10);
      this.context.bezierCurveTo(object.xPixels + radius * 0.66, object.yPixels + radius * 0.88,
        object.xPixels - radius * 0.30, object.yPixels + radius,
        object.xPixels - radius, object.yPixels + radius * 0.18);
      this.context.closePath();
      this.context.fill();
      this.context.globalAlpha = opacity * 0.82;
      if (object.glyphKind === SkyObjectGlyphKind.DARK_NEBULA) this.context.setLineDash([3.0, 2.0]);
      this.context.stroke();
      this.context.setLineDash([]);
      return;
    }
    this.context.globalAlpha = opacity * 0.88;
    this.context.beginPath();
    this.context.moveTo(object.xPixels, object.yPixels - radius);
    this.context.lineTo(object.xPixels + radius, object.yPixels);
    this.context.lineTo(object.xPixels, object.yPixels + radius);
    this.context.lineTo(object.xPixels - radius, object.yPixels);
    this.context.closePath();
    this.context.stroke();
  }

  private drawDisc(x: number, y: number, radius: number, color: string, opacity: number): void {
    this.context.globalAlpha = opacity;
    this.context.fillStyle = color;
    this.context.beginPath();
    this.context.arc(x, y, radius, 0.0, Math.PI * 2.0);
    this.context.fill();
    this.context.globalAlpha = opacity * 0.66;
    this.context.strokeStyle = '#F7FBFF';
    this.context.lineWidth = 0.7;
    this.context.stroke();
  }

  private drawHalo(x: number, y: number, radius: number, color: string, opacity: number): void {
    this.context.globalAlpha = opacity;
    this.context.fillStyle = color;
    this.context.beginPath();
    this.context.arc(x, y, radius, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private drawSolarRays(x: number, y: number, radius: number, color: string, opacity: number): void {
    this.context.globalAlpha = opacity * 0.72;
    this.context.strokeStyle = color;
    this.context.lineWidth = 0.9;
    const inner: number = radius * 1.18;
    const outer: number = radius * 1.48;
    this.context.beginPath();
    this.context.moveTo(x - outer, y); this.context.lineTo(x - inner, y);
    this.context.moveTo(x + inner, y); this.context.lineTo(x + outer, y);
    this.context.moveTo(x, y - outer); this.context.lineTo(x, y - inner);
    this.context.moveTo(x, y + inner); this.context.lineTo(x, y + outer);
    this.context.stroke();
  }

  private drawClusterPoint(x: number, y: number, opacity: number): void {
    this.context.globalAlpha = opacity * 0.90;
    this.context.beginPath();
    this.context.arc(x, y, 1.15, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private ellipsePath(x: number, y: number, radiusX: number, radiusY: number): void {
    const control: number = 0.5522847498;
    this.context.beginPath();
    this.context.moveTo(x + radiusX, y);
    this.context.bezierCurveTo(x + radiusX, y + radiusY * control,
      x + radiusX * control, y + radiusY, x, y + radiusY);
    this.context.bezierCurveTo(x - radiusX * control, y + radiusY,
      x - radiusX, y + radiusY * control, x - radiusX, y);
    this.context.bezierCurveTo(x - radiusX, y - radiusY * control,
      x - radiusX * control, y - radiusY, x, y - radiusY);
    this.context.bezierCurveTo(x + radiusX * control, y - radiusY,
      x + radiusX, y - radiusY * control, x + radiusX, y);
    this.context.closePath();
  }

  private drawDirectionMarkers(markers: SkyDirectionMarker[]): void {
    this.context.save();
    this.context.font = '600 10px sans-serif';
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    for (let index: number = 0; index < markers.length; index++) {
      const marker: SkyDirectionMarker = markers[index];
      const radians: number = marker.angleDegrees * Math.PI / 180.0;
      const directionX: number = Math.sin(radians);
      const directionY: number = -Math.cos(radians);
      this.context.globalAlpha = marker.inViewport ? 0.88 : 0.72;
      this.context.strokeStyle = '#72D3F5';
      this.context.fillStyle = '#BDEFFF';
      this.context.lineWidth = 1.1;
      if (marker.atEdge) {
        const normalX: number = -directionY;
        const normalY: number = directionX;
        this.context.beginPath();
        this.context.moveTo(marker.xPixels + directionX * 7.0, marker.yPixels + directionY * 7.0);
        this.context.lineTo(marker.xPixels - directionX * 4.0 + normalX * 4.0,
          marker.yPixels - directionY * 4.0 + normalY * 4.0);
        this.context.lineTo(marker.xPixels - directionX * 4.0 - normalX * 4.0,
          marker.yPixels - directionY * 4.0 - normalY * 4.0);
        this.context.closePath();
        this.context.fill();
      } else {
        this.context.beginPath();
        this.context.arc(marker.xPixels, marker.yPixels, 7.0, 0.0, Math.PI * 2.0);
        this.context.stroke();
      }
      const labelX: number = marker.xPixels - directionX * (marker.atEdge ? 16.0 : -15.0);
      const labelY: number = marker.yPixels - directionY * (marker.atEdge ? 16.0 : -15.0);
      this.context.globalAlpha = 0.92;
      this.context.fillText(this.directionMarkerLabel(marker.kind), labelX, labelY);
    }
    this.context.restore();
  }

  private directionMarkerLabel(kind: SkyDirectionKind): string {
    if (kind === SkyDirectionKind.NORTH_CELESTIAL_POLE) return 'NCP';
    if (kind === SkyDirectionKind.SOUTH_CELESTIAL_POLE) return 'SCP';
    if (kind === SkyDirectionKind.NORTH) return 'N';
    if (kind === SkyDirectionKind.EAST) return 'E';
    if (kind === SkyDirectionKind.SOUTH) return 'S';
    if (kind === SkyDirectionKind.WEST) return 'W';
    return 'Z';
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

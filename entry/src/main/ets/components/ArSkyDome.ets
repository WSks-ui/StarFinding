import {
  SkyDomeFrame,
  SkyDomeMarker,
  SkyDomePoint,
  SkyDomePolyline
} from '../models/ArSkyModels';

const FRAME_INTERVAL_MS: number = 33;
const MAX_GLOW_MARKERS: number = 56;
const TAP_MOVE_TOLERANCE_PIXELS: number = 14;
const MINIMUM_HIT_RADIUS_PIXELS: number = 28;
const DUPLICATE_MARKER_TOLERANCE_SQUARED: number = 36;

/**
 * 透明 AR 天穹层。
 *
 * 组件只保留一个 Canvas 节点，恒星、网格和标签均在同一绘制批次内完成，避免为数百颗
 * 恒星创建 ArkUI 节点。背景始终透明，真实相机预览应由父级放在本组件下方。
 */
@Component
export struct ArSkyDome {
  @Prop @Watch('onRenderInputChanged') frame: SkyDomeFrame;
  @Prop @Watch('onRenderInputChanged') widthPixels: number = 1;
  @Prop @Watch('onRenderInputChanged') heightPixels: number = 1;
  // ArkUI V1 不允许把函数放入 @Prop 状态同步；回调保持普通构造参数即可由父组件注入。
  onMarkerSelected: (markerId: string) => void = (_markerId: string): void => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private animationTimerId: number = -1;
  private canvasReady: boolean = false;
  private touchTracking: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;

  aboutToDisappear(): void {
    this.stopAnimation();
    this.canvasReady = false;
  }

  build() {
    Canvas(this.context)
      .width(Math.max(1, this.widthPixels))
      .height(Math.max(1, this.heightPixels))
      .clip(true)
      .onReady(() => {
        this.canvasReady = true;
        this.drawFrame();
        this.startAnimation();
      })
      .onAreaChange((_oldArea: Area, _newArea: Area) => {
        this.drawFrame();
      })
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
  }

  private startAnimation(): void {
    if (this.animationTimerId >= 0) {
      return;
    }
    // 数据变化由 @Watch 立即重绘；定时器只负责亮星和选中光环的轻动画。
    // 30 FPS 足以保持呼吸与闪烁连贯，同时比原 50 FPS 显著降低全屏 Canvas 开销。
    this.animationTimerId = setInterval(() => {
      this.drawFrame();
    }, FRAME_INTERVAL_MS);
  }

  private onRenderInputChanged(): void {
    this.drawFrame();
  }

  private stopAnimation(): void {
    if (this.animationTimerId < 0) {
      return;
    }
    clearInterval(this.animationTimerId);
    this.animationTimerId = -1;
  }

  private drawFrame(): void {
    if (!this.canvasReady) {
      return;
    }
    const width: number = Math.max(1, this.widthPixels);
    const height: number = Math.max(1, this.heightPixels);
    const phase: number = Date.now() / 1000;
    const markers: SkyDomeMarker[] = this.frame.markers === undefined ? [] : this.frame.markers;
    const guideLines: SkyDomePolyline[] = this.frame.guideLines === undefined ? [] : this.frame.guideLines;
    const milkyWayLines: SkyDomePolyline[] = this.frame.milkyWayLines === undefined ? [] :
      this.frame.milkyWayLines;

    this.context.clearRect(0, 0, width, height);
    this.drawCameraVignette(width, height);
    this.drawMilkyWayBand(milkyWayLines, width, height, phase);
    this.drawSphericalGrid(guideLines, width, height);
    this.drawStars(markers, phase, width, height);
    this.drawSelectedMarker(markers, phase, width, height);
    this.resetContextState();
  }

  /** 轻微压暗画面边缘，让相机画面仍可辨认，同时形成向天顶内收的穹顶纵深。 */
  private drawCameraVignette(width: number, height: number): void {
    const centerX: number = width * 0.5;
    const centerY: number = height * 0.43;
    const outerRadius: number = Math.sqrt(width * width + height * height) * 0.62;
    const gradient: CanvasGradient = this.context.createRadialGradient(
      centerX, centerY, Math.min(width, height) * 0.08,
      centerX, centerY, outerRadius
    );
    gradient.addColorStop(0, 'rgba(3, 10, 18, 0.00)');
    gradient.addColorStop(0.62, 'rgba(3, 12, 22, 0.03)');
    gradient.addColorStop(0.84, 'rgba(3, 12, 22, 0.10)');
    gradient.addColorStop(1, 'rgba(2, 8, 16, 0.24)');
    this.context.save();
    this.context.globalAlpha = 1;
    this.context.fillStyle = gradient;
    this.context.fillRect(0, 0, width, height);
    this.context.restore();
  }

  /**
   * 用多层贝塞尔曲线生成银河弧带，不依赖位图或 SVG。当前数据模型尚未提供银河边界，
   * 因而这里保持低透明度，只承担沉浸氛围；后续加入真实银河采样线时可直接替换控制点。
   */
  private drawMilkyWayBand(lines: SkyDomePolyline[], width: number, height: number, phase: number): void {
    if (lines.length === 0) {
      this.drawFallbackMilkyWayBand(width, height, phase);
      return;
    }
    const gradient: CanvasGradient = this.context.createLinearGradient(0, height, width, 0);
    gradient.addColorStop(0, 'rgba(82, 163, 205, 0.08)');
    gradient.addColorStop(0.38, 'rgba(205, 229, 224, 0.23)');
    gradient.addColorStop(0.62, 'rgba(242, 222, 184, 0.20)');
    gradient.addColorStop(1, 'rgba(91, 145, 202, 0.07)');
    const breathing: number = 0.96 + Math.sin(phase * 0.22) * 0.025;

    this.context.save();
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    for (let index: number = 0; index < lines.length; index++) {
      const line: SkyDomePolyline = lines[index];
      if (line.points.length < 2) {
        continue;
      }
      this.context.beginPath();
      this.context.moveTo(line.points[0].xPixels, line.points[0].yPixels);
      for (let pointIndex: number = 1; pointIndex < line.points.length; pointIndex++) {
        this.context.lineTo(line.points[pointIndex].xPixels, line.points[pointIndex].yPixels);
      }
      this.context.shadowColor = 'rgba(102, 190, 221, 0.18)';
      this.context.shadowBlur = Math.max(8, line.lineWidthPixels * 0.16);
      this.context.globalAlpha = this.clamp(line.opacity * breathing, 0, 0.34);
      this.context.strokeStyle = gradient;
      this.context.lineWidth = line.lineWidthPixels;
      this.context.stroke();

      // 银河中央暗带与宽弧使用同一路径，转动时不会出现装饰层滞留在屏幕上的违和感。
      this.context.shadowBlur = 0;
      this.context.globalAlpha = this.clamp(line.opacity * 0.82, 0, 0.25);
      this.context.strokeStyle = '#07111E';
      this.context.lineWidth = Math.max(8, line.lineWidthPixels * 0.16);
      this.context.stroke();
    }
    this.context.restore();
  }

  private drawFallbackMilkyWayBand(width: number, height: number, phase: number): void {
    const minSide: number = Math.min(width, height);
    const startX: number = -width * 0.12;
    const startY: number = height * 0.82;
    const control1X: number = width * 0.18;
    const control1Y: number = height * 0.49;
    const control2X: number = width * 0.58;
    const control2Y: number = height * 0.19;
    const endX: number = width * 1.12;
    const endY: number = height * 0.16;
    const bandWidth: number = Math.max(54, minSide * 0.19);
    const bandGradient: CanvasGradient = this.context.createLinearGradient(startX, startY, endX, endY);
    bandGradient.addColorStop(0, 'rgba(88, 174, 205, 0.00)');
    bandGradient.addColorStop(0.18, 'rgba(92, 180, 210, 0.11)');
    bandGradient.addColorStop(0.48, 'rgba(229, 236, 220, 0.18)');
    bandGradient.addColorStop(0.72, 'rgba(132, 156, 205, 0.12)');
    bandGradient.addColorStop(1, 'rgba(88, 174, 205, 0.00)');

    this.context.save();
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    this.context.shadowColor = 'rgba(126, 193, 221, 0.16)';
    this.context.shadowBlur = Math.max(8, bandWidth * 0.17);
    this.context.globalAlpha = 0.92;
    this.context.strokeStyle = bandGradient;
    this.context.lineWidth = bandWidth;
    this.context.beginPath();
    this.context.moveTo(startX, startY);
    this.context.bezierCurveTo(control1X, control1Y, control2X, control2Y, endX, endY);
    this.context.stroke();

    // 中间暗带能避免银河变成一条均匀发光色带，并增强球面弧线的层次。
    this.context.shadowBlur = 0;
    this.context.globalAlpha = 0.42;
    this.context.strokeStyle = 'rgba(5, 13, 24, 0.40)';
    this.context.lineWidth = Math.max(10, bandWidth * 0.17);
    this.context.beginPath();
    this.context.moveTo(startX, startY);
    this.context.bezierCurveTo(control1X, control1Y, control2X, control2Y, endX, endY);
    this.context.stroke();

    this.drawMilkyWayMist(
      startX, startY, control1X, control1Y, control2X, control2Y, endX, endY,
      minSide, phase
    );
    this.context.restore();
  }

  private drawMilkyWayMist(startX: number, startY: number, control1X: number, control1Y: number,
    control2X: number, control2Y: number, endX: number, endY: number,
    minSide: number, phase: number): void {
    const mistOpacity: number = 0.10 + Math.sin(phase * 0.24) * 0.008;
    this.context.shadowBlur = 0;
    for (let index: number = 0; index < 26; index++) {
      const t: number = (index + 0.5) / 26;
      const inverse: number = 1 - t;
      const x: number = inverse * inverse * inverse * startX +
        3 * inverse * inverse * t * control1X +
        3 * inverse * t * t * control2X +
        t * t * t * endX;
      const baseY: number = inverse * inverse * inverse * startY +
        3 * inverse * inverse * t * control1Y +
        3 * inverse * t * t * control2Y +
        t * t * t * endY;
      const offset: number = (((index * 37) % 13) - 6) * minSide * 0.0042;
      const radius: number = 0.8 + ((index * 17) % 5) * 0.28;
      this.context.globalAlpha = mistOpacity * (0.72 + ((index * 19) % 4) * 0.09);
      this.context.fillStyle = index % 5 === 0 ? '#FFE7C1' : '#D8F3FF';
      this.context.beginPath();
      this.context.arc(x, baseY + offset, radius, 0, Math.PI * 2);
      this.context.fill();
    }
  }

  private drawSphericalGrid(lines: SkyDomePolyline[], width: number, height: number): void {
    if (lines.length === 0) {
      this.drawFallbackDomeGrid(width, height);
      return;
    }
    const jumpThresholdSquared: number = Math.max(width, height) * Math.max(width, height) * 0.20;
    this.context.save();
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      const line: SkyDomePolyline = lines[lineIndex];
      if (line.points.length < 2) {
        continue;
      }
      this.context.globalAlpha = this.clamp(line.opacity, 0, 1);
      this.context.strokeStyle = this.gridColor(line.altitudeDegrees);
      this.context.lineWidth = Math.max(0.7, line.lineWidthPixels);
      this.context.setLineDash(line.altitudeDegrees === 0 ? [] : [7, 9]);
      this.context.beginPath();
      let hasPoint: boolean = false;
      let previousX: number = 0;
      let previousY: number = 0;
      for (let pointIndex: number = 0; pointIndex < line.points.length; pointIndex++) {
        const point: SkyDomePoint = line.points[pointIndex];
        if (!this.isFinitePoint(point.xPixels, point.yPixels)) {
          hasPoint = false;
          continue;
        }
        if (!hasPoint) {
          this.context.moveTo(point.xPixels, point.yPixels);
          hasPoint = true;
        } else {
          const deltaX: number = point.xPixels - previousX;
          const deltaY: number = point.yPixels - previousY;
          if (deltaX * deltaX + deltaY * deltaY > jumpThresholdSquared) {
            this.context.moveTo(point.xPixels, point.yPixels);
          } else {
            this.context.lineTo(point.xPixels, point.yPixels);
          }
        }
        previousX = point.xPixels;
        previousY = point.yPixels;
      }
      this.context.stroke();
    }
    this.context.restore();
  }

  private drawFallbackDomeGrid(width: number, height: number): void {
    const centerX: number = width * 0.5;
    const centerY: number = height * 0.56;
    this.context.save();
    this.context.lineCap = 'round';
    this.context.setLineDash([7, 10]);
    this.context.strokeStyle = '#76D5E8';
    this.context.globalAlpha = 0.20;
    this.context.lineWidth = 1;

    for (let layer: number = 0; layer < 3; layer++) {
      const spread: number = 0.72 - layer * 0.17;
      const rise: number = height * (0.18 + layer * 0.10);
      this.context.beginPath();
      this.context.moveTo(centerX - width * spread, centerY + rise * 0.18);
      this.context.bezierCurveTo(
        centerX - width * spread * 0.48, centerY - rise,
        centerX + width * spread * 0.48, centerY - rise,
        centerX + width * spread, centerY + rise * 0.18
      );
      this.context.stroke();
    }

    this.context.globalAlpha = 0.14;
    for (let meridian: number = -2; meridian <= 2; meridian++) {
      const edgeX: number = centerX + width * meridian * 0.18;
      this.context.beginPath();
      this.context.moveTo(centerX, -height * 0.05);
      this.context.quadraticCurveTo(edgeX, centerY * 0.52, edgeX, height * 1.04);
      this.context.stroke();
    }
    this.context.restore();
  }

  private drawStars(markers: SkyDomeMarker[], phase: number, width: number, height: number): void {
    this.context.save();
    this.context.lineCap = 'round';
    let glowCount: number = 0;

    // 亮星辉光合并为一个路径，只触发一次填充和阴影计算；低端 Pad 上的成本不会随亮星数线性放大。
    this.context.beginPath();
    for (let index: number = 0; index < markers.length && glowCount < MAX_GLOW_MARKERS; index++) {
      const marker: SkyDomeMarker = markers[index];
      if (!this.shouldDrawMarker(marker, width, height) || marker.sizePixels < 2.35 ||
        marker.altitudeDegrees < 0) {
        continue;
      }
      const radius: number = Math.max(4.2, marker.sizePixels * 3.1);
      this.context.moveTo(marker.xPixels + radius, marker.yPixels);
      this.context.arc(marker.xPixels, marker.yPixels, radius, 0, Math.PI * 2);
      glowCount++;
    }
    if (glowCount > 0) {
      this.context.globalAlpha = 0.12;
      this.context.fillStyle = '#BDEBFF';
      this.context.shadowColor = 'rgba(126, 215, 246, 0.46)';
      this.context.shadowBlur = 7;
      this.context.fill();
    }

    this.context.shadowBlur = 0;
    this.context.shadowColor = 'rgba(0, 0, 0, 0)';
    for (let index: number = 0; index < markers.length; index++) {
      const marker: SkyDomeMarker = markers[index];
      if (!this.shouldDrawMarker(marker, width, height)) {
        continue;
      }
      const twinkle: number = this.twinkleFor(marker, phase);
      const radius: number = Math.max(0.55, marker.sizePixels * 0.5);
      const renderOpacity: number = this.markerRenderOpacity(marker);
      this.context.globalAlpha = this.clamp(renderOpacity * twinkle, 0, 1);
      this.context.fillStyle = marker.color;
      this.context.beginPath();
      this.context.arc(marker.xPixels, marker.yPixels, radius, 0, Math.PI * 2);
      this.context.fill();

      if (marker.sizePixels >= 2.7) {
        this.context.globalAlpha = this.clamp(renderOpacity * twinkle * 0.82, 0, 1);
        this.context.fillStyle = '#FFFFFF';
        this.context.beginPath();
        this.context.arc(marker.xPixels, marker.yPixels, Math.max(0.48, radius * 0.38), 0, Math.PI * 2);
        this.context.fill();
      }
    }
    this.context.restore();
  }

  private drawSelectedMarker(markers: SkyDomeMarker[], phase: number, width: number, height: number): void {
    let selected: SkyDomeMarker | undefined = undefined;
    for (let index: number = 0; index < markers.length; index++) {
      if (markers[index].selected && this.shouldDrawMarker(markers[index], width, height)) {
        selected = markers[index];
        break;
      }
    }
    if (selected === undefined) {
      return;
    }

    const pulse: number = (Math.sin(phase * 2.2) + 1) * 0.5;
    const ringRadius: number = Math.max(13, selected.sizePixels * 0.5 + 10) + pulse * 1.8;
    const renderOpacity: number = this.markerRenderOpacity(selected);
    this.context.save();
    this.context.setLineDash([]);
    this.context.lineCap = 'round';
    this.context.shadowColor = 'rgba(102, 220, 238, 0.60)';
    this.context.shadowBlur = 8 + pulse * 3;
    this.context.globalAlpha = 0.88 * renderOpacity;
    this.context.strokeStyle = '#7DE5EA';
    this.context.lineWidth = 1.6;
    this.context.beginPath();
    this.context.arc(selected.xPixels, selected.yPixels, ringRadius, 0, Math.PI * 2);
    this.context.stroke();

    this.context.shadowBlur = 0;
    this.context.globalAlpha = 0.34 * renderOpacity;
    this.context.strokeStyle = '#FFFFFF';
    this.context.lineWidth = 0.8;
    this.context.beginPath();
    this.context.arc(selected.xPixels, selected.yPixels, ringRadius + 5.5, 0, Math.PI * 2);
    this.context.stroke();
    this.drawSelectedLabel(selected, ringRadius, width, height);
    this.context.restore();
  }

  private drawSelectedLabel(marker: SkyDomeMarker, ringRadius: number, width: number, height: number): void {
    const label: string = marker.label.length === 0 ? marker.id : marker.label;
    this.context.font = '600 14px sans-serif';
    this.context.textAlign = 'left';
    this.context.textBaseline = 'middle';
    const textWidth: number = Math.min(188, this.context.measureText(label).width);
    const boxWidth: number = textWidth + 20;
    const boxHeight: number = 30;
    let boxX: number = marker.xPixels + ringRadius + 11;
    let boxY: number = marker.yPixels - boxHeight * 0.5;
    if (boxX + boxWidth > width - 8) {
      boxX = marker.xPixels - ringRadius - 11 - boxWidth;
    }
    boxX = this.clamp(boxX, 8, Math.max(8, width - boxWidth - 8));
    boxY = this.clamp(boxY, 8, Math.max(8, height - boxHeight - 8));

    const leaderEndX: number = boxX > marker.xPixels ? boxX : boxX + boxWidth;
    this.context.globalAlpha = 0.68;
    this.context.strokeStyle = '#7DE5EA';
    this.context.lineWidth = 1;
    this.context.beginPath();
    this.context.moveTo(
      marker.xPixels + (boxX > marker.xPixels ? ringRadius : -ringRadius),
      marker.yPixels
    );
    this.context.lineTo(leaderEndX, boxY + boxHeight * 0.5);
    this.context.stroke();

    this.roundedRectPath(boxX, boxY, boxWidth, boxHeight, 6);
    this.context.globalAlpha = 0.82;
    this.context.fillStyle = 'rgba(4, 14, 24, 0.88)';
    this.context.fill();
    this.context.globalAlpha = 0.80;
    this.context.strokeStyle = '#4CB8CA';
    this.context.lineWidth = 0.8;
    this.context.stroke();

    this.context.globalAlpha = 1;
    this.context.fillStyle = '#F4FBFF';
    this.context.fillText(label, boxX + 10, boxY + boxHeight * 0.5, Math.max(1, boxWidth - 20));
  }

  private roundedRectPath(x: number, y: number, width: number, height: number, radius: number): void {
    const safeRadius: number = Math.min(radius, Math.min(width, height) * 0.5);
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
    const moveX: number = touch.x - this.touchStartX;
    const moveY: number = touch.y - this.touchStartY;
    if (moveX * moveX + moveY * moveY > TAP_MOVE_TOLERANCE_PIXELS * TAP_MOVE_TOLERANCE_PIXELS) {
      return;
    }
    const nearest: SkyDomeMarker | undefined = this.findNearestMarker(touch.x, touch.y);
    if (nearest !== undefined) {
      this.onMarkerSelected(nearest.id);
    }
  }

  private findNearestMarker(x: number, y: number): SkyDomeMarker | undefined {
    const markers: SkyDomeMarker[] = this.frame.markers === undefined ? [] : this.frame.markers;
    let nearest: SkyDomeMarker | undefined = undefined;
    let nearestDistanceSquared: number = Number.MAX_VALUE;
    let nearestPriority: number = -1;
    for (let index: number = 0; index < markers.length; index++) {
      const marker: SkyDomeMarker = markers[index];
      if (!this.shouldDrawMarker(marker, this.widthPixels, this.heightPixels)) {
        continue;
      }
      const deltaX: number = marker.xPixels - x;
      const deltaY: number = marker.yPixels - y;
      const distanceSquared: number = deltaX * deltaX + deltaY * deltaY;
      const hitRadius: number = Math.max(MINIMUM_HIT_RADIUS_PIXELS, marker.sizePixels * 3.2);
      if (distanceSquared > hitRadius * hitRadius) {
        continue;
      }
      const priority: number = this.markerSelectionPriority(marker);
      const clearlyCloser: boolean = distanceSquared + DUPLICATE_MARKER_TOLERANCE_SQUARED <
        nearestDistanceSquared;
      const overlapsCurrent: boolean = Math.abs(distanceSquared - nearestDistanceSquared) <=
        DUPLICATE_MARKER_TOLERANCE_SQUARED;
      // 规范目标与 HYG 亮星可能投影到同一点。重叠时优先保留带完整详情、规划和拍摄能力的
      // target 标记；只有明显更近的普通目录星才覆盖它。
      if (nearest === undefined || clearlyCloser || (overlapsCurrent && priority > nearestPriority)) {
        nearest = marker;
        nearestDistanceSquared = distanceSquared;
        nearestPriority = priority;
      }
    }
    return nearest;
  }

  private markerSelectionPriority(marker: SkyDomeMarker): number {
    if (marker.selected) return 3;
    if (marker.id.startsWith('target:')) return 2;
    if (marker.id.startsWith('catalog:')) return 1;
    return 0;
  }

  private shouldDrawMarker(marker: SkyDomeMarker, width: number, height: number): boolean {
    const margin: number = Math.max(8, marker.sizePixels * 3.2);
    return marker.inViewport && marker.altitudeDegrees >= -8 && this.markerRenderOpacity(marker) > 0.02 &&
      this.isFinitePoint(marker.xPixels, marker.yPixels) &&
      marker.xPixels >= -margin && marker.xPixels <= width + margin &&
      marker.yPixels >= -margin && marker.yPixels <= height + margin;
  }

  /** 地平线下的目标用于“即将升起”预览，在 -8° 到 0° 之间平滑淡入，避免边缘跳变。 */
  private markerRenderOpacity(marker: SkyDomeMarker): number {
    if (marker.altitudeDegrees >= 0) {
      return this.clamp(marker.opacity, 0, 1);
    }
    const horizonFade: number = this.clamp((marker.altitudeDegrees + 8) / 8, 0, 1);
    return this.clamp(marker.opacity * horizonFade * 0.52, 0, 1);
  }

  private twinkleFor(marker: SkyDomeMarker, phase: number): number {
    if (marker.sizePixels < 2.45) {
      return 1;
    }
    const hash: number = this.stableHash(marker.id);
    if (hash % 5 !== 0) {
      return 1;
    }
    const offset: number = (hash % 628) / 100;
    return 0.94 + Math.sin(phase * 1.35 + offset) * 0.055;
  }

  private stableHash(value: string): number {
    let hash: number = 17;
    for (let index: number = 0; index < value.length; index++) {
      hash = ((hash << 5) - hash + value.charCodeAt(index)) | 0;
    }
    return hash & 0x7fffffff;
  }

  private gridColor(altitudeDegrees: number): string {
    if (altitudeDegrees === 0) {
      return '#77E0D1';
    }
    if (altitudeDegrees >= 60) {
      return '#B1D8EA';
    }
    return '#68B8D3';
  }

  private resetContextState(): void {
    this.context.globalAlpha = 1;
    this.context.shadowBlur = 0;
    this.context.shadowColor = 'rgba(0, 0, 0, 0)';
    this.context.setLineDash([]);
  }

  private isFinitePoint(x: number, y: number): boolean {
    return Number.isFinite(x) && Number.isFinite(y);
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

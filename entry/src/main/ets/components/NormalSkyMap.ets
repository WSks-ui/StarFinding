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
const STAR_DISC_COLORS: string[] = [
  '#B9D8FF', '#E1ECFF', '#FFF7E1', '#FFE6A8',
  '#FFC887', '#FF9C7A', '#E8F1FF', '#FFFFFF'
];
const STAR_DISC_BUCKET_COUNT: number = 16;
const LABEL_BUCKET_COUNT: number = 6;

/** 普通星图单 Canvas 渲染器；绘制对象与命中对象来自同一 NormalSkyScene。 */
@Component
export struct NormalSkyMap {
  @Prop @Watch('onRenderInputChanged') scene: NormalSkyScene;
  @Prop @Watch('onRenderInputChanged') widthPixels: number = 1.0;
  @Prop @Watch('onRenderInputChanged') heightPixels: number = 1.0;
  @Prop @Watch('onBackdropVisibilityChanged') photographyBackdropVisible: boolean = false;
  onObjectSelected: (objectId: string) => void = (_objectId: string): void => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private dynamicSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private dynamicContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.dynamicSettings);
  private staticCanvasReady: boolean = false;
  private dynamicCanvasReady: boolean = false;
  private lastStaticRevision: number = -1;
  private lastStaticWidth: number = 0.0;
  private lastStaticHeight: number = 0.0;
  private touchTracking: boolean = false;
  private touchStartX: number = 0.0;
  private touchStartY: number = 0.0;
  /**
   * Canvas 高频绘制复用桶数组，避免拖动期间为每帧创建 22 组临时数组。
   * 前 8 桶为地平线上恒星，后 8 桶为地平线下恒星。
   */
  private starDiscBuckets: ProjectedSkyObject[][] = [
    [], [], [], [], [], [], [], [],
    [], [], [], [], [], [], [], []
  ];
  private labelBuckets: ProjectedSkyObject[][] = [[], [], [], [], [], []];

  aboutToDisappear(): void {
    this.staticCanvasReady = false;
    this.dynamicCanvasReady = false;
  }

  build() {
    Stack() {
      Canvas(this.context)
        .width(Math.max(1.0, this.widthPixels))
        .height(Math.max(1.0, this.heightPixels))
        .onReady(() => {
          this.staticCanvasReady = true;
          this.lastStaticRevision = -1;
          this.drawScene();
        })
      Canvas(this.dynamicContext)
        .width(Math.max(1.0, this.widthPixels))
        .height(Math.max(1.0, this.heightPixels))
        .onReady(() => {
          this.dynamicCanvasReady = true;
          this.drawScene();
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
    }
      .width(Math.max(1.0, this.widthPixels))
      .height(Math.max(1.0, this.heightPixels))
      .clip(true)
      .onAreaChange((_oldArea: Area, _newArea: Area) => {
        this.lastStaticRevision = -1;
        this.drawScene();
      })
  }

  private onRenderInputChanged(): void {
    this.drawScene();
  }

  /**
   * 摄影底图与目录场景拥有独立修订号。纹理从“正在加载”切换到“已就绪”时，
   * 即使星表没有变化，也必须重画静态 Canvas 的夜视遮罩和目录恒星层。
   */
  private onBackdropVisibilityChanged(): void {
    this.lastStaticRevision = -1;
    this.drawScene();
  }

  private drawScene(): void {
    if (!this.staticCanvasReady && !this.dynamicCanvasReady) return;
    const width: number = Math.max(1.0, this.widthPixels);
    const height: number = Math.max(1.0, this.heightPixels);
    const sizeChanged: boolean = Math.abs(width - this.lastStaticWidth) > 0.01 ||
      Math.abs(height - this.lastStaticHeight) > 0.01;
    if (this.staticCanvasReady &&
      (sizeChanged || this.lastStaticRevision !== this.scene.staticRevision)) {
      this.drawStaticScene(width, height);
      this.lastStaticRevision = this.scene.staticRevision;
      this.lastStaticWidth = width;
      this.lastStaticHeight = height;
    }
    if (this.dynamicCanvasReady) this.drawDynamicScene(width, height);
  }

  private drawStaticScene(width: number, height: number): void {
    this.context.clearRect(0.0, 0.0, width, height);
    this.drawSkyBackground(width, height);
    this.drawGalacticPlane(this.scene.galacticPlaneLines);
    this.drawPolylines(this.scene.gridLines, '#29404E', 0.38, 0.7);
    this.drawPolylines(this.scene.eclipticLines, '#B69955', 0.68, 1.0);
    const constellationOpacity: number =
      this.scene.viewportSnapshot.fieldOfViewDegrees >= 100.0 ? 0.52 : 0.70;
    this.drawPolylines(this.scene.constellationLines, '#426B82', constellationOpacity, 1.0);
    this.drawObjects(this.scene.staticObjects, width, height, this.photographyBackdropVisible);
    this.resetContextState();
  }

  /**
   * 摄影底图由页面层的独立 @State PixelMap 绘制在普通星图下方。
   *
   * API 23 真机会丢失封装在对象 @Prop 内的原生 PixelMap 纹理句柄，因此这里必须保持
   * Canvas 透明，只叠加星座线、标签和目录图符。导航模式仍绘制完整深色背景。
   */
  private drawSkyBackground(width: number, height: number): void {
    if (this.photographyBackdropVisible) {
      return;
    }
    const gradient: CanvasGradient = this.context.createRadialGradient(
      width * 0.52, height * 0.44, Math.min(width, height) * 0.06,
      width * 0.52, height * 0.44, Math.sqrt(width * width + height * height) * 0.66);
    gradient.addColorStop(0.0, '#08131E');
    gradient.addColorStop(0.56, '#050C14');
    gradient.addColorStop(1.0, '#02060B');
    this.context.globalAlpha = 1.0;
    this.context.fillStyle = gradient;
    this.context.fillRect(0.0, 0.0, width, height);
  }

  private drawGalacticPlane(lines: SkyPolyline[]): void {
    if (lines.length === 0) {
      return;
    }
    this.context.save();
    this.context.strokeStyle = '#9B86C7';
    this.context.globalAlpha = 0.62;
    this.context.lineWidth = 1.0;
    this.context.setLineDash([4.0, 4.0]);
    this.context.beginPath();
    for (let index: number = 0; index < lines.length; index++) {
      const points: SkyScreenPoint[] = lines[index].points;
      if (points.length < 2) {
        continue;
      }
      this.context.moveTo(points[0].xPixels, points[0].yPixels);
      for (let pointIndex: number = 1; pointIndex < points.length; pointIndex++) {
        this.context.lineTo(points[pointIndex].xPixels, points[pointIndex].yPixels);
      }
    }
    this.context.stroke();
    this.context.setLineDash([]);
    this.context.restore();
  }

  private drawDynamicScene(width: number, height: number): void {
    const staticContext: CanvasRenderingContext2D = this.context;
    this.context = this.dynamicContext;
    this.context.clearRect(0.0, 0.0, width, height);
    this.drawTrajectoryLines(this.scene.trajectoryLines);
    this.drawHorizonMask(this.scene.horizonMask);
    this.drawPolylines(this.scene.horizonLines, '#78C9C5', 0.88, 1.4);
    this.drawObjects(this.scene.dynamicObjects, width, height);
    this.drawDirectionMarkers(this.scene.orientationSnapshot.markers);
    this.resetContextState();
    this.context = staticContext;
  }

  private drawPolylines(lines: SkyPolyline[], color: string, opacity: number, lineWidth: number): void {
    this.context.save();
    this.context.strokeStyle = color;
    this.context.globalAlpha = opacity;
    this.context.lineWidth = lineWidth;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    this.context.beginPath();
    let hasPath: boolean = false;
    for (let index: number = 0; index < lines.length; index++) {
      const points: SkyScreenPoint[] = lines[index].points;
      if (points.length < 2) {
        continue;
      }
      this.context.moveTo(points[0].xPixels, points[0].yPixels);
      for (let pointIndex: number = 1; pointIndex < points.length; pointIndex++) {
        this.context.lineTo(points[pointIndex].xPixels, points[pointIndex].yPixels);
      }
      hasPath = true;
    }
    if (hasPath) this.context.stroke();
    this.context.restore();
  }

  /** 真实视运动轨迹使用虚线，避免被误解成固定圆形行星轨道。 */
  private drawTrajectoryLines(lines: SkyPolyline[]): void {
    this.context.save();
    this.context.strokeStyle = '#7DE5EA';
    this.context.globalAlpha = 0.78;
    this.context.lineWidth = 1.4;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';
    this.context.setLineDash([6.0, 4.0]);
    this.context.beginPath();
    let hasPath: boolean = false;
    for (let index: number = 0; index < lines.length; index++) {
      const points: SkyScreenPoint[] = lines[index].points;
      if (points.length < 2) continue;
      this.context.moveTo(points[0].xPixels, points[0].yPixels);
      for (let pointIndex: number = 1; pointIndex < points.length; pointIndex++) {
        this.context.lineTo(points[pointIndex].xPixels, points[pointIndex].yPixels);
      }
      hasPath = true;
    }
    if (hasPath) this.context.stroke();
    this.context.setLineDash([]);
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

  private drawObjects(objects: ProjectedSkyObject[], width: number, height: number,
    suppressCatalogStars: boolean = false): void {
    const occupied: SkyLabelBox[] = [];
    let selectedObject: ProjectedSkyObject | undefined = undefined;
    this.context.save();
    this.prepareObjectBuckets(objects, width, height, suppressCatalogStars);
    this.drawStarDiscBuckets();
    for (let index: number = 0; index < objects.length; index++) {
      const object: ProjectedSkyObject = objects[index];
      if (!this.inDrawingBounds(object, width, height)) {
        continue;
      }
      if (object.type !== CelestialType.CONSTELLATION) {
        const opacity: number = object.aboveHorizon === false ? 0.42 : 1.0;
        if (object.glyphKind === SkyObjectGlyphKind.STAR) {
          if (object.selected) this.drawStarGlyph(object, opacity);
        } else if (this.isSolarSystemGlyph(object.glyphKind)) {
          this.drawSolarSystemGlyph(object, opacity);
        } else {
          this.drawDeepSkyGlyph(object, opacity);
        }
      }
      if (object.selected) {
        selectedObject = object;
      }
    }
    // 标签已在 prepareObjectBuckets 中按优先级收集，这里无需再重复扫描整个对象数组。
    for (let bucketIndex: number = LABEL_BUCKET_COUNT - 1; bucketIndex >= 0; bucketIndex--) {
      const bucket: ProjectedSkyObject[] = this.labelBuckets[bucketIndex];
      for (let objectIndex: number = 0; objectIndex < bucket.length; objectIndex++) {
        this.drawLabel(bucket[objectIndex], occupied, width, height);
      }
    }
    if (selectedObject !== undefined) {
      this.drawSelectedObject(selectedObject);
    }
    this.context.restore();
  }

  private prepareObjectBuckets(objects: ProjectedSkyObject[], width: number, height: number,
    suppressCatalogStars: boolean = false): void {
    this.clearObjectBuckets();
    for (let index: number = 0; index < objects.length; index++) {
      const object: ProjectedSkyObject = objects[index];
      if (!this.inDrawingBounds(object, width, height)) {
        continue;
      }
      if (object.label.length > 0) {
        this.labelBuckets[this.labelBucketIndex(object)].push(object);
      }
      /*
       * 摄影模式的底图已经保留了大尺度恒星云和可见光星野。这里不再叠加 HYG
       * 普通星点及其高光，避免亮星出现双影；名称、命中对象和被选中的星仍完整保留。
       */
      if (object.glyphKind !== SkyObjectGlyphKind.STAR || object.selected || suppressCatalogStars) {
        continue;
      }
      const dimmed: boolean = object.aboveHorizon === false;
      const bucketIndex: number = this.starColorBucketIndex(object.color) +
        (dimmed ? STAR_DISC_COLORS.length : 0);
      this.starDiscBuckets[bucketIndex].push(object);
      this.drawStarHighlightEffects(object, dimmed ? 0.42 : 1.0);
    }
  }

  private clearObjectBuckets(): void {
    for (let index: number = 0; index < STAR_DISC_BUCKET_COUNT; index++) {
      this.starDiscBuckets[index].length = 0;
    }
    for (let index: number = 0; index < LABEL_BUCKET_COUNT; index++) {
      this.labelBuckets[index].length = 0;
    }
  }

  private drawStarDiscBuckets(): void {
    for (let bucketIndex: number = 0; bucketIndex < STAR_DISC_BUCKET_COUNT; bucketIndex++) {
      const bucket: ProjectedSkyObject[] = this.starDiscBuckets[bucketIndex];
      if (bucket.length === 0) {
        continue;
      }
      this.context.beginPath();
      for (let objectIndex: number = 0; objectIndex < bucket.length; objectIndex++) {
        const object: ProjectedSkyObject = bucket[objectIndex];
        const radius: number = Math.max(0.7, object.sizePixels / 2.0);
        this.context.moveTo(object.xPixels + radius, object.yPixels);
        this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
      }
      const dimmed: boolean = bucketIndex >= STAR_DISC_COLORS.length;
      const colorIndex: number = dimmed ? bucketIndex - STAR_DISC_COLORS.length : bucketIndex;
      this.context.globalAlpha = dimmed ? 0.42 : 1.0;
      this.context.fillStyle = STAR_DISC_COLORS[colorIndex];
      this.context.fill();
    }
  }

  private starColorBucketIndex(color: string): number {
    for (let index: number = 0; index < STAR_DISC_COLORS.length; index++) {
      if (STAR_DISC_COLORS[index] === color) {
        return index;
      }
    }
    return STAR_DISC_COLORS.length - 1;
  }

  private drawStarGlyph(object: ProjectedSkyObject, opacity: number): void {
    this.drawStarHighlightEffects(object, opacity);
    const radius: number = Math.max(0.7, object.sizePixels / 2.0);
    this.context.globalAlpha = opacity;
    this.context.fillStyle = object.color;
    this.context.beginPath();
    this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
    this.context.fill();
  }

  private drawStarHighlightEffects(object: ProjectedSkyObject, opacity: number): void {
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
      this.drawPhaseGlyph(object, radius, opacity, '#27313B');
      this.drawMoonTexture(object.xPixels, object.yPixels, radius, opacity);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.SATURN) {
      const ringTiltDegrees: number = object.appearance?.ringTiltDegrees === undefined ? 12.0 :
        object.appearance.ringTiltDegrees;
      const ringOpening: number = 0.14 + Math.abs(Math.sin(ringTiltDegrees * Math.PI / 180.0)) * 0.72;
      const ringRadiusX: number = radius * 1.78;
      const ringRadiusY: number = Math.max(radius * 0.14, radius * ringOpening);
      this.context.globalAlpha = opacity * 0.58;
      this.context.strokeStyle = '#BFA66C';
      this.context.lineWidth = Math.max(1.3, radius * 0.17);
      this.ellipsePath(object.xPixels, object.yPixels, ringRadiusX, ringRadiusY);
      this.context.stroke();
      this.context.globalAlpha = opacity * 0.48;
      this.context.strokeStyle = '#66583B';
      this.context.lineWidth = Math.max(0.7, radius * 0.07);
      this.ellipsePath(object.xPixels, object.yPixels, ringRadiusX * 0.78, ringRadiusY * 0.78);
      this.context.stroke();
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.72, object.color, opacity);
      this.context.globalAlpha = opacity * 0.34;
      this.context.strokeStyle = '#8F7447';
      this.context.lineWidth = Math.max(0.7, radius * 0.08);
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.62, object.yPixels - radius * 0.10);
      this.context.lineTo(object.xPixels + radius * 0.62, object.yPixels - radius * 0.10);
      this.context.stroke();
      // 先画完整后环、再画行星盘，最后只补前半环，形成明确的前后遮挡关系。
      this.context.globalAlpha = opacity * 0.96;
      this.context.strokeStyle = '#D8BD7A';
      this.context.lineWidth = Math.max(1.25, radius * 0.17);
      const frontStart: number = ringTiltDegrees >= 0.0 ? 0.0 : Math.PI;
      this.ellipseArcPath(object.xPixels, object.yPixels, ringRadiusX, ringRadiusY,
        frontStart, frontStart + Math.PI);
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
    if (object.glyphKind === SkyObjectGlyphKind.VENUS ||
      object.glyphKind === SkyObjectGlyphKind.MERCURY) {
      const bodyRadius: number = object.glyphKind === SkyObjectGlyphKind.MERCURY ?
        radius * 0.74 : radius * 0.90;
      const darkColor: string = object.glyphKind === SkyObjectGlyphKind.MERCURY ? '#3E403F' : '#4A4435';
      if (object.glyphKind === SkyObjectGlyphKind.VENUS) {
        this.drawHalo(object.xPixels, object.yPixels, radius * 1.45, object.color, opacity * 0.15);
      }
      this.drawPhaseGlyph(object, bodyRadius, opacity, darkColor);
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.NEPTUNE) {
      this.drawHalo(object.xPixels, object.yPixels, radius * 1.22, '#5F83E8', opacity * 0.12);
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.86, object.color, opacity);
      this.context.globalAlpha = opacity * 0.82;
      this.context.strokeStyle = '#B5D6FF';
      this.context.lineWidth = Math.max(0.7, radius * 0.08);
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.62, object.yPixels + radius * 0.12);
      this.context.quadraticCurveTo(object.xPixels, object.yPixels + radius * 0.30,
        object.xPixels + radius * 0.62, object.yPixels + radius * 0.05);
      this.context.stroke();
      return;
    }
    if (object.glyphKind === SkyObjectGlyphKind.SOLAR_SYSTEM_GENERIC) {
      this.drawHalo(object.xPixels, object.yPixels, radius * 1.45, object.color, opacity * 0.15);
      this.drawDisc(object.xPixels, object.yPixels, radius * 0.88, object.color, opacity);
      return;
    }
    this.drawDisc(object.xPixels, object.yPixels, radius * 0.86, object.color, opacity);
    if (object.glyphKind === SkyObjectGlyphKind.MARS) {
      this.context.globalAlpha = opacity * 0.72;
      this.context.strokeStyle = '#7F3A2B';
      this.context.lineWidth = Math.max(0.8, radius * 0.10);
      this.context.beginPath();
      this.context.moveTo(object.xPixels - radius * 0.52, object.yPixels + radius * 0.12);
      this.context.quadraticCurveTo(object.xPixels - radius * 0.06, object.yPixels - radius * 0.12,
        object.xPixels + radius * 0.48, object.yPixels + radius * 0.10);
      this.context.stroke();
      this.context.globalAlpha = opacity * 0.86;
      this.context.fillStyle = '#F5DDC8';
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels - radius * 0.62,
        Math.max(0.8, radius * 0.18), Math.PI, Math.PI * 2.0);
      this.context.fill();
    }
  }

  /** 用照明比例和亮边屏幕角绘制月球、水星、金星的真实盈亏。 */
  private drawPhaseGlyph(object: ProjectedSkyObject, radius: number,
    opacity: number, darkColor: string): void {
    const fraction: number = object.appearance === undefined ? 1.0 :
      this.clamp(object.appearance.illuminatedFraction, 0.0, 1.0);
    const angleDegrees: number = object.brightLimbScreenAngleDegrees === undefined ? 0.0 :
      object.brightLimbScreenAngleDegrees;
    this.context.globalAlpha = opacity;
    this.context.fillStyle = darkColor;
    this.context.beginPath();
    this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
    this.context.fill();
    if (fraction >= 0.999) {
      this.context.fillStyle = object.color;
      this.context.beginPath();
      this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
      this.context.fill();
    } else if (fraction > 0.001) {
      const angleRadians: number = angleDegrees * Math.PI / 180.0;
      const brightX: number = Math.sin(angleRadians);
      const brightY: number = -Math.cos(angleRadians);
      const tangentX: number = Math.cos(angleRadians);
      const tangentY: number = Math.sin(angleRadians);
      const terminatorScale: number = 1.0 - fraction * 2.0;
      const samples: number = 32;
      this.context.globalAlpha = opacity;
      this.context.fillStyle = object.color;
      this.context.beginPath();
      for (let index: number = 0; index <= samples; index++) {
        const localY: number = -1.0 + 2.0 * index / samples;
        const localX: number = Math.sqrt(Math.max(0.0, 1.0 - localY * localY));
        const x: number = object.xPixels + radius * (localX * brightX + localY * tangentX);
        const y: number = object.yPixels + radius * (localX * brightY + localY * tangentY);
        if (index === 0) this.context.moveTo(x, y); else this.context.lineTo(x, y);
      }
      for (let index: number = samples; index >= 0; index--) {
        const localY: number = -1.0 + 2.0 * index / samples;
        const localX: number = terminatorScale * Math.sqrt(Math.max(0.0, 1.0 - localY * localY));
        this.context.lineTo(object.xPixels + radius * (localX * brightX + localY * tangentX),
          object.yPixels + radius * (localX * brightY + localY * tangentY));
      }
      this.context.closePath();
      this.context.fill();
    }
    this.context.globalAlpha = opacity * 0.70;
    this.context.strokeStyle = '#F7FBFF';
    this.context.lineWidth = 0.7;
    this.context.beginPath();
    this.context.arc(object.xPixels, object.yPixels, radius, 0.0, Math.PI * 2.0);
    this.context.stroke();
  }

  private drawMoonTexture(x: number, y: number, radius: number, opacity: number): void {
    this.context.globalAlpha = opacity * 0.18;
    this.context.fillStyle = '#6F7983';
    this.context.beginPath();
    this.context.arc(x - radius * 0.28, y - radius * 0.18, Math.max(0.7, radius * 0.13),
      0.0, Math.PI * 2.0);
    this.context.arc(x + radius * 0.24, y + radius * 0.26, Math.max(0.6, radius * 0.10),
      0.0, Math.PI * 2.0);
    this.context.fill();
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

  private ellipseArcPath(x: number, y: number, radiusX: number, radiusY: number,
    startRadians: number, endRadians: number): void {
    const segments: number = 28;
    this.context.beginPath();
    for (let index: number = 0; index <= segments; index++) {
      const radians: number = startRadians + (endRadians - startRadians) * index / segments;
      const pointX: number = x + Math.cos(radians) * radiusX;
      const pointY: number = y + Math.sin(radians) * radiusY;
      if (index === 0) this.context.moveTo(pointX, pointY); else this.context.lineTo(pointX, pointY);
    }
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
      const pole: boolean = marker.kind === SkyDirectionKind.NORTH_CELESTIAL_POLE ||
        marker.kind === SkyDirectionKind.SOUTH_CELESTIAL_POLE;
      const zenith: boolean = marker.kind === SkyDirectionKind.ZENITH;
      this.context.strokeStyle = pole ? '#B8A7F3' : (zenith ? '#F2CF7A' : '#72D3F5');
      this.context.fillStyle = pole ? '#D8CEFF' : (zenith ? '#FFE6A8' : '#BDEFFF');
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

  private drawSelectedObject(object: ProjectedSkyObject): void {
    this.context.globalAlpha = 0.92;
    this.context.strokeStyle = '#7DE5EA';
    this.context.lineWidth = 1.8;
    this.context.beginPath();
    this.context.arc(object.xPixels, object.yPixels, Math.max(12.0, object.sizePixels + 7.0),
      0.0, Math.PI * 2.0);
    this.context.stroke();
  }

  private labelBucketIndex(object: ProjectedSkyObject): number {
    if (object.selected) return 5;
    if (object.type === CelestialType.SUN || object.type === CelestialType.MOON ||
      object.type === CelestialType.PLANET) return 4;
    if (object.type === CelestialType.MESSIER) return 3;
    if (object.type === CelestialType.CONSTELLATION) return 2;
    if (object.magnitude !== undefined && object.magnitude <= 1.5) return 1;
    return 0;
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

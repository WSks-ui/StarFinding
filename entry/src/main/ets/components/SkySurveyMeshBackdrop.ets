import { common } from '@kit.AbilityKit';
import { drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import {
  NormalSkyViewport,
  SkyMapOrientation
} from '../models/NormalSkyModels';
import {
  SkySurveyBackdropService,
  SkySurveyBackdropStatus
} from '../services/SkySurveyBackdropService';
import {
  SkySurveyMeshFrame,
  SkySurveyMeshProjectionService
} from '../services/SkySurveyMeshProjectionService';

/**
 * 高频视口更新通过控制器直接送入摄影 Canvas，避免把 60/120Hz 手势状态提升到巨大页面
 * 的 @State。控制器同时保存最后快照，组件重新挂载时会立即恢复正确视口。
 */
export class SkySurveyBackdropController {
  private viewport: NormalSkyViewport = {
    centerRaHours: 0.0,
    centerDecDegrees: 0.0,
    fieldOfViewDegrees: 100.0,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
  private interactive: boolean = false;
  private listener:
    ((viewport: NormalSkyViewport, interactive: boolean) => void) | undefined = undefined;

  attach(listener: (viewport: NormalSkyViewport, interactive: boolean) => void): void {
    this.listener = listener;
    listener(this.viewport, this.interactive);
  }

  detach(listener: (viewport: NormalSkyViewport, interactive: boolean) => void): void {
    /*
     * 页面转场期间旧、新组件可能短暂共存。只有仍持有当前绑定的实例才能解除监听，
     * 避免旧组件稍晚执行 aboutToDisappear() 时误删新组件刚建立的监听。
     */
    if (this.listener === listener) {
      this.listener = undefined;
    }
  }

  update(viewport: NormalSkyViewport, interactive: boolean): void {
    this.viewport = viewport;
    this.interactive = interactive;
    if (this.listener !== undefined) {
      this.listener(viewport, interactive);
    }
  }
}

/**
 * 使用完整全天纹理和动态球面网格绘制普通星图摄影底图。
 *
 * 该组件自己持有 PixelMap 原生句柄，页面只传递数值视口，避免 PixelMap 经复杂 @Prop
 * 对象传递后在部分 API 23 真机上失去纹理。视口每次变化都立即更新网格，不存在停手后的
 * 二次“校准”，也不会再把一张矩形图片拖出屏幕露出斜向边界。
 */
@Component
export struct SkySurveyMeshBackdrop {
  /*
   * 控制器依赖稳定对象身份且不参与声明式状态同步，因此使用普通组件参数。
   * 若改成 @Prop，ArkUI 的状态包装或复制语义可能使父、子组件不再持有同一监听实例。
   */
  controller: SkySurveyBackdropController = new SkySurveyBackdropController();
  private viewport: NormalSkyViewport = {
    centerRaHours: 0.0,
    centerDecDegrees: 0.0,
    fieldOfViewDegrees: 100.0,
    rotationDegrees: 0.0,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
  @Prop widthPixels: number = 1.0;
  @Prop heightPixels: number = 1.0;
  private interactive: boolean = false;
  @Prop @Watch('onBackdropActiveChanged') backdropActive: boolean = false;
  @State private backdropOpacity: number = 0.92;
  onStatusChange: (status: SkySurveyBackdropStatus, message: string) => void =
    (_status: SkySurveyBackdropStatus, _message: string): void => {};

  /*
   * ArkUI 布局宽高使用 vp，但 ArkGraphics2D drawVertices 的顶点落在物理像素画布。
   * 显式使用 PX 并从 context.size 读取真实尺寸，避免把约 1228×800vp 的投影坐标直接
   * 提交到约 2456×1600px 的真机画布，造成纹理只覆盖左上部分。
   */
  private context: DrawingRenderingContext =
    new DrawingRenderingContext(LengthMetricsUnit.PX);
  private brush: drawing.Brush = new drawing.Brush();
  private readonly samplingOptions: drawing.SamplingOptions =
    new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
  private readonly backdropService: SkySurveyBackdropService = new SkySurveyBackdropService();
  private readonly projectionService: SkySurveyMeshProjectionService =
    new SkySurveyMeshProjectionService();
  private readonly interactiveProjectionService: SkySurveyMeshProjectionService =
    new SkySurveyMeshProjectionService(64, 32);
  private pixelMap: image.PixelMap | undefined = undefined;
  private textureShader: drawing.ShaderEffect | undefined = undefined;
  private canvasReady: boolean = false;
  private loading: boolean = false;
  private loadGeneration: number = 0;
  private canvasCleared: boolean = true;
  private lastStatus: SkySurveyBackdropStatus = SkySurveyBackdropStatus.DISABLED;
  private lastMessage: string = '';
  private readonly viewportListener:
    (viewport: NormalSkyViewport, interactive: boolean) => void =
    (viewport: NormalSkyViewport, interactive: boolean): void => {
      this.viewport = viewport;
      this.interactive = interactive;
      const nextOpacity: number = SkySurveyBackdropService.opacityForFieldOfView(
        viewport.fieldOfViewDegrees);
      /*
       * 透明度是子组件自己的局部声明式状态，只在缩放真正改变数值时更新。
       * 平移和旋转仍直接重绘原生 Canvas，不会触发巨大 Index 页面的高频重组。
       */
      if (Math.abs(nextOpacity - this.backdropOpacity) > 0.001) {
        this.backdropOpacity = nextOpacity;
      }
      if (this.backdropActive) {
        this.refresh();
      }
    };

  aboutToAppear(): void {
    this.brush.setAntiAlias(true);
    // Brush 的 SRC_OVER 负责网格与下层星空的画布合成；顶点与纹理的组合模式在 drawVertices 中指定。
    this.brush.setBlendMode(drawing.BlendMode.SRC_OVER);
    this.controller.attach(this.viewportListener);
  }

  aboutToDisappear(): void {
    this.controller.detach(this.viewportListener);
    this.canvasReady = false;
    this.loadGeneration++;
    this.loading = false;
    this.brush.setShaderEffect(null);
    this.textureShader = undefined;
    this.pixelMap = undefined;
    this.backdropService.clear();
  }

  build() {
    Canvas(this.context)
      .width(Math.max(1.0, this.widthPixels))
      .height(Math.max(1.0, this.heightPixels))
      .opacity(this.backdropActive ? this.backdropOpacity : 0.0)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.canvasReady = true;
        this.refresh();
      })
      .onAreaChange((_oldArea: Area, _newArea: Area) => {
        this.refresh();
      })
  }

  private onBackdropActiveChanged(): void {
    if (!this.backdropActive) {
      this.clearCanvas();
      this.publishStatus(SkySurveyBackdropStatus.DISABLED, '');
      return;
    }
    this.backdropOpacity = SkySurveyBackdropService.opacityForFieldOfView(
      this.viewport.fieldOfViewDegrees);
    this.refresh();
  }

  private refresh(): void {
    if (!this.canvasReady) {
      return;
    }
    if (!this.backdropActive || this.currentOpacity() <= 0.0) {
      this.clearCanvas();
      this.publishStatus(SkySurveyBackdropStatus.DISABLED, '摄影底图仅在 20° 以上视场显示');
      return;
    }
    if (this.pixelMap === undefined) {
      this.ensureTexture();
      return;
    }
    this.drawCurrentViewport();
  }

  private async ensureTexture(): Promise<void> {
    if (this.loading || this.pixelMap !== undefined) {
      return;
    }
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      this.publishStatus(SkySurveyBackdropStatus.FAILED, '应用上下文未就绪');
      return;
    }
    this.loading = true;
    const generation: number = ++this.loadGeneration;
    this.publishStatus(SkySurveyBackdropStatus.LOADING, '正在加载摄影底图');
    try {
      const loaded: image.PixelMap = await this.backdropService.load(context);
      if (generation !== this.loadGeneration || !this.canvasReady) {
        return;
      }
      this.pixelMap = loaded;
      /*
       * 横向使用 REPEAT，使最后一列纹理坐标 6000 精确回到首列；纵向必须 CLAMP，
       * 否则银河南北极会被错误地首尾相接。Shader 只在首次解码后创建一次。
       */
      this.textureShader = drawing.ShaderEffect.createImageShader(
        loaded,
        drawing.TileMode.REPEAT,
        drawing.TileMode.CLAMP,
        this.samplingOptions);
      this.brush.setShaderEffect(this.textureShader);
      if (!this.backdropActive || this.currentOpacity() <= 0.0) {
        this.clearCanvas();
        this.publishStatus(SkySurveyBackdropStatus.DISABLED, '');
        return;
      }
      this.drawCurrentViewport();
    } catch (error) {
      if (generation === this.loadGeneration && this.canvasReady) {
        this.publishStatus(SkySurveyBackdropStatus.FAILED, `摄影底图不可用：${error}`);
      }
    } finally {
      if (generation === this.loadGeneration) {
        this.loading = false;
      }
    }
  }

  private drawCurrentViewport(): void {
    const texture: image.PixelMap | undefined = this.pixelMap;
    if (!this.canvasReady || texture === undefined || this.textureShader === undefined) {
      return;
    }
    try {
      /*
       * 拖动期间使用较疏的网格保证跟手；停手后由完整网格立即恢复最终几何精度。
       * 两套服务均复用自己的顶点缓冲，不在高频交互中创建临时大数组。
       */
      const projectionService: SkySurveyMeshProjectionService = this.interactive ?
        this.interactiveProjectionService : this.projectionService;
      const drawingWidthPixels: number = Math.max(1.0, this.context.size.width);
      const drawingHeightPixels: number = Math.max(1.0, this.context.size.height);
      const frame: SkySurveyMeshFrame = projectionService.project(this.viewport, {
        widthPixels: drawingWidthPixels,
        heightPixels: drawingHeightPixels
      });
      const canvas: drawing.Canvas = this.context.canvas;
      canvas.clear(0x00000000);
      if (frame.drawVertexCount < 3) {
        this.canvasCleared = true;
        this.context.invalidate();
        this.publishStatus(SkySurveyBackdropStatus.READY, 'ESO 可见光参考影像');
        return;
      }
      canvas.attachBrush(this.brush);
      try {
        canvas.drawVertices(
          drawing.VertexMode.TRIANGLES_VERTEXMODE,
          frame.drawVertexCount,
          frame.drawPositions,
          frame.drawTextureCoordinates,
          null,
          0,
          null,
          drawing.BlendMode.MODULATE);
      } finally {
        canvas.detachBrush();
      }
      this.canvasCleared = false;
      this.context.invalidate();
      this.publishStatus(SkySurveyBackdropStatus.READY, 'ESO 可见光参考影像');
    } catch (error) {
      this.clearCanvas();
      this.publishStatus(SkySurveyBackdropStatus.FAILED, `摄影底图绘制失败：${error}`);
    }
  }

  private clearCanvas(): void {
    if (!this.canvasReady || this.canvasCleared) {
      return;
    }
    this.context.canvas.clear(0x00000000);
    this.canvasCleared = true;
    this.context.invalidate();
  }

  private currentOpacity(): number {
    if (!this.backdropActive) {
      return 0.0;
    }
    return this.backdropOpacity;
  }

  private publishStatus(status: SkySurveyBackdropStatus, message: string): void {
    if (status === this.lastStatus && message === this.lastMessage) {
      return;
    }
    this.lastStatus = status;
    this.lastMessage = message;
    this.onStatusChange(status, message);
  }
}

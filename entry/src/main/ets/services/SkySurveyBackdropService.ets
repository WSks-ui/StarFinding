import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  NormalSkyViewport,
  SkyMapSize
} from '../models/NormalSkyModels';
import {
  NormalSkyPreparedProjection,
  NormalSkyProjectionService
} from './NormalSkyProjectionService';

/**
 * 普通星图的视觉底图模式。导航模式只显示目录对象；摄影模式显示固定历元的可见光银河参考纹理。
 *
 * 该模式不会改变星表坐标、命中测试、观测规划或设备控制的坐标来源。
 */
export enum SkyBackdropMode {
  NAVIGATION = 'navigation',
  VISIBLE_PHOTOGRAPHY = 'visible_photography'
}

export enum SkySurveyBackdropStatus {
  DISABLED = 'disabled',
  LOADING = 'loading',
  READY = 'ready',
  FAILED = 'failed'
}

/**
 * 传递给 ArkUI 背景层的单帧结果。
 *
 * PixelMap 与生成视口绑定：新请求完成前继续保留旧帧，避免拖动、飞行或尺寸变化时出现黑屏闪烁。
 */
export interface SkySurveyBackdropFrame {
  status: SkySurveyBackdropStatus;
  pixelMap: image.PixelMap | undefined;
  widthPixels: number;
  heightPixels: number;
  opacity: number;
  generation: number;
  message: string;
}

/**
 * 对 ESO 可见光全天图进行离线重投影的轻量服务。
 *
 * 原始摄影纹理已在构建期抑制点状恒星和拍摄年代的移动天体残影；运行时仅采样大尺度银河尘埃、
 * 星云和恒星云结构。这样摄影底图不会与 HYG 目录星重复，也不会把历史行星伪装为当前行星。
 */
export class SkySurveyBackdropService {
  private static readonly RAW_FILE_NAME: string = 'sky_survey_eso_visible_diffuse.rgb';
  private static readonly SOURCE_WIDTH: number = 1536;
  private static readonly SOURCE_HEIGHT: number = 768;
  private static readonly SOURCE_CHANNELS: number = 3;
  private static readonly MINIMUM_VISIBLE_FIELD_OF_VIEW: number = 20.0;
  private static readonly FULL_VISIBLE_FIELD_OF_VIEW: number = 40.0;
  private static readonly MAX_OUTPUT_WIDTH: number = 640;
  private static readonly MIN_OUTPUT_WIDTH: number = 480;
  /*
   * API 23 真机上的 setTimeout(0) 让出通常并非零成本。14 行一片会让 624×408
   * 纹理产生约 30 次调度，实测停手重投影约 640ms。48 行一片仍会在计算期间
   * 周期性归还 ArkUI，但将同档位调度次数压到 8–9 次。
   */
  private static readonly ROWS_PER_SLICE: number = 48;
  private static readonly TWO_PI: number = Math.PI * 2.0;

  private sourcePixels: Uint8Array | undefined = undefined;
  private loadPromise: Promise<void> | undefined = undefined;
  private latestGeneration: number = 0;

  static emptyFrame(message: string = ''): SkySurveyBackdropFrame {
    return {
      status: SkySurveyBackdropStatus.DISABLED,
      pixelMap: undefined,
      widthPixels: 0,
      heightPixels: 0,
      opacity: 0.0,
      generation: 0,
      message: message
    };
  }

  /**
   * 请求指定视口的摄影底图。
   *
   * 逐行分片主动让出 ArkUI 主线程，避免一次性计算几十万像素造成长帧；generation 不一致时
   * 立即放弃旧结果，调用方因此不会被已经过期的拖动或搜索请求覆盖。
   */
  async render(context: common.Context, viewport: NormalSkyViewport, size: SkyMapSize,
    generation: number): Promise<SkySurveyBackdropFrame> {
    const startedAtMs: number = Date.now();
    this.latestGeneration = Math.max(this.latestGeneration, generation);
    const opacity: number = this.opacityForFieldOfView(viewport.fieldOfViewDegrees);
    if (opacity <= 0.0) {
      return SkySurveyBackdropService.emptyFrame('视场较深，已隐藏摄影底图');
    }
    try {
      await this.ensureSource(context);
      if (generation !== this.latestGeneration) {
        return SkySurveyBackdropService.emptyFrame();
      }
      const outputSize: SkyMapSize = this.outputSizeFor(size);
      const prepared: NormalSkyPreparedProjection = NormalSkyProjectionService.prepare(viewport, size);
      const rgba: Uint8Array | undefined = await this.projectPixels(
        prepared, size, outputSize, generation);
      if (rgba === undefined || generation !== this.latestGeneration) {
        return SkySurveyBackdropService.emptyFrame();
      }
      /*
       * ImageKit 的缓冲区入口只接受 ArrayBuffer，且默认源格式是 BGRA_8888。
       * 本服务生成的是 RGBA_8888；若直接传 Uint8Array 且不声明源格式，真机会记录
       * “colors mismatch”并创建出不可见的 PixelMap。这里显式固定输入、输出和透明度
       * 语义，避免不同设备或 API 版本按默认格式猜测。
       */
      /*
       * 必须给 ImageKit 一份独立的 ArrayBuffer。若直接传临时 Uint8Array 的底层
       * buffer，PixelMap 虽可立即回读，但原数组离开作用域后 RenderService 可能只
       * 收到空纹理；官方 API 23 示例同样使用 buffer.slice(0) 固定数据生命周期。
       */
      const pixelBuffer: ArrayBuffer = rgba.buffer.slice(0);
      const pixelMap: image.PixelMap = await image.createPixelMap(pixelBuffer, {
        size: {
          width: Math.max(1, Math.round(outputSize.widthPixels)),
          height: Math.max(1, Math.round(outputSize.heightPixels))
        },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.OPAQUE,
        editable: false
      });
      if (generation !== this.latestGeneration) {
        pixelMap.release();
        return SkySurveyBackdropService.emptyFrame();
      }
      /*
       * 每次停手只输出一条性能记录，便于在不同 Pad 上确认清晰度档位是否越过卡顿阈值。
       * 该日志不位于逐帧触控或 Canvas 绘制路径，不会影响星图滑动性能。
       */
      console.info(`[SkySurveyBackdrop] ${outputSize.widthPixels}x${outputSize.heightPixels} ` +
        `generation=${generation} fov=${viewport.fieldOfViewDegrees.toFixed(1)} ` +
        `rotation=${viewport.rotationDegrees.toFixed(1)} duration=${Date.now() - startedAtMs}ms`);
      return {
        status: SkySurveyBackdropStatus.READY,
        pixelMap: pixelMap,
        widthPixels: outputSize.widthPixels,
        heightPixels: outputSize.heightPixels,
        opacity: opacity,
        generation: generation,
        message: 'ESO 可见光参考影像'
      };
    } catch (error) {
      return {
        status: SkySurveyBackdropStatus.FAILED,
        pixelMap: undefined,
        widthPixels: 0,
        heightPixels: 0,
        opacity: 0.0,
        generation: generation,
        message: `摄影底图不可用：${error}`
      };
    }
  }

  release(frame: SkySurveyBackdropFrame): void {
    if (frame.pixelMap !== undefined) {
      frame.pixelMap.release();
    }
  }

  clear(): void {
    this.sourcePixels = undefined;
    this.loadPromise = undefined;
    this.latestGeneration++;
  }

  private async ensureSource(context: common.Context): Promise<void> {
    if (this.sourcePixels !== undefined) {
      return;
    }
    if (this.loadPromise !== undefined) {
      await this.loadPromise;
      return;
    }
    this.loadPromise = this.loadSource(context);
    try {
      await this.loadPromise;
    } finally {
      this.loadPromise = undefined;
    }
  }

  private async loadSource(context: common.Context): Promise<void> {
    let bytes: Uint8Array;
    try {
      bytes = await context.resourceManager.getRawFileContent(
        SkySurveyBackdropService.RAW_FILE_NAME);
    } catch (error) {
      throw new Error(`读取摄影底图资源失败：${error}`);
    }
    const expectedLength: number = SkySurveyBackdropService.SOURCE_WIDTH *
      SkySurveyBackdropService.SOURCE_HEIGHT * SkySurveyBackdropService.SOURCE_CHANNELS;
    if (bytes.length !== expectedLength) {
      throw new Error(`摄影底图数据长度异常：${bytes.length}/${expectedLength}`);
    }
    this.sourcePixels = bytes;
  }

  private async projectPixels(prepared: NormalSkyPreparedProjection, screenSize: SkyMapSize,
    outputSize: SkyMapSize, generation: number): Promise<Uint8Array | undefined> {
    const source: Uint8Array | undefined = this.sourcePixels;
    if (source === undefined) {
      throw new Error('摄影底图资源尚未加载');
    }
    const width: number = Math.max(1, Math.round(outputSize.widthPixels));
    const height: number = Math.max(1, Math.round(outputSize.heightPixels));
    const result: Uint8Array = new Uint8Array(width * height * 4);
    for (let startY: number = 0; startY < height; startY += SkySurveyBackdropService.ROWS_PER_SLICE) {
      if (generation !== this.latestGeneration) {
        return undefined;
      }
      const endY: number = Math.min(height, startY + SkySurveyBackdropService.ROWS_PER_SLICE);
      for (let y: number = startY; y < endY; y++) {
        const screenY: number = (y + 0.5) * screenSize.heightPixels / height;
        for (let x: number = 0; x < width; x++) {
          const screenX: number = (x + 0.5) * screenSize.widthPixels / width;
          /*
           * 这里是每次重投影最热的循环。若逐像素调用完整数学服务，会为方向、银河坐标和
           * UV 连续创建多个临时对象，还会对理论上已经归一化的向量重复开平方。高分辨率
           * Pad 上会产生数十万次短命对象并加重 GC。下面直接展开同一套立体反投影与
           * IAU J2000 旋转公式，只保留真正需要的 atan2/asin，计算结果与公共数学服务一致。
           */
          const screenOffsetX: number = screenX - prepared.widthPixels / 2.0;
          const screenOffsetY: number = screenY - prepared.heightPixels / 2.0;
          const unrotatedX: number = screenOffsetX * prepared.rotationCosine +
            screenOffsetY * prepared.rotationSine;
          const unrotatedY: number = -screenOffsetX * prepared.rotationSine +
            screenOffsetY * prepared.rotationCosine;
          const planeEast: number = -unrotatedX / prepared.pixelScale;
          const planeNorth: number = -unrotatedY / prepared.pixelScale;
          const radiusSquared: number = planeEast * planeEast + planeNorth * planeNorth;
          const inverseDenominator: number = 1.0 / (1.0 + radiusSquared / 4.0);
          const centerFactor: number = (1.0 - radiusSquared / 4.0) * inverseDenominator;
          const directionX: number = centerFactor * prepared.centerX + inverseDenominator *
            (planeEast * prepared.eastX + planeNorth * prepared.northX);
          const directionY: number = centerFactor * prepared.centerY + inverseDenominator *
            (planeEast * prepared.eastY + planeNorth * prepared.northY);
          const directionZ: number = centerFactor * prepared.centerZ + inverseDenominator *
            (planeEast * prepared.eastZ + planeNorth * prepared.northZ);
          const galacticX: number = -0.0548755604 * directionX -
            0.8734370902 * directionY - 0.4838350155 * directionZ;
          const galacticY: number = 0.4941094279 * directionX -
            0.4448296300 * directionY + 0.7469822445 * directionZ;
          const galacticZ: number = -0.8676661490 * directionX -
            0.1980763734 * directionY + 0.4559837762 * directionZ;
          const galacticLongitude: number = Math.atan2(galacticY, galacticX);
          let textureU: number = 0.5 - galacticLongitude / SkySurveyBackdropService.TWO_PI;
          if (textureU < 0.0) {
            textureU += 1.0;
          } else if (textureU >= 1.0) {
            textureU -= 1.0;
          }
          const textureV: number = 0.5 - Math.asin(
            Math.max(-1.0, Math.min(1.0, galacticZ))) / Math.PI;
          this.sampleBilinear(source, textureU, textureV, result, (y * width + x) * 4);
        }
      }
      await this.yieldToUi();
    }
    return result;
  }

  private sampleBilinear(source: Uint8Array, textureU: number, textureV: number,
    output: Uint8Array, outputOffset: number): void {
    const sourceX: number = textureU * (SkySurveyBackdropService.SOURCE_WIDTH - 1);
    const sourceY: number = textureV * (SkySurveyBackdropService.SOURCE_HEIGHT - 1);
    const left: number = Math.max(0, Math.min(SkySurveyBackdropService.SOURCE_WIDTH - 1,
      Math.floor(sourceX)));
    const top: number = Math.max(0, Math.min(SkySurveyBackdropService.SOURCE_HEIGHT - 1,
      Math.floor(sourceY)));
    const right: number = (left + 1) % SkySurveyBackdropService.SOURCE_WIDTH;
    const bottom: number = Math.min(SkySurveyBackdropService.SOURCE_HEIGHT - 1, top + 1);
    const horizontal: number = sourceX - left;
    const vertical: number = sourceY - top;
    const topLeft: number = (top * SkySurveyBackdropService.SOURCE_WIDTH + left) *
      SkySurveyBackdropService.SOURCE_CHANNELS;
    const topRight: number = (top * SkySurveyBackdropService.SOURCE_WIDTH + right) *
      SkySurveyBackdropService.SOURCE_CHANNELS;
    const bottomLeft: number = (bottom * SkySurveyBackdropService.SOURCE_WIDTH + left) *
      SkySurveyBackdropService.SOURCE_CHANNELS;
    const bottomRight: number = (bottom * SkySurveyBackdropService.SOURCE_WIDTH + right) *
      SkySurveyBackdropService.SOURCE_CHANNELS;
    for (let channel: number = 0; channel < 3; channel++) {
      const topValue: number = source[topLeft + channel] * (1.0 - horizontal) +
        source[topRight + channel] * horizontal;
      const bottomValue: number = source[bottomLeft + channel] * (1.0 - horizontal) +
        source[bottomRight + channel] * horizontal;
      output[outputOffset + channel] = Math.round(topValue * (1.0 - vertical) +
        bottomValue * vertical);
    }
    output[outputOffset + 3] = 255;
  }

  private outputSizeFor(size: SkyMapSize): SkyMapSize {
    /*
     * 纹理已经在构建期做过点源抑制，只承载银河尘埃与恒星云的大尺度结构。
     * 真机验证表明 0.30 倍宽度在 MatePad 上仅约 336px，放大到全屏后银河结构明显发糊。
     * 这里提升到约 0.52 倍并限制在 480–640px：MatePad 当前 1120px 视口生成约
     * 576px，分屏和手机也不会低于 480px。运行时热循环已改为标量计算，
     * 清晰度提升不会再叠加大量临时对象和重复向量归一化。
     */
    const widthRatio: number = 0.52;
    const width: number = Math.max(SkySurveyBackdropService.MIN_OUTPUT_WIDTH,
      Math.min(SkySurveyBackdropService.MAX_OUTPUT_WIDTH,
        Math.round(Math.max(1.0, size.widthPixels) * widthRatio / 16.0) * 16.0));
    const height: number = Math.max(160.0, Math.round(width *
      Math.max(1.0, size.heightPixels) / Math.max(1.0, size.widthPixels) / 8.0) * 8.0);
    return {
      widthPixels: width,
      heightPixels: height
    };
  }

  private opacityForFieldOfView(fieldOfViewDegrees: number): number {
    if (!Number.isFinite(fieldOfViewDegrees) ||
      fieldOfViewDegrees <= SkySurveyBackdropService.MINIMUM_VISIBLE_FIELD_OF_VIEW) {
      return 0.0;
    }
    const ratio: number = Math.max(0.0, Math.min(1.0,
      (fieldOfViewDegrees - SkySurveyBackdropService.MINIMUM_VISIBLE_FIELD_OF_VIEW) /
      (SkySurveyBackdropService.FULL_VISIBLE_FIELD_OF_VIEW -
        SkySurveyBackdropService.MINIMUM_VISIBLE_FIELD_OF_VIEW)));
    return 0.92 * ratio;
  }

  private async yieldToUi(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 0);
    });
  }
}

import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';

/**
 * 普通星图的视觉底图模式。导航模式只显示目录对象；摄影模式显示固定历元的可见光银河参考纹理。
 *
 * 摄影底图不会改变星表坐标、命中测试、观测规划或设备控制的坐标来源。
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
 * ESO 全天摄影纹理加载器。
 *
 * 旧实现会在每次停手后把当前视口逐像素重投影为一张矩形 PixelMap，既耗时，也无法在
 * 宽视场和天极附近用单个仿射矩形逼近真实球面。本服务只负责一次性解码完整全天纹理；
 * 实时球面变形由 SkySurveyMeshBackdrop 的 Drawing Canvas 完成。
 */
export class SkySurveyBackdropService {
  private static readonly RAW_FILE_NAME: string = 'sky_survey_eso_visible_6000x3000.png';
  private static readonly SOURCE_WIDTH: number = 6000;
  private static readonly SOURCE_HEIGHT: number = 3000;
  private static readonly MINIMUM_VISIBLE_FIELD_OF_VIEW: number = 20.0;
  private static readonly FULL_VISIBLE_FIELD_OF_VIEW: number = 40.0;

  private pixelMap: image.PixelMap | undefined = undefined;
  private loadPromise: Promise<image.PixelMap> | undefined = undefined;
  private generation: number = 0;

  /**
   * 返回完整 6000×3000 全天纹理。
   *
   * API 23 真机对 HAP 内大尺寸 PNG 的 RawFileDescriptor 解码存在兼容性差异：
   * 类型声明允许把 descriptor 直接交给 ImageSource，但 MatePad 11.5 2026 实测会在
   * createPixelMap 阶段报 “Decode image header failed”。这里改为读取压缩资源字节后
   * 创建 ImageSource，避开 HAP 文件描述符的 offset/length 解析差异。字节缓冲只在
   * 首次进入摄影模式时短暂存在，完成解码后不保存，不会进入拖动、旋转或缩放热路径。
   */
  async load(context: common.Context): Promise<image.PixelMap> {
    if (this.pixelMap !== undefined) {
      return this.pixelMap;
    }
    if (this.loadPromise !== undefined) {
      return await this.loadPromise;
    }
    const requestedGeneration: number = this.generation;
    this.loadPromise = this.decode(context, requestedGeneration);
    try {
      const loaded: image.PixelMap = await this.loadPromise;
      if (requestedGeneration !== this.generation) {
        loaded.release();
        throw new Error('摄影底图加载已取消');
      }
      this.pixelMap = loaded;
      return loaded;
    } finally {
      this.loadPromise = undefined;
    }
  }

  /**
   * 页面销毁时释放唯一的全天纹理所有权。普通拖动、缩放和模式内切换不得调用此方法，
   * 否则会反复解码大图并造成明显卡顿。
   */
  clear(): void {
    this.generation++;
    if (this.pixelMap !== undefined) {
      this.pixelMap.release();
      this.pixelMap = undefined;
    }
  }

  /** 深视场下原图分辨率不足，平滑隐藏摄影纹理，避免把有限像素强行放大成模糊色块。 */
  static opacityForFieldOfView(fieldOfViewDegrees: number): number {
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

  private async decode(context: common.Context, requestedGeneration: number): Promise<image.PixelMap> {
    let source: image.ImageSource | undefined = undefined;
    try {
      const encodedBytes: Uint8Array = await context.resourceManager.getRawFileContent(
        SkySurveyBackdropService.RAW_FILE_NAME);
      const encodedBuffer: ArrayBuffer = encodedBytes.buffer.slice(
        encodedBytes.byteOffset, encodedBytes.byteOffset + encodedBytes.byteLength);
      source = image.createImageSource(encodedBuffer);
      /*
       * 不向解码器重复指定原图尺寸，也不强制 RGB_888。部分 API 23 设备会把
       * “大尺寸 PNG + 原尺寸缩放请求 + 三通道输出”错误地送入不兼容的解码路径，
       * 最终统一报成 image header failed。让 ImageKit 保留源尺寸并选择其原生
       * PixelMap 格式，Drawing Canvas 可以直接消费，且避免一次无意义的同尺寸缩放。
       */
      const decoded: image.PixelMap = await source.createPixelMap();
      if (requestedGeneration !== this.generation) {
        decoded.release();
        throw new Error('摄影底图加载已取消');
      }
      return decoded;
    } catch (error) {
      throw new Error(`读取摄影底图资源失败：${error}`);
    } finally {
      if (source !== undefined) {
        await source.release();
      }
    }
  }
}

import {
  CameraCapabilities,
  CaptureMode,
  CapturePlan,
  CelestialObject,
  CelestialType,
  HorizontalCoordinate,
  ImageFormat
} from '../models/DomainModels';

export interface CaptureRecommendationInput {
  target: CelestialObject;
  horizontal: HorizontalCoordinate;
  mode: CaptureMode;
  bortleClass: number;
  moonIllumination: number;
  moonSeparationDegrees: number;
  cameraCapabilities?: CameraCapabilities;
}
/** 根据 18mm 广角、无传统导星和城市光污染约束生成保守可执行的拍摄计划。 */
export class CapturePlanner {
  static recommend(input: CaptureRecommendationInput): CapturePlan {
    const warnings: string[] = [];
    const bortle: number = CapturePlanner.clamp(Math.round(input.bortleClass), 1, 9);
    const moonIllumination: number = CapturePlanner.clamp(input.moonIllumination, 0.0, 1.0);
    const capabilities: CameraCapabilities | undefined = input.cameraCapabilities;

    if (!input.target.gotoAllowed) {
      warnings.push('该条目只有目录索引，缺少可靠坐标，禁止自动 GOTO。');
    }
    if (input.horizontal.altitudeDegrees < 20.0) {
      warnings.push('目标高度低于 20°，大气消光和城市光污染会明显增加。');
    }
    if (moonIllumination > 0.6 && input.moonSeparationDegrees < 60.0) {
      warnings.push('月光较强且接近目标，建议调整拍摄日期或避开月球方向。');
    }
    if (input.target.angularSizeDegrees !== undefined && input.target.angularSizeDegrees < 0.5) {
      warnings.push('目标角尺寸偏小，18mm 镜头只能记录环境星野，无法呈现主体细节。');
    }
    if (!input.target.recommendedFor18mm && input.target.type === CelestialType.MESSIER) {
      warnings.push('该深空目标不属于 18mm 推荐目标，建议改选大型星云、星团或星座星野。');
    }

    if (input.mode === CaptureMode.OBSERVE_ONLY) {
      return CapturePlanner.createPlan(input, 0.0, 0, 0, 0, 0.0, ImageFormat.JPEG,
        false, false, false, false, '仅执行 GOTO 与恒星时跟踪，不触发相机快门。', warnings);
    }

    if (input.mode === CaptureMode.TIMELAPSE) {
      const exposure: number = bortle >= 7 ? 5.0 : 8.0;
      return CapturePlanner.createPlan(input, exposure, 180, 12, bortle >= 7 ? 800 : 1250, 2.8,
        ImageFormat.JPEG, false, false, false, false,
        '城市广角延时默认 180 帧，曝光与间隔留出相机写卡余量，输出 25 fps。', warnings);
    }

    let exposureSeconds: number = bortle >= 7 ? 12.0 : (bortle >= 5 ? 20.0 : 30.0);
    if (capabilities !== undefined) {
      exposureSeconds = Math.min(exposureSeconds, capabilities.maxExposureSeconds);
    } else {
      // 未读取 R7 能力前按非 Bulb 的 30 秒上限设计，防止计划在现场无法执行。
      exposureSeconds = Math.min(exposureSeconds, 30.0);
    }
    let frameCount: number = 80;
    let iso: number = bortle >= 7 ? 800 : 1600;
    if (input.target.type === CelestialType.MOON) {
      exposureSeconds = 0.01;
      frameCount = 40;
      iso = 200;
      warnings.push('月面曝光需在现场按月相检查直方图，避免高光溢出。');
    } else if (input.target.type === CelestialType.SUN) {
      exposureSeconds = 0.001;
      frameCount = 30;
      iso = 100;
      warnings.push('太阳拍摄必须安装合格的镜头前端太阳滤镜；未确认滤镜时不得执行。');
    }
    const rawSupported: boolean = capabilities === undefined || capabilities.rawSupported;
    return CapturePlanner.createPlan(input, exposureSeconds, frameCount, 2, iso, 2.8,
      rawSupported ? ImageFormat.RAW_JPEG : ImageFormat.JPEG, true, true, true, true,
      `Bortle ${bortle} 城市条件采用短子曝光、星点配准堆栈和子曝光间漂移修正。`, warnings);
  }

  static validate(plan: CapturePlan): string[] {
    const errors: string[] = [];
    if (plan.mode !== CaptureMode.OBSERVE_ONLY && plan.exposureSeconds <= 0.0) {
      errors.push('曝光时间必须大于 0 秒。');
    }
    if (plan.mode !== CaptureMode.OBSERVE_ONLY && plan.frameCount <= 0) {
      errors.push('拍摄张数必须大于 0。');
    }
    if (plan.mode === CaptureMode.TIMELAPSE && plan.intervalSeconds < plan.exposureSeconds) {
      errors.push('延时间隔不能短于单帧曝光时间。');
    }
    if (plan.iso < 50 || plan.iso > 51200) {
      errors.push('ISO 超出佳能 R7 常用安全范围。');
    }
    if (plan.outputFps < 1 || plan.outputFps > 60) {
      errors.push('视频输出帧率必须在 1–60 fps。');
    }
    return errors;
  }

  private static createPlan(input: CaptureRecommendationInput, exposureSeconds: number,
    frameCount: number, intervalSeconds: number, iso: number, aperture: number, imageFormat: ImageFormat,
    enablePlateSolve: boolean, enableDriftCorrection: boolean, enableLocalStack: boolean,
    enableCloudEnhancement: boolean, reason: string, warnings: string[]): CapturePlan {
    return {
      id: `plan-${Date.now()}-${input.target.id}`,
      mode: input.mode,
      targetId: input.target.id,
      targetName: input.target.nameZh,
      exposureSeconds: exposureSeconds,
      frameCount: frameCount,
      intervalSeconds: intervalSeconds,
      iso: iso,
      aperture: aperture,
      imageFormat: imageFormat,
      outputFps: 25,
      enablePlateSolve: enablePlateSolve,
      enableDriftCorrection: enableDriftCorrection,
      enableLocalStack: enableLocalStack,
      enableCloudEnhancement: enableCloudEnhancement,
      recommendationReason: reason,
      warnings: warnings.slice()
    };
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

import { BusinessError } from '@kit.BasicServicesKit';
import {
  ArEngineAvailability,
  ArEngineCapabilityResult,
  ArEngineErrorCategory,
  ArEngineFailure
} from '../models/HuaweiArModels';

export const AR_ENGINE_CORE_SYSCAP: string = 'SystemCapability.AREngine.Core';

/**
 * API 22 的 AR Engine 能力检测与错误归一化入口。
 *
 * `arViewController.isARTypeSupported` 从 API 23 才提供，当前工程必须只使用
 * `canIUse('SystemCapability.AREngine.Core')` 做预检，并在 init 阶段继续处理设备、
 * 配置和相机占用错误。能力预检通过不等于当前设备一定能成功创建 AR 会话。
 */
export class ArEngineCapabilityService {
  static inspect(): ArEngineCapabilityResult {
    let available: boolean = false;
    try {
      available = canIUse(AR_ENGINE_CORE_SYSCAP);
    } catch (error) {
      available = false;
    }
    return {
      availability: available ? ArEngineAvailability.AVAILABLE :
        ArEngineAvailability.CORE_CAPABILITY_MISSING,
      available: available,
      message: available ? '设备声明支持 HarmonyOS AR Engine' : '当前设备不支持 HarmonyOS AR Engine 核心能力'
    };
  }

  static isCoreCapabilityAvailable(): boolean {
    return ArEngineCapabilityService.inspect().available;
  }

  static classifyError(error: Error): ArEngineFailure {
    const businessError: BusinessError = error as BusinessError;
    const code: number = businessError.code;
    const message: string = error.message.length > 0 ? error.message : 'AR Engine 未返回详细错误信息';
    return ArEngineCapabilityService.classifyCode(code, message);
  }

  static classifyCode(code: number, message: string): ArEngineFailure {
    switch (code) {
      case 201:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.PERMISSION_DENIED, message,
          '缺少相机或运动传感器权限', false);
      case 401:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.INVALID_ARGUMENT, message,
          'AR Engine 参数无效', false);
      case 801:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.DEVICE_UNSUPPORTED, message,
          '当前设备不支持 AR Engine', false);
      case 1009200001:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.INTERNAL_FAILURE, message,
          'AR Engine 运行失败', true);
      case 1009200007:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.CONFIGURATION_UNSUPPORTED, message,
          '当前设备不支持所选 AR 配置', false);
      case 1009200008:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.RESOURCE_EXHAUSTED, message,
          'AR Engine 可用资源不足', true);
      case 1009200009:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.SERVICE_UNAVAILABLE, message,
          'AR Engine 服务暂时不可用', true);
      case 1009200010:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.CAMERA_UNAVAILABLE, message,
          '后置相机正被占用或暂时不可用', true);
      case 1009200201:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.INVALID_OPERATION, message,
          '当前 ARView 状态不允许此操作', false);
      case 1009200202:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.AR_SCENE_REQUIRED, message,
          'ARView 缺少 ArkGraphics3D 场景', false);
      case 1009200203:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.CONFIG_REQUIRED, message,
          'ARView 缺少 AR Engine 配置', false);
      case 1009200204:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.SESSION_SETUP_FAILED, message,
          'AR Engine 会话创建失败', true);
      case 1009200205:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.CAMERA_SETUP_FAILED, message,
          'AR 场景相机创建失败', true);
      default:
        return ArEngineCapabilityService.failure(code, ArEngineErrorCategory.UNKNOWN, message,
          'AR Engine 出现未知错误', true);
    }
  }

  private static failure(code: number, category: ArEngineErrorCategory, message: string,
    userMessage: string, retryable: boolean): ArEngineFailure {
    return {
      code: code,
      category: category,
      message: message,
      userMessage: userMessage,
      retryable: retryable
    };
  }
}

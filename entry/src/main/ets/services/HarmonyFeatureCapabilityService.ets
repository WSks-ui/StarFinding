import { deviceInfo } from '@kit.BasicServicesKit';
import {
  HarmonyCapabilityReason,
  HarmonyCapabilityState,
  HarmonyFeatureCapability,
  HarmonyFeatureKind,
  HarmonyFeatureProbeInput,
  HarmonyFeatureSnapshot
} from '../models/HarmonyFeatureModels';

export const API_23_LEVEL: number = 23;
export const SCAN_KIT_SYSCAP: string = 'SystemCapability.Multimedia.Scan.ScanBarcode';
export const LIVE_VIEW_SYSCAP: string = 'SystemCapability.LiveView.LiveViewService';
export const FORM_KIT_SYSCAP: string = 'SystemCapability.Ability.Form';
export const SYSTEM_SHARE_SYSCAP: string = 'SystemCapability.Collaboration.SystemShare';
export const HARMONY_SHARE_SYSCAP: string = 'SystemCapability.Collaboration.HarmonyShare';

/**
 * 鸿蒙能力预检入口。
 *
 * canIUse 只表示系统声明了对应 SystemCapability，不能代替权益、用户开关或设备状态检查。
 * 因此实况窗和 Harmony Share 在本服务中只会进入 RUNTIME_PROBE_REQUIRED；调用方必须在
 * 真正使用前继续执行各 Kit 的官方运行时探测，禁止据此直接显示“已启用”。
 */
export class HarmonyFeatureCapabilityService {
  static inspect(): HarmonyFeatureSnapshot {
    const input: HarmonyFeatureProbeInput = {
      runtimeApiLevel: deviceInfo.sdkApiVersion,
      osFullName: deviceInfo.osFullName,
      scanKitDeclared: HarmonyFeatureCapabilityService.safeCanIUse(SCAN_KIT_SYSCAP),
      liveViewDeclared: HarmonyFeatureCapabilityService.safeCanIUse(LIVE_VIEW_SYSCAP),
      formKitDeclared: HarmonyFeatureCapabilityService.safeCanIUse(FORM_KIT_SYSCAP),
      systemShareDeclared: HarmonyFeatureCapabilityService.safeCanIUse(SYSTEM_SHARE_SYSCAP),
      harmonyShareDeclared: HarmonyFeatureCapabilityService.safeCanIUse(HARMONY_SHARE_SYSCAP),
      // 当前 module.json5 尚未注册卡片 ExtensionAbility，必须如实标记为未配置。
      formExtensionConfigured: false
    };
    return HarmonyFeatureCapabilityService.inspectWithInput(input);
  }

  /**
   * 纯函数入口供单元测试和后续构建变体使用，避免测试依赖真实设备的系统能力集合。
   */
  static inspectWithInput(input: HarmonyFeatureProbeInput): HarmonyFeatureSnapshot {
    const supportsApi23Runtime: boolean = input.runtimeApiLevel >= API_23_LEVEL;
    return {
      runtimeApiLevel: input.runtimeApiLevel,
      osFullName: input.osFullName,
      supportsApi23Runtime: supportsApi23Runtime,
      scanKit: HarmonyFeatureCapabilityService.createDirectCapability(
        HarmonyFeatureKind.SCAN_KIT, 10, SCAN_KIT_SYSCAP, input.runtimeApiLevel, input.scanKitDeclared),
      liveView: HarmonyFeatureCapabilityService.createRuntimeProbeCapability(
        HarmonyFeatureKind.LIVE_VIEW, 11, LIVE_VIEW_SYSCAP, input.runtimeApiLevel, input.liveViewDeclared,
        HarmonyCapabilityReason.LIVE_VIEW_RIGHT_AND_SWITCH_REQUIRED),
      formKit: HarmonyFeatureCapabilityService.createFormCapability(input),
      systemShare: HarmonyFeatureCapabilityService.createDirectCapability(
        HarmonyFeatureKind.SYSTEM_SHARE, 11, SYSTEM_SHARE_SYSCAP,
        input.runtimeApiLevel, input.systemShareDeclared),
      harmonyShare: HarmonyFeatureCapabilityService.createRuntimeProbeCapability(
        HarmonyFeatureKind.HARMONY_SHARE, 12, HARMONY_SHARE_SYSCAP,
        input.runtimeApiLevel, input.harmonyShareDeclared,
        HarmonyCapabilityReason.HARMONY_SHARE_DEVICE_PROBE_REQUIRED)
    };
  }

  static api23RuntimeCapability(runtimeApiLevel: number): HarmonyFeatureCapability {
    if (runtimeApiLevel < API_23_LEVEL) {
      return HarmonyFeatureCapabilityService.createCapability(
        HarmonyFeatureKind.API_23_RUNTIME,
        HarmonyCapabilityState.API_LEVEL_TOO_LOW,
        HarmonyCapabilityReason.API_LEVEL_TOO_LOW,
        API_23_LEVEL,
        '',
        false,
        false);
    }
    return HarmonyFeatureCapabilityService.createCapability(
      HarmonyFeatureKind.API_23_RUNTIME,
      HarmonyCapabilityState.AVAILABLE,
      HarmonyCapabilityReason.READY,
      API_23_LEVEL,
      '',
      true,
      true);
  }

  private static safeCanIUse(systemCapability: string): boolean {
    try {
      return canIUse(systemCapability);
    } catch (error) {
      return false;
    }
  }

  private static createDirectCapability(kind: HarmonyFeatureKind, minimumApiLevel: number,
    systemCapability: string, runtimeApiLevel: number, declared: boolean): HarmonyFeatureCapability {
    const unavailable: HarmonyFeatureCapability | undefined =
      HarmonyFeatureCapabilityService.createUnavailableCapability(
        kind, minimumApiLevel, systemCapability, runtimeApiLevel, declared);
    if (unavailable !== undefined) {
      return unavailable;
    }
    return HarmonyFeatureCapabilityService.createCapability(
      kind,
      HarmonyCapabilityState.AVAILABLE,
      HarmonyCapabilityReason.READY,
      minimumApiLevel,
      systemCapability,
      true,
      true);
  }

  private static createRuntimeProbeCapability(kind: HarmonyFeatureKind, minimumApiLevel: number,
    systemCapability: string, runtimeApiLevel: number, declared: boolean,
    reason: HarmonyCapabilityReason): HarmonyFeatureCapability {
    const unavailable: HarmonyFeatureCapability | undefined =
      HarmonyFeatureCapabilityService.createUnavailableCapability(
        kind, minimumApiLevel, systemCapability, runtimeApiLevel, declared);
    if (unavailable !== undefined) {
      return unavailable;
    }
    return HarmonyFeatureCapabilityService.createCapability(
      kind,
      HarmonyCapabilityState.RUNTIME_PROBE_REQUIRED,
      reason,
      minimumApiLevel,
      systemCapability,
      true,
      false);
  }

  private static createFormCapability(input: HarmonyFeatureProbeInput): HarmonyFeatureCapability {
    const unavailable: HarmonyFeatureCapability | undefined =
      HarmonyFeatureCapabilityService.createUnavailableCapability(
        HarmonyFeatureKind.FORM_KIT, 9, FORM_KIT_SYSCAP,
        input.runtimeApiLevel, input.formKitDeclared);
    if (unavailable !== undefined) {
      return unavailable;
    }
    if (!input.formExtensionConfigured) {
      return HarmonyFeatureCapabilityService.createCapability(
        HarmonyFeatureKind.FORM_KIT,
        HarmonyCapabilityState.BUILD_NOT_CONFIGURED,
        HarmonyCapabilityReason.FORM_EXTENSION_NOT_CONFIGURED,
        9,
        FORM_KIT_SYSCAP,
        true,
        false);
    }
    return HarmonyFeatureCapabilityService.createCapability(
      HarmonyFeatureKind.FORM_KIT,
      HarmonyCapabilityState.AVAILABLE,
      HarmonyCapabilityReason.READY,
      9,
      FORM_KIT_SYSCAP,
      true,
      true);
  }

  private static createUnavailableCapability(kind: HarmonyFeatureKind, minimumApiLevel: number,
    systemCapability: string, runtimeApiLevel: number,
    declared: boolean): HarmonyFeatureCapability | undefined {
    if (runtimeApiLevel < minimumApiLevel) {
      return HarmonyFeatureCapabilityService.createCapability(
        kind,
        HarmonyCapabilityState.API_LEVEL_TOO_LOW,
        HarmonyCapabilityReason.API_LEVEL_TOO_LOW,
        minimumApiLevel,
        systemCapability,
        declared,
        false);
    }
    if (!declared) {
      return HarmonyFeatureCapabilityService.createCapability(
        kind,
        HarmonyCapabilityState.SYSTEM_CAPABILITY_MISSING,
        HarmonyCapabilityReason.SYSTEM_CAPABILITY_MISSING,
        minimumApiLevel,
        systemCapability,
        false,
        false);
    }
    return undefined;
  }

  private static createCapability(kind: HarmonyFeatureKind, state: HarmonyCapabilityState,
    reason: HarmonyCapabilityReason, minimumApiLevel: number, systemCapability: string,
    declared: boolean, available: boolean): HarmonyFeatureCapability {
    return {
      kind: kind,
      state: state,
      reason: reason,
      minimumApiLevel: minimumApiLevel,
      systemCapability: systemCapability,
      systemCapabilityDeclared: declared,
      available: available
    };
  }
}

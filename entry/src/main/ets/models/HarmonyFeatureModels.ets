/**
 * 鸿蒙创新能力的统一标识。
 *
 * 这里描述的是应用需要的能力，不等同于“设备一定可用”。例如实况窗即使存在对应
 * SystemCapability，也仍需要后续权益和开关探测，因此不能仅凭本枚举显示“已启用”。
 */
export enum HarmonyFeatureKind {
  API_23_RUNTIME = 'api_23_runtime',
  SCAN_KIT = 'scan_kit',
  LIVE_VIEW = 'live_view',
  FORM_KIT = 'form_kit',
  SYSTEM_SHARE = 'system_share',
  HARMONY_SHARE = 'harmony_share'
}

export enum HarmonyCapabilityState {
  AVAILABLE = 'available',
  API_LEVEL_TOO_LOW = 'api_level_too_low',
  SYSTEM_CAPABILITY_MISSING = 'system_capability_missing',
  RUNTIME_PROBE_REQUIRED = 'runtime_probe_required',
  BUILD_NOT_CONFIGURED = 'build_not_configured'
}

export enum HarmonyCapabilityReason {
  READY = 'ready',
  API_LEVEL_TOO_LOW = 'api_level_too_low',
  SYSTEM_CAPABILITY_MISSING = 'system_capability_missing',
  LIVE_VIEW_RIGHT_AND_SWITCH_REQUIRED = 'live_view_right_and_switch_required',
  FORM_EXTENSION_NOT_CONFIGURED = 'form_extension_not_configured',
  HARMONY_SHARE_DEVICE_PROBE_REQUIRED = 'harmony_share_device_probe_required'
}

export interface HarmonyFeatureCapability {
  kind: HarmonyFeatureKind;
  state: HarmonyCapabilityState;
  reason: HarmonyCapabilityReason;
  minimumApiLevel: number;
  systemCapability: string;
  systemCapabilityDeclared: boolean;
  available: boolean;
}

export interface HarmonyFeatureProbeInput {
  runtimeApiLevel: number;
  osFullName: string;
  scanKitDeclared: boolean;
  liveViewDeclared: boolean;
  formKitDeclared: boolean;
  systemShareDeclared: boolean;
  harmonyShareDeclared: boolean;
  formExtensionConfigured: boolean;
}

export interface HarmonyFeatureSnapshot {
  runtimeApiLevel: number;
  osFullName: string;
  supportsApi23Runtime: boolean;
  scanKit: HarmonyFeatureCapability;
  liveView: HarmonyFeatureCapability;
  formKit: HarmonyFeatureCapability;
  systemShare: HarmonyFeatureCapability;
  harmonyShare: HarmonyFeatureCapability;
}

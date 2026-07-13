import type { Matrix4 } from '@kit.ArkUI';

/**
 * Huawei AR Engine 的页面间共享契约。
 *
 * 本文件刻意不导入 @kit.AREngine：默认页面需要先读取能力并安全走 CameraKit 降级链，
 * 只有显式 lazy import 的 AR 组件才能触发原生 AR 模块实例化。
 */
export enum ArEngineAvailability {
  AVAILABLE = 'available',
  CORE_CAPABILITY_MISSING = 'core_capability_missing'
}

export enum ArEngineErrorCategory {
  PERMISSION_DENIED = 'permission_denied',
  INVALID_ARGUMENT = 'invalid_argument',
  DEVICE_UNSUPPORTED = 'device_unsupported',
  INTERNAL_FAILURE = 'internal_failure',
  CONFIGURATION_UNSUPPORTED = 'configuration_unsupported',
  RESOURCE_EXHAUSTED = 'resource_exhausted',
  SERVICE_UNAVAILABLE = 'service_unavailable',
  CAMERA_UNAVAILABLE = 'camera_unavailable',
  INVALID_OPERATION = 'invalid_operation',
  AR_SCENE_REQUIRED = 'ar_scene_required',
  CONFIG_REQUIRED = 'config_required',
  SESSION_SETUP_FAILED = 'session_setup_failed',
  CAMERA_SETUP_FAILED = 'camera_setup_failed',
  UNKNOWN = 'unknown'
}

export interface ArEngineCapabilityResult {
  availability: ArEngineAvailability;
  available: boolean;
  message: string;
}

export interface ArEngineFailure {
  code: number;
  category: ArEngineErrorCategory;
  message: string;
  userMessage: string;
  retryable: boolean;
}

export interface HuaweiArQuaternion {
  x: number;
  y: number;
  z: number;
  w: number;
}

export enum HuaweiArCameraTrackingState {
  TRACKING = 'tracking',
  PAUSED = 'paused',
  STOPPED = 'stopped'
}

export enum HuaweiArCameraTrackingReason {
  NONE = 'none',
  EXCESSIVE_MOTION = 'excessive_motion',
  INSUFFICIENT_FEATURES = 'insufficient_features',
  UNKNOWN = 'unknown'
}

export interface HuaweiArFrameSnapshot {
  /** ARFrame 与系统启动时间戳均为单调时钟纳秒，不能直接换算成 Unix 时间。 */
  frameTimestampNs: number;
  systemBootTimestampNs: number;
  cameraState: HuaweiArCameraTrackingState;
  cameraStateReason: HuaweiArCameraTrackingReason;
  viewMatrix: Matrix4;
  projectionMatrix: Matrix4;
  /** 跟踪暂停时官方不保证 Pose 有效，因此该字段必须为空并让上层清除旧姿态。 */
  displayQuaternion?: HuaweiArQuaternion;
}

export enum HuaweiArViewPhase {
  IDLE = 'idle',
  CHECKING = 'checking',
  REQUESTING_PERMISSION = 'requesting_permission',
  INITIALIZING = 'initializing',
  RUNNING = 'running',
  LIMITED = 'limited',
  UNSUPPORTED = 'unsupported',
  PERMISSION_REQUIRED = 'permission_required',
  FAILED = 'failed',
  DESTROYED = 'destroyed'
}

export interface HuaweiArViewStatus {
  phase: HuaweiArViewPhase;
  message: string;
  failure?: ArEngineFailure;
}

export type HuaweiArFrameListener = (snapshot: HuaweiArFrameSnapshot) => void;
export type HuaweiArStatusListener = (status: HuaweiArViewStatus) => void;

/**
 * StarScope 设备码中的固定协议载荷。
 *
 * token 只允许在解析和校验期间短暂存在，禁止把整个载荷保存到页面状态、日志、
 * 分享内容或普通 Preferences 中。当前比赛版仅提交网络终点配置。
 */
export interface DevicePairingPayload {
  schema: string;
  deviceId: string;
  deviceName: string;
  mountHost: string;
  mountPort: number;
  gatewayHost: string;
  gatewayPort: number;
  issuedAtMs: number;
  expiresAtMs?: number;
  token?: string;
  checksum: string;
}

export class DevicePairingConfiguration {
  mountHost: string;
  mountPort: number;
  gatewayHost: string;
  gatewayPort: number;

  constructor(mountHost: string, mountPort: number, gatewayHost: string, gatewayPort: number) {
    this.mountHost = mountHost;
    this.mountPort = mountPort;
    this.gatewayHost = gatewayHost;
    this.gatewayPort = gatewayPort;
  }
}

/**
 * 可安全进入 ArkUI 状态的配对预览。
 *
 * 这里故意不包含 token、二维码原文和完整 JSON，避免敏感字段被 ArkUI 状态快照、
 * 调试输出或后续分享功能意外带出。
 */
export class DevicePairingPreview {
  deviceId: string;
  deviceName: string;
  configuration: DevicePairingConfiguration;
  mountChanged: boolean;
  gatewayChanged: boolean;
  issuedAtMs: number;
  expiresAtMs: number;
  tokenIncluded: boolean;

  constructor(deviceId: string, deviceName: string, configuration: DevicePairingConfiguration,
    mountChanged: boolean, gatewayChanged: boolean, issuedAtMs: number,
    expiresAtMs: number, tokenIncluded: boolean) {
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    this.configuration = configuration;
    this.mountChanged = mountChanged;
    this.gatewayChanged = gatewayChanged;
    this.issuedAtMs = issuedAtMs;
    this.expiresAtMs = expiresAtMs;
    this.tokenIncluded = tokenIncluded;
  }
}

export enum DevicePairingFailureReason {
  NONE = 'none',
  EMPTY_VALUE = 'empty_value',
  CODE_TOO_LARGE = 'code_too_large',
  INVALID_SCHEME = 'invalid_scheme',
  INVALID_QUERY = 'invalid_query',
  UNSUPPORTED_VERSION = 'unsupported_version',
  INVALID_BASE64URL = 'invalid_base64url',
  INVALID_UTF8 = 'invalid_utf8',
  INVALID_JSON = 'invalid_json',
  INVALID_SCHEMA = 'invalid_schema',
  INVALID_DEVICE_ID = 'invalid_device_id',
  INVALID_DEVICE_NAME = 'invalid_device_name',
  INVALID_HOST = 'invalid_host',
  INVALID_PORT = 'invalid_port',
  INVALID_TIME = 'invalid_time',
  EXPIRED = 'expired',
  INVALID_TOKEN = 'invalid_token',
  INVALID_CHECKSUM = 'invalid_checksum'
}

export class DevicePairingValidationResult {
  success: boolean;
  reason: DevicePairingFailureReason;
  message: string;
  preview: DevicePairingPreview | undefined;

  constructor(success: boolean, reason: DevicePairingFailureReason,
    message: string, preview: DevicePairingPreview | undefined) {
    this.success = success;
    this.reason = reason;
    this.message = message;
    this.preview = preview;
  }
}

export enum DevicePairingScanState {
  SUCCESS = 'success',
  CANCELLED = 'cancelled',
  UNAVAILABLE = 'unavailable',
  FAILED = 'failed'
}

/**
 * 扫码原文可能包含 token，只能由调用方立即交给 DevicePairingService 解析。
 * 不得把 originalValue 赋给 @State、写入日志或拼入错误提示。
 */
export class DevicePairingScanResult {
  state: DevicePairingScanState;
  originalValue: string;
  message: string;

  constructor(state: DevicePairingScanState, originalValue: string, message: string) {
    this.state = state;
    this.originalValue = originalValue;
    this.message = message;
  }
}

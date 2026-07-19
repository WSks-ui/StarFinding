import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * Pad 到现场设备的网络终点。
 *
 * OnStepX 的 TCP Socket 使用 IPv4 地址族，网关也部署在临时热点网络中；因此这里明确只接受
 * IPv4 地址和端口，不把“可编辑地址”误做成会在现场解析失败的任意 URL 输入框。
 */
export class DeviceConnectionSettings {
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

interface DeviceConnectionSettingsEnvelope {
  version: number;
  mountHost: string;
  mountPort: number;
  gatewayHost: string;
  gatewayPort: number;
}

export const DEVICE_CONNECTION_PREFERENCES_NAME: string = 'starfinding_device_connection';
export const DEVICE_CONNECTION_PREFERENCES_KEY: string = 'endpoint_v1';
export const DEVICE_CONNECTION_SCHEMA_VERSION: number = 1;

/**
 * 仅持久化用户明确保存的网络地址。读取或保存配置不会建立 TCP/HTTP 连接，
 * 更不会向赤道仪、相机发送任何控制指令。
 */
export class DeviceConnectionSettingsStore {
  private readonly context: common.Context;
  private storage?: preferences.Preferences;
  private settings: DeviceConnectionSettings = DeviceConnectionSettingsStore.defaults();

  constructor(context: common.Context) {
    this.context = context;
  }

  async initialize(): Promise<DeviceConnectionSettings> {
    this.storage = await preferences.getPreferences(this.context, {
      name: DEVICE_CONNECTION_PREFERENCES_NAME
    });
    const stored: preferences.ValueType = await this.storage.get(DEVICE_CONNECTION_PREFERENCES_KEY, '');
    if (typeof stored === 'string') {
      this.settings = DeviceConnectionSettingsStore.decode(stored);
    }
    return DeviceConnectionSettingsStore.copy(this.settings);
  }

  getSettings(): DeviceConnectionSettings {
    return DeviceConnectionSettingsStore.copy(this.settings);
  }

  async save(settings: DeviceConnectionSettings): Promise<void> {
    this.requireInitialized();
    DeviceConnectionSettingsStore.validate(settings);
    this.settings = DeviceConnectionSettingsStore.copy(settings);
    const storage: preferences.Preferences | undefined = this.storage;
    if (storage === undefined) {
      throw new Error('设备地址存储尚未初始化');
    }
    await storage.put(DEVICE_CONNECTION_PREFERENCES_KEY,
      DeviceConnectionSettingsStore.encode(this.settings));
    await storage.flush();
  }

  static defaults(): DeviceConnectionSettings {
    return new DeviceConnectionSettings('10.42.0.20', 9999, '10.42.0.1', 8000);
  }

  static createFromText(mountHost: string, mountPortText: string,
    gatewayHost: string, gatewayPortText: string): DeviceConnectionSettings {
    const normalizedMountHost: string = DeviceConnectionSettingsStore.validateIpv4(mountHost, '赤道仪 IP');
    const mountPort: number = DeviceConnectionSettingsStore.validatePort(mountPortText, '赤道仪端口');
    const normalizedGatewayHost: string =
      DeviceConnectionSettingsStore.validateIpv4(gatewayHost, '网关 IP');
    const gatewayPort: number = DeviceConnectionSettingsStore.validatePort(gatewayPortText, '网关端口');
    return new DeviceConnectionSettings(normalizedMountHost, mountPort, normalizedGatewayHost, gatewayPort);
  }

  static copy(settings: DeviceConnectionSettings): DeviceConnectionSettings {
    return new DeviceConnectionSettings(settings.mountHost, settings.mountPort,
      settings.gatewayHost, settings.gatewayPort);
  }

  static encode(settings: DeviceConnectionSettings): string {
    DeviceConnectionSettingsStore.validate(settings);
    const envelope: DeviceConnectionSettingsEnvelope = {
      version: DEVICE_CONNECTION_SCHEMA_VERSION,
      mountHost: settings.mountHost,
      mountPort: settings.mountPort,
      gatewayHost: settings.gatewayHost,
      gatewayPort: settings.gatewayPort
    };
    return JSON.stringify(envelope);
  }

  static decode(value: string): DeviceConnectionSettings {
    if (value.trim().length === 0) {
      return DeviceConnectionSettingsStore.defaults();
    }
    try {
      const envelope: DeviceConnectionSettingsEnvelope = JSON.parse(value) as DeviceConnectionSettingsEnvelope;
      if (envelope.version !== DEVICE_CONNECTION_SCHEMA_VERSION) {
        return DeviceConnectionSettingsStore.defaults();
      }
      const settings: DeviceConnectionSettings = new DeviceConnectionSettings(
        envelope.mountHost, envelope.mountPort, envelope.gatewayHost, envelope.gatewayPort);
      DeviceConnectionSettingsStore.validate(settings);
      return settings;
    } catch (error) {
      // 地址配置损坏时回退到项目默认拓扑，不能阻断离线星图、规划和设备页启动。
      return DeviceConnectionSettingsStore.defaults();
    }
  }

  static validate(settings: DeviceConnectionSettings): void {
    settings.mountHost = DeviceConnectionSettingsStore.validateIpv4(settings.mountHost, '赤道仪 IP');
    settings.mountPort = DeviceConnectionSettingsStore.validatePortNumber(settings.mountPort, '赤道仪端口');
    settings.gatewayHost = DeviceConnectionSettingsStore.validateIpv4(settings.gatewayHost, '网关 IP');
    settings.gatewayPort = DeviceConnectionSettingsStore.validatePortNumber(settings.gatewayPort, '网关端口');
  }

  private static validateIpv4(value: string, label: string): string {
    const host: string = value.trim();
    const segments: string[] = host.split('.');
    if (segments.length !== 4) {
      throw new Error(`${label}必须是 IPv4 地址，例如 192.168.137.20`);
    }
    const normalized: string[] = [];
    for (let index: number = 0; index < segments.length; index++) {
      const segment: string = segments[index].trim();
      const numeric: number = Number(segment);
      if (segment.length === 0 || !Number.isInteger(numeric) || numeric < 0 || numeric > 255) {
        throw new Error(`${label}第 ${index + 1} 段无效`);
      }
      normalized.push(numeric.toString());
    }
    return `${normalized[0]}.${normalized[1]}.${normalized[2]}.${normalized[3]}`;
  }

  private static validatePort(value: string, label: string): number {
    const text: string = value.trim();
    if (text.length === 0) {
      throw new Error(`${label}不能为空`);
    }
    return DeviceConnectionSettingsStore.validatePortNumber(Number(text), label);
  }

  private static validatePortNumber(value: number, label: string): number {
    if (!Number.isInteger(value) || value < 1 || value > 65535) {
      throw new Error(`${label}必须在 1 到 65535 之间`);
    }
    return value;
  }

  private requireInitialized(): void {
    if (this.storage === undefined) {
      throw new Error('设备地址存储尚未初始化');
    }
  }
}

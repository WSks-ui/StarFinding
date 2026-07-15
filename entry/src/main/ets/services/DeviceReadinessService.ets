import { ConnectionState } from '../models/DomainModels';

export enum MountReadinessStage {
  CONNECT = 'connect',
  BLOCKED = 'blocked',
  HOME = 'home',
  SYNC = 'sync',
  READY = 'ready'
}

export interface MountReadinessInput {
  connection: ConnectionState;
  coordinateModeCompatible: boolean;
  mountHomed: boolean;
  locationSynced: boolean;
  observerAvailable: boolean;
  simulatedTimeActive: boolean;
}

/**
 * 设备页与拍摄入口共享的就绪语义。这里仅解释已经确认的状态，不读取网络或硬件，
 * 防止“默认 false”在未连接时被 UI 错误展示成真实的不兼容或未回零结论。
 */
export class DeviceReadinessService {
  static stage(input: MountReadinessInput): MountReadinessStage {
    if (!DeviceReadinessService.connectionReady(input)) return MountReadinessStage.CONNECT;
    if (!input.coordinateModeCompatible) return MountReadinessStage.BLOCKED;
    if (!input.mountHomed) return MountReadinessStage.HOME;
    if (!DeviceReadinessService.syncReady(input)) return MountReadinessStage.SYNC;
    return MountReadinessStage.READY;
  }

  static connectionReady(input: MountReadinessInput): boolean {
    return input.connection === ConnectionState.CONNECTED;
  }

  static homeReady(input: MountReadinessInput): boolean {
    return DeviceReadinessService.connectionReady(input) &&
      input.coordinateModeCompatible && input.mountHomed;
  }

  static syncReady(input: MountReadinessInput): boolean {
    return DeviceReadinessService.homeReady(input) && input.observerAvailable &&
      !input.simulatedTimeActive && input.locationSynced;
  }

  static fullyReady(input: MountReadinessInput): boolean {
    return DeviceReadinessService.stage(input) === MountReadinessStage.READY;
  }

  static telemetryAvailable(connection: ConnectionState, updatedAtMs: number): boolean {
    return connection === ConnectionState.CONNECTED && Number.isFinite(updatedAtMs) && updatedAtMs > 0;
  }
}

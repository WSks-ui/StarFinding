import { ObservationRunMode } from '../models/DigitalTwinModels';

export interface SimulationEntryState {
  mountDisconnected: boolean;
  gatewayDisconnected: boolean;
  realSessionInactive: boolean;
  operationIdle: boolean;
}

export interface SimulationEntryDecision {
  allowed: boolean;
  reason: string;
}

/**
 * 运行模式安全策略集中在纯 ArkTS 服务中，避免页面遗漏某个硬件按钮。
 * 后续新增 GOTO、同步、拍摄等入口时，必须先经过 allowsHardwareAccess()。
 */
export class ObservationRunModePolicy {
  static allowsHardwareAccess(mode: ObservationRunMode): boolean {
    return mode === ObservationRunMode.REAL;
  }

  static evaluateSimulationEntry(state: SimulationEntryState): SimulationEntryDecision {
    if (!state.operationIdle) {
      return { allowed: false, reason: '正在执行设备操作，请完成后再进入演练模式' };
    }
    if (!state.realSessionInactive) {
      return { allowed: false, reason: '存在真实观测会话，请先结束或归档后再进入演练模式' };
    }
    if (!state.mountDisconnected || !state.gatewayDisconnected) {
      return { allowed: false, reason: '请先断开赤道仪和相机网关，再进入演练模式' };
    }
    return { allowed: true, reason: '' };
  }
}

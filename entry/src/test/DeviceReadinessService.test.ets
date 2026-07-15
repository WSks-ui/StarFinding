import { describe, expect, it } from '@ohos/hypium';
import { ConnectionState } from '../main/ets/models/DomainModels';
import {
  DeviceReadinessService,
  MountReadinessInput,
  MountReadinessStage
} from '../main/ets/services/DeviceReadinessService';

function readinessInput(connection: ConnectionState, coordinateModeCompatible: boolean,
  mountHomed: boolean, locationSynced: boolean, observerAvailable: boolean,
  simulatedTimeActive: boolean): MountReadinessInput {
  return {
    connection: connection,
    coordinateModeCompatible: coordinateModeCompatible,
    mountHomed: mountHomed,
    locationSynced: locationSynced,
    observerAvailable: observerAvailable,
    simulatedTimeActive: simulatedTimeActive
  };
}

export default function deviceReadinessServiceTest(): void {
  describe('设备就绪状态', () => {
    it('未连接时不提供遥测且停留在连接步骤', 0, () => {
      const input: MountReadinessInput = readinessInput(
        ConnectionState.DISCONNECTED, false, false, false, true, false);
      expect(DeviceReadinessService.stage(input)).assertEqual(MountReadinessStage.CONNECT);
      expect(DeviceReadinessService.telemetryAvailable(ConnectionState.DISCONNECTED, 1000)).assertFalse();
      expect(DeviceReadinessService.telemetryAvailable(ConnectionState.CONNECTED, 0)).assertFalse();
    });

    it('已连接但坐标模式不兼容时锁定流程', 0, () => {
      const input: MountReadinessInput = readinessInput(
        ConnectionState.CONNECTED, false, false, false, true, false);
      expect(DeviceReadinessService.stage(input)).assertEqual(MountReadinessStage.BLOCKED);
      expect(DeviceReadinessService.homeReady(input)).assertFalse();
    });

    it('坐标自检通过后要求先完成回零', 0, () => {
      const input: MountReadinessInput = readinessInput(
        ConnectionState.CONNECTED, true, false, false, true, false);
      expect(DeviceReadinessService.stage(input)).assertEqual(MountReadinessStage.HOME);
      expect(DeviceReadinessService.connectionReady(input)).assertTrue();
    });

    it('回零后仍要求真实地点时间同步', 0, () => {
      const missingLocation: MountReadinessInput = readinessInput(
        ConnectionState.CONNECTED, true, true, false, false, false);
      const simulatedTime: MountReadinessInput = readinessInput(
        ConnectionState.CONNECTED, true, true, true, true, true);
      expect(DeviceReadinessService.stage(missingLocation)).assertEqual(MountReadinessStage.SYNC);
      expect(DeviceReadinessService.stage(simulatedTime)).assertEqual(MountReadinessStage.SYNC);
      expect(DeviceReadinessService.syncReady(simulatedTime)).assertFalse();
    });

    it('全部安全条件确认后进入就绪状态', 0, () => {
      const input: MountReadinessInput = readinessInput(
        ConnectionState.CONNECTED, true, true, true, true, false);
      expect(DeviceReadinessService.stage(input)).assertEqual(MountReadinessStage.READY);
      expect(DeviceReadinessService.fullyReady(input)).assertTrue();
      expect(DeviceReadinessService.telemetryAvailable(ConnectionState.CONNECTED, 1000)).assertTrue();
    });
  });
}

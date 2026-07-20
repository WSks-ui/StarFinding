import { describe, expect, it } from '@ohos/hypium';
import {
  CaptureMode,
  CapturePlan,
  CatalogPrecision,
  CelestialType,
  EquatorialFrame,
  ImageFormat
} from '../main/ets/models/DomainModels';
import {
  DigitalTwinPhase,
  DigitalTwinSnapshot,
  ObservationRunMode,
  ReplayAssetManifest,
  ReplayAssetSource
} from '../main/ets/models/DigitalTwinModels';
import { SessionStatus, TaskTargetSnapshot } from '../main/ets/models/TaskSessionModels';
import { DigitalTwinReplayService } from '../main/ets/services/DigitalTwinReplayService';
import {
  ObservationRunModePolicy,
  SimulationEntryDecision,
  SimulationEntryState
} from '../main/ets/services/ObservationRunModePolicy';

function demoPlan(): CapturePlan {
  return {
    id: 'digital-twin-test-plan',
    mode: CaptureMode.SMART_LONG_EXPOSURE,
    targetId: 'star-vega',
    targetName: '织女星',
    exposureSeconds: 15,
    frameCount: 20,
    intervalSeconds: 2,
    iso: 800,
    aperture: 4,
    imageFormat: ImageFormat.RAW_JPEG,
    outputFps: 25,
    enablePlateSolve: true,
    enableDriftCorrection: true,
    enableLocalStack: true,
    enableCloudEnhancement: true,
    recommendationReason: '测试演练',
    warnings: []
  };
}

function demoTarget(): TaskTargetSnapshot {
  return {
    id: 'star-vega',
    name: '织女星',
    designation: 'Alpha Lyr',
    type: CelestialType.STAR,
    coordinate: {
      raHours: 18.6156,
      decDegrees: 38.7837,
      frame: EquatorialFrame.ICRS_J2000
    },
    precision: CatalogPrecision.EXACT,
    gotoAllowed: true
  };
}

export default function digitalTwinReplayServiceTest(): void {
  describe('数字孪生回放与运行模式隔离', () => {
    it('标准演练覆盖异常恢复并保持模拟来源', 0, () => {
      const manifest: ReplayAssetManifest =
        DigitalTwinReplayService.createSimulatedManifest('织女星');
      const frames: DigitalTwinSnapshot[] =
        DigitalTwinReplayService.createStandardDemo(demoPlan(), demoTarget(), manifest);

      expect(frames.length).assertEqual(11);
      expect(frames[0].phase).assertEqual(DigitalTwinPhase.DEVICE_DISCOVERY);
      expect(frames[8].phase).assertEqual(DigitalTwinPhase.RECOVERY);
      expect(frames[10].phase).assertEqual(DigitalTwinPhase.COMPLETE);
      expect(frames[10].session.status).assertEqual(SessionStatus.SUCCEEDED);
      for (let index: number = 0; index < frames.length; index++) {
        expect(frames[index].runMode).assertEqual(ObservationRunMode.SIMULATION);
        expect(frames[index].dataSource).assertEqual(ReplayAssetSource.SIMULATED);
        expect(frames[index].session.gatewayTaskIds.length).assertEqual(0);
        if (index > 0) {
          expect(frames[index].sequence > frames[index - 1].sequence).assertTrue();
        }
      }
    });

    it('停止演练只生成内存取消快照', 0, () => {
      const service: DigitalTwinReplayService = new DigitalTwinReplayService();
      service.loadStandardDemo(demoPlan(), demoTarget());
      service.stop();
      const received: DigitalTwinSnapshot | undefined = service.current();

      expect(received !== undefined).assertTrue();
      if (received !== undefined) {
        expect(received.phase).assertEqual(DigitalTwinPhase.STOPPED);
        expect(received.session.status).assertEqual(SessionStatus.CANCELLED);
        expect(received.session.gatewayTaskIds.length).assertEqual(0);
      }
    });

    it('演练运行域永久拒绝真实硬件访问', 0, () => {
      expect(ObservationRunModePolicy.allowsHardwareAccess(ObservationRunMode.REAL)).assertTrue();
      expect(ObservationRunModePolicy.allowsHardwareAccess(
        ObservationRunMode.SIMULATION)).assertFalse();
    });

    it('真实设备或真实会话未清理时拒绝进入演练', 0, () => {
      const blockedState: SimulationEntryState = {
        mountDisconnected: false,
        gatewayDisconnected: true,
        realSessionInactive: true,
        operationIdle: true
      };
      const blocked: SimulationEntryDecision =
        ObservationRunModePolicy.evaluateSimulationEntry(blockedState);
      expect(blocked.allowed).assertFalse();

      const allowedState: SimulationEntryState = {
        mountDisconnected: true,
        gatewayDisconnected: true,
        realSessionInactive: true,
        operationIdle: true
      };
      const allowed: SimulationEntryDecision =
        ObservationRunModePolicy.evaluateSimulationEntry(allowedState);
      expect(allowed.allowed).assertTrue();
    });
  });
}

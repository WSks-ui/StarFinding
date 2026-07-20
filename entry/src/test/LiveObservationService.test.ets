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
  LiveObservationState
} from '../main/ets/models/LiveObservationModels';
import {
  ObservationRunMode
} from '../main/ets/models/DigitalTwinModels';
import {
  SessionStatus,
  TaskSession,
  TaskTargetSnapshot,
  WorkflowStage
} from '../main/ets/models/TaskSessionModels';
import { DigitalTwinReplayService } from '../main/ets/services/DigitalTwinReplayService';
import { LiveObservationService } from '../main/ets/services/LiveObservationService';

function demoPlan(): CapturePlan {
  return {
    id: 'live-state-plan',
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
    recommendationReason: '实况状态测试',
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

export default function liveObservationServiceTest(): void {
  describe('应用内任务实况映射', () => {
    it('曝光阶段显示真实帧进度并保留演练序号', 0, () => {
      const session: TaskSession = DigitalTwinReplayService.createStandardDemo(
        demoPlan(), demoTarget(),
        DigitalTwinReplayService.createSimulatedManifest('织女星'))[4].session;
      const state: LiveObservationState | undefined = LiveObservationService.fromSession(
        session, ObservationRunMode.SIMULATION, 5);
      expect(state !== undefined).assertTrue();
      if (state !== undefined) {
        expect(state.workflowStage).assertEqual(WorkflowStage.CAPTURE);
        expect(state.totalFrames).assertEqual(20);
        expect(state.sequence).assertEqual(5);
        expect(state.statusText.includes('曝光')).assertTrue();
      }
    });

    it('终态与 TaskSession 保持一致', 0, () => {
      const session: TaskSession = DigitalTwinReplayService.createStandardDemo(
        demoPlan(), demoTarget(),
        DigitalTwinReplayService.createSimulatedManifest('织女星'))[10].session;
      const state: LiveObservationState | undefined = LiveObservationService.fromSession(
        session, ObservationRunMode.REAL, 100);
      expect(state !== undefined).assertTrue();
      if (state !== undefined) {
        expect(state.status).assertEqual(SessionStatus.SUCCEEDED);
        expect(state.progressPercent).assertEqual(100);
        expect(state.statusText).assertEqual('观测任务已完成');
      }
    });

    it('无活动会话时不生成虚假的实况状态', 0, () => {
      const state: LiveObservationState | undefined = LiveObservationService.fromSession(
        undefined, ObservationRunMode.REAL, 0);
      expect(state === undefined).assertTrue();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  CaptureMode,
  CapturePlan,
  CatalogPrecision,
  CelestialType,
  ImageFormat
} from '../main/ets/models/DomainModels';
import {
  GatewaySubtaskKind,
  SessionKind,
  SessionStatus,
  TaskSession,
  TaskSessionStoreSnapshot,
  WorkflowStage,
  WorkflowStepState
} from '../main/ets/models/TaskSessionModels';
import {
  TASK_SESSION_SCHEMA_VERSION,
  TaskSessionStore
} from '../main/ets/services/TaskSessionStore';
import { TaskSessionPresentationService } from '../main/ets/services/TaskSessionPresentationService';

interface TestSessionEnvelope {
  version: number;
  activeSessionJson: string;
  historySessionJson: string[];
}
function testPlan(mode: CaptureMode): CapturePlan {
  return {
    id: `plan-${mode}`,
    mode: mode,
    targetId: 'star-vega',
    targetName: '织女星',
    exposureSeconds: mode === CaptureMode.OBSERVE_ONLY ? 0 : 10,
    frameCount: mode === CaptureMode.OBSERVE_ONLY ? 0 : 20,
    intervalSeconds: mode === CaptureMode.OBSERVE_ONLY ? 0 : 2,
    iso: mode === CaptureMode.OBSERVE_ONLY ? 0 : 800,
    aperture: 4,
    imageFormat: ImageFormat.RAW_JPEG,
    outputFps: 25,
    enablePlateSolve: mode === CaptureMode.SMART_LONG_EXPOSURE,
    enableDriftCorrection: mode === CaptureMode.SMART_LONG_EXPOSURE,
    enableLocalStack: mode === CaptureMode.SMART_LONG_EXPOSURE,
    enableCloudEnhancement: false,
    recommendationReason: '测试快照',
    warnings: ['原始警告']
  };
}

function testSession(id: string, mode: CaptureMode, status: SessionStatus): TaskSession {
  const kind: SessionKind = mode === CaptureMode.OBSERVE_ONLY ? SessionKind.OBSERVATION :
    (mode === CaptureMode.SMART_LONG_EXPOSURE ? SessionKind.SMART_LONG_EXPOSURE : SessionKind.TIMELAPSE);
  return {
    id: id,
    kind: kind,
    status: status,
    stage: WorkflowStage.SAFETY_CHECK,
    progressPercent: 1,
    completedFrames: 0,
    plan: testPlan(mode),
    target: {
      id: 'star-vega',
      name: '织女星',
      designation: 'Alpha Lyr',
      type: CelestialType.STAR,
      coordinate: undefined,
      precision: CatalogPrecision.EXACT,
      gotoAllowed: true
    },
    checkpoint: {
      stage: WorkflowStage.SAFETY_CHECK,
      stepState: WorkflowStepState.ACTIVE,
      childKind: GatewaySubtaskKind.NONE,
      operationKey: '',
      childTaskId: '',
      requestStartedAtMs: 1,
      responseReceivedAtMs: 0,
      requiresManualContinue: false,
      detail: '测试'
    },
    gatewayTaskIds: [],
    jpegFileIds: [],
    rawFileIds: [],
    plateSolveCount: 0,
    correctionCount: 0,
    products: [],
    warnings: ['会话警告'],
    statusDetail: '测试会话',
    errorMessage: '',
    createdAtMs: 1,
    startedAtMs: 1,
    updatedAtMs: 1,
    completedAtMs: TaskSessionStore.isTerminal(status) ? 2 : 0
  };
}

export default function taskSessionStoreTest(): void {
  describe('任务会话持久化与展示派生', () => {
    it('冻结快照不受源计划和目标后续修改影响', 0, () => {
      const source: TaskSession = testSession('active', CaptureMode.SMART_LONG_EXPOSURE,
        SessionStatus.RUNNING);
      const frozen: TaskSession = TaskSessionStore.copySession(source);
      source.plan.targetName = '已切换目标';
      source.target.name = '已切换目标';
      source.plan.warnings.push('新警告');

      expect(frozen.plan.targetName).assertEqual('织女星');
      expect(frozen.target.name).assertEqual('织女星');
      expect(frozen.plan.warnings.length).assertEqual(1);
    });

    it('单条历史损坏时保留其余会话', 0, () => {
      const active: TaskSession = testSession('active', CaptureMode.TIMELAPSE, SessionStatus.INTERRUPTED);
      const first: TaskSession = testSession('first', CaptureMode.TIMELAPSE, SessionStatus.SUCCEEDED);
      const second: TaskSession = testSession('second', CaptureMode.OBSERVE_ONLY, SessionStatus.CANCELLED);
      const envelope: TestSessionEnvelope = {
        version: TASK_SESSION_SCHEMA_VERSION,
        activeSessionJson: JSON.stringify(active),
        historySessionJson: [JSON.stringify(first), '{broken-json', JSON.stringify(second)]
      };
      const decoded: TaskSessionStoreSnapshot = TaskSessionStore.decode(JSON.stringify(envelope));

      expect(decoded.activeSession !== undefined).assertTrue();
      expect(decoded.history.length).assertEqual(2);
      expect(decoded.corruptedRecords).assertEqual(1);
    });

    it('历史只保留最新十条终态会话', 0, () => {
      const history: TaskSession[] = [];
      for (let index: number = 0; index < 12; index++) {
        history.push(testSession(`history-${index}`, CaptureMode.TIMELAPSE, SessionStatus.SUCCEEDED));
      }
      const snapshot: TaskSessionStoreSnapshot = {
        activeSession: undefined,
        history: history,
        corruptedRecords: 0,
        warning: ''
      };
      const decoded: TaskSessionStoreSnapshot = TaskSessionStore.decode(TaskSessionStore.encode(snapshot));
      expect(decoded.history.length).assertEqual(10);
      expect(decoded.history[0].id).assertEqual('history-0');
      expect(decoded.history[9].id).assertEqual('history-9');
    });

    it('不兼容版本不会阻断应用启动', 0, () => {
      const envelope: TestSessionEnvelope = {
        version: 99,
        activeSessionJson: '',
        historySessionJson: []
      };
      const decoded: TaskSessionStoreSnapshot = TaskSessionStore.decode(JSON.stringify(envelope));
      expect(decoded.activeSession === undefined).assertTrue();
      expect(decoded.history.length).assertEqual(0);
      expect(decoded.warning.length > 0).assertTrue();
    });

    it('仅观测流水线不包含曝光和后处理', 0, () => {
      const session: TaskSession = testSession('observe', CaptureMode.OBSERVE_ONLY, SessionStatus.RUNNING);
      const stages: WorkflowStage[] = TaskSessionPresentationService.pipelineStages(session);
      expect(stages.includes(WorkflowStage.SAFETY_CHECK)).assertTrue();
      expect(stages.includes(WorkflowStage.GOTO)).assertTrue();
      expect(stages.includes(WorkflowStage.TRACKING)).assertTrue();
      expect(stages.includes(WorkflowStage.CAPTURE)).assertFalse();
      expect(stages.includes(WorkflowStage.STACK)).assertFalse();
    });

    it('任务页在分屏和手机宽度使用单列', 0, () => {
      expect(TaskSessionPresentationService.resolveLayout(1024).compact).assertFalse();
      expect(TaskSessionPresentationService.resolveLayout(1024).sidebarWidth).assertEqual(320);
      expect(TaskSessionPresentationService.resolveLayout(600).compact).assertTrue();
      expect(TaskSessionPresentationService.resolveLayout(599).compact).assertTrue();
      expect(TaskSessionPresentationService.resolveLayout(360).mainWidth > 0).assertTrue();
    });
  });
}

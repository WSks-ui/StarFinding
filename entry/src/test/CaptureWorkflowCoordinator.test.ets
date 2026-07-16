import { describe, expect, it } from '@ohos/hypium';
import {
  CaptureMode,
  CapturePlan,
  CaptureTask,
  ConnectionState,
  EquatorialCoordinate,
  EquatorialFrame,
  ImageFormat,
  MountState,
  MountTargetCoordinate,
  ObserverState,
  PlateSolveResult,
  TaskStatus,
  TrackingMode
} from '../main/ets/models/DomainModels';
import {
  GatewaySubtaskKind,
  SessionStatus,
  WorkflowCheckpoint,
  WorkflowStage,
  WorkflowStepState
} from '../main/ets/models/TaskSessionModels';
import {
  CaptureWorkflowCancelledError,
  CaptureWorkflowCoordinator,
  CaptureWorkflowProgress,
  CaptureWorkflowReconciliation
} from '../main/ets/services/CaptureWorkflowCoordinator';
import { OnStepLX200Client } from '../main/ets/services/OnStepLX200Client';
import {
  GatewayFile,
  GatewayTask,
  PlateSolveOptions,
  RaspberryPiClient,
  StackOptions,
  TimelapseOptions
} from '../main/ets/services/RaspberryPiClient';

const TEST_TARGET: EquatorialCoordinate = {
  raHours: 10.0,
  decDegrees: 20.0,
  frame: EquatorialFrame.ICRS_J2000
};

function createPlan(mode: CaptureMode, enablePlateSolve: boolean = false): CapturePlan {
  return {
    id: `workflow-test-${mode}`,
    mode: mode,
    targetId: 'test-target',
    targetName: '测试目标',
    exposureSeconds: 1,
    frameCount: 2,
    intervalSeconds: 0,
    iso: 800,
    aperture: 4.0,
    imageFormat: ImageFormat.RAW_JPEG,
    outputFps: 25,
    enablePlateSolve: enablePlateSolve,
    enableDriftCorrection: enablePlateSolve,
    enableLocalStack: mode === CaptureMode.SMART_LONG_EXPOSURE,
    enableCloudEnhancement: false,
    recommendationReason: '协调器单元测试',
    warnings: []
  };
}

function createGatewayFile(taskId: string, id: string, kind: string, name: string,
  mimeType: string): GatewayFile {
  return {
    id: id,
    taskId: taskId,
    name: name,
    mimeType: mimeType,
    sizeBytes: 1024,
    kind: kind,
    downloadUrl: `http://127.0.0.1/files/${id}`,
    createdAtMs: 1
  };
}

function createGatewayTask(id: string, type: string, status: TaskStatus,
  files: GatewayFile[] = []): GatewayTask {
  return {
    id: id,
    type: type,
    status: status,
    progressPercent: status === TaskStatus.SUCCEEDED ? 100 : 0,
    message: status === TaskStatus.SUCCEEDED ? '完成' : '等待',
    errorMessage: '',
    files: files,
    capturedFrames: 1,
    createdAtMs: 1,
    updatedAtMs: 1
  };
}

class WorkflowFakeGateway extends RaspberryPiClient {
  coordinator?: CaptureWorkflowCoordinator;
  cancelDuringCaptureCreate: boolean = false;
  cancelDuringStackCreate: boolean = false;
  cancelDuringTimelapseCreate: boolean = false;
  emitStackProduct: boolean = true;
  emitTimelapseProduct: boolean = true;
  cancelledTaskIds: string[] = [];
  idempotencyKeys: string[] = [];
  getTaskCalls: number = 0;
  forcedTaskStatus: TaskStatus | undefined = undefined;
  private captureSequence: number = 0;

  getCaptureSequence(): number {
    return this.captureSequence;
  }

  async createCaptureTask(plan: CapturePlan, idempotencyKey?: string): Promise<CaptureTask> {
    this.captureSequence++;
    if (idempotencyKey !== undefined) this.idempotencyKeys.push(idempotencyKey);
    const id: string = `capture-${this.captureSequence}`;
    if (this.cancelDuringCaptureCreate && this.coordinator !== undefined) {
      await this.coordinator.cancel();
    }
    return {
      id: id,
      plan: plan,
      status: TaskStatus.PENDING,
      progressPercent: 0,
      completedFrames: 0,
      currentStage: '等待',
      errorMessage: '',
      products: [],
      createdAtMs: 1,
      updatedAtMs: 1
    };
  }

  async getTask(taskId: string): Promise<GatewayTask> {
    this.getTaskCalls++;
    if (this.forcedTaskStatus !== undefined) {
      return createGatewayTask(taskId, 'capture', this.forcedTaskStatus);
    }
    if (taskId.startsWith('stack-')) {
      const files: GatewayFile[] = this.emitStackProduct ?
        [createGatewayFile(taskId, 'stack-file', 'stack', 'stack.jpg', 'image/jpeg')] : [];
      return createGatewayTask(taskId, 'stack', TaskStatus.SUCCEEDED, files);
    }
    if (taskId.startsWith('timelapse-')) {
      const files: GatewayFile[] = this.emitTimelapseProduct ?
        [createGatewayFile(taskId, 'video-file', 'timelapse', 'timelapse.mp4', 'video/mp4')] : [];
      return createGatewayTask(taskId, 'timelapse', TaskStatus.SUCCEEDED, files);
    }
    if (taskId.startsWith('plate-')) {
      return createGatewayTask(taskId, 'plate_solve', TaskStatus.SUCCEEDED);
    }
    return createGatewayTask(taskId, 'capture', TaskStatus.SUCCEEDED);
  }

  async cancelTask(taskId: string): Promise<GatewayTask> {
    this.cancelledTaskIds.push(taskId);
    return createGatewayTask(taskId, 'test', TaskStatus.CANCELLED);
  }

  async listFiles(taskId: string, _limit: number = 100): Promise<GatewayFile[]> {
    return [createGatewayFile(taskId, `${taskId}-jpeg`, 'jpeg', `${taskId}.jpg`, 'image/jpeg')];
  }

  async createPlateSolveTask(_fileId: string, _options?: PlateSolveOptions,
    _idempotencyKey?: string): Promise<GatewayTask> {
    return createGatewayTask(`plate-${this.captureSequence}`, 'plate_solve', TaskStatus.PENDING);
  }

  async getPlateSolveResult(taskId: string): Promise<PlateSolveResult> {
    return {
      taskId: taskId,
      status: TaskStatus.SUCCEEDED,
      solved: true,
      frame: EquatorialFrame.ICRS_J2000,
      centerRaHours: 9.99,
      centerDecDegrees: 20.0,
      fieldWidthDegrees: 60,
      fieldHeightDegrees: 40,
      rotationDegrees: 0,
      residualArcSeconds: 2,
      errorMessage: ''
    };
  }

  async createStackTask(_fileIds: string[], _options?: StackOptions,
    _idempotencyKey?: string): Promise<GatewayTask> {
    if (this.cancelDuringStackCreate && this.coordinator !== undefined) {
      await this.coordinator.cancel();
    }
    return createGatewayTask('stack-1', 'stack', TaskStatus.PENDING);
  }

  async createTimelapseTask(_fileIds: string[], _options?: TimelapseOptions,
    _idempotencyKey?: string): Promise<GatewayTask> {
    if (this.cancelDuringTimelapseCreate && this.coordinator !== undefined) {
      await this.coordinator.cancel();
    }
    return createGatewayTask('timelapse-1', 'timelapse', TaskStatus.PENDING);
  }
}

class WorkflowFakeMount extends OnStepLX200Client {
  coordinator?: CaptureWorkflowCoordinator;
  cancelOnRefresh: boolean = false;
  cancelDuringGoto: boolean = false;
  gotoCalls: number = 0;
  abortCalls: number = 0;

  async refreshState(): Promise<MountState> {
    if (this.cancelOnRefresh && this.coordinator !== undefined) {
      this.cancelOnRefresh = false;
      await this.coordinator.cancel();
    }
    return {
      connection: ConnectionState.CONNECTED,
      host: '127.0.0.1',
      port: 9999,
      rightAscensionHours: 10.0,
      declinationDegrees: 20.0,
      trackingMode: TrackingMode.SIDEREAL,
      slewing: false,
      homed: true,
      parked: false,
      lastError: '',
      updatedAtMs: 1
    };
  }

  getSyncedObserver(): ObserverState | undefined {
    return {
      latitudeDegrees: 34.75,
      longitudeDegrees: 113.62,
      elevationMeters: 100.0,
      timestampMs: Date.now()
    };
  }

  async setObserver(_observer: ObserverState, _utcFromLocalOffsetHours: number): Promise<void> {
  }

  async gotoRaDec(_coordinate: MountTargetCoordinate): Promise<void> {
    this.gotoCalls++;
    if (this.cancelDuringGoto && this.coordinator !== undefined) {
      this.cancelDuringGoto = false;
      await this.coordinator.cancel();
    }
  }

  async abort(): Promise<void> {
    this.abortCalls++;
  }
}

async function runAndCaptureError(coordinator: CaptureWorkflowCoordinator, plan: CapturePlan,
  maxProgress: number[]): Promise<Object | undefined> {
  try {
    await coordinator.run(plan, TEST_TARGET, (progress: CaptureWorkflowProgress) => {
      maxProgress[0] = Math.max(maxProgress[0], progress.progressPercent);
    });
    return undefined;
  } catch (error) {
    return error;
  }
}

export default function captureWorkflowCoordinatorTest(): void {
  describe('拍摄闭环安全状态', () => {
    it('软取消允许当前曝光完成且不会提交后续帧', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      gateway.coordinator = coordinator;
      gateway.cancelDuringCaptureCreate = true;
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.TIMELAPSE), progress);

      expect(error instanceof CaptureWorkflowCancelledError).assertTrue();
      expect(gateway.cancelledTaskIds.includes('capture-1')).assertFalse();
      expect(gateway.getCaptureSequence()).assertEqual(1);
      expect(gateway.idempotencyKeys.length).assertEqual(1);
      expect(gateway.idempotencyKeys[0]).assertEqual('workflow-test-timelapse-frame-1');
      expect(progress[0] > 0).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });

    it('网关 POST 前后按顺序保存幂等键和子任务 ID', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      const checkpoints: WorkflowCheckpoint[] = [];

      await coordinator.run(createPlan(CaptureMode.TIMELAPSE), TEST_TARGET,
        (_progress: CaptureWorkflowProgress): void => {},
        async (checkpoint: WorkflowCheckpoint): Promise<void> => {
          checkpoints.push(checkpoint);
        });

      let requestCheckpoint: WorkflowCheckpoint | undefined = undefined;
      let responseCheckpoint: WorkflowCheckpoint | undefined = undefined;
      for (let index: number = 0; index < checkpoints.length; index++) {
        const item: WorkflowCheckpoint = checkpoints[index];
        if (item.operationKey === 'workflow-test-timelapse-frame-1') {
          if (item.childTaskId.length === 0 && requestCheckpoint === undefined) requestCheckpoint = item;
          if (item.childTaskId === 'capture-1' && responseCheckpoint === undefined) responseCheckpoint = item;
        }
      }
      expect(requestCheckpoint !== undefined).assertTrue();
      expect(responseCheckpoint !== undefined).assertTrue();
      if (requestCheckpoint !== undefined && responseCheckpoint !== undefined) {
        expect(requestCheckpoint.requiresManualContinue).assertTrue();
        expect(responseCheckpoint.requiresManualContinue).assertFalse();
        expect(responseCheckpoint.responseReceivedAtMs >= requestCheckpoint.requestStartedAtMs).assertTrue();
      }
    });

    it('请求结果未知时恢复不会访问网关或移动赤道仪', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      const checkpoint: WorkflowCheckpoint = {
        stage: WorkflowStage.CAPTURE,
        stepState: WorkflowStepState.ACTIVE,
        childKind: GatewaySubtaskKind.CAPTURE,
        operationKey: 'capture-unknown',
        childTaskId: '',
        requestStartedAtMs: 1,
        responseReceivedAtMs: 0,
        requiresManualContinue: true,
        detail: '等待响应'
      };

      const result: CaptureWorkflowReconciliation = await coordinator.reconcile(checkpoint);

      expect(result.sessionStatus).assertEqual(SessionStatus.INTERRUPTED);
      expect(result.unknownOutcome).assertTrue();
      expect(gateway.getTaskCalls).assertEqual(0);
      expect(mount.gotoCalls).assertEqual(0);
      expect(mount.abortCalls).assertEqual(0);
    });

    it('已知运行中子任务只读对账且不发送设备命令', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      gateway.forcedTaskStatus = TaskStatus.RUNNING;
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      const checkpoint: WorkflowCheckpoint = {
        stage: WorkflowStage.CAPTURE,
        stepState: WorkflowStepState.ACTIVE,
        childKind: GatewaySubtaskKind.CAPTURE,
        operationKey: 'capture-known',
        childTaskId: 'capture-existing',
        requestStartedAtMs: 1,
        responseReceivedAtMs: 2,
        requiresManualContinue: false,
        detail: '运行中'
      };

      const result: CaptureWorkflowReconciliation = await coordinator.reconcile(checkpoint);

      expect(result.monitoring).assertTrue();
      expect(result.sessionStatus).assertEqual(SessionStatus.INTERRUPTED);
      expect(gateway.getTaskCalls).assertEqual(1);
      expect(mount.gotoCalls).assertEqual(0);
      expect(mount.abortCalls).assertEqual(0);
    });

    it('堆栈阶段取消不会被降级成成功', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      gateway.coordinator = coordinator;
      gateway.cancelDuringStackCreate = true;
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.SMART_LONG_EXPOSURE), progress);

      expect(error instanceof CaptureWorkflowCancelledError).assertTrue();
      expect(gateway.cancelledTaskIds.includes('stack-1')).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });

    it('延时制片阶段取消不会被降级成成功', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      gateway.coordinator = coordinator;
      gateway.cancelDuringTimelapseCreate = true;
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.TIMELAPSE), progress);

      expect(error instanceof CaptureWorkflowCancelledError).assertTrue();
      expect(gateway.cancelledTaskIds.includes('timelapse-1')).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });

    it('智能长曝光缺少堆栈图时明确失败', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      gateway.emitStackProduct = false;
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.SMART_LONG_EXPOSURE), progress);

      expect(error instanceof Error && error.message.includes('未生成有效堆栈图')).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });

    it('延时摄影缺少 MP4 时明确失败', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      gateway.emitTimelapseProduct = false;
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.TIMELAPSE), progress);

      expect(error instanceof Error && error.message.includes('未生成有效 MP4')).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });

    it('漂移修正读取状态期间取消不会发出 GOTO', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      mount.coordinator = coordinator;
      mount.cancelOnRefresh = true;
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.SMART_LONG_EXPOSURE, true), progress);

      expect(error instanceof CaptureWorkflowCancelledError).assertTrue();
      expect(mount.gotoCalls).assertEqual(0);
      expect(progress[0] < 100).assertTrue();
    });

    it('漂移 GOTO 内部取消会在退出前再次中止运动', 0, async () => {
      const mount = new WorkflowFakeMount();
      const gateway = new WorkflowFakeGateway();
      const coordinator = new CaptureWorkflowCoordinator(mount, gateway);
      mount.coordinator = coordinator;
      mount.cancelDuringGoto = true;
      const progress: number[] = [0];

      const error: Object | undefined = await runAndCaptureError(
        coordinator, createPlan(CaptureMode.SMART_LONG_EXPOSURE, true), progress);

      expect(error instanceof CaptureWorkflowCancelledError).assertTrue();
      expect(mount.gotoCalls).assertEqual(1);
      expect(mount.abortCalls >= 2).assertTrue();
      expect(progress[0] < 100).assertTrue();
    });
  });
}

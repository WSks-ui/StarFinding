import {
  CaptureMode,
  CapturePlan,
  CaptureTask,
  EquatorialCoordinate,
  EquatorialFrame,
  ImageFormat,
  MountState,
  MountTargetCoordinate,
  ObserverState,
  PlateSolveResult,
  TaskStatus
} from '../models/DomainModels';
import {
  GatewaySubtaskKind,
  SessionStatus,
  WorkflowCheckpoint,
  WorkflowStage,
  WorkflowStepState
} from '../models/TaskSessionModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';
import { OnStepLX200Client } from './OnStepLX200Client';
import { GatewayFile, GatewayTask, RaspberryPiClient } from './RaspberryPiClient';

export interface WorkflowChildTaskReference {
  taskId: string;
  kind: GatewaySubtaskKind;
  status: TaskStatus;
  progressPercent: number;
  message: string;
}

export interface CaptureWorkflowProgress {
  progressPercent: number;
  completedFrames: number;
  stage: WorkflowStage;
  stageText: string;
  activeTaskId: string;
  childTask?: WorkflowChildTaskReference;
  checkpoint: WorkflowCheckpoint;
  jpegFileIds: string[];
  rawFileIds: string[];
  plateSolveCount: number;
  correctionCount: number;
}

export type CaptureWorkflowProgressListener = (progress: CaptureWorkflowProgress) => void;
export type CaptureWorkflowCheckpointListener = (checkpoint: WorkflowCheckpoint) => Promise<void>;

export interface CaptureWorkflowResumeState {
  completedFrames: number;
  captureFiles: GatewayFile[];
  jpegFileIds: string[];
  rawFileIds: string[];
  plateSolveCount: number;
  correctionCount: number;
  warnings: string[];
}

export interface CaptureWorkflowResult {
  captureFiles: GatewayFile[];
  stackFile?: GatewayFile;
  timelapseFile?: GatewayFile;
  plateSolveCount: number;
  correctionCount: number;
  warnings: string[];
}

export interface CaptureWorkflowReconciliation {
  sessionStatus: SessionStatus;
  checkpoint: WorkflowCheckpoint;
  childTask?: WorkflowChildTaskReference;
  files: GatewayFile[];
  completedFrames: number;
  monitoring: boolean;
  unknownOutcome: boolean;
  detail: string;
}

/** 主动取消与普通失败分离，后处理降级逻辑不得把取消改写成成功。 */
export class CaptureWorkflowCancelledError extends Error {
  constructor(message: string = '拍摄工作流已由用户取消') {
    super(message);
    this.name = 'CaptureWorkflowCancelledError';
  }
}

/**
 * Pad 端只在子曝光之间编排任务。每个副作用 POST 都先持久化幂等键，再提交网关；
 * 恢复入口只读查询已知子任务，不包含 GOTO、同步、跟踪或快门操作。
 */
export class CaptureWorkflowCoordinator {
  private readonly mount: OnStepLX200Client;
  private readonly gateway: RaspberryPiClient;
  private cancelled: boolean = false;
  private activeTaskId: string = '';
  private activeTaskKind: GatewaySubtaskKind = GatewaySubtaskKind.NONE;
  private driftCorrectionActive: boolean = false;
  private currentCheckpoint: WorkflowCheckpoint = CaptureWorkflowCoordinator.emptyCheckpoint();

  constructor(mount: OnStepLX200Client, gateway: RaspberryPiClient) {
    this.mount = mount;
    this.gateway = gateway;
  }

  getActiveTaskId(): string {
    return this.activeTaskId;
  }

  getCheckpoint(): WorkflowCheckpoint {
    return CaptureWorkflowCoordinator.copyCheckpoint(this.currentCheckpoint);
  }

  async cancel(): Promise<void> {
    this.cancelled = true;
    const failures: string[] = [];
    if (this.driftCorrectionActive) {
      try {
        await this.mount.abort();
      } catch (error) {
        failures.push(`赤道仪漂移修正停止失败：${error}`);
      }
    }

    // 相机任务以单帧提交。运行中的 gphoto2 不可安全强杀，因此让本帧完成并由循环边界停止后续帧。
    if (this.activeTaskId.length > 0 && this.activeTaskKind !== GatewaySubtaskKind.CAPTURE) {
      try {
        await this.gateway.cancelTask(this.activeTaskId);
      } catch (error) {
        failures.push(`网关任务 ${this.activeTaskId} 取消未确认：${error}`);
      }
    }
    if (failures.length > 0) {
      throw new Error(failures.join('；'));
    }
  }

  async run(plan: CapturePlan, target: EquatorialCoordinate, listener: CaptureWorkflowProgressListener,
    checkpointListener?: CaptureWorkflowCheckpointListener,
    resumeState?: CaptureWorkflowResumeState): Promise<CaptureWorkflowResult> {
    this.validatePlan(plan);
    this.cancelled = false;
    this.activeTaskId = '';
    this.activeTaskKind = GatewaySubtaskKind.NONE;
    this.driftCorrectionActive = false;
    this.currentCheckpoint = CaptureWorkflowCoordinator.emptyCheckpoint();

    const captureFiles: GatewayFile[] = resumeState === undefined ? [] : resumeState.captureFiles.slice();
    const jpegFileIds: string[] = resumeState === undefined ? [] : resumeState.jpegFileIds.slice();
    const rawFileIds: string[] = resumeState === undefined ? [] : resumeState.rawFileIds.slice();
    const warnings: string[] = resumeState === undefined ? [] : resumeState.warnings.slice();
    let plateSolveCount: number = resumeState === undefined ? 0 : resumeState.plateSolveCount;
    let correctionCount: number = resumeState === undefined ? 0 : resumeState.correctionCount;
    const startFrame: number = resumeState === undefined ? 0 :
      Math.max(0, Math.min(plan.frameCount, Math.trunc(resumeState.completedFrames)));

    for (let frameIndex: number = startFrame; frameIndex < plan.frameCount; frameIndex++) {
      this.throwIfCancelled();
      const captureKey: string = `${plan.id}-frame-${frameIndex + 1}`;
      await this.beginOperation(WorkflowStage.CAPTURE, GatewaySubtaskKind.CAPTURE, captureKey,
        `准备拍摄第 ${frameIndex + 1}/${plan.frameCount} 帧`, checkpointListener);
      this.emitProgress(listener, Math.max(1, Math.floor(frameIndex / plan.frameCount * 72)), frameIndex,
        WorkflowStage.CAPTURE, `正在拍摄第 ${frameIndex + 1}/${plan.frameCount} 帧`, jpegFileIds, rawFileIds,
        plateSolveCount, correctionCount);

      const framePlan: CapturePlan = this.singleFramePlan(plan, frameIndex);
      const capture: CaptureTask = await this.gateway.createCaptureTask(framePlan, captureKey);
      await this.bindChildTask(capture.id, checkpointListener);
      // 即使用户在 POST 等待期间点击停止，也必须只读等待当前曝光结束，不能强杀 gphoto2。
      await this.waitForTask(capture.id, Math.max(120000, plan.exposureSeconds * 1000 + 90000), true);
      const frameFiles: GatewayFile[] = await this.gateway.listFiles(capture.id, 10);
      let plateFile: GatewayFile | undefined = undefined;
      for (let fileIndex: number = 0; fileIndex < frameFiles.length; fileIndex++) {
        const file: GatewayFile = frameFiles[fileIndex];
        captureFiles.push(file);
        if (this.isJpeg(file)) {
          jpegFileIds.push(file.id);
          plateFile = file;
        } else if (this.isRaw(file)) {
          rawFileIds.push(file.id);
        }
      }

      const completed: number = frameIndex + 1;
      await this.completeOperation(WorkflowStage.CAPTURE,
        `已完成第 ${completed}/${plan.frameCount} 帧`, checkpointListener);
      this.emitProgress(listener, Math.max(1, Math.floor(completed / plan.frameCount * 72)), completed,
        WorkflowStage.CAPTURE, this.cancelled ? '当前曝光已完成，后续帧已停止' :
          `已完成第 ${completed}/${plan.frameCount} 帧`, jpegFileIds, rawFileIds,
        plateSolveCount, correctionCount);
      this.throwIfCancelled('当前曝光已完成，后续帧已停止');

      if (plan.enablePlateSolve && plateFile !== undefined) {
        try {
          const plateKey: string = `${plan.id}-plate-${completed}`;
          await this.beginOperation(WorkflowStage.PLATE_SOLVE, GatewaySubtaskKind.PLATE_SOLVE, plateKey,
            `准备板解析第 ${completed} 帧`, checkpointListener);
          const plateTask: GatewayTask = await this.gateway.createPlateSolveTask(plateFile.id, {
            hintRaHours: target.raHours,
            hintDecDegrees: target.decDegrees,
            searchRadiusDegrees: 12
          }, plateKey);
          await this.bindChildTask(plateTask.id, checkpointListener);
          this.emitProgress(listener, Math.max(1, Math.floor(completed / plan.frameCount * 72)), completed,
            WorkflowStage.PLATE_SOLVE, `正在板解析第 ${completed} 帧`, jpegFileIds, rawFileIds,
            plateSolveCount, correctionCount);
          await this.waitForTask(plateTask.id, 240000, false);
          this.throwIfCancelled();
          const result: PlateSolveResult = await this.gateway.getPlateSolveResult(plateTask.id);
          if (result.solved) {
            plateSolveCount++;
            if (plan.enableDriftCorrection && completed < plan.frameCount) {
              await this.markLocalStage(WorkflowStage.DRIFT_CORRECTION, WorkflowStepState.ACTIVE,
                '正在计算帧间漂移修正', checkpointListener);
              if (await this.correctDrift(target, result, plan.targetId)) {
                correctionCount++;
              }
              await this.markLocalStage(WorkflowStage.DRIFT_CORRECTION, WorkflowStepState.SUCCEEDED,
                '帧间漂移检查完成', checkpointListener);
            }
          }
          await this.completeOperation(WorkflowStage.PLATE_SOLVE, `第 ${completed} 帧板解析完成`,
            checkpointListener);
        } catch (error) {
          this.rethrowCancellation(error);
          warnings.push(`第 ${completed} 帧板解析/漂移修正跳过：${error}`);
        }
      }

      if (completed < plan.frameCount && plan.intervalSeconds > 0) {
        await this.delay(plan.intervalSeconds * 1000, true);
      }
    }

    this.throwIfCancelled();
    if (jpegFileIds.length < 2) {
      throw new Error(`仅取得 ${jpegFileIds.length} 个 JPEG，无法生成${
        plan.mode === CaptureMode.SMART_LONG_EXPOSURE ? '本地堆栈' : '延时视频'}；已保留现有原片`);
    }

    let stackFile: GatewayFile | undefined = undefined;
    let timelapseFile: GatewayFile | undefined = undefined;
    if (plan.mode === CaptureMode.SMART_LONG_EXPOSURE) {
      const stackKey: string = `${plan.id}-stack`;
      try {
        await this.beginOperation(WorkflowStage.STACK, GatewaySubtaskKind.STACK, stackKey,
          '准备本地堆栈', checkpointListener);
        const stackTask: GatewayTask = await this.gateway.createStackTask(jpegFileIds, {
          rejectBadFrames: true,
          correctLightPollution: true
        }, stackKey);
        await this.bindChildTask(stackTask.id, checkpointListener);
        this.emitProgress(listener, 78, plan.frameCount, WorkflowStage.STACK,
          '正在进行星点配准、坏帧剔除和本地堆栈', jpegFileIds, rawFileIds,
          plateSolveCount, correctionCount);
        const completedStack: GatewayTask = await this.waitForTask(stackTask.id, 900000, false);
        stackFile = this.findStackProduct(completedStack.files);
        await this.completeOperation(WorkflowStage.STACK, '本地堆栈完成', checkpointListener);
      } catch (error) {
        this.rethrowCancellation(error);
        warnings.push(`本地堆栈失败，已保留全部原始帧：${error}`);
      }
      if (stackFile === undefined) {
        throw new Error(`智能长曝光未生成有效堆栈图；已保留全部原始帧${
          warnings.length > 0 ? `；${warnings[warnings.length - 1]}` : ''}`);
      }
    }

    if (plan.mode === CaptureMode.TIMELAPSE) {
      const timelapseKey: string = `${plan.id}-timelapse`;
      try {
        await this.beginOperation(WorkflowStage.TIMELAPSE, GatewaySubtaskKind.TIMELAPSE, timelapseKey,
          '准备生成延时视频', checkpointListener);
        const timelapseTask: GatewayTask = await this.gateway.createTimelapseTask(jpegFileIds, {
          fps: plan.outputFps,
          width: 1920,
          height: 1080
        }, timelapseKey);
        await this.bindChildTask(timelapseTask.id, checkpointListener);
        this.emitProgress(listener, 82, plan.frameCount, WorkflowStage.TIMELAPSE,
          '正在生成 1080p H.264 延时视频', jpegFileIds, rawFileIds,
          plateSolveCount, correctionCount);
        const completedVideo: GatewayTask = await this.waitForTask(timelapseTask.id, 900000, false);
        timelapseFile = this.findTimelapseProduct(completedVideo.files);
        await this.completeOperation(WorkflowStage.TIMELAPSE, '延时视频生成完成', checkpointListener);
      } catch (error) {
        this.rethrowCancellation(error);
        warnings.push(`延时视频生成失败，已保留全部 JPEG：${error}`);
      }
      if (timelapseFile === undefined) {
        throw new Error(`延时摄影未生成有效 MP4 视频；已保留全部 JPEG${
          warnings.length > 0 ? `；${warnings[warnings.length - 1]}` : ''}`);
      }
    }

    this.throwIfCancelled();
    this.activeTaskId = '';
    this.activeTaskKind = GatewaySubtaskKind.NONE;
    await this.markLocalStage(WorkflowStage.COMPLETE, WorkflowStepState.SUCCEEDED,
      warnings.length === 0 ? '本地拍摄与处理工作流完成' : '拍摄完成，部分后处理已降级',
      checkpointListener);
    this.emitProgress(listener, 100, plan.frameCount, WorkflowStage.COMPLETE,
      warnings.length === 0 ? '本地拍摄与处理工作流完成' : '拍摄完成，部分后处理已降级',
      jpegFileIds, rawFileIds, plateSolveCount, correctionCount);
    return {
      captureFiles: captureFiles,
      stackFile: stackFile,
      timelapseFile: timelapseFile,
      plateSolveCount: plateSolveCount,
      correctionCount: correctionCount,
      warnings: warnings
    };
  }

  /** 恢复只查询一个已知子任务；调用方可按需再次查询，不启动任何设备动作。 */
  async reconcile(checkpoint: WorkflowCheckpoint): Promise<CaptureWorkflowReconciliation> {
    const copy: WorkflowCheckpoint = CaptureWorkflowCoordinator.copyCheckpoint(checkpoint);
    copy.requiresManualContinue = true;
    if (copy.operationKey.length > 0 && copy.childTaskId.length === 0) {
      copy.stepState = WorkflowStepState.FAILED;
      copy.detail = '请求结果无法确认；需要人工继续并以同一幂等键重试';
      return this.reconciliation(SessionStatus.INTERRUPTED, copy, undefined, [], 0,
        false, true, copy.detail);
    }
    if (copy.childTaskId.length === 0) {
      copy.detail = '没有可对账的网关子任务';
      return this.reconciliation(SessionStatus.INTERRUPTED, copy, undefined, [], 0,
        false, false, copy.detail);
    }

    const task: GatewayTask = await this.gateway.getTask(copy.childTaskId);
    const reference: WorkflowChildTaskReference = this.childReference(task, copy.childKind);
    if (task.status === TaskStatus.PENDING || task.status === TaskStatus.RUNNING) {
      copy.stepState = WorkflowStepState.ACTIVE;
      copy.detail = '网关子任务仍在运行，仅进行只读监控';
      return this.reconciliation(SessionStatus.INTERRUPTED, copy, reference, task.files,
        task.capturedFrames, true, false, copy.detail);
    }
    if (task.status === TaskStatus.SUCCEEDED) {
      copy.stepState = WorkflowStepState.SUCCEEDED;
      copy.detail = '网关子任务已完成，等待人工继续会话';
      return this.reconciliation(SessionStatus.WAITING_FOR_USER, copy, reference, task.files,
        task.capturedFrames, false, false, copy.detail);
    }
    copy.stepState = task.status === TaskStatus.CANCELLED ? WorkflowStepState.CANCELLED :
      WorkflowStepState.FAILED;
    copy.detail = task.errorMessage.length > 0 ? task.errorMessage : task.message;
    return this.reconciliation(task.status === TaskStatus.CANCELLED ? SessionStatus.CANCELLED :
      SessionStatus.FAILED, copy, reference, task.files, task.capturedFrames,
      false, false, copy.detail);
  }

  private validatePlan(plan: CapturePlan): void {
    if (plan.mode === CaptureMode.OBSERVE_ONLY) {
      throw new Error('仅观测计划不应提交相机工作流');
    }
    if (plan.mode === CaptureMode.SMART_LONG_EXPOSURE && !plan.enableLocalStack) {
      throw new Error('智能长曝光计划必须启用本地堆栈，不能只拍摄而不生成对应成品');
    }
  }

  private async beginOperation(stage: WorkflowStage, kind: GatewaySubtaskKind, operationKey: string,
    detail: string, listener?: CaptureWorkflowCheckpointListener): Promise<void> {
    this.throwIfCancelled();
    this.activeTaskId = '';
    this.activeTaskKind = kind;
    this.currentCheckpoint = {
      stage: stage,
      stepState: WorkflowStepState.ACTIVE,
      childKind: kind,
      operationKey: operationKey,
      childTaskId: '',
      requestStartedAtMs: Date.now(),
      responseReceivedAtMs: 0,
      requiresManualContinue: true,
      detail: detail
    };
    await this.persistCheckpoint(listener);
  }

  private async bindChildTask(taskId: string, listener?: CaptureWorkflowCheckpointListener): Promise<void> {
    this.activeTaskId = taskId;
    this.currentCheckpoint.childTaskId = taskId;
    this.currentCheckpoint.responseReceivedAtMs = Date.now();
    this.currentCheckpoint.requiresManualContinue = false;
    await this.persistCheckpoint(listener);
    if (this.cancelled && this.activeTaskKind !== GatewaySubtaskKind.CAPTURE) {
      try {
        await this.gateway.cancelTask(taskId);
      } catch (error) {
      }
      throw new CaptureWorkflowCancelledError();
    }
  }

  private async completeOperation(stage: WorkflowStage, detail: string,
    listener?: CaptureWorkflowCheckpointListener): Promise<void> {
    this.currentCheckpoint.stage = stage;
    this.currentCheckpoint.stepState = WorkflowStepState.SUCCEEDED;
    this.currentCheckpoint.requiresManualContinue = false;
    this.currentCheckpoint.detail = detail;
    await this.persistCheckpoint(listener);
  }

  private async markLocalStage(stage: WorkflowStage, state: WorkflowStepState, detail: string,
    listener?: CaptureWorkflowCheckpointListener): Promise<void> {
    this.currentCheckpoint = {
      stage: stage,
      stepState: state,
      childKind: GatewaySubtaskKind.NONE,
      operationKey: '',
      childTaskId: '',
      requestStartedAtMs: Date.now(),
      responseReceivedAtMs: Date.now(),
      requiresManualContinue: false,
      detail: detail
    };
    await this.persistCheckpoint(listener);
  }

  private async persistCheckpoint(listener?: CaptureWorkflowCheckpointListener): Promise<void> {
    if (listener !== undefined) {
      await listener(CaptureWorkflowCoordinator.copyCheckpoint(this.currentCheckpoint));
    }
  }

  private emitProgress(listener: CaptureWorkflowProgressListener, progressPercent: number,
    completedFrames: number, stage: WorkflowStage, stageText: string, jpegFileIds: string[], rawFileIds: string[],
    plateSolveCount: number, correctionCount: number): void {
    const child: WorkflowChildTaskReference | undefined = this.activeTaskId.length === 0 ? undefined : {
      taskId: this.activeTaskId,
      kind: this.activeTaskKind,
      status: TaskStatus.RUNNING,
      progressPercent: progressPercent,
      message: stageText
    };
    listener({
      progressPercent: progressPercent,
      completedFrames: completedFrames,
      stage: stage,
      stageText: stageText,
      activeTaskId: this.activeTaskId,
      childTask: child,
      checkpoint: CaptureWorkflowCoordinator.copyCheckpoint(this.currentCheckpoint),
      jpegFileIds: jpegFileIds.slice(),
      rawFileIds: rawFileIds.slice(),
      plateSolveCount: plateSolveCount,
      correctionCount: correctionCount
    });
  }

  private async waitForTask(taskId: string, timeoutMs: number,
    allowCaptureToFinishAfterCancel: boolean): Promise<GatewayTask> {
    const startedAt: number = Date.now();
    while (Date.now() - startedAt <= timeoutMs) {
      if (!allowCaptureToFinishAfterCancel) {
        this.throwIfCancelled();
      }
      const task: GatewayTask = await this.gateway.getTask(taskId);
      if (task.status === TaskStatus.SUCCEEDED) return task;
      if (task.status === TaskStatus.FAILED) {
        throw new Error(task.errorMessage.length > 0 ? task.errorMessage : task.message);
      }
      if (task.status === TaskStatus.CANCELLED) {
        throw new CaptureWorkflowCancelledError('网关任务已取消');
      }
      await this.delay(650, !allowCaptureToFinishAfterCancel);
    }
    if (!allowCaptureToFinishAfterCancel) {
      try {
        await this.gateway.cancelTask(taskId);
      } catch (error) {
      }
    }
    throw new Error(`网关任务 ${taskId} 超时`);
  }

  private async correctDrift(target: EquatorialCoordinate, result: PlateSolveResult,
    targetId: string): Promise<boolean> {
    this.throwIfCancelled();
    if (result.frame !== EquatorialFrame.ICRS_J2000 ||
      target.frame === EquatorialFrame.TOPOCENTRIC_OF_DATE) {
      throw new Error('板解析与目标坐标未统一到 J2000 轴系');
    }
    const solved: EquatorialCoordinate = {
      raHours: result.centerRaHours,
      decDegrees: result.centerDecDegrees,
      frame: result.frame
    };
    const errorDegrees: number = AstronomyService.angularSeparation(target, solved);
    if (errorDegrees < 0.04) return false;
    if (errorDegrees > 2.0) {
      throw new Error(`板解析偏差 ${errorDegrees.toFixed(2)}° 超过 2° 修正安全阈值`);
    }

    const syncedObserver: ObserverState | undefined = this.mount.getSyncedObserver();
    if (syncedObserver === undefined) throw new Error('漂移修正前缺少已同步观测地点');
    const correctionTimeMs: number = Date.now();
    const currentObserver: ObserverState = {
      latitudeDegrees: syncedObserver.latitudeDegrees,
      longitudeDegrees: syncedObserver.longitudeDegrees,
      elevationMeters: syncedObserver.elevationMeters,
      timestampMs: correctionTimeMs
    };
    await this.mount.setObserver(currentObserver, new Date().getTimezoneOffset() / 60.0);
    this.throwIfCancelled();
    const state: MountState = await this.mount.refreshState();
    this.throwIfCancelled();
    const currentMountCoordinate: MountTargetCoordinate = {
      targetId: targetId,
      raHours: state.rightAscensionHours,
      decDegrees: state.declinationDegrees,
      frame: EquatorialFrame.TOPOCENTRIC_OF_DATE,
      calculatedAtMs: correctionTimeMs,
      observerKey: EphemerisService.observerKey(currentObserver)
    };
    const currentEqj: EquatorialCoordinate = EphemerisService.topocentricOfDateToEqj(currentMountCoordinate);
    const correctedEqj: EquatorialCoordinate = AstronomyService.applyShortestSkyRotation(solved, target,
      currentEqj);
    const corrected: MountTargetCoordinate = EphemerisService.eqjToTopocentricOfDate(
      correctedEqj, currentObserver, correctionTimeMs, targetId);
    this.driftCorrectionActive = true;
    try {
      await this.mount.gotoRaDec(corrected);
      this.throwIfCancelled();
      await this.waitForMountStop(60000);
      this.throwIfCancelled();
      return true;
    } catch (error) {
      if (this.cancelled) {
        try {
          await this.mount.abort();
        } catch (abortError) {
        }
      }
      this.rethrowCancellation(error);
      if (error instanceof Error) throw error;
      throw new Error(`漂移修正失败：${error}`);
    } finally {
      this.driftCorrectionActive = false;
    }
  }

  private async waitForMountStop(timeoutMs: number): Promise<void> {
    const startedAt: number = Date.now();
    while (Date.now() - startedAt <= timeoutMs) {
      this.throwIfCancelled();
      const state: MountState = await this.mount.refreshState();
      if (!state.slewing) return;
      await this.delay(750, true);
    }
    throw new Error('漂移修正 GOTO 超时');
  }

  private singleFramePlan(plan: CapturePlan, frameIndex: number): CapturePlan {
    return {
      id: `${plan.id}-frame-${frameIndex + 1}`,
      mode: plan.mode,
      targetId: plan.targetId,
      targetName: plan.targetName,
      exposureSeconds: plan.exposureSeconds,
      frameCount: 1,
      intervalSeconds: 0,
      iso: plan.iso,
      aperture: plan.aperture,
      imageFormat: plan.imageFormat === ImageFormat.RAW_JPEG ? ImageFormat.RAW_JPEG : ImageFormat.JPEG,
      outputFps: plan.outputFps,
      enablePlateSolve: false,
      enableDriftCorrection: false,
      enableLocalStack: false,
      enableCloudEnhancement: false,
      recommendationReason: plan.recommendationReason,
      warnings: plan.warnings.slice()
    };
  }

  private throwIfCancelled(message: string = '拍摄工作流已由用户取消'): void {
    if (this.cancelled) throw new CaptureWorkflowCancelledError(message);
  }

  private rethrowCancellation(error: Object): void {
    if (error instanceof CaptureWorkflowCancelledError) throw error;
    this.throwIfCancelled();
  }

  private isJpeg(file: GatewayFile): boolean {
    const name: string = file.name.toLowerCase();
    return file.mimeType.toLowerCase() === 'image/jpeg' || name.endsWith('.jpg') || name.endsWith('.jpeg');
  }

  private isRaw(file: GatewayFile): boolean {
    const name: string = file.name.toLowerCase();
    return file.kind === 'raw' || file.mimeType.toLowerCase() === 'image/x-canon-cr3' || name.endsWith('.cr3');
  }

  private findStackProduct(files: GatewayFile[]): GatewayFile | undefined {
    for (let index: number = 0; index < files.length; index++) {
      const file: GatewayFile = files[index];
      const mimeType: string = file.mimeType.toLowerCase();
      const name: string = file.name.toLowerCase();
      if (file.kind === 'stack' && (mimeType === 'image/jpeg' || mimeType === 'image/png' ||
        name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'))) return file;
    }
    return undefined;
  }

  private findTimelapseProduct(files: GatewayFile[]): GatewayFile | undefined {
    for (let index: number = 0; index < files.length; index++) {
      const file: GatewayFile = files[index];
      if (file.kind === 'timelapse' &&
        (file.mimeType.toLowerCase() === 'video/mp4' || file.name.toLowerCase().endsWith('.mp4'))) return file;
    }
    return undefined;
  }

  private childReference(task: GatewayTask, kind: GatewaySubtaskKind): WorkflowChildTaskReference {
    return {
      taskId: task.id,
      kind: kind,
      status: task.status,
      progressPercent: task.progressPercent,
      message: task.errorMessage.length > 0 ? task.errorMessage : task.message
    };
  }

  private reconciliation(status: SessionStatus, checkpoint: WorkflowCheckpoint,
    childTask: WorkflowChildTaskReference | undefined, files: GatewayFile[], completedFrames: number,
    monitoring: boolean, unknownOutcome: boolean, detail: string): CaptureWorkflowReconciliation {
    return {
      sessionStatus: status,
      checkpoint: checkpoint,
      childTask: childTask,
      files: files.slice(),
      completedFrames: completedFrames,
      monitoring: monitoring,
      unknownOutcome: unknownOutcome,
      detail: detail
    };
  }

  private async delay(milliseconds: number, honorCancellation: boolean): Promise<void> {
    let remaining: number = Math.max(0, milliseconds);
    while (remaining > 0) {
      if (honorCancellation) this.throwIfCancelled();
      const slice: number = Math.min(remaining, 250);
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, slice); });
      remaining -= slice;
    }
  }

  private static emptyCheckpoint(): WorkflowCheckpoint {
    return {
      stage: WorkflowStage.SAFETY_CHECK,
      stepState: WorkflowStepState.WAITING,
      childKind: GatewaySubtaskKind.NONE,
      operationKey: '',
      childTaskId: '',
      requestStartedAtMs: 0,
      responseReceivedAtMs: 0,
      requiresManualContinue: false,
      detail: ''
    };
  }

  private static copyCheckpoint(checkpoint: WorkflowCheckpoint): WorkflowCheckpoint {
    return {
      stage: checkpoint.stage,
      stepState: checkpoint.stepState,
      childKind: checkpoint.childKind,
      operationKey: checkpoint.operationKey,
      childTaskId: checkpoint.childTaskId,
      requestStartedAtMs: checkpoint.requestStartedAtMs,
      responseReceivedAtMs: checkpoint.responseReceivedAtMs,
      requiresManualContinue: checkpoint.requiresManualContinue,
      detail: checkpoint.detail
    };
  }
}

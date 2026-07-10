import {
  CaptureMode,
  CapturePlan,
  CaptureTask,
  EquatorialCoordinate,
  ImageFormat,
  MountState,
  PlateSolveResult,
  TaskStatus
} from '../models/DomainModels';
import { AstronomyService } from './AstronomyService';
import { OnStepLX200Client } from './OnStepLX200Client';
import { GatewayFile, GatewayTask, RaspberryPiClient } from './RaspberryPiClient';

export interface CaptureWorkflowProgress {
  progressPercent: number;
  completedFrames: number;
  stage: string;
  activeTaskId: string;
}

export type CaptureWorkflowProgressListener = (progress: CaptureWorkflowProgress) => void;

export interface CaptureWorkflowResult {
  captureFiles: GatewayFile[];
  stackFile?: GatewayFile;
  timelapseFile?: GatewayFile;
  plateSolveCount: number;
  correctionCount: number;
  warnings: string[];
}

/**
 * 工作流主动取消使用独立错误类型，不能与板解析、堆栈等可降级错误混为一谈。
 * 页面可以继续通过 TaskStatus.CANCELLED 展示用户取消；协调器内部则依靠该类型保证
 * 任何后处理 catch 都不会把取消误写成“降级后成功”。
 */
export class CaptureWorkflowCancelledError extends Error {
  constructor(message: string = '拍摄工作流已由用户取消') {
    super(message);
    this.name = 'CaptureWorkflowCancelledError';
  }
}

/**
 * Pad 端的一键拍摄闭环。相机任务仍由树莓派串行执行，Pad 只在子曝光之间根据板解析结果
 * 发出受限的小幅 GOTO 修正，因此这不是连续导星，也不会在快门打开期间移动赤道仪。
 */
export class CaptureWorkflowCoordinator {
  private readonly mount: OnStepLX200Client;
  private readonly gateway: RaspberryPiClient;
  private cancelled: boolean = false;
  private activeTaskId: string = '';
  private driftCorrectionActive: boolean = false;

  constructor(mount: OnStepLX200Client, gateway: RaspberryPiClient) {
    this.mount = mount;
    this.gateway = gateway;
  }

  getActiveTaskId(): string {
    return this.activeTaskId;
  }

  async cancel(): Promise<void> {
    this.cancelled = true;
    const activeTaskId: string = this.activeTaskId;
    const failures: string[] = [];

    // 只有协调器正在执行帧间漂移 GOTO 时才中止赤道仪；当前 abort 也会关闭跟踪，
    // 普通曝光取消则只撤销相机任务，保留赤道仪指向供用户继续观测。
    if (this.driftCorrectionActive) {
      try {
        await this.mount.abort();
      } catch (error) {
        failures.push(`赤道仪漂移修正停止失败：${error}`);
      }
    }

    if (activeTaskId.length > 0) {
      try {
        await this.gateway.cancelTask(activeTaskId);
      } catch (error) {
        failures.push(`网关任务 ${activeTaskId} 取消未确认：${error}`);
      }
    }
    if (failures.length > 0) {
      // cancelled 标志仍会阻止后续设备操作，但调用方必须知道哪些链路没有获得确认。
      throw new Error(failures.join('；'));
    }
  }

  async run(plan: CapturePlan, target: EquatorialCoordinate,
    listener: CaptureWorkflowProgressListener): Promise<CaptureWorkflowResult> {
    if (plan.mode === CaptureMode.OBSERVE_ONLY) {
      throw new Error('仅观测计划不应提交相机工作流');
    }
    if (plan.mode === CaptureMode.SMART_LONG_EXPOSURE && !plan.enableLocalStack) {
      throw new Error('智能长曝光计划必须启用本地堆栈，不能只拍摄而不生成对应成品');
    }
    this.cancelled = false;
    this.activeTaskId = '';
    this.driftCorrectionActive = false;
    const captureFiles: GatewayFile[] = [];
    const jpegFileIds: string[] = [];
    const warnings: string[] = [];
    let plateSolveCount: number = 0;
    let correctionCount: number = 0;

    for (let frameIndex: number = 0; frameIndex < plan.frameCount; frameIndex++) {
      this.throwIfCancelled();
      listener({
        progressPercent: Math.max(1, Math.floor(frameIndex / plan.frameCount * 72)),
        completedFrames: frameIndex,
        stage: `正在拍摄第 ${frameIndex + 1}/${plan.frameCount} 帧`,
        activeTaskId: this.activeTaskId
      });
      const framePlan: CapturePlan = this.singleFramePlan(plan, frameIndex);
      const capture: CaptureTask = await this.gateway.createCaptureTask(
        framePlan, `${plan.id}-frame-${frameIndex + 1}`);
      this.activeTaskId = capture.id;
      await this.cancelTaskCreatedAfterCancellation(capture.id);
      await this.waitForTask(capture.id, Math.max(120000, plan.exposureSeconds * 1000 + 90000));
      this.throwIfCancelled();
      const frameFiles: GatewayFile[] = await this.gateway.listFiles(capture.id, 10);
      this.throwIfCancelled();
      let plateFile: GatewayFile | undefined = undefined;
      for (let fileIndex: number = 0; fileIndex < frameFiles.length; fileIndex++) {
        const file: GatewayFile = frameFiles[fileIndex];
        captureFiles.push(file);
        if (file.mimeType === 'image/jpeg' || file.name.toLowerCase().endsWith('.jpg') ||
          file.name.toLowerCase().endsWith('.jpeg')) {
          jpegFileIds.push(file.id);
          plateFile = file;
        }
      }

      const completed: number = frameIndex + 1;
      listener({
        progressPercent: Math.max(1, Math.floor(completed / plan.frameCount * 72)),
        completedFrames: completed,
        stage: `已完成第 ${completed}/${plan.frameCount} 帧`,
        activeTaskId: this.activeTaskId
      });

      if (plan.enablePlateSolve && plateFile !== undefined) {
        try {
          this.throwIfCancelled();
          const plateTask: GatewayTask = await this.gateway.createPlateSolveTask(plateFile.id, {
            hintRaHours: target.raHours,
            hintDecDegrees: target.decDegrees,
            searchRadiusDegrees: 12
          }, `${plan.id}-plate-${completed}`);
          this.activeTaskId = plateTask.id;
          await this.cancelTaskCreatedAfterCancellation(plateTask.id);
          listener({
            progressPercent: Math.max(1, Math.floor(completed / plan.frameCount * 72)),
            completedFrames: completed,
            stage: `正在板解析第 ${completed} 帧`,
            activeTaskId: this.activeTaskId
          });
          await this.waitForTask(plateTask.id, 240000);
          this.throwIfCancelled();
          const result: PlateSolveResult = await this.gateway.getPlateSolveResult(plateTask.id);
          this.throwIfCancelled();
          if (result.solved) {
            plateSolveCount++;
            if (plan.enableDriftCorrection && completed < plan.frameCount &&
              await this.correctDrift(target, result)) {
              correctionCount++;
            }
          }
        } catch (error) {
          this.rethrowCancellation(error);
          // 单次板解析失败不能让已经获取的原片失效；后续帧继续拍摄并把降级原因写入任务结果。
          warnings.push(`第 ${completed} 帧板解析/漂移修正跳过：${error}`);
        }
      }

      if (completed < plan.frameCount && plan.intervalSeconds > 0) {
        await this.delayWithCancellation(plan.intervalSeconds * 1000);
      }
    }

    this.throwIfCancelled();
    if ((plan.mode === CaptureMode.SMART_LONG_EXPOSURE || plan.mode === CaptureMode.TIMELAPSE) &&
      jpegFileIds.length < 2) {
      throw new Error(`仅取得 ${jpegFileIds.length} 个 JPEG，无法生成${
        plan.mode === CaptureMode.SMART_LONG_EXPOSURE ? '本地堆栈' : '延时视频'}；已保留现有原片`);
    }

    let stackFile: GatewayFile | undefined = undefined;
    let timelapseFile: GatewayFile | undefined = undefined;
    if (plan.mode === CaptureMode.SMART_LONG_EXPOSURE) {
      try {
        this.throwIfCancelled();
        const stackTask: GatewayTask = await this.gateway.createStackTask(jpegFileIds, {
          rejectBadFrames: true,
          correctLightPollution: true
        }, `${plan.id}-stack`);
        this.activeTaskId = stackTask.id;
        await this.cancelTaskCreatedAfterCancellation(stackTask.id);
        listener({
          progressPercent: 78,
          completedFrames: plan.frameCount,
          stage: '正在进行星点配准、坏帧剔除和本地堆栈',
          activeTaskId: this.activeTaskId
        });
        const completedStack: GatewayTask = await this.waitForTask(stackTask.id, 900000);
        this.throwIfCancelled();
        stackFile = this.findStackProduct(completedStack.files);
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
      try {
        this.throwIfCancelled();
        const timelapseTask: GatewayTask = await this.gateway.createTimelapseTask(jpegFileIds, {
          fps: plan.outputFps,
          width: 1920,
          height: 1080
        }, `${plan.id}-timelapse`);
        this.activeTaskId = timelapseTask.id;
        await this.cancelTaskCreatedAfterCancellation(timelapseTask.id);
        listener({
          progressPercent: 82,
          completedFrames: plan.frameCount,
          stage: '正在生成 1080p H.264 延时视频',
          activeTaskId: this.activeTaskId
        });
        const completedVideo: GatewayTask = await this.waitForTask(timelapseTask.id, 900000);
        this.throwIfCancelled();
        timelapseFile = this.findTimelapseProduct(completedVideo.files);
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
    listener({
      progressPercent: 100,
      completedFrames: plan.frameCount,
      stage: warnings.length === 0 ? '本地拍摄与处理工作流完成' : '拍摄完成，部分后处理已降级',
      activeTaskId: ''
    });
    return {
      captureFiles: captureFiles,
      stackFile: stackFile,
      timelapseFile: timelapseFile,
      plateSolveCount: plateSolveCount,
      correctionCount: correctionCount,
      warnings: warnings
    };
  }

  private async waitForTask(taskId: string, timeoutMs: number): Promise<GatewayTask> {
    const startedAt: number = Date.now();
    while (Date.now() - startedAt <= timeoutMs) {
      this.throwIfCancelled();
      const task: GatewayTask = await this.gateway.getTask(taskId);
      if (task.status === TaskStatus.SUCCEEDED) {
        return task;
      }
      if (task.status === TaskStatus.FAILED) {
        throw new Error(task.errorMessage.length > 0 ? task.errorMessage : task.message);
      }
      if (task.status === TaskStatus.CANCELLED) {
        throw new CaptureWorkflowCancelledError('网关任务已取消');
      }
      await this.delayWithCancellation(650);
    }
    try {
      await this.gateway.cancelTask(taskId);
    } catch (error) {
    }
    throw new Error(`网关任务 ${taskId} 超时`);
  }

  private async correctDrift(target: EquatorialCoordinate, result: PlateSolveResult): Promise<boolean> {
    this.throwIfCancelled();
    const solved: EquatorialCoordinate = {
      raHours: result.centerRaHours,
      decDegrees: result.centerDecDegrees,
      epoch: 2000
    };
    const errorDegrees: number = AstronomyService.angularSeparation(target, solved);
    if (errorDegrees < 0.04) {
      return false;
    }
    // 18mm 的正常帧间漂移应远小于 2°。更大误差通常意味着板解析错解，禁止据此运动设备。
    if (errorDegrees > 2.0) {
      throw new Error(`板解析偏差 ${errorDegrees.toFixed(2)}° 超过 2° 修正安全阈值`);
    }

    const state: MountState = await this.mount.refreshState();
    // refreshState 期间用户可能已经取消；真正发出物理 GOTO 前必须再次检查。
    this.throwIfCancelled();
    const rightAscensionErrorDegrees: number = AstronomyService.normalizeSignedDegrees(
      target.raHours * 15.0 - result.centerRaHours * 15.0);
    const corrected: EquatorialCoordinate = {
      raHours: AstronomyService.normalizeHours(state.rightAscensionHours + rightAscensionErrorDegrees / 15.0),
      decDegrees: Math.max(-90.0, Math.min(90.0,
        state.declinationDegrees + target.decDegrees - result.centerDecDegrees)),
      epoch: 2000
    };
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
          // 取消可能发生在 gotoRaDec 内部设置坐标和最终 :MS# 之间；退出前再次中止，
          // 防止较早发送的 :Q# 被随后完成的 GOTO 覆盖。
          await this.mount.abort();
        } catch (abortError) {
          // 明确取消错误仍需向上抛出，由全局急停界面提示人工确认物理急停。
        }
      }
      this.rethrowCancellation(error);
      if (error instanceof Error) {
        throw error;
      }
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
      if (!state.slewing) {
        return;
      }
      await this.delayWithCancellation(750);
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
      // 帧间间隔由协调器掌控，确保板解析和修正完成后才开始计时，网关内部不重复等待。
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

  private throwIfCancelled(): void {
    if (this.cancelled) {
      throw new CaptureWorkflowCancelledError();
    }
  }

  private rethrowCancellation(error: Object): void {
    if (error instanceof CaptureWorkflowCancelledError) {
      throw error;
    }
    this.throwIfCancelled();
  }

  /**
   * 取消可能与创建任务的 HTTP 请求同时发生。POST 返回后再次核对并撤销新任务，避免取消后
   * 仍遗留一帧曝光、堆栈或制片任务在树莓派后台继续运行。
   */
  private async cancelTaskCreatedAfterCancellation(taskId: string): Promise<void> {
    if (!this.cancelled) {
      return;
    }
    try {
      await this.gateway.cancelTask(taskId);
    } catch (error) {
      // 无论网关是否确认，协调器都不能继续提交后续设备操作。
    }
    throw new CaptureWorkflowCancelledError();
  }

  private findStackProduct(files: GatewayFile[]): GatewayFile | undefined {
    for (let index: number = 0; index < files.length; index++) {
      const file: GatewayFile = files[index];
      const mimeType: string = file.mimeType.toLowerCase();
      const name: string = file.name.toLowerCase();
      if (file.kind === 'stack' && (mimeType === 'image/jpeg' || mimeType === 'image/png' ||
        name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'))) {
        return file;
      }
    }
    return undefined;
  }

  private findTimelapseProduct(files: GatewayFile[]): GatewayFile | undefined {
    for (let index: number = 0; index < files.length; index++) {
      const file: GatewayFile = files[index];
      if (file.kind === 'timelapse' &&
        (file.mimeType.toLowerCase() === 'video/mp4' || file.name.toLowerCase().endsWith('.mp4'))) {
        return file;
      }
    }
    return undefined;
  }

  private async delayWithCancellation(milliseconds: number): Promise<void> {
    let remaining: number = Math.max(0, milliseconds);
    while (remaining > 0) {
      this.throwIfCancelled();
      const slice: number = Math.min(remaining, 250);
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, slice);
      });
      remaining -= slice;
    }
  }
}

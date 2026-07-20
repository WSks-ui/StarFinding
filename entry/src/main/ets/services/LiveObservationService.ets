import {
  LiveObservationState,
  ObservationRunMode,
  SessionKind,
  SessionStatus,
  TaskSession,
  WorkflowStage
} from '../models';

/**
 * 将任务会话映射为统一实况状态。
 *
 * 该服务不调用需要权益的系统实况窗 API，也不控制硬件。它先保证应用内任务中心的状态
 * 与 TaskSession 完全一致；后续真机权益通过后，系统实况窗只需消费同一状态即可。
 */
export class LiveObservationService {
  static fromSession(session: TaskSession | undefined, runMode: ObservationRunMode,
    sequence: number = 0): LiveObservationState | undefined {
    if (session === undefined) return undefined;
    return {
      sessionId: session.id,
      targetName: session.target.name,
      sessionKind: session.kind,
      workflowStage: session.stage,
      progressPercent: LiveObservationService.clamp(session.progressPercent, 0, 100),
      completedFrames: Math.max(0, session.completedFrames),
      totalFrames: session.kind === SessionKind.OBSERVATION ? 0 : Math.max(0, session.plan.frameCount),
      status: session.status,
      statusText: LiveObservationService.statusText(session),
      warning: session.errorMessage.length > 0 ? session.errorMessage :
        (session.warnings.length > 0 ? session.warnings[0] : ''),
      sequence: Math.max(sequence, 0),
      runMode: runMode,
      updatedAtMs: session.updatedAtMs
    };
  }

  private static statusText(session: TaskSession): string {
    if (session.status === SessionStatus.FAILED) {
      return session.errorMessage.length > 0 ? session.errorMessage : '任务失败';
    }
    if (session.status === SessionStatus.CANCELLED) return '任务已取消';
    if (session.status === SessionStatus.INTERRUPTED) return '任务中断，等待人工检查';
    if (session.status === SessionStatus.WAITING_FOR_USER) return '检查点已恢复，等待人工继续';
    if (session.status === SessionStatus.SUCCEEDED) return '观测任务已完成';
    if (session.stage === WorkflowStage.SAFETY_CHECK ||
      session.stage === WorkflowStage.CAMERA_PREFLIGHT) return '正在进行设备预检';
    if (session.stage === WorkflowStage.GOTO) return '赤道仪正在转向目标';
    if (session.stage === WorkflowStage.TRACKING) return '已开始目标跟踪';
    if (session.stage === WorkflowStage.CAPTURE) {
      return `正在曝光第 ${Math.min(session.completedFrames + 1, session.plan.frameCount)} / ${
        session.plan.frameCount} 帧`;
    }
    if (session.stage === WorkflowStage.PLATE_SOLVE) return '正在进行板解析';
    if (session.stage === WorkflowStage.DRIFT_CORRECTION) return '正在执行漂移修正';
    if (session.stage === WorkflowStage.STACK) return '正在生成本地堆栈';
    if (session.stage === WorkflowStage.TIMELAPSE) return '正在生成延时视频';
    if (session.stage === WorkflowStage.CLOUD_ENHANCEMENT) return '正在生成云端增强结果';
    return '观测任务已完成';
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.min(Math.max(value, minimum), maximum);
  }
}

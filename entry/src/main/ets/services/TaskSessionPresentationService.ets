import {
  SessionKind,
  SessionStatus,
  TaskSession,
  WorkflowStage,
  WorkflowStepState
} from '../models/TaskSessionModels';

export interface TaskWorkspaceLayout {
  compact: boolean;
  pageMargin: number;
  sidebarWidth: number;
  columnGap: number;
  mainWidth: number;
}
/** 任务中心的纯展示派生，单元测试可直接覆盖布局边界和会话类型流水线。 */
export class TaskSessionPresentationService {
  static resolveLayout(viewportWidth: number): TaskWorkspaceLayout {
    const safeWidth: number = Math.max(240, viewportWidth);
    const compact: boolean = safeWidth < 900;
    const pageMargin: number = safeWidth < 600 ? 16 : (compact ? 20 : 32);
    const sidebarWidth: number = compact ? 0 : 320;
    const columnGap: number = compact ? 0 : 12;
    const mainWidth: number = Math.max(0,
      safeWidth - pageMargin * 2 - sidebarWidth - columnGap);
    return {
      compact: compact,
      pageMargin: pageMargin,
      sidebarWidth: sidebarWidth,
      columnGap: columnGap,
      mainWidth: mainWidth
    };
  }

  static pipelineStages(session: TaskSession): WorkflowStage[] {
    const stages: WorkflowStage[] = [WorkflowStage.SAFETY_CHECK, WorkflowStage.GOTO];
    if (session.kind === SessionKind.OBSERVATION) {
      stages.push(WorkflowStage.TRACKING);
      stages.push(WorkflowStage.COMPLETE);
      return stages;
    }
    stages.push(WorkflowStage.CAPTURE);
    if (session.kind === SessionKind.SMART_LONG_EXPOSURE) {
      stages.push(WorkflowStage.PLATE_SOLVE);
      stages.push(WorkflowStage.STACK);
      stages.push(WorkflowStage.CLOUD_ENHANCEMENT);
    } else {
      stages.push(WorkflowStage.TIMELAPSE);
    }
    return stages;
  }

  static stepState(session: TaskSession, stage: WorkflowStage): WorkflowStepState {
    if (stage === WorkflowStage.CLOUD_ENHANCEMENT && !session.plan.enableCloudEnhancement) {
      return WorkflowStepState.SKIPPED;
    }
    const currentRank: number = TaskSessionPresentationService.stageRank(session.stage);
    const stepRank: number = TaskSessionPresentationService.stageRank(stage);
    if (stepRank < currentRank) return WorkflowStepState.SUCCEEDED;
    if (stepRank > currentRank) return WorkflowStepState.WAITING;
    if (session.status === SessionStatus.FAILED) return WorkflowStepState.FAILED;
    if (session.status === SessionStatus.CANCELLED) return WorkflowStepState.CANCELLED;
    return session.checkpoint.stage === stage ? session.checkpoint.stepState : WorkflowStepState.ACTIVE;
  }

  private static stageRank(stage: WorkflowStage): number {
    if (stage === WorkflowStage.SAFETY_CHECK || stage === WorkflowStage.CAMERA_PREFLIGHT) return 0;
    if (stage === WorkflowStage.GOTO) return 1;
    if (stage === WorkflowStage.TRACKING) return 2;
    if (stage === WorkflowStage.CAPTURE) return 3;
    if (stage === WorkflowStage.PLATE_SOLVE || stage === WorkflowStage.DRIFT_CORRECTION) return 4;
    if (stage === WorkflowStage.STACK || stage === WorkflowStage.TIMELAPSE) return 5;
    if (stage === WorkflowStage.CLOUD_ENHANCEMENT) return 6;
    return 7;
  }
}

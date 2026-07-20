import { ObservationRunMode } from './DigitalTwinModels';
import {
  SessionKind,
  SessionStatus,
  WorkflowStage
} from './TaskSessionModels';

/**
 * 应用内实况状态。
 * 当前比赛版不虚假启用需要权益的系统实况窗；无论系统权益是否可用，任务中心都消费同一份状态。
 */
export interface LiveObservationState {
  sessionId: string;
  targetName: string;
  sessionKind: SessionKind;
  workflowStage: WorkflowStage;
  progressPercent: number;
  completedFrames: number;
  totalFrames: number;
  status: SessionStatus;
  statusText: string;
  warning: string;
  sequence: number;
  runMode: ObservationRunMode;
  updatedAtMs: number;
}

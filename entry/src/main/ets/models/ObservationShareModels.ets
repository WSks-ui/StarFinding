import { PlanningSnapshot } from './DomainModels';
import { ReplayAssetManifest } from './DigitalTwinModels';
import { TaskSession } from './TaskSessionModels';

/** 系统分享的业务类型。载荷只包含用户可理解的观测信息，不包含设备连接配置。 */
export enum ObservationShareKind {
  PLANNING = 'planning',
  TASK_REPORT = 'task_report'
}

/**
 * 规划分享输入保持对 PlanningSnapshot 的完整引用。
 * 分享服务会在生成文本前再次校验快照一致性，避免分享“明晚标题 + 今晚结果”的错配内容。
 */
export interface PlanningShareInput {
  snapshot: PlanningSnapshot;
  targetName: string;
  designation: string;
}

/**
 * 任务报告分享输入。
 * replayManifest 仅用于追加演练素材来源，不允许把预览 URI、哈希之外的内部连接信息写入正文。
 */
export interface TaskReportShareInput {
  session: TaskSession;
  replayManifest?: ReplayAssetManifest;
}

/** 交给系统分享面板的最小文本载荷。 */
export interface ObservationSharePayload {
  kind: ObservationShareKind;
  title: string;
  description: string;
  content: string;
  simulated: boolean;
}

/** 系统分享调用结果，用显式状态驱动 UI，避免用异常字符串判断业务分支。 */
export interface ObservationShareResult {
  succeeded: boolean;
  message: string;
}

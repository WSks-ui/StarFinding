import {
  CapturePlan,
  CaptureProduct,
  CatalogPrecision,
  CelestialType,
  EquatorialCoordinate
} from './DomainModels';

/** 会话类型与拍摄模式分离，避免“仅观测”被误画成相机任务。 */
export enum SessionKind {
  OBSERVATION = 'observation',
  SMART_LONG_EXPOSURE = 'smart_long_exposure',
  TIMELAPSE = 'timelapse'
}

export enum SessionStatus {
  PREPARING = 'preparing',
  RUNNING = 'running',
  WAITING_FOR_USER = 'waiting_for_user',
  INTERRUPTED = 'interrupted',
  SUCCEEDED = 'succeeded',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export enum WorkflowStage {
  SAFETY_CHECK = 'safety_check',
  CAMERA_PREFLIGHT = 'camera_preflight',
  GOTO = 'goto',
  TRACKING = 'tracking',
  CAPTURE = 'capture',
  PLATE_SOLVE = 'plate_solve',
  DRIFT_CORRECTION = 'drift_correction',
  STACK = 'stack',
  TIMELAPSE = 'timelapse',
  CLOUD_ENHANCEMENT = 'cloud_enhancement',
  COMPLETE = 'complete'
}

export enum WorkflowStepState {
  WAITING = 'waiting',
  ACTIVE = 'active',
  SUCCEEDED = 'succeeded',
  SKIPPED = 'skipped',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export enum GatewaySubtaskKind {
  NONE = 'none',
  CAPTURE = 'capture',
  PLATE_SOLVE = 'plate_solve',
  STACK = 'stack',
  TIMELAPSE = 'timelapse'
}

/** 会话创建时冻结的目标信息；后续星图选中项变化不会污染任务页。 */
export interface TaskTargetSnapshot {
  id: string;
  name: string;
  designation: string;
  type: CelestialType;
  coordinate?: EquatorialCoordinate;
  precision: CatalogPrecision;
  gotoAllowed: boolean;
}

/**
 * 每次有副作用的网关 POST 都先写入 operationKey，再发送请求；收到响应后才写 childTaskId。
 * operationKey 存在但 childTaskId 为空表示结果未知，恢复时必须等待人工确认后以同一键重试。
 */
export interface WorkflowCheckpoint {
  stage: WorkflowStage;
  stepState: WorkflowStepState;
  childKind: GatewaySubtaskKind;
  operationKey: string;
  childTaskId: string;
  requestStartedAtMs: number;
  responseReceivedAtMs: number;
  requiresManualContinue: boolean;
  detail: string;
}

export interface TaskSession {
  id: string;
  kind: SessionKind;
  status: SessionStatus;
  stage: WorkflowStage;
  progressPercent: number;
  completedFrames: number;
  plan: CapturePlan;
  target: TaskTargetSnapshot;
  checkpoint: WorkflowCheckpoint;
  gatewayTaskIds: string[];
  jpegFileIds: string[];
  rawFileIds: string[];
  plateSolveCount: number;
  correctionCount: number;
  products: CaptureProduct[];
  warnings: string[];
  statusDetail: string;
  errorMessage: string;
  createdAtMs: number;
  startedAtMs: number;
  updatedAtMs: number;
  completedAtMs: number;
}

/** Preferences 读取结果会带上隔离记录数量，UI 可提示用户但不阻断星图启动。 */
export interface TaskSessionStoreSnapshot {
  activeSession?: TaskSession;
  history: TaskSession[];
  corruptedRecords: number;
  warning: string;
}

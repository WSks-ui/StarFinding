import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  CapturePlan,
  CaptureProduct,
  EquatorialCoordinate,
  ImageFormat
} from '../models/DomainModels';
import {
  GatewaySubtaskKind,
  SessionKind,
  SessionStatus,
  TaskSession,
  TaskSessionStoreSnapshot,
  TaskTargetSnapshot,
  WorkflowCheckpoint,
  WorkflowStage,
  WorkflowStepState
} from '../models/TaskSessionModels';

interface TaskSessionEnvelope {
  version: number;
  activeSessionJson: string;
  historySessionJson: string[];
}

export const TASK_SESSION_PREFERENCES_NAME: string = 'starfinding_task_sessions';
export const TASK_SESSION_PREFERENCES_KEY: string = 'sessions_v1';
export const TASK_SESSION_SCHEMA_VERSION: number = 1;
export const TASK_SESSION_HISTORY_LIMIT: number = 10;

export class TaskSessionStore {
  private readonly context: common.Context;
  private storage?: preferences.Preferences;
  private snapshot: TaskSessionStoreSnapshot = TaskSessionStore.emptySnapshot();

  constructor(context: common.Context) {
    this.context = context;
  }

  async initialize(): Promise<TaskSessionStoreSnapshot> {
    this.storage = await preferences.getPreferences(this.context, {
      name: TASK_SESSION_PREFERENCES_NAME
    });
    const value: preferences.ValueType = await this.storage.get(TASK_SESSION_PREFERENCES_KEY, '');
    this.snapshot = typeof value === 'string' ? TaskSessionStore.decode(value) : TaskSessionStore.emptySnapshot();
    return TaskSessionStore.copySnapshot(this.snapshot);
  }

  getSnapshot(): TaskSessionStoreSnapshot {
    return TaskSessionStore.copySnapshot(this.snapshot);
  }

  async saveActive(session: TaskSession): Promise<void> {
    this.requireInitialized();
    if (TaskSessionStore.isTerminal(session.status)) {
      throw new Error('终态会话必须归档，不能继续保存为活动会话');
    }
    this.snapshot.activeSession = TaskSessionStore.copySession(session);
    await this.flush();
  }

  async archive(session: TaskSession): Promise<void> {
    this.requireInitialized();
    if (!TaskSessionStore.isTerminal(session.status)) {
      throw new Error('只有完成、失败或取消的会话可以归档');
    }
    const nextHistory: TaskSession[] = [TaskSessionStore.copySession(session)];
    for (let index: number = 0; index < this.snapshot.history.length; index++) {
      const item: TaskSession = this.snapshot.history[index];
      if (item.id !== session.id && nextHistory.length < TASK_SESSION_HISTORY_LIMIT) {
        nextHistory.push(TaskSessionStore.copySession(item));
      }
    }
    this.snapshot.activeSession = undefined;
    this.snapshot.history = nextHistory;
    await this.flush();
  }

  async clearActive(): Promise<void> {
    this.requireInitialized();
    this.snapshot.activeSession = undefined;
    await this.flush();
  }

  async replaceForTest(snapshot: TaskSessionStoreSnapshot): Promise<void> {
    this.requireInitialized();
    this.snapshot = TaskSessionStore.normalizeSnapshot(snapshot);
    await this.flush();
  }

  static encode(snapshot: TaskSessionStoreSnapshot): string {
    const normalized: TaskSessionStoreSnapshot = TaskSessionStore.normalizeSnapshot(snapshot);
    const activeJson: string = normalized.activeSession === undefined ? '' :
      JSON.stringify(normalized.activeSession);
    const historyJson: string[] = [];
    for (let index: number = 0; index < normalized.history.length; index++) {
      historyJson.push(JSON.stringify(normalized.history[index]));
    }
    const envelope: TaskSessionEnvelope = {
      version: TASK_SESSION_SCHEMA_VERSION,
      activeSessionJson: activeJson,
      historySessionJson: historyJson
    };
    return JSON.stringify(envelope);
  }

  static decode(value: string): TaskSessionStoreSnapshot {
    if (value.trim().length === 0) {
      return TaskSessionStore.emptySnapshot();
    }
    let envelope: TaskSessionEnvelope;
    try {
      envelope = JSON.parse(value) as TaskSessionEnvelope;
    } catch (error) {
      return {
        activeSession: undefined,
        history: [],
        corruptedRecords: 1,
        warning: `任务会话索引损坏，已隔离：${error}`
      };
    }
    if (envelope.version !== TASK_SESSION_SCHEMA_VERSION || !Array.isArray(envelope.historySessionJson)) {
      return {
        activeSession: undefined,
        history: [],
        corruptedRecords: 1,
        warning: '任务会话版本不兼容，已忽略旧数据'
      };
    }

    let corrupted: number = 0;
    let active: TaskSession | undefined = undefined;
    if (typeof envelope.activeSessionJson === 'string' && envelope.activeSessionJson.length > 0) {
      active = TaskSessionStore.decodeSession(envelope.activeSessionJson);
      if (active === undefined || TaskSessionStore.isTerminal(active.status)) {
        active = undefined;
        corrupted++;
      }
    }
    const history: TaskSession[] = [];
    for (let index: number = 0;
      index < envelope.historySessionJson.length && history.length < TASK_SESSION_HISTORY_LIMIT; index++) {
      const encoded: string = envelope.historySessionJson[index];
      const item: TaskSession | undefined = TaskSessionStore.decodeSession(encoded);
      if (item === undefined || !TaskSessionStore.isTerminal(item.status)) {
        corrupted++;
      } else {
        history.push(item);
      }
    }
    return {
      activeSession: active,
      history: history,
      corruptedRecords: corrupted,
      warning: corrupted > 0 ? `已隔离 ${corrupted} 条不可读任务记录` : ''
    };
  }

  static isTerminal(status: SessionStatus): boolean {
    return status === SessionStatus.SUCCEEDED || status === SessionStatus.FAILED ||
      status === SessionStatus.CANCELLED;
  }

  static copySession(session: TaskSession): TaskSession {
    return {
      id: session.id,
      kind: session.kind,
      status: session.status,
      stage: session.stage,
      progressPercent: session.progressPercent,
      completedFrames: session.completedFrames,
      plan: TaskSessionStore.copyPlan(session.plan),
      target: TaskSessionStore.copyTarget(session.target),
      checkpoint: TaskSessionStore.copyCheckpoint(session.checkpoint),
      gatewayTaskIds: session.gatewayTaskIds.slice(),
      jpegFileIds: session.jpegFileIds.slice(),
      rawFileIds: session.rawFileIds.slice(),
      plateSolveCount: session.plateSolveCount,
      correctionCount: session.correctionCount,
      products: TaskSessionStore.copyProducts(session.products),
      warnings: session.warnings.slice(),
      statusDetail: session.statusDetail,
      errorMessage: session.errorMessage,
      createdAtMs: session.createdAtMs,
      startedAtMs: session.startedAtMs,
      updatedAtMs: session.updatedAtMs,
      completedAtMs: session.completedAtMs
    };
  }

  static emptyCheckpoint(): WorkflowCheckpoint {
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

  private static decodeSession(value: string): TaskSession | undefined {
    try {
      const parsed: TaskSession | null = JSON.parse(value) as TaskSession | null;
      if (parsed === null || !TaskSessionStore.validSession(parsed)) {
        return undefined;
      }
      return TaskSessionStore.copySession(parsed);
    } catch (error) {
      return undefined;
    }
  }

  private static validSession(session: TaskSession): boolean {
    return typeof session.id === 'string' && session.id.length > 0 &&
      TaskSessionStore.validKind(session.kind) && TaskSessionStore.validStatus(session.status) &&
      TaskSessionStore.validStage(session.stage) && Number.isFinite(session.progressPercent) &&
      Number.isFinite(session.completedFrames) && session.plan !== undefined &&
      typeof session.plan.id === 'string' && session.target !== undefined &&
      typeof session.target.id === 'string' && session.checkpoint !== undefined &&
      Array.isArray(session.gatewayTaskIds) && Array.isArray(session.jpegFileIds) &&
      Array.isArray(session.rawFileIds) && Array.isArray(session.products) &&
      Array.isArray(session.warnings) && Number.isFinite(session.createdAtMs) &&
      Number.isFinite(session.updatedAtMs);
  }

  private static validKind(kind: SessionKind): boolean {
    return kind === SessionKind.OBSERVATION || kind === SessionKind.SMART_LONG_EXPOSURE ||
      kind === SessionKind.TIMELAPSE;
  }

  private static validStatus(status: SessionStatus): boolean {
    return status === SessionStatus.PREPARING || status === SessionStatus.RUNNING ||
      status === SessionStatus.WAITING_FOR_USER || status === SessionStatus.INTERRUPTED ||
      status === SessionStatus.SUCCEEDED || status === SessionStatus.FAILED ||
      status === SessionStatus.CANCELLED;
  }

  private static validStage(stage: WorkflowStage): boolean {
    return stage === WorkflowStage.SAFETY_CHECK || stage === WorkflowStage.CAMERA_PREFLIGHT ||
      stage === WorkflowStage.GOTO || stage === WorkflowStage.TRACKING || stage === WorkflowStage.CAPTURE ||
      stage === WorkflowStage.PLATE_SOLVE || stage === WorkflowStage.DRIFT_CORRECTION ||
      stage === WorkflowStage.STACK || stage === WorkflowStage.TIMELAPSE ||
      stage === WorkflowStage.CLOUD_ENHANCEMENT || stage === WorkflowStage.COMPLETE;
  }

  private static copyPlan(plan: CapturePlan): CapturePlan {
    return {
      id: plan.id,
      mode: plan.mode,
      targetId: plan.targetId,
      targetName: plan.targetName,
      exposureSeconds: plan.exposureSeconds,
      frameCount: plan.frameCount,
      intervalSeconds: plan.intervalSeconds,
      iso: plan.iso,
      aperture: plan.aperture,
      imageFormat: plan.imageFormat === ImageFormat.RAW_JPEG ? ImageFormat.RAW_JPEG : ImageFormat.JPEG,
      outputFps: plan.outputFps,
      enablePlateSolve: plan.enablePlateSolve,
      enableDriftCorrection: plan.enableDriftCorrection,
      enableLocalStack: plan.enableLocalStack,
      enableCloudEnhancement: plan.enableCloudEnhancement,
      recommendationReason: plan.recommendationReason,
      warnings: plan.warnings.slice()
    };
  }

  private static copyTarget(target: TaskTargetSnapshot): TaskTargetSnapshot {
    const coordinate: EquatorialCoordinate | undefined = target.coordinate === undefined ? undefined : {
      raHours: target.coordinate.raHours,
      decDegrees: target.coordinate.decDegrees,
      frame: target.coordinate.frame,
      validAtMs: target.coordinate.validAtMs
    };
    return {
      id: target.id,
      name: target.name,
      designation: target.designation,
      type: target.type,
      coordinate: coordinate,
      precision: target.precision,
      gotoAllowed: target.gotoAllowed
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

  private static copyProducts(products: CaptureProduct[]): CaptureProduct[] {
    const copies: CaptureProduct[] = [];
    for (let index: number = 0; index < products.length; index++) {
      const product: CaptureProduct = products[index];
      copies.push({
        kind: product.kind,
        fileName: product.fileName,
        downloadUrl: product.downloadUrl,
        createdAtMs: product.createdAtMs
      });
    }
    return copies;
  }

  private static normalizeSnapshot(snapshot: TaskSessionStoreSnapshot): TaskSessionStoreSnapshot {
    const history: TaskSession[] = [];
    for (let index: number = 0; index < snapshot.history.length && history.length < TASK_SESSION_HISTORY_LIMIT;
      index++) {
      const item: TaskSession = snapshot.history[index];
      if (TaskSessionStore.isTerminal(item.status)) {
        history.push(TaskSessionStore.copySession(item));
      }
    }
    const active: TaskSession | undefined = snapshot.activeSession !== undefined &&
      !TaskSessionStore.isTerminal(snapshot.activeSession.status) ?
      TaskSessionStore.copySession(snapshot.activeSession) : undefined;
    return {
      activeSession: active,
      history: history,
      corruptedRecords: Math.max(0, Math.trunc(snapshot.corruptedRecords)),
      warning: snapshot.warning
    };
  }

  private static copySnapshot(snapshot: TaskSessionStoreSnapshot): TaskSessionStoreSnapshot {
    return TaskSessionStore.normalizeSnapshot(snapshot);
  }

  private static emptySnapshot(): TaskSessionStoreSnapshot {
    return {
      activeSession: undefined,
      history: [],
      corruptedRecords: 0,
      warning: ''
    };
  }

  private requireInitialized(): void {
    if (this.storage === undefined) {
      throw new Error('任务会话存储尚未初始化');
    }
  }

  private async flush(): Promise<void> {
    const storage: preferences.Preferences | undefined = this.storage;
    if (storage === undefined) {
      throw new Error('任务会话存储尚未初始化');
    }
    await storage.put(TASK_SESSION_PREFERENCES_KEY, TaskSessionStore.encode(this.snapshot));
    await storage.flush();
  }
}

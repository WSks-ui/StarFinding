import {
  CameraState,
  CapturePlan,
  CaptureProduct,
  ConnectionState,
  EquatorialCoordinate,
  MountState,
  TrackingMode
} from '../models/DomainModels';
import {
  DigitalTwinListener,
  DigitalTwinPhase,
  DigitalTwinSnapshot,
  ObservationRunMode,
  ReplayAsset,
  ReplayAssetKind,
  ReplayAssetManifest,
  ReplayAssetSource
} from '../models/DigitalTwinModels';
import {
  GatewaySubtaskKind,
  SessionKind,
  SessionStatus,
  TaskSession,
  TaskTargetSnapshot,
  WorkflowCheckpoint,
  WorkflowStage,
  WorkflowStepState
} from '../models/TaskSessionModels';

/**
 * 无硬件演练回放器。它只生成内存快照，不持有 OnStepX、Linux 网关或相机客户端，
 * 因此播放、暂停、跳转和停止均不具备向真实硬件发送命令的能力。
 */
export class DigitalTwinReplayService {
  private frames: DigitalTwinSnapshot[] = [];
  private listeners: DigitalTwinListener[] = [];
  private currentIndex: number = 0;
  private playbackRate: number = 1.0;
  private startedAtMs: number = 0;
  private startElapsedMs: number = 0;
  private timerHandle: number = -1;
  private lastSnapshot: DigitalTwinSnapshot | undefined = undefined;

  load(frames: DigitalTwinSnapshot[]): void {
    this.pause();
    this.frames = frames.slice().sort((first: DigitalTwinSnapshot, second: DigitalTwinSnapshot) =>
      first.elapsedMs - second.elapsedMs);
    this.currentIndex = 0;
    this.lastSnapshot = undefined;
    if (this.frames.length > 0) {
      this.emit(this.frames[0]);
    }
  }

  loadStandardDemo(plan: CapturePlan, target: TaskTargetSnapshot,
    manifest?: ReplayAssetManifest): void {
    const assets: ReplayAssetManifest = manifest === undefined ?
      DigitalTwinReplayService.createSimulatedManifest(plan.targetName) :
      DigitalTwinReplayService.copyManifest(manifest);
    this.load(DigitalTwinReplayService.createStandardDemo(plan, target, assets));
  }

  play(playbackRate: number = 1.0): void {
    if (this.frames.length === 0 || this.timerHandle >= 0) return;
    if (this.currentIndex >= this.frames.length - 1) this.currentIndex = 0;
    this.playbackRate = Math.max(0.25, Math.min(8.0, playbackRate));
    this.startElapsedMs = this.frames[this.currentIndex].elapsedMs;
    this.startedAtMs = Date.now();
    this.timerHandle = setInterval(() => {
      this.advance();
    }, 50);
  }

  pause(): void {
    if (this.timerHandle >= 0) {
      clearInterval(this.timerHandle);
      this.timerHandle = -1;
    }
  }

  restart(playbackRate: number = 1.0): void {
    if (this.frames.length === 0) return;
    this.pause();
    this.currentIndex = 0;
    this.emit(this.frames[0]);
    this.play(playbackRate);
  }

  stop(): void {
    this.pause();
    const current: DigitalTwinSnapshot | undefined = this.current();
    if (current === undefined) return;
    const stoppedSession: TaskSession = DigitalTwinReplayService.copySession(current.session);
    stoppedSession.status = SessionStatus.CANCELLED;
    stoppedSession.checkpoint.stepState = WorkflowStepState.CANCELLED;
    stoppedSession.checkpoint.requiresManualContinue = false;
    stoppedSession.statusDetail = '演练回放已停止；未访问任何真实设备';
    stoppedSession.updatedAtMs = Date.now();
    stoppedSession.completedAtMs = stoppedSession.updatedAtMs;
    const stopped: DigitalTwinSnapshot = {
      elapsedMs: current.elapsedMs,
      sequence: current.sequence + 1,
      runMode: ObservationRunMode.SIMULATION,
      dataSource: current.dataSource,
      phase: DigitalTwinPhase.STOPPED,
      mount: DigitalTwinReplayService.copyMount(current.mount),
      camera: DigitalTwinReplayService.copyCamera(current.camera),
      session: stoppedSession,
      assetManifest: DigitalTwinReplayService.copyManifest(current.assetManifest),
      note: '演练已停止',
      warning: '这只是数字孪生回放，未发送 TCP、GOTO、同步、跟踪或快门指令'
    };
    this.emit(stopped);
  }

  seek(elapsedMs: number): void {
    if (this.frames.length === 0) return;
    this.pause();
    let targetIndex: number = 0;
    for (let index: number = 0; index < this.frames.length; index++) {
      if (this.frames[index].elapsedMs <= elapsedMs) {
        targetIndex = index;
      } else {
        break;
      }
    }
    this.currentIndex = targetIndex;
    this.emit(this.frames[this.currentIndex]);
  }

  subscribe(listener: DigitalTwinListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
    if (this.frames.length > 0) listener(this.frames[this.currentIndex]);
  }

  unsubscribe(listener: DigitalTwinListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  current(): DigitalTwinSnapshot | undefined {
    return this.lastSnapshot;
  }

  isPlaying(): boolean {
    return this.timerHandle >= 0;
  }

  private advance(): void {
    const elapsed: number = this.startElapsedMs + (Date.now() - this.startedAtMs) * this.playbackRate;
    while (this.currentIndex + 1 < this.frames.length &&
      this.frames[this.currentIndex + 1].elapsedMs <= elapsed) {
      this.currentIndex++;
      this.emit(this.frames[this.currentIndex]);
    }
    if (this.currentIndex >= this.frames.length - 1) this.pause();
  }

  private emit(snapshot: DigitalTwinSnapshot): void {
    this.lastSnapshot = snapshot;
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index](snapshot);
    }
  }

  static createStandardDemo(plan: CapturePlan, target: TaskTargetSnapshot,
    manifest: ReplayAssetManifest): DigitalTwinSnapshot[] {
    const now: number = Date.now();
    const baseMount: MountState = {
      connection: ConnectionState.SIMULATED,
      host: 'DIGITAL_TWIN',
      port: 0,
      rightAscensionHours: 0,
      declinationDegrees: 0,
      trackingMode: TrackingMode.STOPPED,
      slewing: false,
      homed: false,
      parked: false,
      lastError: '',
      updatedAtMs: now
    };
    const baseCamera: CameraState = {
      connection: ConnectionState.SIMULATED,
      cameraModel: manifest.cameraName,
      batteryPercent: 86,
      storageFreeBytes: 64000000000,
      busy: false,
      liveViewActive: false,
      lastError: '',
      updatedAtMs: now
    };
    const source: ReplayAssetSource = manifest.source;
    const frames: DigitalTwinSnapshot[] = [];
    frames.push(DigitalTwinReplayService.frame(0, 1, DigitalTwinPhase.DEVICE_DISCOVERY,
      baseMount, baseCamera, DigitalTwinReplayService.session(plan, target, now,
        WorkflowStage.SAFETY_CHECK, SessionStatus.PREPARING, 2, 0,
        '演练：发现 StarScope 赤道仪与相机网关', WorkflowStepState.ACTIVE, []),
      manifest, source, '设备发现', '模拟连接只用于演练，不代表现场硬件在线'));
    frames.push(DigitalTwinReplayService.frame(1200, 2, DigitalTwinPhase.CAMERA_PREFLIGHT,
      DigitalTwinReplayService.mount(baseMount, true, false, TrackingMode.STOPPED, 0, 0, now + 1200),
      DigitalTwinReplayService.camera(baseCamera, false, now + 1200),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.CAMERA_PREFLIGHT,
        SessionStatus.PREPARING, 7, 0, '演练：EOS R7 参数自检通过',
        WorkflowStepState.SUCCEEDED, []),
      manifest, source, '相机预检', '参数来自演练脚本，不是当前相机实时读数'));
    frames.push(DigitalTwinReplayService.frame(3000, 3, DigitalTwinPhase.GOTO,
      DigitalTwinReplayService.mount(baseMount, true, true, TrackingMode.STOPPED,
        0.3, 12.0, now + 3000),
      DigitalTwinReplayService.camera(baseCamera, false, now + 3000),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.GOTO,
        SessionStatus.PREPARING, 14, 0, `演练：正在转向 ${target.designation}`,
        WorkflowStepState.ACTIVE, []),
      manifest, source, 'GOTO 演练', '未向 OnStepX 发送 GOTO 指令'));
    frames.push(DigitalTwinReplayService.frame(6500, 4, DigitalTwinPhase.TRACKING,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 6500),
      DigitalTwinReplayService.camera(baseCamera, false, now + 6500),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.TRACKING,
        SessionStatus.RUNNING, 22, 0, '演练：目标已到位并开始恒星时跟踪',
        WorkflowStepState.SUCCEEDED, []),
      manifest, source, '跟踪演练', '模拟回零与同步证明不会带回真实模式'));
    frames.push(DigitalTwinReplayService.frame(9500, 5, DigitalTwinPhase.CAPTURE,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 9500),
      DigitalTwinReplayService.camera(baseCamera, true, now + 9500),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.CAPTURE,
        SessionStatus.RUNNING, 38, Math.max(1, Math.floor(plan.frameCount * 0.35)),
        '演练：短子曝光采集中', WorkflowStepState.ACTIVE, []),
      manifest, source, '曝光演练', '演练不会触发 EOS R7 快门'));
    frames.push(DigitalTwinReplayService.frame(13500, 6, DigitalTwinPhase.DOWNLOAD,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 13500),
      DigitalTwinReplayService.camera(baseCamera, true, now + 13500),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.CAPTURE,
        SessionStatus.RUNNING, 54, Math.max(1, Math.floor(plan.frameCount * 0.7)),
        '演练：接收 RAW+JPEG', WorkflowStepState.ACTIVE, []),
      manifest, source, '文件下载演练', DigitalTwinReplayService.assetWarning(source)));
    frames.push(DigitalTwinReplayService.frame(17000, 7, DigitalTwinPhase.PLATE_SOLVE,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 17000),
      DigitalTwinReplayService.camera(baseCamera, false, now + 17000),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.PLATE_SOLVE,
        SessionStatus.RUNNING, 68, plan.frameCount, '演练：板解析确认构图中心',
        WorkflowStepState.ACTIVE, []),
      manifest, source, '板解析演练', '解析结果为演练脚本数据'));
    frames.push(DigitalTwinReplayService.frame(20500, 8, DigitalTwinPhase.STACK,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 20500),
      DigitalTwinReplayService.camera(baseCamera, false, now + 20500),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.STACK,
        SessionStatus.RUNNING, 82, plan.frameCount, '演练：星点配准与本地堆栈',
        WorkflowStepState.ACTIVE, []),
      manifest, source, '堆栈演练', DigitalTwinReplayService.assetWarning(source)));
    frames.push(DigitalTwinReplayService.frame(23500, 9, DigitalTwinPhase.RECOVERY,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 23500),
      DigitalTwinReplayService.camera(baseCamera, false, now + 23500),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.STACK,
        SessionStatus.INTERRUPTED, 82, plan.frameCount,
        '演练：网关短暂中断，已停在安全检查点', WorkflowStepState.FAILED,
        ['演练异常：网关连接中断，未自动补拍']),
      manifest, source, '异常恢复演练', '演练将在只读检查后继续，不触发真实设备'));
    frames.push(DigitalTwinReplayService.frame(27000, 10, DigitalTwinPhase.STACK,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 27000),
      DigitalTwinReplayService.camera(baseCamera, false, now + 27000),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.STACK,
        SessionStatus.RUNNING, 90, plan.frameCount, '演练：从堆栈检查点恢复',
        WorkflowStepState.ACTIVE, ['已演练网关中断与人工恢复']),
      manifest, source, '恢复堆栈', DigitalTwinReplayService.assetWarning(source)));
    frames.push(DigitalTwinReplayService.frame(32000, 11, DigitalTwinPhase.COMPLETE,
      DigitalTwinReplayService.mount(baseMount, false, true, TrackingMode.SIDEREAL,
        target.coordinate === undefined ? 0.7123 : target.coordinate.raHours,
        target.coordinate === undefined ? 41.2692 : target.coordinate.decDegrees,
        now + 32000),
      DigitalTwinReplayService.camera(baseCamera, false, now + 32000),
      DigitalTwinReplayService.session(plan, target, now, WorkflowStage.COMPLETE,
        SessionStatus.SUCCEEDED, 100, plan.frameCount, '演练完成：成品与来源清单已生成',
        WorkflowStepState.SUCCEEDED, ['本会话为数字孪生演练，不进入真实任务历史'],
        DigitalTwinReplayService.products(manifest)),
      manifest, source, '演练完成', DigitalTwinReplayService.assetWarning(source)));
    return frames;
  }

  static createSimulatedManifest(targetName: string): ReplayAssetManifest {
    const now: number = Date.now();
    const source: ReplayAssetSource = ReplayAssetSource.SIMULATED;
    const files: ReplayAsset[] = [
      DigitalTwinReplayService.asset('sim-jpeg', ReplayAssetKind.JPEG,
        'simulation-preview.jpg', source, now, '模拟 JPEG 预览'),
      DigitalTwinReplayService.asset('sim-stack', ReplayAssetKind.STACKED,
        'simulation-stacked.jpg', source, now, '模拟堆栈结果'),
      DigitalTwinReplayService.asset('sim-ai', ReplayAssetKind.ENHANCED,
        'simulation-enhanced.jpg', source, now, '模拟增强预览')
    ];
    return {
      replayId: `simulation-${now}`,
      source: source,
      targetName: targetName,
      cameraName: 'EOS R7（数字孪生）',
      capturedAtMs: 0,
      files: files,
      sha256: '',
      note: '模拟素材，仅用于演练软件状态机和恢复流程'
    };
  }

  private static frame(elapsedMs: number, sequence: number, phase: DigitalTwinPhase,
    mount: MountState, camera: CameraState, session: TaskSession, manifest: ReplayAssetManifest,
    source: ReplayAssetSource, note: string, warning: string): DigitalTwinSnapshot {
    return {
      elapsedMs: elapsedMs,
      sequence: sequence,
      runMode: ObservationRunMode.SIMULATION,
      dataSource: source,
      phase: phase,
      mount: mount,
      camera: camera,
      session: session,
      assetManifest: DigitalTwinReplayService.copyManifest(manifest),
      note: note,
      warning: warning
    };
  }

  private static session(plan: CapturePlan, target: TaskTargetSnapshot, createdAtMs: number,
    stage: WorkflowStage, status: SessionStatus, progressPercent: number, completedFrames: number,
    detail: string, stepState: WorkflowStepState, warnings: string[],
    products: CaptureProduct[] = []): TaskSession {
    const checkpoint: WorkflowCheckpoint = {
      stage: stage,
      stepState: stepState,
      childKind: GatewaySubtaskKind.NONE,
      operationKey: '',
      childTaskId: '',
      requestStartedAtMs: 0,
      responseReceivedAtMs: 0,
      requiresManualContinue: false,
      detail: detail
    };
    return {
      id: `digital-twin-${plan.id}`,
      kind: SessionKind.SMART_LONG_EXPOSURE,
      status: status,
      stage: stage,
      progressPercent: progressPercent,
      completedFrames: completedFrames,
      plan: DigitalTwinReplayService.copyPlan(plan),
      target: DigitalTwinReplayService.copyTarget(target),
      checkpoint: checkpoint,
      gatewayTaskIds: [],
      jpegFileIds: [],
      rawFileIds: [],
      plateSolveCount: stage === WorkflowStage.PLATE_SOLVE || stage === WorkflowStage.STACK ||
        stage === WorkflowStage.COMPLETE ? 1 : 0,
      correctionCount: 0,
      products: DigitalTwinReplayService.copyProducts(products),
      warnings: warnings.slice(),
      statusDetail: detail,
      errorMessage: status === SessionStatus.INTERRUPTED ? '演练网关中断' : '',
      createdAtMs: createdAtMs,
      startedAtMs: createdAtMs,
      updatedAtMs: createdAtMs + progressPercent * 100,
      completedAtMs: status === SessionStatus.SUCCEEDED ? createdAtMs + 32000 : 0
    };
  }

  private static mount(base: MountState, slewing: boolean, homed: boolean,
    trackingMode: TrackingMode, raHours: number, decDegrees: number, updatedAtMs: number): MountState {
    return {
      connection: ConnectionState.SIMULATED,
      host: base.host,
      port: base.port,
      rightAscensionHours: raHours,
      declinationDegrees: decDegrees,
      trackingMode: trackingMode,
      slewing: slewing,
      homed: homed,
      parked: false,
      lastError: '',
      updatedAtMs: updatedAtMs
    };
  }

  private static camera(base: CameraState, busy: boolean, updatedAtMs: number): CameraState {
    return {
      connection: ConnectionState.SIMULATED,
      cameraModel: base.cameraModel,
      batteryPercent: base.batteryPercent,
      storageFreeBytes: base.storageFreeBytes,
      busy: busy,
      liveViewActive: false,
      lastError: '',
      updatedAtMs: updatedAtMs
    };
  }

  private static asset(id: string, kind: ReplayAssetKind, fileName: string,
    source: ReplayAssetSource, capturedAtMs: number, description: string): ReplayAsset {
    return {
      id: id,
      kind: kind,
      fileName: fileName,
      previewUri: '',
      source: source,
      capturedAtMs: capturedAtMs,
      sha256: '',
      description: description
    };
  }

  private static products(manifest: ReplayAssetManifest): CaptureProduct[] {
    const result: CaptureProduct[] = [];
    for (let index: number = 0; index < manifest.files.length; index++) {
      const file: ReplayAsset = manifest.files[index];
      result.push({
        kind: file.kind,
        fileName: file.fileName,
        downloadUrl: file.previewUri,
        createdAtMs: file.capturedAtMs
      });
    }
    return result;
  }

  private static assetWarning(source: ReplayAssetSource): string {
    return source === ReplayAssetSource.REAL_CAPTURE_REPLAY ?
      '真实设备历史素材 · 非实时' : '模拟素材 · 非现场实拍';
  }

  private static copyMount(state: MountState): MountState {
    return {
      connection: state.connection,
      host: state.host,
      port: state.port,
      rightAscensionHours: state.rightAscensionHours,
      declinationDegrees: state.declinationDegrees,
      trackingMode: state.trackingMode,
      slewing: state.slewing,
      homed: state.homed,
      parked: state.parked,
      lastError: state.lastError,
      updatedAtMs: state.updatedAtMs
    };
  }

  private static copyCamera(state: CameraState): CameraState {
    return {
      connection: state.connection,
      cameraModel: state.cameraModel,
      batteryPercent: state.batteryPercent,
      storageFreeBytes: state.storageFreeBytes,
      busy: state.busy,
      liveViewActive: state.liveViewActive,
      lastError: state.lastError,
      updatedAtMs: state.updatedAtMs
    };
  }

  private static copyManifest(manifest: ReplayAssetManifest): ReplayAssetManifest {
    const files: ReplayAsset[] = [];
    for (let index: number = 0; index < manifest.files.length; index++) {
      const file: ReplayAsset = manifest.files[index];
      files.push({
        id: file.id,
        kind: file.kind,
        fileName: file.fileName,
        previewUri: file.previewUri,
        source: file.source,
        capturedAtMs: file.capturedAtMs,
        sha256: file.sha256,
        description: file.description
      });
    }
    return {
      replayId: manifest.replayId,
      source: manifest.source,
      targetName: manifest.targetName,
      cameraName: manifest.cameraName,
      capturedAtMs: manifest.capturedAtMs,
      files: files,
      sha256: manifest.sha256,
      note: manifest.note
    };
  }

  private static copySession(session: TaskSession): TaskSession {
    return {
      id: session.id,
      kind: session.kind,
      status: session.status,
      stage: session.stage,
      progressPercent: session.progressPercent,
      completedFrames: session.completedFrames,
      plan: DigitalTwinReplayService.copyPlan(session.plan),
      target: DigitalTwinReplayService.copyTarget(session.target),
      checkpoint: {
        stage: session.checkpoint.stage,
        stepState: session.checkpoint.stepState,
        childKind: session.checkpoint.childKind,
        operationKey: session.checkpoint.operationKey,
        childTaskId: session.checkpoint.childTaskId,
        requestStartedAtMs: session.checkpoint.requestStartedAtMs,
        responseReceivedAtMs: session.checkpoint.responseReceivedAtMs,
        requiresManualContinue: session.checkpoint.requiresManualContinue,
        detail: session.checkpoint.detail
      },
      gatewayTaskIds: session.gatewayTaskIds.slice(),
      jpegFileIds: session.jpegFileIds.slice(),
      rawFileIds: session.rawFileIds.slice(),
      plateSolveCount: session.plateSolveCount,
      correctionCount: session.correctionCount,
      products: DigitalTwinReplayService.copyProducts(session.products),
      warnings: session.warnings.slice(),
      statusDetail: session.statusDetail,
      errorMessage: session.errorMessage,
      createdAtMs: session.createdAtMs,
      startedAtMs: session.startedAtMs,
      updatedAtMs: session.updatedAtMs,
      completedAtMs: session.completedAtMs
    };
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
      imageFormat: plan.imageFormat,
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
    let coordinate: EquatorialCoordinate | undefined = undefined;
    if (target.coordinate !== undefined) {
      coordinate = {
        raHours: target.coordinate.raHours,
        decDegrees: target.coordinate.decDegrees,
        frame: target.coordinate.frame,
        validAtMs: target.coordinate.validAtMs
      };
    }
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

  private static copyProducts(products: CaptureProduct[]): CaptureProduct[] {
    const result: CaptureProduct[] = [];
    for (let index: number = 0; index < products.length; index++) {
      result.push({
        kind: products[index].kind,
        fileName: products[index].fileName,
        downloadUrl: products[index].downloadUrl,
        createdAtMs: products[index].createdAtMs
      });
    }
    return result;
  }
}

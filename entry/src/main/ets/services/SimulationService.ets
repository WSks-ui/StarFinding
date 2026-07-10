import {
  CameraState,
  CaptureMode,
  CapturePlan,
  CaptureTask,
  ConnectionState,
  MountState,
  TaskStatus,
  TrackingMode
} from '../models/DomainModels';

export interface SimulationSnapshot {
  elapsedMs: number;
  mount: MountState;
  camera: CameraState;
  captureTask?: CaptureTask;
  note: string;
}
export type SimulationListener = (snapshot: SimulationSnapshot) => void;

/**
 * 比赛回放与无硬件联调服务。只播放明确标记为 SIMULATED 的状态，绝不冒充真实设备连接。
 */
export class SimulationService {
  private frames: SimulationSnapshot[] = [];
  private listeners: SimulationListener[] = [];
  private currentIndex: number = 0;
  private playbackRate: number = 1.0;
  private startedAtMs: number = 0;
  private startElapsedMs: number = 0;
  private timerHandle: number = -1;

  load(frames: SimulationSnapshot[]): void {
    this.pause();
    this.frames = frames.slice().sort((first: SimulationSnapshot, second: SimulationSnapshot) =>
      first.elapsedMs - second.elapsedMs);
    this.currentIndex = 0;
    if (this.frames.length > 0) {
      this.emit(this.frames[0]);
    }
  }

  loadStandardDemo(plan: CapturePlan): void {
    this.load(SimulationService.createStandardDemo(plan));
  }

  play(playbackRate: number = 1.0): void {
    if (this.frames.length === 0 || this.timerHandle >= 0) {
      return;
    }
    this.playbackRate = Math.max(0.1, Math.min(8.0, playbackRate));
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

  seek(elapsedMs: number): void {
    if (this.frames.length === 0) {
      return;
    }
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

  stop(): void {
    this.pause();
    this.currentIndex = 0;
    if (this.frames.length > 0) {
      this.emit(this.frames[0]);
    }
  }

  subscribe(listener: SimulationListener): void {
    this.listeners.push(listener);
    if (this.frames.length > 0) {
      listener(this.frames[this.currentIndex]);
    }
  }

  unsubscribe(listener: SimulationListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  current(): SimulationSnapshot | undefined {
    return this.frames.length === 0 ? undefined : this.frames[this.currentIndex];
  }

  private advance(): void {
    const elapsed: number = this.startElapsedMs + (Date.now() - this.startedAtMs) * this.playbackRate;
    while (this.currentIndex + 1 < this.frames.length &&
      this.frames[this.currentIndex + 1].elapsedMs <= elapsed) {
      this.currentIndex++;
      this.emit(this.frames[this.currentIndex]);
    }
    if (this.currentIndex >= this.frames.length - 1) {
      this.pause();
    }
  }

  private emit(snapshot: SimulationSnapshot): void {
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index](snapshot);
    }
  }

  static createStandardDemo(plan: CapturePlan): SimulationSnapshot[] {
    const now: number = Date.now();
    const camera: CameraState = {
      connection: ConnectionState.SIMULATED,
      cameraModel: 'EOS R7（回放）',
      batteryPercent: 86,
      storageFreeBytes: 64000000000,
      busy: false,
      liveViewActive: false,
      lastError: '',
      updatedAtMs: now
    };
    const mount: MountState = {
      connection: ConnectionState.SIMULATED,
      host: 'SIMULATION',
      port: 0,
      rightAscensionHours: 0.0,
      declinationDegrees: 0.0,
      trackingMode: TrackingMode.STOPPED,
      slewing: false,
      homed: true,
      parked: false,
      lastError: '',
      updatedAtMs: now
    };
    const pending: CaptureTask = SimulationService.task(plan, TaskStatus.PENDING, 0, 0,
      '等待设备', now, '');
    const slewingMount: MountState = SimulationService.mount(mount, true, TrackingMode.STOPPED,
      0.0, 0.0, now + 1000);
    const trackingMount: MountState = SimulationService.mount(mount, false, TrackingMode.SIDEREAL,
      0.7123, 41.2692, now + 5000);
    const running: CaptureTask = SimulationService.task(plan, TaskStatus.RUNNING, 35,
      Math.max(1, Math.floor(plan.frameCount * 0.35)), '短曝光采集中', now + 10000, '');
    const stacking: CaptureTask = SimulationService.task(plan, TaskStatus.RUNNING, 82,
      plan.frameCount, '星点配准与本地堆栈', now + 20000, '');
    const finished: CaptureTask = SimulationService.task(plan, TaskStatus.SUCCEEDED, 100,
      plan.frameCount, '已完成', now + 30000, '');
    return [
      { elapsedMs: 0, mount: mount, camera: camera, captureTask: pending, note: '回放：设备已发现' },
      { elapsedMs: 1000, mount: slewingMount, camera: camera, captureTask: pending, note: '回放：赤道仪 GOTO' },
      { elapsedMs: 5000, mount: trackingMount, camera: camera, captureTask: pending, note: '回放：目标已居中并开始跟踪' },
      { elapsedMs: 10000, mount: trackingMount, camera: camera, captureTask: running, note: '回放：R7 子曝光采集' },
      { elapsedMs: 20000, mount: trackingMount, camera: camera, captureTask: stacking, note: '回放：本地配准堆栈' },
      { elapsedMs: 30000, mount: trackingMount, camera: camera, captureTask: finished, note: '回放：原片、堆栈图与增强图已生成' }
    ];
  }

  private static mount(base: MountState, slewing: boolean, trackingMode: TrackingMode,
    raHours: number, decDegrees: number, updatedAtMs: number): MountState {
    return {
      connection: ConnectionState.SIMULATED,
      host: base.host,
      port: base.port,
      rightAscensionHours: raHours,
      declinationDegrees: decDegrees,
      trackingMode: trackingMode,
      slewing: slewing,
      homed: base.homed,
      parked: false,
      lastError: '',
      updatedAtMs: updatedAtMs
    };
  }

  private static task(plan: CapturePlan, status: TaskStatus, progress: number,
    completedFrames: number, stage: string, updatedAtMs: number, error: string): CaptureTask {
    return {
      id: `simulation-${plan.id}`,
      plan: plan,
      status: status,
      progressPercent: progress,
      completedFrames: completedFrames,
      currentStage: stage,
      errorMessage: error,
      products: status === TaskStatus.SUCCEEDED ? [
        { kind: 'stacked', fileName: 'simulation-stacked.jpg', downloadUrl: '', createdAtMs: updatedAtMs },
        { kind: 'enhanced', fileName: 'simulation-enhanced.jpg', downloadUrl: '', createdAtMs: updatedAtMs }
      ] : [],
      createdAtMs: updatedAtMs - progress * 100,
      updatedAtMs: updatedAtMs
    };
  }
}

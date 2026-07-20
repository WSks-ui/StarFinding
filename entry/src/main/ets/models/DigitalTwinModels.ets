import {
  CameraState,
  MountState
} from './DomainModels';
import { TaskSession } from './TaskSessionModels';

/** 应用运行域。真实设备指令只能在 REAL 域中发送。 */
export enum ObservationRunMode {
  REAL = 'real',
  SIMULATION = 'simulation'
}

/** 回放素材来源必须始终显示，禁止把历史素材或生成素材描述为现场实拍。 */
export enum ReplayAssetSource {
  REAL_CAPTURE_REPLAY = 'real_capture_replay',
  SIMULATED = 'simulated'
}

export enum ReplayAssetKind {
  RAW = 'raw',
  JPEG = 'jpeg',
  STACKED = 'stacked',
  ENHANCED = 'enhanced',
  TIMELAPSE = 'timelapse'
}

export enum DigitalTwinPhase {
  DEVICE_DISCOVERY = 'device_discovery',
  CAMERA_PREFLIGHT = 'camera_preflight',
  GOTO = 'goto',
  TRACKING = 'tracking',
  CAPTURE = 'capture',
  DOWNLOAD = 'download',
  PLATE_SOLVE = 'plate_solve',
  STACK = 'stack',
  RECOVERY = 'recovery',
  COMPLETE = 'complete',
  STOPPED = 'stopped'
}

export interface ReplayAsset {
  id: string;
  kind: ReplayAssetKind;
  fileName: string;
  previewUri: string;
  source: ReplayAssetSource;
  capturedAtMs: number;
  sha256: string;
  description: string;
}

export interface ReplayAssetManifest {
  replayId: string;
  source: ReplayAssetSource;
  targetName: string;
  cameraName: string;
  capturedAtMs: number;
  files: ReplayAsset[];
  sha256: string;
  note: string;
}

/**
 * 数字孪生快照只描述 UI 回放状态，不包含任何可执行的 TCP、HTTP 或设备命令。
 * sequence 用于拒绝乱序状态，session 也不会写入真实 TaskSessionStore。
 */
export interface DigitalTwinSnapshot {
  elapsedMs: number;
  sequence: number;
  runMode: ObservationRunMode;
  dataSource: ReplayAssetSource;
  phase: DigitalTwinPhase;
  mount: MountState;
  camera: CameraState;
  session: TaskSession;
  assetManifest: ReplayAssetManifest;
  note: string;
  warning: string;
}

export type DigitalTwinListener = (snapshot: DigitalTwinSnapshot) => void;

import { image } from '@kit.ImageKit';
import { HandLandmarks, HandPoint } from '../models/DomainModels';

/**
 * 手部关键点分析器的运行阶段。AVAILABLE 不是单独阶段：只有 READY/ANALYZING 且
 * modelLoaded=true 时，status.available 才允许为 true。
 */
export enum HandLandmarkAnalyzerState {
  UNAVAILABLE = 'unavailable',
  INITIALIZING = 'initializing',
  READY = 'ready',
  ANALYZING = 'analyzing',
  ERROR = 'error',
  CLOSED = 'closed'
}

/**
 * 手势推理后端。只有完成两个模型加载、预热和真实预测的后端才允许标记为可用。
 */
export enum HandInferenceBackend {
  NNRT_ACCELERATOR = 'NNRT_ACCELERATOR',
  NNRT_GPU = 'NNRT_GPU',
  CPU_DIAGNOSTIC = 'CPU_DIAGNOSTIC',
  UNAVAILABLE = 'UNAVAILABLE'
}

export interface HandLandmarkAnalyzerStatus {
  state: HandLandmarkAnalyzerState;
  available: boolean;
  modelLoaded: boolean;
  modelName: string;
  modelVersion: string;
  message: string;
  analyzedFrames: number;
  lastInferenceAtMs: number;
  /** 真实运行时后端；禁止根据设备枚举结果伪报加速已启用。 */
  inferenceBackend: HandInferenceBackend;
  /** NNRT 设备名称，仅在实际完成模型预热后展示。 */
  backendDeviceName: string;
  /** 用于真机性能诊断，不参与模型可用性判断。 */
  averageInferenceMs: number;
  p95InferenceMs: number;
  inferenceFps: number;
  droppedFrameCount: number;
}

/**
 * ImageReceiver 平面的自有副本。CameraHandFrameSource 在释放系统 Image 前复制完整平面，
 * 因此分析器或 Worker 可以在 analyze 的整个异步周期内安全读取，不得再持有相机原始缓冲。
 */
export interface HandImagePlane {
  buffer: ArrayBuffer;
  rowStride: number;
  pixelStride: number;
}

export interface HandYuvPlaneSet {
  yPlane: HandImagePlane;
  uPlane: HandImagePlane;
  vPlane: HandImagePlane;
}

/**
 * 将 ImageReceiver 通过 ComponentType.JPEG 暴露的整块 NV21 缓冲拆成紧凑的 Y/U/V 平面。
 *
 * HarmonyOS 部分设备对 YUV_420_SP 预览流不支持 YUV_Y/YUV_U/YUV_V 三组件访问，
 * 但会按官方 ImageReceiver 用法从 JPEG 组件返回带 rowStride 的 packed NV21。这里显式
 * 跳过每行尾部填充，并把交错 VU 色度拆开，后续 Worker 因此不需要感知设备差异。
 */
export class HandPackedNv21Decoder {
  static decode(buffer: ArrayBuffer, width: number, height: number,
    rowStride: number, pool?: HandYuvBufferPool): HandYuvPlaneSet {
    if (width <= 0 || height <= 0 || width % 2 !== 0 || height % 2 !== 0) {
      throw new Error('NV21 分析帧必须使用正数偶数宽高');
    }
    const sourceStride: number = rowStride > 0 ? rowStride : width;
    if (sourceStride < width) {
      throw new Error('NV21 行步长小于图像宽度');
    }
    const chromaHeight: number = height / 2;
    const chromaWidth: number = width / 2;
    const sourceRows: number = height + chromaHeight;
    const requiredBytes: number = (sourceRows - 1) * sourceStride + width;
    if (buffer.byteLength < requiredBytes) {
      throw new Error('NV21 缓冲长度不足');
    }

    const source: Uint8Array = new Uint8Array(buffer);
    const target: HandYuvPlaneSet = pool === undefined ?
      HandYuvBufferPool.allocate(width, height) : pool.acquire(width, height);
    const yBuffer: ArrayBuffer = target.yPlane.buffer;
    const uBuffer: ArrayBuffer = target.uPlane.buffer;
    const vBuffer: ArrayBuffer = target.vPlane.buffer;
    const y: Uint8Array = new Uint8Array(yBuffer);
    const u: Uint8Array = new Uint8Array(uBuffer);
    const v: Uint8Array = new Uint8Array(vBuffer);

    for (let row: number = 0; row < height; row++) {
      const sourceOffset: number = row * sourceStride;
      const targetOffset: number = row * width;
      for (let column: number = 0; column < width; column++) {
        y[targetOffset + column] = source[sourceOffset + column];
      }
    }

    for (let row: number = 0; row < chromaHeight; row++) {
      const sourceOffset: number = (height + row) * sourceStride;
      const targetOffset: number = row * chromaWidth;
      for (let column: number = 0; column < chromaWidth; column++) {
        // NV21 的色度顺序固定为 VU；拆平面后统一交给现有 YUV→RGB 预处理。
        v[targetOffset + column] = source[sourceOffset + column * 2];
        u[targetOffset + column] = source[sourceOffset + column * 2 + 1];
      }
    }

    return target;
  }
}

/**
 * 相机分析帧只允许串行消费，因此可以安全复用最近一帧的 Y/U/V 自有缓冲。
 * 分辨率变化时重新分配，稳定运行阶段不再为每帧创建约 1MiB 的临时平面。
 */
export class HandYuvBufferPool {
  private width: number = 0;
  private height: number = 0;
  private planes?: HandYuvPlaneSet;

  static allocate(width: number, height: number): HandYuvPlaneSet {
    const chromaWidth: number = width / 2;
    const chromaHeight: number = height / 2;
    return {
      yPlane: { buffer: new ArrayBuffer(width * height), rowStride: width, pixelStride: 1 },
      uPlane: {
        buffer: new ArrayBuffer(chromaWidth * chromaHeight),
        rowStride: chromaWidth,
        pixelStride: 1
      },
      vPlane: {
        buffer: new ArrayBuffer(chromaWidth * chromaHeight),
        rowStride: chromaWidth,
        pixelStride: 1
      }
    };
  }

  acquire(width: number, height: number): HandYuvPlaneSet {
    if (this.planes === undefined || this.width !== width || this.height !== height) {
      this.width = width;
      this.height = height;
      this.planes = HandYuvBufferPool.allocate(width, height);
    }
    return this.planes;
  }
}

/**
 * 从传感器帧映射到用户所见预览的参数。裁剪区域位于旋转后的 0–1 坐标空间，
 * 镜像最后应用且只应用一次，避免前摄点击方向与画面相反。
 */
export interface HandLandmarkPreviewTransform {
  mirrored: boolean;
  rotationDegrees: number;
  cropLeft: number;
  cropTop: number;
  cropWidth: number;
  cropHeight: number;
  /** 用户实际看到的预览宽高比，用于在归一化坐标中恢复等比例几何。 */
  previewAspectRatio: number;
}

export interface HandLandmarkFrame {
  width: number;
  height: number;
  cameraFormat: number;
  yPlane: HandImagePlane;
  uPlane: HandImagePlane;
  vPlane: HandImagePlane;
  /**
   * 兼容尚未迁移的灰度预处理代码；该缓冲与 yPlane.buffer 指向同一份自有副本，
   * 后续分析器应优先读取 yPlane，不能据此假设相机只提供亮度数据。
   */
  lumaBuffer: ArrayBuffer;
  rowStride: number;
  pixelStride: number;
  cameraTimestamp: number;
  receivedAtMs: number;
  mirrored: boolean;
  rotationDegrees: number;
  cropLeft: number;
  cropTop: number;
  cropWidth: number;
  cropHeight: number;
  previewAspectRatio: number;
  /** 每次 prepare/stop 都会推进代次，迟到推理结果必须按此值丢弃。 */
  runGeneration: number;
}

export interface HandLandmarkAnalysisResult {
  hands: HandLandmarks[];
  frameReceivedAtMs: number;
  inferenceDurationMs: number;
  /** 与本帧同一推理运行时生成，避免 UI 线程读取到跨运行时未同步的统计字段。 */
  averageInferenceMs: number;
  p95InferenceMs: number;
  inferenceFps: number;
  runGeneration: number;
  inferenceBackend: HandInferenceBackend;
  palmDetectionRan: boolean;
  roiTrackingUsed: boolean;
  droppedFrameCount: number;
}

/**
 * 把模型的传感器坐标转换为用户看到的前摄预览坐标。真实模型适配器必须在返回关键点前
 * 调用此映射，手势层因此不需要猜测相机旋转和镜像方向。
 */
export class HandLandmarkCoordinateMapper {
  static mapPoint(point: HandPoint, mirrored: boolean, rotationDegrees: number): HandPoint {
    return HandLandmarkCoordinateMapper.mapPointToPreview(point, {
      mirrored: mirrored,
      rotationDegrees: rotationDegrees,
      cropLeft: 0.0,
      cropTop: 0.0,
      cropWidth: 1.0,
      cropHeight: 1.0,
      previewAspectRatio: 1.0
    });
  }

  static mapPointToPreview(point: HandPoint, transform: HandLandmarkPreviewTransform): HandPoint {
    const quarterTurns: number = HandLandmarkCoordinateMapper.quarterTurns(transform.rotationDegrees);
    let x: number = point.x;
    let y: number = point.y;
    if (quarterTurns === 1) {
      const previousX: number = x;
      x = 1.0 - y;
      y = previousX;
    } else if (quarterTurns === 2) {
      x = 1.0 - x;
      y = 1.0 - y;
    } else if (quarterTurns === 3) {
      const previousX: number = x;
      x = y;
      y = 1.0 - previousX;
    }
    const cropWidth: number = Math.max(0.000001, transform.cropWidth);
    const cropHeight: number = Math.max(0.000001, transform.cropHeight);
    x = (x - transform.cropLeft) / cropWidth;
    y = (y - transform.cropTop) / cropHeight;
    if (transform.mirrored) {
      x = 1.0 - x;
    }
    const result: HandPoint = {
      x: HandLandmarkCoordinateMapper.clamp(x, 0.0, 1.0),
      y: HandLandmarkCoordinateMapper.clamp(y, 0.0, 1.0),
      confidence: point.confidence
    };
    if (point.z !== undefined) {
      result.z = point.z;
    }
    return result;
  }

  static mapHands(hands: HandLandmarks[], mirrored: boolean, rotationDegrees: number): HandLandmarks[] {
    return HandLandmarkCoordinateMapper.mapHandsToPreview(hands, {
      mirrored: mirrored,
      rotationDegrees: rotationDegrees,
      cropLeft: 0.0,
      cropTop: 0.0,
      cropWidth: 1.0,
      cropHeight: 1.0,
      previewAspectRatio: 1.0
    });
  }

  static mapHandsToPreview(hands: HandLandmarks[],
    transform: HandLandmarkPreviewTransform): HandLandmarks[] {
    const result: HandLandmarks[] = [];
    for (let handIndex: number = 0; handIndex < hands.length; handIndex++) {
      const points: HandPoint[] = [];
      for (let pointIndex: number = 0; pointIndex < hands[handIndex].points.length; pointIndex++) {
        points.push(HandLandmarkCoordinateMapper.mapPointToPreview(
          hands[handIndex].points[pointIndex], transform));
      }
      result.push({
        trackingId: hands[handIndex].trackingId,
        points: points,
        coordinateAspectRatio: Math.max(0.000001, transform.previewAspectRatio),
        worldPoints: hands[handIndex].worldPoints,
        confidence: hands[handIndex].confidence,
        palmConfidence: hands[handIndex].palmConfidence,
        palmFacingConfidence: hands[handIndex].palmFacingConfidence,
        timestampMs: hands[handIndex].timestampMs
      });
    }
    return result;
  }

  private static quarterTurns(rotationDegrees: number): number {
    const rounded: number = Math.round(rotationDegrees / 90.0);
    const normalized: number = rounded % 4;
    return normalized < 0 ? normalized + 4 : normalized;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

/**
 * 真实手部关键点模型的最小契约。实现方应在 initialize 中完成模型来源、许可、
 * 输入尺寸和推理后端检查；检查未通过时必须保持 available=false，不能生成占位点位。
 */
export interface HandLandmarkAnalyzer {
  initialize(): Promise<void>;
  analyze(frame: HandLandmarkFrame): Promise<HandLandmarkAnalysisResult>;
  getStatus(): HandLandmarkAnalyzerStatus;
  close(): Promise<void>;
}

/**
 * 手势模型无法加载、设备能力不足或应用上下文尚未就绪时使用的诚实降级实现。
 * 该类刻意不返回空成功结果，避免上层把“分析器不可用”误判为“画面中没有手”。
 */
export class UnavailableHandLandmarkAnalyzer implements HandLandmarkAnalyzer {
  private readonly reason: string;
  private closed: boolean = false;

  constructor(reason: string = '未配置经过许可并完成精度验收的手部关键点模型') {
    this.reason = reason;
  }

  async initialize(): Promise<void> {
    this.closed = false;
  }

  async analyze(_frame: HandLandmarkFrame): Promise<HandLandmarkAnalysisResult> {
    throw new Error(this.reason);
  }

  getStatus(): HandLandmarkAnalyzerStatus {
    return {
      state: this.closed ? HandLandmarkAnalyzerState.CLOSED : HandLandmarkAnalyzerState.UNAVAILABLE,
      available: false,
      modelLoaded: false,
      modelName: '',
      modelVersion: '',
      message: this.closed ? '手部关键点分析器已关闭' : this.reason,
      analyzedFrames: 0,
      lastInferenceAtMs: 0,
      inferenceBackend: HandInferenceBackend.UNAVAILABLE,
      backendDeviceName: '',
      averageInferenceMs: 0.0,
      p95InferenceMs: 0.0,
      inferenceFps: 0.0,
      droppedFrameCount: 0
    };
  }

  async close(): Promise<void> {
    this.closed = true;
  }
}

export enum HandFrameSourceState {
  IDLE = 'idle',
  PREPARING = 'preparing',
  READY = 'ready',
  RUNNING = 'running',
  ERROR = 'error',
  CLOSED = 'closed'
}

export interface HandFrameSourceProfile {
  width: number;
  height: number;
  cameraFormat: number;
  mirrored: boolean;
  rotationDegrees: number;
  /** 实际承载预览的组件宽高，仅用于计算 center-crop，不要求与相机像素单位相同。 */
  previewWidth: number;
  previewHeight: number;
  /** 设备没有满足模型输入尺寸的输出时，保留可运行的降级原因并回传页面。 */
  qualityWarning: string;
}

export interface HandFramePresentationProfile {
  mirrored: boolean;
  rotationDegrees: number;
  previewWidth: number;
  previewHeight: number;
}

export interface HandFrameSourceStatus {
  state: HandFrameSourceState;
  message: string;
  droppedFrames: number;
  throttledFrames: number;
  targetInferenceFps: number;
  runGeneration: number;
  analyzer: HandLandmarkAnalyzerStatus;
}

export type HandLandmarkResultListener = (result: HandLandmarkAnalysisResult) => void;
export type HandFrameSourceStatusListener = (status: HandFrameSourceStatus) => void;

/**
 * DeviceCameraPreview 使用的可插拔帧入口。模型适配器与页面解耦，后续替换成经过
 * 验收的 MindSpore Lite 实现时，不需要改动 CameraKit 会话管理。
 */
export interface HandLandmarkFrameSource {
  /** 仅加载模型，不创建 ImageReceiver，也不申请相机权限。 */
  prewarm(): Promise<HandLandmarkAnalyzerStatus>;
  prepare(profile: HandFrameSourceProfile): Promise<string>;
  updatePresentation(profile: HandFramePresentationProfile): void;
  start(): void;
  rejectCameraOutput(reason: string): Promise<void>;
  stop(): Promise<void>;
  getStatus(): HandFrameSourceStatus;
}

/**
 * 纯帧率策略，便于单元测试固定边界。50ms 最短间隔对应不高于20fps；
 * 配合相机常见30fps节拍，会稳定落在约15–20fps，且停止流程无需等待 setTimeout。
 */
export class HandFrameThrottlePolicy {
  static readonly MINIMUM_INFERENCE_INTERVAL_MS: number = 50.0;

  static shouldStartInference(nowMs: number, lastStartedAtMs: number,
    minimumIntervalMs: number = HandFrameThrottlePolicy.MINIMUM_INFERENCE_INTERVAL_MS): boolean {
    if (lastStartedAtMs <= 0.0) {
      return true;
    }
    return nowMs - lastStartedAtMs >= Math.max(0.0, minimumIntervalMs);
  }
}

/**
 * 掌心检测刷新策略：首帧必须完整检测，稳定跟踪时每12帧或500ms重新校正一次。
 * 作为纯函数公开，便于在没有相机和模型的 Hypium 环境验证边界。
 */
export class HandPalmRefreshPolicy {
  static readonly DEFAULT_REFRESH_FRAMES: number = 12;
  static readonly DEFAULT_REFRESH_INTERVAL_MS: number = 500.0;

  static shouldRun(hasRoi: boolean, trackingFrameCount: number,
    lastPalmDetectionAtMs: number, timestampMs: number,
    refreshFrames: number = HandPalmRefreshPolicy.DEFAULT_REFRESH_FRAMES,
    refreshIntervalMs: number = HandPalmRefreshPolicy.DEFAULT_REFRESH_INTERVAL_MS): boolean {
    if (!hasRoi || trackingFrameCount <= 0 || lastPalmDetectionAtMs < 0.0) {
      return true;
    }
    return trackingFrameCount >= Math.max(1, refreshFrames) ||
      timestampMs - lastPalmDetectionAtMs >= Math.max(1.0, refreshIntervalMs);
  }
}

/**
 * 将 CameraKit 的预览 Surface 转成 ImageReceiver 帧，再交给真实分析器。
 * API 22 的 PreviewOutput 只提供 frameStart/frameEnd 时序事件，不携带像素；
 * 因而这里使用受支持的 Surface + imageArrival 路径获取实际 YUV 数据。
 */
export class CameraHandFrameSource implements HandLandmarkFrameSource {
  private readonly analyzer: HandLandmarkAnalyzer;
  private readonly resultListener?: HandLandmarkResultListener;
  private readonly statusListener?: HandFrameSourceStatusListener;
  private readonly yuvBufferPool: HandYuvBufferPool = new HandYuvBufferPool();
  private receiver?: image.ImageReceiver;
  private profile?: HandFrameSourceProfile;
  private receiverArrivalCallback?: () => void;
  private state: HandFrameSourceState = HandFrameSourceState.IDLE;
  private message: string = '等待前摄分析输出';
  private droppedFrames: number = 0;
  private throttledFrames: number = 0;
  private runGeneration: number = 0;
  private presentationRevision: number = 0;
  private lastInferenceStartedAtMs: number = 0.0;
  private active: boolean = false;
  private processing: boolean = false;
  private processingTask?: Promise<void>;
  private prewarmTask?: Promise<void>;
  private framePending: boolean = false;
  private imageArrivalCount: number = 0;
  private imageReadCount: number = 0;

  constructor(analyzer: HandLandmarkAnalyzer, resultListener?: HandLandmarkResultListener,
    statusListener?: HandFrameSourceStatusListener) {
    this.analyzer = analyzer;
    this.resultListener = resultListener;
    this.statusListener = statusListener;
  }

  async prewarm(): Promise<HandLandmarkAnalyzerStatus> {
    const current: HandLandmarkAnalyzerStatus = this.analyzer.getStatus();
    if (current.available && current.modelLoaded &&
      current.state === HandLandmarkAnalyzerState.READY) {
      return current;
    }

    let task: Promise<void> | undefined = this.prewarmTask;
    if (task === undefined) {
      task = this.analyzer.initialize();
      this.prewarmTask = task;
    }
    try {
      await task;
    } finally {
      if (this.prewarmTask === task) {
        this.prewarmTask = undefined;
      }
    }
    return this.analyzer.getStatus();
  }

  async prepare(profile: HandFrameSourceProfile): Promise<string> {
    this.active = false;
    const generation: number = ++this.runGeneration;
    console.info(`[StarFindingHandFrame] prepare begin generation=${generation}, ` +
      `${profile.width}x${profile.height}, cameraFormat=${profile.cameraFormat}`);
    await this.waitForProcessing();
    await this.releaseReceiver();
    this.state = HandFrameSourceState.PREPARING;
    this.message = '正在初始化手部关键点分析器';
    this.emitStatus();
    const analyzerStatus: HandLandmarkAnalyzerStatus = await this.prewarm();
    if (!analyzerStatus.available || !analyzerStatus.modelLoaded ||
      analyzerStatus.state !== HandLandmarkAnalyzerState.READY) {
      this.state = HandFrameSourceState.ERROR;
      this.message = analyzerStatus.message.length > 0 ? analyzerStatus.message : '手部关键点模型不可用';
      this.emitStatus();
      throw new Error(this.message);
    }
    if (profile.width <= 0 || profile.height <= 0) {
      this.state = HandFrameSourceState.ERROR;
      this.message = '前摄分析帧尺寸无效';
      this.emitStatus();
      throw new Error(this.message);
    }

    this.profile = this.normalizedProfile(profile);
    this.presentationRevision++;
    this.lastInferenceStartedAtMs = 0.0;
    try {
      this.receiver = this.createAnalysisReceiver(profile);
      console.info(`[StarFindingHandFrame] ImageReceiver created format=${this.receiver.format}, ` +
        `size=${this.receiver.size.width}x${this.receiver.size.height}`);
      const arrivalCallback = (): void => {
        this.onImageArrival(generation);
      };
      this.receiverArrivalCallback = arrivalCallback;
      this.receiver.on('imageArrival', arrivalCallback);
      const surfaceId: string = await this.receiver.getReceivingSurfaceId();
      if (surfaceId.length === 0) {
        throw new Error('ImageReceiver 未返回有效 Surface');
      }
      if (generation !== this.runGeneration) {
        throw new Error('前摄分析帧入口已过期');
      }
      this.state = HandFrameSourceState.READY;
      this.message = '前摄分析帧入口已就绪';
      this.imageArrivalCount = 0;
      this.imageReadCount = 0;
      console.info(`[StarFindingHandFrame] receiver surface ready generation=${generation}`);
      this.emitStatus();
      return surfaceId;
    } catch (error) {
      console.error(`[StarFindingHandFrame] prepare failed: ${this.errorMessage(error, 'unknown')}`);
      await this.releaseReceiver();
      this.state = HandFrameSourceState.ERROR;
      this.message = this.errorMessage(error, '无法创建前摄分析帧入口');
      this.emitStatus();
      throw new Error(this.message);
    }
  }

  private createAnalysisReceiver(profile: HandFrameSourceProfile): image.ImageReceiver {
    // API 22 仍需使用自 API 9 起提供的数字重载；这里声明 ImageFormat.JPEG 是因为
    // ImageReceiver 的 format 参数只接受 ImageFormat 常量，后续通过 ComponentType.JPEG
    // 取得 packed NV21。实际生产者仍由 CameraKit 的 YUV_420_SP PreviewProfile 决定，
    // 因此不会把分析 Surface 误切换成 JPEG 相机流。
    return image.createImageReceiver(
      profile.width,
      profile.height,
      image.ImageFormat.JPEG,
      2
    );
  }

  updatePresentation(profile: HandFramePresentationProfile): void {
    const current: HandFrameSourceProfile | undefined = this.profile;
    if (current === undefined) {
      return;
    }
    const next: HandFrameSourceProfile = this.normalizedProfile({
      width: current.width,
      height: current.height,
      cameraFormat: current.cameraFormat,
      mirrored: profile.mirrored,
      rotationDegrees: profile.rotationDegrees,
      previewWidth: profile.previewWidth,
      previewHeight: profile.previewHeight,
      qualityWarning: current.qualityWarning
    });
    if (this.samePresentation(current, next)) {
      return;
    }
    this.profile = next;
    this.presentationRevision++;
  }

  start(): void {
    if (this.receiver === undefined || this.state !== HandFrameSourceState.READY) {
      this.state = HandFrameSourceState.ERROR;
      this.message = '前摄分析帧入口尚未就绪';
      this.emitStatus();
      throw new Error(this.message);
    }
    this.active = true;
    console.info(`[StarFindingHandFrame] start generation=${this.runGeneration}`);
    this.state = HandFrameSourceState.RUNNING;
    const profile: HandFrameSourceProfile | undefined = this.profile;
    this.message = profile !== undefined && profile.qualityWarning.length > 0 ?
      `手部关键点分析运行中；${profile.qualityWarning}` : '手部关键点分析运行中';
    this.emitStatus();
  }

  async rejectCameraOutput(reason: string): Promise<void> {
    console.error(`[StarFindingHandFrame] reject camera output: ${reason}`);
    this.active = false;
    this.runGeneration++;
    await this.waitForProcessing();
    await this.releaseReceiver();
    this.state = HandFrameSourceState.ERROR;
    this.message = reason;
    this.emitStatus();
  }

  async stop(): Promise<void> {
    console.info(`[StarFindingHandFrame] stop generation=${this.runGeneration}`);
    this.active = false;
    this.runGeneration++;
    await this.waitForProcessing();
    await this.releaseReceiver();
    if (this.state !== HandFrameSourceState.ERROR) {
      this.state = HandFrameSourceState.IDLE;
      this.message = '前摄分析已停止';
    }
    this.emitStatus();
  }

  getStatus(): HandFrameSourceStatus {
    return {
      state: this.state,
      message: this.message,
      droppedFrames: this.droppedFrames,
      throttledFrames: this.throttledFrames,
      targetInferenceFps: 1000.0 / HandFrameThrottlePolicy.MINIMUM_INFERENCE_INTERVAL_MS,
      runGeneration: this.runGeneration,
      analyzer: this.analyzer.getStatus()
    };
  }

  async close(): Promise<void> {
    console.info(`[StarFindingHandFrame] close generation=${this.runGeneration}`);
    this.active = false;
    this.runGeneration++;
    await this.waitForProcessing();
    await this.releaseReceiver();
    await this.analyzer.close();
    this.state = HandFrameSourceState.CLOSED;
    this.message = '前摄分析帧入口已关闭';
    this.emitStatus();
  }

  private onImageArrival(generation: number): void {
    if (!this.active || generation !== this.runGeneration) {
      return;
    }
    this.imageArrivalCount++;
    if (this.imageArrivalCount <= 3 || this.imageArrivalCount % 30 === 0) {
      console.info(`[StarFindingHandFrame] imageArrival count=${this.imageArrivalCount}, ` +
        `processing=${this.processing}, pending=${this.framePending}`);
    }
    if (!this.processing && !HandFrameThrottlePolicy.shouldStartInference(
      Date.now(), this.lastInferenceStartedAtMs)) {
      this.droppedFrames++;
      this.throttledFrames++;
      return;
    }
    if (this.framePending) {
      // readLatestImage 会直接取得最新帧，已经挂起的旧帧在这里视为主动丢弃。
      this.droppedFrames++;
    }
    this.framePending = true;
    if (!this.processing) {
      this.processingTask = this.consumePendingFrames(generation);
    }
  }

  private async consumePendingFrames(generation: number): Promise<void> {
    this.processing = true;
    try {
      while (this.active && generation === this.runGeneration && this.framePending) {
        const nowMs: number = Date.now();
        if (!HandFrameThrottlePolicy.shouldStartInference(nowMs, this.lastInferenceStartedAtMs)) {
          this.framePending = false;
          this.droppedFrames++;
          this.throttledFrames++;
          break;
        }
        this.framePending = false;
        this.lastInferenceStartedAtMs = nowMs;
        await this.consumeLatestFrame(generation, this.presentationRevision);
      }
    } finally {
      this.processing = false;
      this.processingTask = undefined;
    }
  }

  private async consumeLatestFrame(generation: number, presentationRevision: number): Promise<void> {
    const receiver: image.ImageReceiver | undefined = this.receiver;
    const profile: HandFrameSourceProfile | undefined = this.profile;
    if (receiver === undefined || profile === undefined || generation !== this.runGeneration) {
      return;
    }
    let cameraImage: image.Image | undefined = undefined;
    let frame: HandLandmarkFrame | undefined = undefined;
    try {
      cameraImage = await receiver.readLatestImage();
      this.imageReadCount++;
      if (this.imageReadCount <= 3 || this.imageReadCount % 30 === 0) {
        console.info(`[StarFindingHandFrame] image read count=${this.imageReadCount}, ` +
          `size=${cameraImage.size.width}x${cameraImage.size.height}, format=${cameraImage.format}`);
      }
      const planes: HandYuvPlaneSet = await this.copyCameraYuvPlanes(cameraImage);
      const transform: HandLandmarkPreviewTransform =
        this.buildPreviewTransform(cameraImage.size.width, cameraImage.size.height, profile);
      frame = {
        width: cameraImage.size.width,
        height: cameraImage.size.height,
        cameraFormat: cameraImage.format,
        yPlane: planes.yPlane,
        uPlane: planes.uPlane,
        vPlane: planes.vPlane,
        lumaBuffer: planes.yPlane.buffer,
        rowStride: planes.yPlane.rowStride,
        pixelStride: planes.yPlane.pixelStride,
        cameraTimestamp: cameraImage.timestamp,
        receivedAtMs: Date.now(),
        mirrored: transform.mirrored,
        rotationDegrees: transform.rotationDegrees,
        cropLeft: transform.cropLeft,
        cropTop: transform.cropTop,
        cropWidth: transform.cropWidth,
        cropHeight: transform.cropHeight,
        previewAspectRatio: transform.previewAspectRatio,
        runGeneration: generation
      };
    } catch (error) {
      console.error(`[StarFindingHandFrame] image read failed generation=${generation}: ` +
        `${this.errorMessage(error, 'unknown')}`);
      this.failCurrentGeneration(generation, this.errorMessage(error, '无法读取前摄 YUV 帧'));
    } finally {
      if (cameraImage !== undefined) {
        try {
          await cameraImage.release();
        } catch (error) {
          // 相机会话结束时系统可能已回收缓冲，不覆盖前面的真实推理状态。
        }
      }
    }

    // Image 已经释放，后续异步推理只访问上面复制出的 Y/U/V 自有缓冲。
    if (frame === undefined || !this.active || generation !== this.runGeneration ||
      presentationRevision !== this.presentationRevision) {
      return;
    }
    try {
      const result: HandLandmarkAnalysisResult = await this.analyzer.analyze(frame);
      if (!this.active || generation !== this.runGeneration || result.runGeneration !== generation ||
        presentationRevision !== this.presentationRevision) {
        return;
      }
      if (this.resultListener !== undefined) {
        // 将帧源的真实丢帧计数补到结果快照，页面不需要拼接两个异步状态。
        this.resultListener({
          hands: result.hands,
          frameReceivedAtMs: result.frameReceivedAtMs,
          inferenceDurationMs: result.inferenceDurationMs,
          averageInferenceMs: result.averageInferenceMs,
          p95InferenceMs: result.p95InferenceMs,
          inferenceFps: result.inferenceFps,
          runGeneration: result.runGeneration,
          inferenceBackend: result.inferenceBackend,
          palmDetectionRan: result.palmDetectionRan,
          roiTrackingUsed: result.roiTrackingUsed,
          droppedFrameCount: this.droppedFrames
        });
      }
    } catch (error) {
      const reason: string = this.errorMessage(error, '手部关键点推理失败');
      // 推理错误会让页面按诚实降级策略卸载前摄；必须在卸载前记录原始原因，
      // 否则日志只会看到 aboutToDisappear，难以区分模型输出、NAPI 句柄或预处理故障。
      console.error(`[StarFindingHandFrame] analyze failed generation=${generation}: ${reason}`);
      this.failCurrentGeneration(generation, reason);
    }
  }

  private async copyCameraYuvPlanes(cameraImage: image.Image): Promise<HandYuvPlaneSet> {
    let packedFailure: string = '';
    try {
      // 对 YUV_420_SP 预览流，部分 HarmonyOS 真机把整块 NV21 数据放在 JPEG 组件中。
      // 该名称来自 ImageReceiver 历史 API，并不表示这里拿到的是压缩 JPEG 文件。
      const packed: image.Component = await cameraImage.getComponent(image.ComponentType.JPEG);
      return HandPackedNv21Decoder.decode(
        packed.byteBuffer,
        cameraImage.size.width,
        cameraImage.size.height,
        packed.rowStride,
        this.yuvBufferPool
      );
    } catch (error) {
      packedFailure = this.errorMessage(error, 'packed NV21 不可读');
    }

    try {
      // 保留支持三平面访问的设备路径，确保 API 22/24 以及不同厂商实现均可工作。
      const luma: image.Component = await cameraImage.getComponent(image.ComponentType.YUV_Y);
      const chromaU: image.Component = await cameraImage.getComponent(image.ComponentType.YUV_U);
      const chromaV: image.Component = await cameraImage.getComponent(image.ComponentType.YUV_V);
      return {
        yPlane: this.copyPlane(luma),
        uPlane: this.copyPlane(chromaU),
        vPlane: this.copyPlane(chromaV)
      };
    } catch (error) {
      const planarFailure: string = this.errorMessage(error, 'YUV 三平面不可读');
      throw new Error(`${packedFailure}；${planarFailure}`);
    }
  }

  private async releaseReceiver(): Promise<void> {
    const receiver: image.ImageReceiver | undefined = this.receiver;
    const arrivalCallback: (() => void) | undefined = this.receiverArrivalCallback;
    this.receiver = undefined;
    this.receiverArrivalCallback = undefined;
    this.profile = undefined;
    this.framePending = false;
    if (receiver === undefined) {
      return;
    }
    try {
      if (arrivalCallback !== undefined) {
        receiver.off('imageArrival', arrivalCallback);
      }
    } catch (error) {
    }
    try {
      await receiver.release();
    } catch (error) {
    }
  }

  private copyPlane(component: image.Component): HandImagePlane {
    const source: Uint8Array = new Uint8Array(component.byteBuffer);
    const ownedBuffer: ArrayBuffer = new ArrayBuffer(source.length);
    const owned: Uint8Array = new Uint8Array(ownedBuffer);
    owned.set(source);
    return {
      buffer: ownedBuffer,
      rowStride: component.rowStride,
      pixelStride: component.pixelStride
    };
  }

  private normalizedProfile(profile: HandFrameSourceProfile): HandFrameSourceProfile {
    const roundedQuarterTurns: number = Math.round(profile.rotationDegrees / 90.0);
    const normalizedQuarterTurns: number = ((roundedQuarterTurns % 4) + 4) % 4;
    const normalizedRotation: number = normalizedQuarterTurns * 90.0;
    return {
      width: profile.width,
      height: profile.height,
      cameraFormat: profile.cameraFormat,
      mirrored: profile.mirrored,
      rotationDegrees: normalizedRotation,
      previewWidth: Math.max(1.0, profile.previewWidth),
      previewHeight: Math.max(1.0, profile.previewHeight),
      qualityWarning: profile.qualityWarning
    };
  }

  private samePresentation(first: HandFrameSourceProfile, second: HandFrameSourceProfile): boolean {
    return first.mirrored === second.mirrored &&
      first.rotationDegrees === second.rotationDegrees &&
      Math.abs(first.previewWidth - second.previewWidth) < 0.01 &&
      Math.abs(first.previewHeight - second.previewHeight) < 0.01;
  }

  private buildPreviewTransform(frameWidth: number, frameHeight: number,
    profile: HandFrameSourceProfile): HandLandmarkPreviewTransform {
    const quarterTurns: number = ((Math.round(profile.rotationDegrees / 90.0) % 4) + 4) % 4;
    const rotatedWidth: number = quarterTurns % 2 === 0 ? frameWidth : frameHeight;
    const rotatedHeight: number = quarterTurns % 2 === 0 ? frameHeight : frameWidth;
    const sourceAspect: number = rotatedWidth / Math.max(1.0, rotatedHeight);
    const previewAspect: number = profile.previewWidth / Math.max(1.0, profile.previewHeight);
    let cropLeft: number = 0.0;
    let cropTop: number = 0.0;
    let cropWidth: number = 1.0;
    let cropHeight: number = 1.0;
    if (sourceAspect > previewAspect) {
      cropWidth = previewAspect / sourceAspect;
      cropLeft = (1.0 - cropWidth) / 2.0;
    } else if (sourceAspect < previewAspect) {
      cropHeight = sourceAspect / previewAspect;
      cropTop = (1.0 - cropHeight) / 2.0;
    }
    return {
      mirrored: profile.mirrored,
      rotationDegrees: profile.rotationDegrees,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      previewAspectRatio: previewAspect
    };
  }

  private failCurrentGeneration(generation: number, reason: string): void {
    if (generation !== this.runGeneration) {
      return;
    }
    console.error(`[StarFindingHandFrame] generation failed generation=${generation}, reason=${reason}`);
    this.state = HandFrameSourceState.ERROR;
    this.message = reason;
    this.active = false;
    this.emitStatus();
  }

  private async waitForProcessing(): Promise<void> {
    const task: Promise<void> | undefined = this.processingTask;
    if (task === undefined) {
      return;
    }
    try {
      await task;
    } catch (error) {
      // consumePendingFrames 会把真实错误写入运行状态；停止流程仍需继续释放相机资源。
    }
  }

  private emitStatus(): void {
    if (this.statusListener !== undefined) {
      this.statusListener(this.getStatus());
    }
  }

  private errorMessage(error: Object, fallback: string): string {
    if (error instanceof Error && error.message.length > 0) {
      return `${fallback}：${error.message}`;
    }
    return fallback;
  }
}

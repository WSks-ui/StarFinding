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

export interface HandLandmarkAnalyzerStatus {
  state: HandLandmarkAnalyzerState;
  available: boolean;
  modelLoaded: boolean;
  modelName: string;
  modelVersion: string;
  message: string;
  analyzedFrames: number;
  lastInferenceAtMs: number;
}

/**
 * 相机帧的亮度平面。当前手势只需要几何关键点，亮度平面可避免复制完整 YUV 帧。
 * 分析器必须在 analyze 返回前完成对 lumaBuffer 的读取；返回后相机缓冲会立即释放。
 */
export interface HandLandmarkFrame {
  width: number;
  height: number;
  cameraFormat: number;
  lumaBuffer: ArrayBuffer;
  rowStride: number;
  pixelStride: number;
  cameraTimestamp: number;
  receivedAtMs: number;
  mirrored: boolean;
  rotationDegrees: number;
}

export interface HandLandmarkAnalysisResult {
  hands: HandLandmarks[];
  frameReceivedAtMs: number;
  inferenceDurationMs: number;
}

/**
 * 把模型的传感器坐标转换为用户看到的前摄预览坐标。真实模型适配器必须在返回关键点前
 * 调用此映射，手势层因此不需要猜测相机旋转和镜像方向。
 */
export class HandLandmarkCoordinateMapper {
  static mapPoint(point: HandPoint, mirrored: boolean, rotationDegrees: number): HandPoint {
    const quarterTurns: number = HandLandmarkCoordinateMapper.quarterTurns(rotationDegrees);
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
    if (mirrored) {
      x = 1.0 - x;
    }
    return {
      x: HandLandmarkCoordinateMapper.clamp(x, 0.0, 1.0),
      y: HandLandmarkCoordinateMapper.clamp(y, 0.0, 1.0),
      confidence: point.confidence
    };
  }

  static mapHands(hands: HandLandmarks[], mirrored: boolean, rotationDegrees: number): HandLandmarks[] {
    const result: HandLandmarks[] = [];
    for (let handIndex: number = 0; handIndex < hands.length; handIndex++) {
      const points: HandPoint[] = [];
      for (let pointIndex: number = 0; pointIndex < hands[handIndex].points.length; pointIndex++) {
        points.push(HandLandmarkCoordinateMapper.mapPoint(
          hands[handIndex].points[pointIndex], mirrored, rotationDegrees));
      }
      result.push({
        trackingId: hands[handIndex].trackingId,
        points: points,
        confidence: hands[handIndex].confidence,
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
 * 当前仓库未包含经过许可和精度验收的手部关键点模型，因此默认实现始终不可用。
 * 该类刻意不返回空成功结果，避免上层把“没有模型”误判为“画面中没有手”。
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
      lastInferenceAtMs: 0
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
}

export interface HandFrameSourceStatus {
  state: HandFrameSourceState;
  message: string;
  droppedFrames: number;
  analyzer: HandLandmarkAnalyzerStatus;
}

export type HandLandmarkResultListener = (result: HandLandmarkAnalysisResult) => void;
export type HandFrameSourceStatusListener = (status: HandFrameSourceStatus) => void;

/**
 * DeviceCameraPreview 使用的可插拔帧入口。模型适配器与页面解耦，后续替换成经过
 * 验收的 MindSpore Lite 实现时，不需要改动 CameraKit 会话管理。
 */
export interface HandLandmarkFrameSource {
  prepare(profile: HandFrameSourceProfile): Promise<string>;
  start(): void;
  rejectCameraOutput(reason: string): Promise<void>;
  stop(): Promise<void>;
  getStatus(): HandFrameSourceStatus;
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
  private receiver?: image.ImageReceiver;
  private profile?: HandFrameSourceProfile;
  private state: HandFrameSourceState = HandFrameSourceState.IDLE;
  private message: string = '等待前摄分析输出';
  private droppedFrames: number = 0;
  private active: boolean = false;
  private processing: boolean = false;
  private processingTask?: Promise<void>;
  private framePending: boolean = false;

  private readonly imageArrivalCallback = (): void => {
    if (!this.active) {
      return;
    }
    this.framePending = true;
    if (!this.processing) {
      this.processingTask = this.consumePendingFrames();
    }
  };

  constructor(analyzer: HandLandmarkAnalyzer, resultListener?: HandLandmarkResultListener,
    statusListener?: HandFrameSourceStatusListener) {
    this.analyzer = analyzer;
    this.resultListener = resultListener;
    this.statusListener = statusListener;
  }

  async prepare(profile: HandFrameSourceProfile): Promise<string> {
    this.active = false;
    await this.waitForProcessing();
    await this.releaseReceiver();
    this.state = HandFrameSourceState.PREPARING;
    this.message = '正在初始化手部关键点分析器';
    this.emitStatus();
    await this.analyzer.initialize();
    const analyzerStatus: HandLandmarkAnalyzerStatus = this.analyzer.getStatus();
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

    this.profile = profile;
    try {
      // 采用接收器的 number 重载，以便传入 CameraKit 的 YUV_420_SP(1003) 格式值。
      // 新版 ImageFormat 枚举没有列出 1003，但 CameraKit 预览能力实际返回该格式。
      this.receiver = image.createImageReceiver(profile.width, profile.height, profile.cameraFormat, 2);
      this.receiver.on('imageArrival', this.imageArrivalCallback);
      const surfaceId: string = await this.receiver.getReceivingSurfaceId();
      if (surfaceId.length === 0) {
        throw new Error('ImageReceiver 未返回有效 Surface');
      }
      this.state = HandFrameSourceState.READY;
      this.message = '前摄分析帧入口已就绪';
      this.emitStatus();
      return surfaceId;
    } catch (error) {
      await this.releaseReceiver();
      this.state = HandFrameSourceState.ERROR;
      this.message = this.errorMessage(error, '无法创建前摄分析帧入口');
      this.emitStatus();
      throw new Error(this.message);
    }
  }

  start(): void {
    if (this.receiver === undefined || this.state !== HandFrameSourceState.READY) {
      return;
    }
    this.active = true;
    this.state = HandFrameSourceState.RUNNING;
    this.message = '手部关键点分析运行中';
    this.emitStatus();
  }

  async rejectCameraOutput(reason: string): Promise<void> {
    this.active = false;
    await this.waitForProcessing();
    await this.releaseReceiver();
    this.state = HandFrameSourceState.ERROR;
    this.message = reason;
    this.emitStatus();
  }

  async stop(): Promise<void> {
    this.active = false;
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
      analyzer: this.analyzer.getStatus()
    };
  }

  async close(): Promise<void> {
    this.active = false;
    await this.waitForProcessing();
    await this.releaseReceiver();
    await this.analyzer.close();
    this.state = HandFrameSourceState.CLOSED;
    this.message = '前摄分析帧入口已关闭';
    this.emitStatus();
  }

  private async consumePendingFrames(): Promise<void> {
    this.processing = true;
    try {
      while (this.active && this.framePending) {
        this.framePending = false;
        await this.consumeLatestFrame();
        if (this.framePending) {
          this.droppedFrames++;
        }
      }
    } finally {
      this.processing = false;
      this.processingTask = undefined;
    }
  }

  private async consumeLatestFrame(): Promise<void> {
    const receiver: image.ImageReceiver | undefined = this.receiver;
    const profile: HandFrameSourceProfile | undefined = this.profile;
    if (receiver === undefined || profile === undefined) {
      return;
    }
    let cameraImage: image.Image | undefined = undefined;
    try {
      cameraImage = await receiver.readLatestImage();
      const luma: image.Component = await cameraImage.getComponent(image.ComponentType.YUV_Y);
      const frame: HandLandmarkFrame = {
        width: cameraImage.size.width,
        height: cameraImage.size.height,
        cameraFormat: cameraImage.format,
        lumaBuffer: luma.byteBuffer,
        rowStride: luma.rowStride,
        pixelStride: luma.pixelStride,
        cameraTimestamp: cameraImage.timestamp,
        receivedAtMs: Date.now(),
        mirrored: profile.mirrored,
        rotationDegrees: profile.rotationDegrees
      };
      const result: HandLandmarkAnalysisResult = await this.analyzer.analyze(frame);
      if (this.resultListener !== undefined) {
        this.resultListener(result);
      }
    } catch (error) {
      this.state = HandFrameSourceState.ERROR;
      this.message = this.errorMessage(error, '手部关键点推理失败');
      this.active = false;
      this.emitStatus();
    } finally {
      if (cameraImage !== undefined) {
        try {
          await cameraImage.release();
        } catch (error) {
          // 相机会话结束时系统可能已回收缓冲，不覆盖前面的真实推理状态。
        }
      }
    }
  }

  private async releaseReceiver(): Promise<void> {
    const receiver: image.ImageReceiver | undefined = this.receiver;
    this.receiver = undefined;
    this.profile = undefined;
    this.framePending = false;
    if (receiver === undefined) {
      return;
    }
    try {
      receiver.off('imageArrival', this.imageArrivalCallback);
    } catch (error) {
    }
    try {
      await receiver.release();
    } catch (error) {
    }
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

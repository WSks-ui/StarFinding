import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { HandLandmarks } from '../models/DomainModels';
import {
  HandLandmarkAnalysisResult,
  HandLandmarkAnalyzer,
  HandLandmarkAnalyzerState,
  HandLandmarkAnalyzerStatus,
  HandLandmarkCoordinateMapper,
  HandLandmarkFrame,
  HandLandmarkPreviewTransform,
  HandInferenceBackend,
  HandPalmRefreshPolicy
} from './HandLandmarkAnalyzer';
import {
  HandModelArtifact,
  HandModelManifest,
  HandModelManifestService,
  HandModelReadinessResult,
  HandTensorSpecification
} from './HandModelManifest';
import {
  HandRegionOfInterest,
  MediaPipeHandPipeline,
  PalmDetection
} from './MediaPipeHandPipeline';
import {
  buildLandmarkTensorBuffer,
  buildPalmTensorBuffer
} from './HandImagePreprocessMath';

interface PalmModelOutputs {
  boxes: Float32Array;
  scores: Float32Array;
}

interface LandmarkModelOutputs {
  landmarks: Float32Array;
  presenceScore: number;
  handednessScore: number;
  worldLandmarks: Float32Array;
}

interface NnrtCandidate {
  backend: HandInferenceBackend;
  deviceId: bigint;
  deviceName: string;
}

interface LoadedModelPair {
  palmModel: mindSporeLite.Model;
  landmarkModel: mindSporeLite.Model;
  palmInputs: mindSporeLite.MSTensor[];
  landmarkInputs: mindSporeLite.MSTensor[];
  palmInputByteLength: number;
  landmarkInputByteLength: number;
}

/**
 * 使用 HarmonyOS 内置 MindSpore Lite 执行官方 MediaPipe Hands Lite 两阶段模型。
 *
 * ArkTS 的 MindSpore Model 不是 Sendable。API 24 真机还会在 TaskPool 预处理完成后
 * 访问输入张量时偶发 NAPI 句柄失效，因此这里将低分辨率（320×240）预处理与模型
 * 调用保持在同一 JS 线程；相机预览仍由 CameraKit 独立线程输出，不会阻塞取景。
 */
export class MindSporeLiteHandLandmarkAnalyzer implements HandLandmarkAnalyzer {
  private static readonly PALM_REFRESH_FRAMES: number = 12;
  private static readonly PALM_REFRESH_INTERVAL_MS: number = 500;
  private static readonly ALLOW_CPU_DIAGNOSTIC: boolean = false;
  private readonly context: common.Context;
  private readonly manifest: HandModelManifest = HandModelManifestService.manifest();
  private readonly pipeline: MediaPipeHandPipeline = new MediaPipeHandPipeline();
  private state: HandLandmarkAnalyzerState = HandLandmarkAnalyzerState.UNAVAILABLE;
  private message: string = '等待加载离线手部模型';
  private palmModel: mindSporeLite.Model | undefined = undefined;
  private landmarkModel: mindSporeLite.Model | undefined = undefined;
  /**
   * API 24 真机在模型完成一次异步 predict 后，再次调用 model.getInputs() 会偶发
   * “GetInputs failed to get model”。输入张量在初始化线程一次性取得并复用，
   * 同时减少每帧重复创建 ArkTS 张量包装对象的开销。
   */
  private palmInputs: mindSporeLite.MSTensor[] | undefined = undefined;
  private landmarkInputs: mindSporeLite.MSTensor[] | undefined = undefined;
  private palmInputByteLength: number = 0;
  private landmarkInputByteLength: number = 0;
  /**
   * 首帧运行时绑定不能再次访问 UIAbilityContext.resourceManager，也不能跨运行时
   * 传递 Uint8Array（真机会丢失 TypedArray internal slot）。预热阶段把已校验的
   * 模型写入应用缓存目录；后续只传递纯字符串路径，并在当前运行时重新读取。
   */
  private palmArtifactPath: string = '';
  private landmarkArtifactPath: string = '';
  private initializationTask: Promise<void> | undefined = undefined;
  /**
   * 预热阶段和 Camera imageArrival 回调可能属于不同的 ArkTS/NAPI 运行时。
   * Model/MSTensor 不是 Sendable，因而不能把预热阶段拿到的句柄直接交给
   * 首帧回调。这里按一次前摄分析会话重新绑定句柄，确保加载、setData、
   * predict 都在同一运行时上下文中完成。
   */
  private boundRunGeneration: number = -1;
  private bindingTask: Promise<void> | undefined = undefined;
  private lifecycleGeneration: number = 0;
  private analyzedFrames: number = 0;
  private lastInferenceAtMs: number = 0;
  private firstInferenceAtMs: number = 0;
  private totalInferenceDurationMs: number = 0.0;
  private readonly inferenceDurationsMs: number[] = [];
  private trackingId: number = 1;
  private lastHandSeenAtMs: number = -1;
  private backend: HandInferenceBackend = HandInferenceBackend.UNAVAILABLE;
  private backendDeviceName: string = '';
  private trackingRoi?: HandRegionOfInterest;
  private trackingFrameCount: number = 0;
  private lastPalmDetectionAtMs: number = -1;
  /**
   * 模型输入张量在整个分析会话内复用。分析源保证 analyze 串行执行，
   * 因而不会出现下一帧覆盖上一帧仍在 predict 的情况。
   */
  private readonly palmInputTensor: Float32Array =
    new Float32Array(MediaPipeHandPipeline.PALM_INPUT_SIZE *
      MediaPipeHandPipeline.PALM_INPUT_SIZE * 3);
  private readonly landmarkInputTensor: Float32Array =
    new Float32Array(MediaPipeHandPipeline.LANDMARK_INPUT_SIZE *
      MediaPipeHandPipeline.LANDMARK_INPUT_SIZE * 3);

  constructor(context: common.Context) {
    this.context = context;
  }

  async initialize(): Promise<void> {
    if (this.state === HandLandmarkAnalyzerState.READY &&
      this.palmModel !== undefined && this.landmarkModel !== undefined &&
      this.palmInputs !== undefined && this.landmarkInputs !== undefined) {
      return;
    }
    const existing: Promise<void> | undefined = this.initializationTask;
    if (existing !== undefined) {
      await existing;
      return;
    }
    const generation: number = ++this.lifecycleGeneration;
    this.state = HandLandmarkAnalyzerState.INITIALIZING;
    this.message = '正在校验并预热离线手部模型';
    const task: Promise<void> = this.initializeInternal(generation);
    this.initializationTask = task;
    try {
      await task;
    } catch (error) {
      if (generation === this.lifecycleGeneration) {
        this.palmModel = undefined;
        this.landmarkModel = undefined;
        this.palmInputs = undefined;
        this.landmarkInputs = undefined;
        this.palmInputByteLength = 0;
        this.landmarkInputByteLength = 0;
        this.state = HandLandmarkAnalyzerState.ERROR;
        this.message = this.errorMessage(error, '离线手部模型初始化失败');
      }
      throw new Error(this.message);
    } finally {
      if (this.initializationTask === task) {
        this.initializationTask = undefined;
      }
    }
  }

  async analyze(frame: HandLandmarkFrame): Promise<HandLandmarkAnalysisResult> {
    await this.initialize();
    await this.bindToAnalysisRuntime(frame.runGeneration);
    const palmModel: mindSporeLite.Model | undefined = this.palmModel;
    const landmarkModel: mindSporeLite.Model | undefined = this.landmarkModel;
    const palmInputs: mindSporeLite.MSTensor[] | undefined = this.palmInputs;
    const landmarkInputs: mindSporeLite.MSTensor[] | undefined = this.landmarkInputs;
    if (palmModel === undefined || landmarkModel === undefined ||
      palmInputs === undefined || landmarkInputs === undefined ||
      this.state === HandLandmarkAnalyzerState.CLOSED) {
      throw new Error('离线手部模型尚未就绪');
    }
    this.validateFrame(frame);
    const generation: number = this.lifecycleGeneration;
    const startedAtMs: number = Date.now();
    this.state = HandLandmarkAnalyzerState.ANALYZING;
    this.message = '正在执行手部关键点推理';
    try {
      const shouldRunPalm: boolean = this.shouldRefreshPalm(frame.receivedAtMs);
      let roi: HandRegionOfInterest | undefined = this.trackingRoi;
      if (shouldRunPalm) {
        const palmInputBuffer: ArrayBuffer = buildPalmTensorBuffer(
          frame.yPlane.buffer, frame.yPlane.rowStride, frame.yPlane.pixelStride,
          frame.uPlane.buffer, frame.uPlane.rowStride, frame.uPlane.pixelStride,
          frame.vPlane.buffer, frame.vPlane.rowStride, frame.vPlane.pixelStride,
          frame.width, frame.height, MediaPipeHandPipeline.PALM_INPUT_SIZE,
          this.palmInputTensor);
        this.ensureGeneration(generation);
        const palmOutputs: mindSporeLite.MSTensor[] =
          await this.predict(palmModel, palmInputs, this.palmInputByteLength, palmInputBuffer);
        const decodedPalmOutputs: PalmModelOutputs = this.palmOutputs(palmOutputs);
        const detection: PalmDetection | undefined = this.pipeline.decodeBestPalm(
          decodedPalmOutputs.boxes, decodedPalmOutputs.scores, frame.width, frame.height);
        if (detection === undefined) {
          this.clearTracking();
          return this.finishFrame([], frame, startedAtMs, generation, true, false);
        }
        roi = this.pipeline.regionOfInterest(detection, frame.width, frame.height);
        if (roi === undefined) {
          this.clearTracking();
          return this.finishFrame([], frame, startedAtMs, generation, true, false);
        }
        this.lastPalmDetectionAtMs = frame.receivedAtMs;
        this.trackingFrameCount = 0;
      }
      if (roi === undefined) {
        return this.finishFrame([], frame, startedAtMs, generation, shouldRunPalm, false);
      }
      const landmarkInputBuffer: ArrayBuffer = buildLandmarkTensorBuffer(
        frame.yPlane.buffer, frame.yPlane.rowStride, frame.yPlane.pixelStride,
        frame.uPlane.buffer, frame.uPlane.rowStride, frame.uPlane.pixelStride,
        frame.vPlane.buffer, frame.vPlane.rowStride, frame.vPlane.pixelStride,
        frame.width, frame.height, MediaPipeHandPipeline.LANDMARK_INPUT_SIZE,
        roi.centerX, roi.centerY, roi.width, roi.height, roi.rotationRadians,
        this.landmarkInputTensor);
      this.ensureGeneration(generation);
      const landmarkOutputs: mindSporeLite.MSTensor[] =
        await this.predict(landmarkModel, landmarkInputs, this.landmarkInputByteLength, landmarkInputBuffer);
      const decodedLandmarkOutputs: LandmarkModelOutputs =
        this.landmarkOutputs(landmarkOutputs);
      this.updateTrackingId(frame.receivedAtMs);
      const hand: HandLandmarks | undefined = this.pipeline.decodeLandmarks(
        decodedLandmarkOutputs.landmarks,
        decodedLandmarkOutputs.presenceScore,
        decodedLandmarkOutputs.worldLandmarks,
        roi, this.trackingId, frame.receivedAtMs);
      if (hand === undefined) {
        this.clearTracking();
        return this.finishFrame([], frame, startedAtMs, generation, shouldRunPalm, !shouldRunPalm);
      }
      const nextRoi: HandRegionOfInterest | undefined =
        this.pipeline.regionOfInterestFromLandmarks(hand, frame.width, frame.height);
      if (nextRoi === undefined) {
        this.clearTracking();
        return this.finishFrame([], frame, startedAtMs, generation, shouldRunPalm, !shouldRunPalm);
      }
      this.trackingRoi = nextRoi;
      this.trackingFrameCount++;
      this.lastHandSeenAtMs = frame.receivedAtMs;
      const transform: HandLandmarkPreviewTransform = {
        mirrored: frame.mirrored,
        rotationDegrees: frame.rotationDegrees,
        cropLeft: frame.cropLeft,
        cropTop: frame.cropTop,
        cropWidth: frame.cropWidth,
        cropHeight: frame.cropHeight,
        previewAspectRatio: frame.previewAspectRatio
      };
      const mappedHands: HandLandmarks[] =
        HandLandmarkCoordinateMapper.mapHandsToPreview([hand], transform);
      return this.finishFrame(mappedHands, frame, startedAtMs, generation, shouldRunPalm, !shouldRunPalm);
    } catch (error) {
      if (generation === this.lifecycleGeneration && !this.isClosed()) {
        this.state = HandLandmarkAnalyzerState.ERROR;
        this.message = this.errorMessage(error, '手部关键点推理失败');
      }
      throw new Error(this.message);
    }
  }

  getStatus(): HandLandmarkAnalyzerStatus {
    const modelLoaded: boolean = this.palmModel !== undefined && this.landmarkModel !== undefined;
    const available: boolean = modelLoaded &&
      (this.state === HandLandmarkAnalyzerState.READY ||
      this.state === HandLandmarkAnalyzerState.ANALYZING);
    let averageInferenceMs: number = 0.0;
    if (this.analyzedFrames > 0) {
      averageInferenceMs = this.totalInferenceDurationMs / this.analyzedFrames;
    }
    let inferenceFps: number = 0.0;
    if (this.analyzedFrames > 1 && this.lastInferenceAtMs > this.firstInferenceAtMs) {
      inferenceFps = (this.analyzedFrames - 1) * 1000.0 /
        (this.lastInferenceAtMs - this.firstInferenceAtMs);
    }
    let p95InferenceMs: number = 0.0;
    if (this.inferenceDurationsMs.length > 0) {
      const sorted: number[] = this.inferenceDurationsMs.slice().sort(
        (left: number, right: number): number => left - right);
      const index: number = Math.min(sorted.length - 1,
        Math.floor((sorted.length - 1) * 0.95));
      p95InferenceMs = sorted[index];
    }
    return {
      state: this.state,
      available: available,
      modelLoaded: modelLoaded,
      modelName: this.manifest.pipelineName,
      modelVersion: this.manifest.pipelineVersion,
      message: this.message,
      analyzedFrames: this.analyzedFrames,
      lastInferenceAtMs: this.lastInferenceAtMs,
      inferenceBackend: this.backend,
      backendDeviceName: this.backendDeviceName,
      averageInferenceMs: averageInferenceMs,
      p95InferenceMs: p95InferenceMs,
      inferenceFps: inferenceFps,
      droppedFrameCount: 0
    };
  }

  async close(): Promise<void> {
    this.lifecycleGeneration++;
    this.boundRunGeneration = -1;
    this.palmModel = undefined;
    this.landmarkModel = undefined;
    this.palmInputs = undefined;
    this.landmarkInputs = undefined;
    this.palmInputByteLength = 0;
    this.landmarkInputByteLength = 0;
    this.backend = HandInferenceBackend.UNAVAILABLE;
    this.backendDeviceName = '';
    this.clearTracking();
    this.state = HandLandmarkAnalyzerState.CLOSED;
    this.message = '手部关键点分析器已关闭';
  }

  /**
   * 将模型句柄绑定到当前前摄分析会话。
   *
   * 说明：API 24 真机的 MindSpore Lite NAPI 包装对象带有创建它的运行时
   * 上下文。页面预热发生在普通页面任务中，而 imageArrival 的首帧通常从
   * 相机回调任务进入；跨上下文复用会表现为 SetData/GetInputs 的 NAPI
   * 句柄错误。因此即使模型已经 READY，也要在每次新的 runGeneration
   * 首帧重新加载一次。模型文件仍是离线固定资源，不产生网络请求。
   */
  private async bindToAnalysisRuntime(runGeneration: number): Promise<void> {
    if (this.boundRunGeneration === runGeneration &&
      this.palmModel !== undefined && this.landmarkModel !== undefined &&
      this.palmInputs !== undefined && this.landmarkInputs !== undefined) {
      return;
    }
    const existing: Promise<void> | undefined = this.bindingTask;
    if (existing !== undefined) {
      await existing;
      if (this.boundRunGeneration === runGeneration) {
        return;
      }
    }

    const generation: number = ++this.lifecycleGeneration;
    this.boundRunGeneration = -1;
    this.palmModel = undefined;
    this.landmarkModel = undefined;
    this.palmInputs = undefined;
    this.landmarkInputs = undefined;
    this.palmInputByteLength = 0;
    this.landmarkInputByteLength = 0;
    this.state = HandLandmarkAnalyzerState.INITIALIZING;
    this.message = '正在将手部模型绑定到前摄分析线程';
    const task: Promise<void> = this.initializeInternal(generation);
    this.bindingTask = task;
    try {
      await task;
      this.ensureGeneration(generation);
      this.boundRunGeneration = runGeneration;
    } catch (error) {
      if (generation === this.lifecycleGeneration && !this.isClosed()) {
        this.state = HandLandmarkAnalyzerState.ERROR;
        this.message = this.errorMessage(error, '手部模型运行时绑定失败');
      }
      throw new Error(this.message);
    } finally {
      if (this.bindingTask === task) {
        this.bindingTask = undefined;
      }
    }
  }

  private async initializeInternal(generation: number): Promise<void> {
    const palmBytes: Uint8Array = await this.artifactBytes(
      this.manifest.palmDetector, this.palmArtifactPath);
    const landmarkBytes: Uint8Array = await this.artifactBytes(
      this.manifest.handLandmark, this.landmarkArtifactPath);
    this.ensureGeneration(generation);

    const candidates: NnrtCandidate[] = this.nnrtCandidates();
    let loaded: LoadedModelPair | undefined = undefined;
    let failureMessage: string = '当前设备没有可用的 NNRT Accelerator/GPU 后端';
    for (let index: number = 0; index < candidates.length; index++) {
      const candidate: NnrtCandidate = candidates[index];
      try {
        loaded = await this.loadModelPair(
          palmBytes, landmarkBytes, this.nnrtContext(candidate.deviceId));
        this.ensureGeneration(generation);
        this.backend = candidate.backend;
        this.backendDeviceName = candidate.deviceName;
        break;
      } catch (error) {
        failureMessage = `${candidate.deviceName}：${this.errorMessage(error, '模型不支持')}`;
      }
    }

    if (loaded === undefined && MindSporeLiteHandLandmarkAnalyzer.ALLOW_CPU_DIAGNOSTIC) {
      const cpuDevice: mindSporeLite.CpuDevice = {
        threadNum: 2,
        threadAffinityMode: mindSporeLite.ThreadAffinityMode.BIG_CORES_FIRST
      };
      try {
        loaded = await this.loadModelPair(
          palmBytes, landmarkBytes, { target: ['cpu'], cpu: cpuDevice });
        this.backend = HandInferenceBackend.CPU_DIAGNOSTIC;
        this.backendDeviceName = 'CPU（开发诊断）';
      } catch (error) {
        failureMessage = this.errorMessage(error, failureMessage);
      }
    }

    if (loaded === undefined) {
      this.backend = HandInferenceBackend.UNAVAILABLE;
      this.backendDeviceName = '';
      throw new Error(`${failureMessage}；实时手势已关闭，触控操作仍可用`);
    }
    this.palmModel = loaded.palmModel;
    this.landmarkModel = loaded.landmarkModel;
    this.palmInputs = loaded.palmInputs;
    this.landmarkInputs = loaded.landmarkInputs;
    this.palmInputByteLength = loaded.palmInputByteLength;
    this.landmarkInputByteLength = loaded.landmarkInputByteLength;
    this.clearTracking();
    this.state = HandLandmarkAnalyzerState.READY;
    this.message = `${this.backendDeviceName}已加载两个模型并完成真实预热`;
  }

  private nnrtCandidates(): NnrtCandidate[] {
    const descriptions: mindSporeLite.NNRTDeviceDescription[] =
      mindSporeLite.getAllNNRTDeviceDescriptions();
    const accelerators: NnrtCandidate[] = [];
    const gpus: NnrtCandidate[] = [];
    for (let index: number = 0; index < descriptions.length; index++) {
      const description: mindSporeLite.NNRTDeviceDescription = descriptions[index];
      const deviceType: mindSporeLite.NNRTDeviceType = description.deviceType();
      const candidate: NnrtCandidate = {
        backend: deviceType === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR ?
          HandInferenceBackend.NNRT_ACCELERATOR : HandInferenceBackend.NNRT_GPU,
        deviceId: description.deviceID(),
        deviceName: description.deviceName()
      };
      if (deviceType === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR) {
        accelerators.push(candidate);
      } else if (deviceType === mindSporeLite.NNRTDeviceType.NNRTDEVICE_GPU) {
        gpus.push(candidate);
      }
    }
    return accelerators.concat(gpus);
  }

  private nnrtContext(deviceId: bigint): mindSporeLite.Context {
    return {
      target: ['nnrt'],
      nnrt: {
        deviceID: deviceId,
        performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH,
        priority: mindSporeLite.Priority.PRIORITY_HIGH
      }
    };
  }

  private async loadModelPair(palmBytes: Uint8Array, landmarkBytes: Uint8Array,
    modelContext: mindSporeLite.Context): Promise<LoadedModelPair> {
    const loadedPalmModel: mindSporeLite.Model = await mindSporeLite.loadModelFromBuffer(
      this.exactArrayBuffer(palmBytes), modelContext);
    const loadedLandmarkModel: mindSporeLite.Model = await mindSporeLite.loadModelFromBuffer(
      this.exactArrayBuffer(landmarkBytes), modelContext);
    const palmInputs: mindSporeLite.MSTensor[] = loadedPalmModel.getInputs();
    const landmarkInputs: mindSporeLite.MSTensor[] = loadedLandmarkModel.getInputs();
    const palmInput: HandTensorSpecification =
      this.singleInputSpecification(palmInputs, '掌心检测');
    const landmarkInput: HandTensorSpecification =
      this.singleInputSpecification(landmarkInputs, '手部关键点');
    const palmWarmupOutputs: mindSporeLite.MSTensor[] =
      await this.warmupModel(loadedPalmModel, palmInputs, palmInput.elementNum);
    const landmarkWarmupOutputs: mindSporeLite.MSTensor[] =
      await this.warmupModel(loadedLandmarkModel, landmarkInputs, landmarkInput.elementNum);
    const readiness: HandModelReadinessResult = HandModelManifestService.evaluateReadiness(
      palmBytes.length > 0, landmarkBytes.length > 0,
      palmInput, landmarkInput,
      this.tensorSpecifications(palmWarmupOutputs),
      this.tensorSpecifications(landmarkWarmupOutputs));
    if (!readiness.available) {
      throw new Error(readiness.message);
    }
    return {
      palmModel: loadedPalmModel,
      landmarkModel: loadedLandmarkModel,
      palmInputs: palmInputs,
      landmarkInputs: landmarkInputs,
      palmInputByteLength: palmInput.elementNum * 4,
      landmarkInputByteLength: landmarkInput.elementNum * 4
    };
  }

  /**
   * 第一次调用从资源管理器读取并校验；之后的运行时重绑定只复用已复制的
   * 字节，避免在 Camera imageArrival 的 NAPI 上下文中解包 UI 资源对象。
   */
  private async artifactBytes(artifact: HandModelArtifact,
    cachedPath: string): Promise<Uint8Array> {
    if (cachedPath.length > 0) {
      return this.readArtifactFile(cachedPath, artifact);
    }
    const loaded: Uint8Array = await this.loadAndVerifyArtifact(artifact);
    const cachePath: string = this.writeArtifactFile(artifact, loaded);
    if (artifact.rawFileName === this.manifest.palmDetector.rawFileName) {
      this.palmArtifactPath = cachePath;
    } else {
      this.landmarkArtifactPath = cachePath;
    }
    return loaded;
  }

  /**
   * 使用应用缓存目录作为跨 ArkTS 运行时的稳定边界。读文件产生的 ArrayBuffer
   * 和 Uint8Array 都在当前相机回调运行时创建，不再携带资源管理器的 NAPI 句柄。
   */
  private writeArtifactFile(artifact: HandModelArtifact, bytes: Uint8Array): string {
    const directory: string = `${this.context.cacheDir}/starfinding-hand-models`;
    try {
      fileIo.mkdirSync(directory, true);
    } catch (error) {
      // 目录已经存在时系统返回 File exists，继续打开目标文件即可。
    }
    const fileName: string = artifact.rawFileName.replace(/\//g, '_');
    const path: string = `${directory}/${fileName}`;
    const file = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const written: number = fileIo.writeSync(file.fd, this.exactArrayBuffer(bytes));
      if (written !== bytes.length) {
        throw new Error(`${artifact.displayName} 缓存文件写入不完整`);
      }
    } finally {
      fileIo.closeSync(file.fd);
    }
    return path;
  }

  private readArtifactFile(path: string, artifact: HandModelArtifact): Uint8Array {
    const stat = fileIo.statSync(path);
    if (stat.size <= 0) {
      throw new Error(`${artifact.displayName} 缓存文件为空`);
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const readLength: number = fileIo.readSync(file.fd, buffer);
      if (readLength !== stat.size) {
        throw new Error(`${artifact.displayName} 缓存文件读取不完整`);
      }
    } finally {
      fileIo.closeSync(file.fd);
    }
    const bytes: Uint8Array = new Uint8Array(buffer);
    if (this.sha256(bytes) !== artifact.convertedSha256) {
      throw new Error(`${artifact.displayName} 缓存文件 SHA-256 不匹配`);
    }
    return bytes;
  }

  private async loadAndVerifyArtifact(artifact: HandModelArtifact): Promise<Uint8Array> {
    let bytes: Uint8Array;
    try {
      bytes = await this.context.resourceManager.getRawFileContent(artifact.rawFileName);
    } catch (error) {
      throw new Error(`读取 ${artifact.displayName} 失败：${this.errorMessage(error, '资源不存在')}`);
    }
    if (bytes.length === 0) {
      throw new Error(`${artifact.displayName} 资源为空`);
    }
    const actualHash: string = this.sha256(bytes);
    if (actualHash !== artifact.convertedSha256) {
      throw new Error(`${artifact.displayName} SHA-256 不匹配`);
    }
    return bytes;
  }

  private sha256(bytes: Uint8Array): string {
    const digest: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    const input: cryptoFramework.DataBlob = {
      data: bytes
    };
    digest.updateSync(input);
    const output: cryptoFramework.DataBlob = digest.digestSync();
    let result: string = '';
    for (let index: number = 0; index < output.data.length; index++) {
      const value: number = output.data[index];
      if (value < 16) {
        result += '0';
      }
      result += value.toString(16);
    }
    return result.toUpperCase();
  }

  private exactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const buffer: ArrayBuffer = new ArrayBuffer(bytes.length);
    const copy: Uint8Array = new Uint8Array(buffer);
    copy.set(bytes);
    return buffer;
  }

  private singleInputSpecification(inputs: mindSporeLite.MSTensor[],
    label: string): HandTensorSpecification {
    if (inputs.length !== 1) {
      throw new Error(`${label}模型输入数量应为 1，实际为 ${inputs.length}`);
    }
    if (inputs[0].dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32) {
      throw new Error(`${label}模型输入必须为 Float32`);
    }
    return this.tensorSpecification(inputs[0]);
  }

  private async warmupModel(model: mindSporeLite.Model,
    inputs: mindSporeLite.MSTensor[], inputElementCount: number): Promise<mindSporeLite.MSTensor[]> {
    const warmupBuffer: ArrayBuffer = new ArrayBuffer(inputElementCount * 4);
    inputs[0].setData(warmupBuffer);
    return await model.predict(inputs);
  }

  private async predict(model: mindSporeLite.Model,
    inputs: mindSporeLite.MSTensor[], expectedByteLength: number,
    inputBuffer: ArrayBuffer): Promise<mindSporeLite.MSTensor[]> {
    // 不读取 MSTensor.dataSize：API 24 在异步 predict 后偶发返回 NAPI tensor error。
    // 规格已在 initialize() 中完成校验，按固定元素数做纯 ArkTS 长度检查即可。
    if (inputs.length !== 1 || expectedByteLength !== inputBuffer.byteLength) {
      throw new Error('模型输入缓冲大小与张量规格不一致');
    }
    inputs[0].setData(inputBuffer);
    return await model.predict(inputs);
  }

  private tensorSpecifications(tensors: mindSporeLite.MSTensor[]): HandTensorSpecification[] {
    const result: HandTensorSpecification[] = [];
    for (let index: number = 0; index < tensors.length; index++) {
      result.push(this.tensorSpecification(tensors[index]));
    }
    return result;
  }

  private tensorSpecification(tensor: mindSporeLite.MSTensor): HandTensorSpecification {
    const shape: number[] = [];
    for (let index: number = 0; index < tensor.shape.length; index++) {
      shape.push(tensor.shape[index]);
    }
    return {
      name: tensor.name,
      shape: shape,
      elementNum: tensor.elementNum
    };
  }

  private palmOutputs(tensors: mindSporeLite.MSTensor[]): PalmModelOutputs {
    let boxes: Float32Array | undefined = undefined;
    let scores: Float32Array | undefined = undefined;
    for (let index: number = 0; index < tensors.length; index++) {
      const tensor: mindSporeLite.MSTensor = tensors[index];
      if (tensor.dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32) {
        continue;
      }
      if (tensor.elementNum === MediaPipeHandPipeline.PALM_BOX_COUNT *
        MediaPipeHandPipeline.PALM_COORDINATE_COUNT) {
        boxes = new Float32Array(tensor.getData());
      } else if (tensor.elementNum === MediaPipeHandPipeline.PALM_BOX_COUNT) {
        scores = new Float32Array(tensor.getData());
      }
    }
    if (boxes === undefined || scores === undefined) {
      throw new Error('掌心检测模型输出张量不匹配');
    }
    return {
      boxes: boxes,
      scores: scores
    };
  }

  private landmarkOutputs(tensors: mindSporeLite.MSTensor[]): LandmarkModelOutputs {
    let landmarks: Float32Array | undefined = undefined;
    let worldLandmarks: Float32Array | undefined = undefined;
    let presenceScore: number | undefined = undefined;
    let handednessScore: number | undefined = undefined;
    const sixtyThreeElementTensors: mindSporeLite.MSTensor[] = [];
    const scalarTensors: mindSporeLite.MSTensor[] = [];
    for (let index: number = 0; index < tensors.length; index++) {
      const tensor: mindSporeLite.MSTensor = tensors[index];
      if (tensor.dtype !== mindSporeLite.DataType.NUMBER_TYPE_FLOAT32) {
        continue;
      }
      if (tensor.elementNum === 63) {
        sixtyThreeElementTensors.push(tensor);
        if (tensor.name === 'Identity_3' || tensor.name.endsWith('/Identity_3')) {
          worldLandmarks = new Float32Array(tensor.getData());
        } else if (tensor.name === 'Identity' || tensor.name.endsWith('/Identity')) {
          landmarks = new Float32Array(tensor.getData());
        }
      } else if (tensor.elementNum === 1) {
        scalarTensors.push(tensor);
        const value: number = new Float32Array(tensor.getData())[0];
        if (tensor.name === 'Identity_1' || tensor.name.endsWith('/Identity_1')) {
          presenceScore = value;
        } else if (tensor.name === 'Identity_2' || tensor.name.endsWith('/Identity_2')) {
          handednessScore = value;
        }
      }
    }

    /*
     * 两个 .ms 文件的来源、转换器版本和 SHA-256 已固定，因此输出顺序也是受版本约束的：
     * 图像关键点、存在分、左右手分、世界关键点。不同 MindSpore Lite 运行时可能保留
     * Identity 名称、添加作用域，也可能生成完全不同但非空的名称。先按语义名称解析，
     * 缺失项再按固定顺序补齐，避免仅因张量名差异把已经通过规格校验的模型判为不可用。
     */
    if (landmarks === undefined && sixtyThreeElementTensors.length > 0) {
      landmarks = new Float32Array(sixtyThreeElementTensors[0].getData());
    }
    if (worldLandmarks === undefined && sixtyThreeElementTensors.length > 1) {
      worldLandmarks = new Float32Array(sixtyThreeElementTensors[1].getData());
    }
    if (presenceScore === undefined && scalarTensors.length > 0) {
      presenceScore = new Float32Array(scalarTensors[0].getData())[0];
    }
    if (handednessScore === undefined && scalarTensors.length > 1) {
      handednessScore = new Float32Array(scalarTensors[1].getData())[0];
    }
    if (landmarks === undefined || worldLandmarks === undefined ||
      presenceScore === undefined || handednessScore === undefined) {
      throw new Error('手部关键点模型输出张量不匹配');
    }
    return {
      landmarks: landmarks,
      presenceScore: presenceScore,
      handednessScore: handednessScore,
      worldLandmarks: worldLandmarks
    };
  }

  private finishFrame(hands: HandLandmarks[], frame: HandLandmarkFrame,
    startedAtMs: number, generation: number, palmDetectionRan: boolean,
    roiTrackingUsed: boolean): HandLandmarkAnalysisResult {
    this.ensureGeneration(generation);
    const completedAtMs: number = Date.now();
    const durationMs: number = Math.max(0.0, completedAtMs - startedAtMs);
    this.analyzedFrames++;
    this.totalInferenceDurationMs += durationMs;
    this.lastInferenceAtMs = completedAtMs;
    if (this.firstInferenceAtMs === 0) {
      this.firstInferenceAtMs = completedAtMs;
    }
    this.inferenceDurationsMs.push(durationMs);
    if (this.inferenceDurationsMs.length > 120) {
      this.inferenceDurationsMs.shift();
    }
    this.state = HandLandmarkAnalyzerState.READY;
    this.message = hands.length > 0 ? '已识别一只手' : '未检测到可靠手部';
    return {
      hands: hands,
      frameReceivedAtMs: frame.receivedAtMs,
      inferenceDurationMs: durationMs,
      runGeneration: frame.runGeneration,
      inferenceBackend: this.backend,
      palmDetectionRan: palmDetectionRan,
      roiTrackingUsed: roiTrackingUsed,
      droppedFrameCount: 0
    };
  }

  private shouldRefreshPalm(timestampMs: number): boolean {
    return HandPalmRefreshPolicy.shouldRun(
      this.trackingRoi !== undefined,
      this.trackingFrameCount,
      this.lastPalmDetectionAtMs,
      timestampMs,
      MindSporeLiteHandLandmarkAnalyzer.PALM_REFRESH_FRAMES,
      MindSporeLiteHandLandmarkAnalyzer.PALM_REFRESH_INTERVAL_MS);
  }

  private clearTracking(): void {
    if (this.trackingRoi !== undefined || this.lastHandSeenAtMs >= 0) {
      this.trackingId++;
      if (this.trackingId > 2147483640) {
        this.trackingId = 1;
      }
    }
    this.trackingRoi = undefined;
    this.trackingFrameCount = 0;
    this.lastPalmDetectionAtMs = -1;
    this.lastHandSeenAtMs = -1;
  }

  private updateTrackingId(timestampMs: number): void {
    if (this.lastHandSeenAtMs >= 0 && timestampMs - this.lastHandSeenAtMs > 150) {
      this.trackingId++;
      if (this.trackingId > 2147483640) {
        this.trackingId = 1;
      }
    }
  }

  private validateFrame(frame: HandLandmarkFrame): void {
    if (frame.width <= 0 || frame.height <= 0 ||
      frame.yPlane.buffer.byteLength === 0 ||
      frame.uPlane.buffer.byteLength === 0 ||
      frame.vPlane.buffer.byteLength === 0 ||
      frame.yPlane.rowStride <= 0 || frame.yPlane.pixelStride <= 0 ||
      frame.uPlane.rowStride <= 0 || frame.uPlane.pixelStride <= 0 ||
      frame.vPlane.rowStride <= 0 || frame.vPlane.pixelStride <= 0) {
      throw new Error('前摄 YUV 三平面规格无效');
    }
  }

  private ensureGeneration(generation: number): void {
    if (generation !== this.lifecycleGeneration ||
      this.state === HandLandmarkAnalyzerState.CLOSED) {
      throw new Error('手部模型运行已取消');
    }
  }

  /**
   * 独立方法避免 ArkTS 把 analyze() 中刚写入的 ANALYZING 状态永久窄化，
   * close() 可能在异步 predict 等待期间改变真实运行状态。
   */
  private isClosed(): boolean {
    return this.state === HandLandmarkAnalyzerState.CLOSED;
  }

  private errorMessage(error: Object, fallback: string): string {
    if (error instanceof Error && error.message.length > 0) {
      return `${fallback}：${error.message}`;
    }
    return fallback;
  }
}

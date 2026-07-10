import { http } from '@kit.NetworkKit';
import {
  CameraCapabilities,
  CameraState,
  CaptureMode,
  CapturePlan,
  CaptureProduct,
  CaptureTask,
  ConnectionState,
  GatewayEndpointConfig,
  GatewayHealth,
  HttpServiceResult,
  ImageFormat,
  PlateSolveResult,
  TaskStatus
} from '../models/DomainModels';

interface GatewayCameraStatusDto {
  connected: boolean;
  backend: string;
  simulated: boolean;
  model: string | null;
  battery: string | null;
  detail: string | null;
}

interface GatewayCameraCapabilitiesDto {
  backend: string;
  liveview: boolean;
  raw_jpeg: boolean;
  bulb: boolean;
  max_exposure_seconds: number;
  iso_values: string[];
  aperture_values: string[];
  shutter_values: string[];
}

interface GatewayPlateSolverHealthDto {
  backend: string;
  simulated: boolean;
}

interface GatewayFfmpegHealthDto {
  available: boolean;
  binary: string;
}

interface GatewayHealthDto {
  status: string;
  version: string;
  camera: GatewayCameraStatusDto;
  plate_solver: GatewayPlateSolverHealthDto;
  ffmpeg: GatewayFfmpegHealthDto;
  database: string;
}

interface GatewayCaptureRequestDto {
  iso: string;
  aperture: string;
  exposure_seconds: number;
  count: number;
  interval_seconds: number;
  raw_jpeg: boolean;
  label: string;
}

interface GatewayPlateSolveRequestDto {
  file_id: string;
  hint_ra_deg?: number;
  hint_dec_deg?: number;
  search_radius_deg: number;
  pixel_scale_low?: number;
  pixel_scale_high?: number;
}

interface GatewayStackRequestDto {
  file_ids: string[];
  reject_bad_frames: boolean;
  correct_light_pollution: boolean;
  output_format: string;
}

interface GatewayTimelapseRequestDto {
  file_ids: string[];
  fps: number;
  width: number;
  height: number;
}

interface GatewayTaskInputDto {
  iso?: string;
  aperture?: string;
  exposure_seconds?: number;
  count?: number;
  interval_seconds?: number;
  raw_jpeg?: boolean;
  label?: string;
  file_id?: string;
  file_ids?: string[];
  fps?: number;
}

interface GatewayFileDto {
  id: string;
  task_id: string | null;
  name: string;
  mime_type: string;
  size: number;
  kind: string;
  created_at: string;
}

interface GatewayPlateSolveResultDto {
  solved: boolean;
  backend: string;
  simulated: boolean;
  ra_deg: number | null;
  dec_deg: number | null;
  rotation_deg: number | null;
  pixel_scale_arcsec: number | null;
  field_width_deg: number | null;
  field_height_deg: number | null;
  detail: string | null;
}

interface GatewayTaskOutputDto {
  files?: GatewayFileDto[];
  captured_frames?: number;
  backend?: string;
  simulated?: boolean;
  plate_solve?: GatewayPlateSolveResultDto;
  file?: GatewayFileDto;
  accepted_count?: number;
  frame_count?: number;
}

interface GatewayTaskDto {
  id: string;
  type: string;
  status: string;
  progress: number;
  message: string;
  input: GatewayTaskInputDto;
  output: GatewayTaskOutputDto | null;
  error: string | null;
  idempotency_key: string | null;
  created_at: string;
  updated_at: string;
}

/** 网关通用后台任务，供板解析、堆栈和延时摄影共用。 */
export interface GatewayTask {
  id: string;
  type: string;
  status: TaskStatus;
  progressPercent: number;
  message: string;
  errorMessage: string;
  files: GatewayFile[];
  capturedFrames: number;
  createdAtMs: number;
  updatedAtMs: number;
}

/** 网关文件元数据。downloadUrl 由客户端根据文件 ID 安全构造。 */
export interface GatewayFile {
  id: string;
  taskId: string;
  name: string;
  mimeType: string;
  sizeBytes: number;
  kind: string;
  downloadUrl: string;
  createdAtMs: number;
}

export interface PlateSolveOptions {
  hintRaHours?: number;
  hintDecDegrees?: number;
  searchRadiusDegrees?: number;
  pixelScaleLowArcSeconds?: number;
  pixelScaleHighArcSeconds?: number;
}

export enum StackOutputFormat {
  JPEG = 'jpeg',
  PNG = 'png'
}

export interface StackOptions {
  rejectBadFrames?: boolean;
  correctLightPollution?: boolean;
  outputFormat?: StackOutputFormat;
}

export interface TimelapseOptions {
  fps?: number;
  width?: number;
  height?: number;
}

/** 树莓派 FastAPI 网关客户端。REST 只提交短请求，耗时工作由网关任务队列串行执行。 */
export class RaspberryPiClient {
  private config: GatewayEndpointConfig;
  private capturePlans: Map<string, CapturePlan> = new Map<string, CapturePlan>();
  private lastCameraModel: string = '';

  constructor(config?: GatewayEndpointConfig) {
    this.config = config === undefined ? {
      baseUrl: 'http://10.42.0.1:8000',
      requestTimeoutMs: 5000,
      readTimeoutMs: 30000
    } : config;
  }

  setEndpoint(config: GatewayEndpointConfig): void {
    this.config = config;
    this.capturePlans.clear();
    this.lastCameraModel = '';
  }

  getEndpoint(): GatewayEndpointConfig {
    return {
      baseUrl: this.config.baseUrl,
      requestTimeoutMs: this.config.requestTimeoutMs,
      readTimeoutMs: this.config.readTimeoutMs
    };
  }

  async health(): Promise<GatewayHealth> {
    // 网关当前仅为健康检查声明 /health；其余 REST 资源统一使用 /api/v1。
    const response: HttpServiceResult = await this.request('/health', http.RequestMethod.GET);
    const dto: GatewayHealthDto = this.parseJson<GatewayHealthDto>(response.body, '网关健康状态');
    if (dto.camera.model !== null && dto.camera.model.length > 0) {
      this.lastCameraModel = dto.camera.model;
    }
    return {
      online: dto.status === 'ok' && dto.database === 'ok',
      serviceVersion: dto.version,
      cameraConnected: dto.camera.connected,
      astrometryAvailable: dto.plate_solver.backend === 'astrometry.net' && !dto.plate_solver.simulated,
      ffmpegAvailable: dto.ffmpeg.available,
      checkedAtMs: Date.now()
    };
  }

  async cameraStatus(): Promise<CameraState> {
    const response: HttpServiceResult = await this.request('/api/v1/camera/status', http.RequestMethod.GET);
    const dto: GatewayCameraStatusDto = this.parseJson<GatewayCameraStatusDto>(response.body, '相机状态');
    if (dto.model !== null && dto.model.length > 0) {
      this.lastCameraModel = dto.model;
    }
    return this.mapCameraState(dto);
  }

  async cameraCapabilities(): Promise<CameraCapabilities> {
    const response: HttpServiceResult = await this.request('/api/v1/camera/capabilities', http.RequestMethod.GET);
    const dto: GatewayCameraCapabilitiesDto =
      this.parseJson<GatewayCameraCapabilitiesDto>(response.body, '相机能力');
    return {
      cameraModel: this.lastCameraModel,
      bulbSupported: dto.bulb,
      maxExposureSeconds: dto.max_exposure_seconds,
      rawSupported: dto.raw_jpeg,
      liveViewSupported: dto.liveview
    };
  }

  async createCaptureTask(plan: CapturePlan, idempotencyKey?: string): Promise<CaptureTask> {
    this.validateCapturePlan(plan);
    const body: GatewayCaptureRequestDto = {
      iso: `${plan.iso}`,
      aperture: `${plan.aperture}`,
      exposure_seconds: plan.exposureSeconds,
      count: plan.frameCount,
      interval_seconds: plan.intervalSeconds,
      raw_jpeg: plan.imageFormat === ImageFormat.RAW_JPEG,
      label: this.captureLabel(plan.id)
    };
    const serialized: string = JSON.stringify(body);
    const key: string = this.resolveIdempotencyKey('capture', serialized, idempotencyKey);
    const response: HttpServiceResult = await this.request('/api/v1/capture/tasks', http.RequestMethod.POST,
      serialized, undefined, key);
    const dto: GatewayTaskDto = this.parseJson<GatewayTaskDto>(response.body, '拍摄任务');
    const planCopy: CapturePlan = this.copyCapturePlan(plan);
    this.capturePlans.set(dto.id, planCopy);
    return this.mapCaptureTask(dto, planCopy);
  }

  async getCaptureTask(taskId: string): Promise<CaptureTask> {
    const dto: GatewayTaskDto = await this.fetchTask(taskId);
    this.requireTaskType(dto, 'capture');
    const cachedPlan: CapturePlan | undefined = this.capturePlans.get(dto.id);
    return this.mapCaptureTask(dto, cachedPlan);
  }

  async cancelCaptureTask(taskId: string): Promise<CaptureTask> {
    const dto: GatewayTaskDto = await this.cancelTaskDto(taskId);
    this.requireTaskType(dto, 'capture');
    const cachedPlan: CapturePlan | undefined = this.capturePlans.get(dto.id);
    return this.mapCaptureTask(dto, cachedPlan);
  }

  async getTask(taskId: string): Promise<GatewayTask> {
    return this.mapGatewayTask(await this.fetchTask(taskId));
  }

  async cancelTask(taskId: string): Promise<GatewayTask> {
    return this.mapGatewayTask(await this.cancelTaskDto(taskId));
  }

  async listTasks(limit: number = 50): Promise<GatewayTask[]> {
    const safeLimit: number = Math.max(1, Math.min(200, Math.trunc(limit)));
    const response: HttpServiceResult = await this.request(`/api/v1/tasks?limit=${safeLimit}`,
      http.RequestMethod.GET);
    const dtos: GatewayTaskDto[] = this.parseJson<GatewayTaskDto[]>(response.body, '任务列表');
    return dtos.map((dto: GatewayTaskDto): GatewayTask => this.mapGatewayTask(dto));
  }

  async createPlateSolveTask(fileId: string, options?: PlateSolveOptions,
    idempotencyKey?: string): Promise<GatewayTask> {
    this.requireNonEmpty(fileId, '板解析文件 ID');
    const body: GatewayPlateSolveRequestDto = this.buildPlateSolveRequest(fileId, options);
    const serialized: string = JSON.stringify(body);
    const key: string = this.resolveIdempotencyKey('plate', serialized, idempotencyKey);
    const response: HttpServiceResult = await this.request('/api/v1/plate-solve', http.RequestMethod.POST,
      serialized, undefined, key);
    return this.mapGatewayTask(this.parseJson<GatewayTaskDto>(response.body, '板解析任务'));
  }

  async plateSolve(fileId: string, options?: PlateSolveOptions,
    idempotencyKey?: string): Promise<GatewayTask> {
    return this.createPlateSolveTask(fileId, options, idempotencyKey);
  }

  async getPlateSolveResult(taskId: string): Promise<PlateSolveResult> {
    const dto: GatewayTaskDto = await this.fetchTask(taskId);
    this.requireTaskType(dto, 'plate_solve');
    return this.mapPlateSolveResult(dto);
  }

  async createStackTask(fileIds: string[], options?: StackOptions,
    idempotencyKey?: string): Promise<GatewayTask> {
    this.validateFileIds(fileIds, 2, 200, '堆栈');
    const body: GatewayStackRequestDto = {
      file_ids: fileIds.slice(),
      reject_bad_frames: options?.rejectBadFrames === undefined ? true : options.rejectBadFrames,
      correct_light_pollution: options?.correctLightPollution === undefined ? true : options.correctLightPollution,
      output_format: options?.outputFormat === undefined ? StackOutputFormat.JPEG : options.outputFormat
    };
    const serialized: string = JSON.stringify(body);
    const key: string = this.resolveIdempotencyKey('stack', serialized, idempotencyKey);
    const response: HttpServiceResult = await this.request('/api/v1/stack', http.RequestMethod.POST,
      serialized, 120000, key);
    return this.mapGatewayTask(this.parseJson<GatewayTaskDto>(response.body, '堆栈任务'));
  }

  async stack(fileIds: string[], options?: StackOptions, idempotencyKey?: string): Promise<GatewayTask> {
    return this.createStackTask(fileIds, options, idempotencyKey);
  }

  async createTimelapseTask(fileIds: string[], options?: TimelapseOptions,
    idempotencyKey?: string): Promise<GatewayTask> {
    this.validateFileIds(fileIds, 2, 2000, '延时摄影');
    const fps: number = options?.fps === undefined ? 24 : Math.trunc(options.fps);
    const width: number = options?.width === undefined ? 1920 : Math.trunc(options.width);
    const height: number = options?.height === undefined ? 1080 : Math.trunc(options.height);
    if (fps < 1 || fps > 60) {
      throw new Error('延时视频帧率必须在 1 到 60 FPS 之间');
    }
    if (width < 320 || width > 4096 || height < 240 || height > 2160 || width % 2 !== 0 || height % 2 !== 0) {
      throw new Error('延时视频尺寸超出网关范围，且宽高必须为偶数');
    }
    const body: GatewayTimelapseRequestDto = {
      file_ids: fileIds.slice(),
      fps: fps,
      width: width,
      height: height
    };
    const serialized: string = JSON.stringify(body);
    const key: string = this.resolveIdempotencyKey('timelapse', serialized, idempotencyKey);
    const response: HttpServiceResult = await this.request('/api/v1/timelapse', http.RequestMethod.POST,
      serialized, 120000, key);
    return this.mapGatewayTask(this.parseJson<GatewayTaskDto>(response.body, '延时摄影任务'));
  }

  async createTimelapse(fileIds: string[], options?: TimelapseOptions,
    idempotencyKey?: string): Promise<GatewayTask> {
    return this.createTimelapseTask(fileIds, options, idempotencyKey);
  }

  async listFiles(taskId: string = '', limit: number = 100): Promise<GatewayFile[]> {
    const safeLimit: number = Math.max(1, Math.min(500, Math.trunc(limit)));
    const taskFilter: string = taskId.trim().length > 0 ? `&task_id=${encodeURIComponent(taskId.trim())}` : '';
    const response: HttpServiceResult = await this.request(`/api/v1/files?limit=${safeLimit}${taskFilter}`,
      http.RequestMethod.GET);
    const dtos: GatewayFileDto[] = this.parseJson<GatewayFileDto[]>(response.body, '文件列表');
    return dtos.map((dto: GatewayFileDto): GatewayFile => this.mapFile(dto));
  }

  fileDownloadUrl(fileId: string): string {
    this.requireNonEmpty(fileId, '文件 ID');
    return `${this.normalizedBaseUrl()}/api/v1/files/${encodeURIComponent(fileId)}`;
  }

  liveViewUrl(): string {
    return `${this.normalizedBaseUrl()}/api/v1/camera/liveview`;
  }

  taskProgressWebSocketUrl(taskId: string): string {
    const base: string = this.normalizedBaseUrl();
    const webSocketBase: string = base.startsWith('https://') ?
      `wss://${base.substring(8)}` : `ws://${base.startsWith('http://') ? base.substring(7) : base}`;
    // WebSocket 路由目前没有 /api/v1 别名，必须与 gateway/app/main.py 保持一致。
    return `${webSocketBase}/ws/tasks/${encodeURIComponent(taskId)}`;
  }

  async requestRaw(path: string, method: http.RequestMethod,
    body: string = '', readTimeoutMs?: number): Promise<HttpServiceResult> {
    return this.request(path, method, body, readTimeoutMs);
  }

  private async fetchTask(taskId: string): Promise<GatewayTaskDto> {
    this.requireNonEmpty(taskId, '任务 ID');
    const response: HttpServiceResult = await this.request(`/api/v1/tasks/${encodeURIComponent(taskId)}`,
      http.RequestMethod.GET);
    return this.parseJson<GatewayTaskDto>(response.body, '任务详情');
  }

  private async cancelTaskDto(taskId: string): Promise<GatewayTaskDto> {
    this.requireNonEmpty(taskId, '任务 ID');
    const response: HttpServiceResult = await this.request(
      `/api/v1/tasks/${encodeURIComponent(taskId)}/cancel`, http.RequestMethod.POST, '{}');
    return this.parseJson<GatewayTaskDto>(response.body, '取消后的任务');
  }

  private async request(path: string, method: http.RequestMethod, body: string = '',
    readTimeoutMs?: number, idempotencyKey?: string): Promise<HttpServiceResult> {
    const request: http.HttpRequest = http.createHttp();
    try {
      let response: http.HttpResponse;
      if (idempotencyKey === undefined) {
        response = await request.request(`${this.normalizedBaseUrl()}${path}`, {
          method: method,
          header: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-StarFinding-Client': 'HarmonyOS'
          },
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: this.config.requestTimeoutMs,
          readTimeout: readTimeoutMs === undefined ? this.config.readTimeoutMs : readTimeoutMs,
          usingCache: false
        });
      } else {
        response = await request.request(`${this.normalizedBaseUrl()}${path}`, {
          method: method,
          header: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-StarFinding-Client': 'HarmonyOS',
            'Idempotency-Key': idempotencyKey
          },
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: this.config.requestTimeoutMs,
          readTimeout: readTimeoutMs === undefined ? this.config.readTimeoutMs : readTimeoutMs,
          usingCache: false
        });
      }
      const responseBody: string = typeof response.result === 'string' ? response.result :
        JSON.stringify(response.result);
      const statusCode: number = Number(response.responseCode);
      const result: HttpServiceResult = {
        statusCode: statusCode,
        body: responseBody,
        succeeded: statusCode >= 200 && statusCode < 300
      };
      if (!result.succeeded) {
        throw new Error(`树莓派网关返回 HTTP ${statusCode}：${responseBody}`);
      }
      return result;
    } catch (error) {
      // 网络异常和网关业务错误都交给页面统一更新连接状态；这里补充请求路径，便于现场排障。
      throw new Error(`访问树莓派网关 ${path} 失败：${error}`);
    } finally {
      request.destroy();
    }
  }

  private mapCameraState(dto: GatewayCameraStatusDto): CameraState {
    let connection: ConnectionState = ConnectionState.DISCONNECTED;
    if (dto.connected) {
      connection = dto.simulated ? ConnectionState.SIMULATED : ConnectionState.CONNECTED;
    }
    return {
      connection: connection,
      cameraModel: dto.model === null ? this.lastCameraModel : dto.model,
      // 网关暂不报告存储空间、busy 和实时取景状态；-1 表示未知，不伪装为真实测量值。
      batteryPercent: this.parseBatteryPercent(dto.battery),
      storageFreeBytes: -1,
      busy: false,
      liveViewActive: false,
      lastError: dto.connected ? '' : (dto.detail === null ? '未检测到 USB 相机' : dto.detail),
      updatedAtMs: Date.now()
    };
  }

  private mapCaptureTask(dto: GatewayTaskDto, cachedPlan?: CapturePlan): CaptureTask {
    const plan: CapturePlan = cachedPlan === undefined ? this.restoreCapturePlan(dto) :
      this.copyCapturePlan(cachedPlan);
    const products: CaptureProduct[] = this.outputFiles(dto).map((file: GatewayFileDto): CaptureProduct => {
      return {
        kind: file.kind,
        fileName: file.name,
        downloadUrl: this.fileDownloadUrl(file.id),
        createdAtMs: this.parseTimestamp(file.created_at)
      };
    });
    return {
      id: dto.id,
      plan: plan,
      status: this.mapTaskStatus(dto.status),
      progressPercent: dto.progress,
      completedFrames: dto.output?.captured_frames === undefined ? 0 : dto.output.captured_frames,
      currentStage: dto.message,
      errorMessage: dto.error === null ? '' : dto.error,
      products: products,
      createdAtMs: this.parseTimestamp(dto.created_at),
      updatedAtMs: this.parseTimestamp(dto.updated_at)
    };
  }

  private mapGatewayTask(dto: GatewayTaskDto): GatewayTask {
    return {
      id: dto.id,
      type: dto.type,
      status: this.mapTaskStatus(dto.status),
      progressPercent: dto.progress,
      message: dto.message,
      errorMessage: dto.error === null ? '' : dto.error,
      files: this.outputFiles(dto).map((file: GatewayFileDto): GatewayFile => this.mapFile(file)),
      capturedFrames: dto.output?.captured_frames === undefined ? 0 : dto.output.captured_frames,
      createdAtMs: this.parseTimestamp(dto.created_at),
      updatedAtMs: this.parseTimestamp(dto.updated_at)
    };
  }

  private mapPlateSolveResult(dto: GatewayTaskDto): PlateSolveResult {
    const result: GatewayPlateSolveResultDto | undefined = dto.output?.plate_solve;
    if (result === undefined) {
      return {
        taskId: dto.id,
        status: this.mapTaskStatus(dto.status),
        solved: false,
        centerRaHours: 0,
        centerDecDegrees: 0,
        fieldWidthDegrees: 0,
        fieldHeightDegrees: 0,
        rotationDegrees: 0,
        residualArcSeconds: -1,
        errorMessage: dto.error === null ? dto.message : dto.error
      };
    }
    return {
      taskId: dto.id,
      status: this.mapTaskStatus(dto.status),
      solved: result.solved,
      centerRaHours: result.ra_deg === null ? 0 : result.ra_deg / 15,
      centerDecDegrees: result.dec_deg === null ? 0 : result.dec_deg,
      fieldWidthDegrees: result.field_width_deg === null ? 0 : result.field_width_deg,
      fieldHeightDegrees: result.field_height_deg === null ? 0 : result.field_height_deg,
      rotationDegrees: result.rotation_deg === null ? 0 : result.rotation_deg,
      // astrometry.net 适配器尚未返回拟合残差，-1 明确表示“网关未提供”。
      residualArcSeconds: -1,
      errorMessage: dto.error === null ? (result.detail === null ? '' : result.detail) :
        dto.error
    };
  }

  private mapFile(dto: GatewayFileDto): GatewayFile {
    return {
      id: dto.id,
      taskId: dto.task_id === null ? '' : dto.task_id,
      name: dto.name,
      mimeType: dto.mime_type,
      sizeBytes: dto.size,
      kind: dto.kind,
      downloadUrl: this.fileDownloadUrl(dto.id),
      createdAtMs: this.parseTimestamp(dto.created_at)
    };
  }

  private outputFiles(dto: GatewayTaskDto): GatewayFileDto[] {
    if (dto.output === null) {
      return [];
    }
    if (dto.output.files !== undefined) {
      return dto.output.files;
    }
    if (dto.output.file !== undefined) {
      return [dto.output.file];
    }
    return [];
  }

  private restoreCapturePlan(dto: GatewayTaskDto): CapturePlan {
    const input: GatewayTaskInputDto = dto.input;
    return {
      id: dto.id,
      mode: CaptureMode.SMART_LONG_EXPOSURE,
      targetId: '',
      targetName: '网关恢复任务',
      exposureSeconds: input.exposure_seconds === undefined ? 10 : input.exposure_seconds,
      frameCount: input.count === undefined ? 1 : input.count,
      intervalSeconds: input.interval_seconds === undefined ? 0 : input.interval_seconds,
      iso: input.iso === undefined ? 800 : this.parseNumericSetting(input.iso, 800),
      aperture: input.aperture === undefined ? 4 : this.parseNumericSetting(input.aperture, 4),
      imageFormat: input.raw_jpeg === false ? ImageFormat.JPEG : ImageFormat.RAW_JPEG,
      outputFps: 24,
      enablePlateSolve: false,
      enableDriftCorrection: false,
      enableLocalStack: false,
      enableCloudEnhancement: false,
      recommendationReason: '从网关持久化的基础拍摄参数恢复',
      warnings: ['Pad 重启后无法从相机网关恢复目标和高级处理策略，请重新确认后续流程']
    };
  }

  private copyCapturePlan(plan: CapturePlan): CapturePlan {
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

  private buildPlateSolveRequest(fileId: string, options?: PlateSolveOptions): GatewayPlateSolveRequestDto {
    const searchRadius: number = options?.searchRadiusDegrees === undefined ? 20 : options.searchRadiusDegrees;
    if (searchRadius <= 0 || searchRadius > 180) {
      throw new Error('板解析搜索半径必须大于 0 度且不超过 180 度');
    }
    const body: GatewayPlateSolveRequestDto = {
      file_id: fileId,
      search_radius_deg: searchRadius
    };
    if (options?.hintRaHours !== undefined) {
      if (options.hintRaHours < 0 || options.hintRaHours >= 24) {
        throw new Error('板解析赤经提示必须在 [0, 24) 小时范围内');
      }
      body.hint_ra_deg = options.hintRaHours * 15;
    }
    if (options?.hintDecDegrees !== undefined) {
      if (options.hintDecDegrees < -90 || options.hintDecDegrees > 90) {
        throw new Error('板解析赤纬提示必须在 -90 到 90 度范围内');
      }
      body.hint_dec_deg = options.hintDecDegrees;
    }
    const hasLow: boolean = options?.pixelScaleLowArcSeconds !== undefined;
    const hasHigh: boolean = options?.pixelScaleHighArcSeconds !== undefined;
    if (hasLow !== hasHigh) {
      throw new Error('像素尺度上下限必须同时提供');
    }
    if (hasLow && hasHigh) {
      const low: number = options?.pixelScaleLowArcSeconds === undefined ? 0 : options.pixelScaleLowArcSeconds;
      const high: number = options?.pixelScaleHighArcSeconds === undefined ? 0 : options.pixelScaleHighArcSeconds;
      if (low <= 0 || low >= high) {
        throw new Error('像素尺度必须为正数，且下限小于上限');
      }
      body.pixel_scale_low = low;
      body.pixel_scale_high = high;
    }
    return body;
  }

  private validateCapturePlan(plan: CapturePlan): void {
    if (plan.mode === CaptureMode.OBSERVE_ONLY) {
      throw new Error('仅观测计划不会触发 R7 快门');
    }
    if (plan.exposureSeconds <= 0 || plan.exposureSeconds > 300) {
      throw new Error('单帧曝光必须大于 0 秒且不超过 300 秒');
    }
    if (!Number.isInteger(plan.frameCount) || plan.frameCount < 1 || plan.frameCount > 500) {
      throw new Error('拍摄帧数必须是 1 到 500 之间的整数');
    }
    if (plan.intervalSeconds < 0 || plan.intervalSeconds > 3600) {
      throw new Error('拍摄间隔必须在 0 到 3600 秒之间');
    }
    if (plan.iso <= 0 || plan.aperture <= 0) {
      throw new Error('ISO 和光圈必须为正数');
    }
  }

  private validateFileIds(fileIds: string[], minCount: number, maxCount: number, label: string): void {
    if (fileIds.length < minCount || fileIds.length > maxCount) {
      throw new Error(`${label}文件数量必须在 ${minCount} 到 ${maxCount} 之间`);
    }
    const distinct: Set<string> = new Set<string>();
    fileIds.forEach((fileId: string): void => {
      this.requireNonEmpty(fileId, `${label}文件 ID`);
      distinct.add(fileId);
    });
    if (distinct.size !== fileIds.length) {
      throw new Error(`${label}文件 ID 不能重复`);
    }
  }

  private requireTaskType(dto: GatewayTaskDto, expected: string): void {
    if (dto.type !== expected) {
      throw new Error(`任务 ${dto.id} 类型为 ${dto.type}，预期为 ${expected}`);
    }
  }

  private requireNonEmpty(value: string, label: string): void {
    if (value.trim().length === 0) {
      throw new Error(`${label}不能为空`);
    }
  }

  private resolveIdempotencyKey(prefix: string, serializedBody: string, supplied?: string): string {
    if (supplied !== undefined) {
      const trimmed: string = supplied.trim();
      if (trimmed.length < 1 || trimmed.length > 128) {
        throw new Error('Idempotency-Key 长度必须在 1 到 128 个字符之间');
      }
      return trimmed;
    }
    let hash: number = 2166136261;
    for (let index: number = 0; index < serializedBody.length; index += 1) {
      hash ^= serializedBody.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `starfinding-${prefix}-${(hash >>> 0).toString(16)}`;
  }

  private captureLabel(planId: string): string {
    const normalized: string = `starfinding_${planId}`.replace(/[^A-Za-z0-9_-]/g, '_').substring(0, 40);
    return normalized.length > 0 ? normalized : 'starfinding_capture';
  }

  private mapTaskStatus(value: string): TaskStatus {
    switch (value) {
      case 'pending':
        return TaskStatus.PENDING;
      case 'running':
        return TaskStatus.RUNNING;
      case 'succeeded':
        return TaskStatus.SUCCEEDED;
      case 'failed':
        return TaskStatus.FAILED;
      case 'cancelled':
        return TaskStatus.CANCELLED;
      default:
        throw new Error(`网关返回未知任务状态：${value}`);
    }
  }

  private parseBatteryPercent(value: string | null): number {
    if (value === null) {
      return -1;
    }
    const parsed: number = Number.parseInt(value.replace('%', '').trim(), 10);
    return Number.isNaN(parsed) ? -1 : Math.max(0, Math.min(100, parsed));
  }

  private parseNumericSetting(value: string, fallback: number): number {
    const parsed: number = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private parseTimestamp(value: string): number {
    const parsed: number = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private parseJson<T>(body: string, label: string): T {
    try {
      return JSON.parse(body) as T;
    } catch (error) {
      throw new Error(`${label}响应不是有效 JSON：${error}`);
    }
  }

  private normalizedBaseUrl(): string {
    let baseUrl: string = this.config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    return baseUrl;
  }
}

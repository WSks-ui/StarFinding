import { http } from '@kit.NetworkKit';
import {
  AiEndpointConfig,
  EnhancementTask,
  TaskStatus
} from '../models/DomainModels';

/** cloud/app/schemas.py 的 TaskView 网络契约，禁止直接当作 Pad 领域模型使用。 */
interface CloudEnhancementLinksDto {
  self?: string;
  original?: string;
  result?: string;
  star_mask?: string;
}

interface CloudEnhancementProcessingDto {
  algorithm_version?: string;
}

interface CloudEnhancementTaskDto {
  task_id: string;
  state: string;
  created_at: string;
  updated_at: string;
  requested_backend: string;
  backend_used: string | null;
  input_sha256: string;
  output_sha256: string | null;
  error: string | null;
  fallback_reason: string | null;
  processing: CloudEnhancementProcessingDto;
  links: CloudEnhancementLinksDto;
}

interface CloudRequestHeaders {
  'Accept': string;
  'Authorization'?: string;
  'X-StarFinding-Client': string;
}

/**
 * StarFinding 受约束图像增强服务客户端。
 *
 * 云端增强是本地堆栈之后的可选步骤：此类既不会修改树莓派文件，也不会把失败解释为
 * 拍摄失败。调用方捕获异常后应继续展示 sourceFileUrl 指向的本地堆栈结果。
 */
export class AIEnhancementClient {
  private readonly maxDownloadedImageBytes: number = 100 * 1024 * 1024;
  private config: AiEndpointConfig;
  /** GET 任务接口不回传来源 URL，因此在当前进程内保留任务与本地堆栈的对应关系。 */
  private sourceUrls: Map<string, string> = new Map<string, string>();

  constructor(config?: AiEndpointConfig) {
    this.config = config === undefined ? {
      baseUrl: '',
      accessToken: '',
      requestTimeoutMs: 30000
    } : config;
  }

  setEndpoint(config: AiEndpointConfig): void {
    this.config = config;
    this.sourceUrls.clear();
  }

  clearEndpoint(): void {
    this.config = { baseUrl: '', accessToken: '', requestTimeoutMs: 30000 };
    this.sourceUrls.clear();
  }

  /** FastAPI 当前不强制鉴权；令牌为空时可连接局域网或开发环境服务。 */
  isConfigured(): boolean {
    return this.config.baseUrl.trim().length > 0;
  }

  /**
   * 从树莓派文件 URL 下载 JPEG，再按云端真实契约上传。
   * 下载请求不会附带云端 Authorization，避免把华为云凭据泄露给另一个主机。
   */
  async create(sourceFileUrl: string, strength: number = 0.65, taskId?: string): Promise<EnhancementTask> {
    const normalizedSourceUrl: string = sourceFileUrl.trim();
    if (normalizedSourceUrl.length === 0) {
      throw new Error('AI 增强源图 URL 不能为空，本地堆栈结果仍然保留');
    }
    try {
      const imageBytes: ArrayBuffer = await this.downloadImage(normalizedSourceUrl);
      const fileName: string = this.fileNameFromUrl(normalizedSourceUrl);
      return await this.upload(imageBytes, fileName, this.contentTypeForFile(fileName), strength,
        normalizedSourceUrl, taskId);
    } catch (error) {
      throw new Error(`AI 增强未提交，本地堆栈结果仍可直接使用：${error}`);
    }
  }

  /**
   * 直接上传内存中的 JPEG、PNG 或 WebP，适合调用方已持有图像字节的场景。
   * NetworkKit 根据 multiFormDataList 自动生成带 boundary 的 Content-Type，不能手工覆盖。
   */
  async upload(imageBytes: ArrayBuffer, fileName: string = 'stack.jpg', contentType: string = 'image/jpeg',
    strength: number = 0.65, sourceFileUrl: string = '', taskId?: string): Promise<EnhancementTask> {
    this.requireConfigured();
    this.validateUpload(imageBytes, contentType, strength);

    const safeFileName: string = this.safeFileName(fileName);
    const formData: Array<http.MultiFormData> = [
      {
        name: 'image',
        contentType: contentType,
        remoteFileName: safeFileName,
        data: imageBytes
      },
      {
        name: 'strength',
        contentType: 'text/plain',
        data: `${strength}`
      }
    ];
    if (taskId !== undefined && taskId.trim().length > 0) {
      formData.push({
        name: 'task_id',
        contentType: 'text/plain',
        data: taskId.trim()
      });
    }

    const responseBody: string = await this.requestTask('/v1/enhancements', http.RequestMethod.POST, formData);
    const dto: CloudEnhancementTaskDto = this.parseJson<CloudEnhancementTaskDto>(responseBody, 'AI 增强任务');
    if (sourceFileUrl.trim().length > 0) {
      this.sourceUrls.set(dto.task_id, sourceFileUrl.trim());
    }
    return this.mapTask(dto);
  }

  async get(taskId: string): Promise<EnhancementTask> {
    this.requireConfigured();
    const normalizedTaskId: string = taskId.trim();
    if (normalizedTaskId.length === 0) {
      throw new Error('AI 增强任务 ID 不能为空');
    }
    const responseBody: string = await this.requestTask(
      `/v1/enhancements/${encodeURIComponent(normalizedTaskId)}`, http.RequestMethod.GET);
    return this.mapTask(this.parseJson<CloudEnhancementTaskDto>(responseBody, 'AI 增强任务'));
  }

  private async downloadImage(sourceFileUrl: string): Promise<ArrayBuffer> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(sourceFileUrl, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'image/jpeg,image/png,image/webp'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: this.config.requestTimeoutMs,
        readTimeout: this.config.requestTimeoutMs,
        maxLimit: this.maxDownloadedImageBytes,
        usingCache: false
      });
      const statusCode: number = Number(response.responseCode);
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`源图下载返回 HTTP ${statusCode}`);
      }
      const imageBytes: ArrayBuffer = response.result as ArrayBuffer;
      if (imageBytes.byteLength < 1) {
        throw new Error('源图下载结果为空');
      }
      return imageBytes;
    } finally {
      request.destroy();
    }
  }

  private async requestTask(path: string, method: http.RequestMethod,
    formData?: Array<http.MultiFormData>): Promise<string> {
    this.requireConfigured();
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: CloudRequestHeaders = {
        'Accept': 'application/json',
        'X-StarFinding-Client': 'HarmonyOS'
      };
      const token: string = this.config.accessToken.trim();
      if (token.length > 0) {
        headers.Authorization = `Bearer ${token}`;
      }

      let response: http.HttpResponse;
      if (formData === undefined) {
        response = await request.request(`${this.normalizedBaseUrl()}${path}`, {
          method: method,
          header: headers,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: this.config.requestTimeoutMs,
          readTimeout: this.config.requestTimeoutMs,
          usingCache: false
        });
      } else {
        response = await request.request(`${this.normalizedBaseUrl()}${path}`, {
          method: method,
          header: headers,
          multiFormDataList: formData,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: this.config.requestTimeoutMs,
          readTimeout: this.config.requestTimeoutMs,
          usingCache: false
        });
      }

      const responseBody: string = typeof response.result === 'string' ? response.result :
        JSON.stringify(response.result);
      const statusCode: number = Number(response.responseCode);
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`AI 服务返回 HTTP ${statusCode}：${responseBody}`);
      }
      return responseBody;
    } catch (error) {
      throw new Error(`访问 AI 增强服务 ${path} 失败：${error}`);
    } finally {
      request.destroy();
    }
  }

  private mapTask(dto: CloudEnhancementTaskDto): EnhancementTask {
    if (dto.task_id.trim().length === 0) {
      throw new Error('AI 服务响应缺少任务 ID');
    }
    const cachedSourceUrl: string | undefined = this.sourceUrls.get(dto.task_id);
    const sourceFileUrl: string = cachedSourceUrl === undefined ?
      this.resolveLink(dto.links.original) : cachedSourceUrl;
    const modelVersion: string = dto.processing.algorithm_version === undefined ? '' :
      dto.processing.algorithm_version;
    return {
      id: dto.task_id,
      sourceFileUrl: sourceFileUrl,
      status: this.mapTaskStatus(dto.state),
      progressPercent: this.progressForState(dto.state),
      resultFileUrl: this.resolveLink(dto.links.result),
      modelVersion: modelVersion,
      // cloud/app/providers.py 无论使用本地还是 ModelArts 候选图，都会重新套用星点保护掩膜。
      preserveStars: true,
      errorMessage: dto.error === null ? '' : dto.error,
      createdAtMs: this.parseTimestamp(dto.created_at),
      updatedAtMs: this.parseTimestamp(dto.updated_at)
    };
  }

  private mapTaskStatus(state: string): TaskStatus {
    switch (state) {
      case 'pending':
        return TaskStatus.PENDING;
      case 'running':
        return TaskStatus.RUNNING;
      case 'succeeded':
        return TaskStatus.SUCCEEDED;
      case 'failed':
        return TaskStatus.FAILED;
      case 'cancelled':
        // schemas.py 保留该状态用于持久化兼容，但当前 HTTP API 没有取消路由。
        return TaskStatus.CANCELLED;
      default:
        throw new Error(`AI 服务返回未知任务状态：${state}`);
    }
  }

  private progressForState(state: string): number {
    if (state === 'pending') {
      return 0;
    }
    if (state === 'running') {
      // 云端没有细粒度进度字段，50 仅表达“后台处理中”，不伪装成算法真实百分比。
      return 50;
    }
    return 100;
  }

  private validateUpload(imageBytes: ArrayBuffer, contentType: string, strength: number): void {
    if (imageBytes.byteLength < 1) {
      throw new Error('AI 增强上传图像不能为空');
    }
    if (imageBytes.byteLength > this.maxDownloadedImageBytes) {
      throw new Error('AI 增强上传图像超过 Pad 客户端 100 MB 安全上限');
    }
    if (contentType !== 'image/jpeg' && contentType !== 'image/png' && contentType !== 'image/webp') {
      throw new Error(`AI 增强不支持图像类型：${contentType}`);
    }
    if (!Number.isFinite(strength) || strength < 0 || strength > 1) {
      throw new Error('AI 增强强度必须在 0 到 1 之间');
    }
  }

  private fileNameFromUrl(sourceFileUrl: string): string {
    let path: string = sourceFileUrl;
    const queryIndex: number = path.indexOf('?');
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }
    const fragmentIndex: number = path.indexOf('#');
    if (fragmentIndex >= 0) {
      path = path.substring(0, fragmentIndex);
    }
    const slashIndex: number = path.lastIndexOf('/');
    const candidate: string = slashIndex >= 0 ? path.substring(slashIndex + 1) : path;
    try {
      return this.safeFileName(decodeURIComponent(candidate));
    } catch (error) {
      return this.safeFileName(candidate);
    }
  }

  private safeFileName(fileName: string): string {
    const normalized: string = fileName.trim().replace(/[^A-Za-z0-9._-]/g, '_').substring(0, 120);
    return normalized.length > 0 ? normalized : 'stack.jpg';
  }

  private contentTypeForFile(fileName: string): string {
    const lowerName: string = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  private resolveLink(link?: string): string {
    if (link === undefined || link.trim().length === 0) {
      return '';
    }
    const normalizedLink: string = link.trim();
    if (normalizedLink.startsWith('http://') || normalizedLink.startsWith('https://')) {
      return normalizedLink;
    }
    return normalizedLink.startsWith('/') ? `${this.normalizedBaseUrl()}${normalizedLink}` :
      `${this.normalizedBaseUrl()}/${normalizedLink}`;
  }

  private parseTimestamp(value: string): number {
    const timestamp: number = Date.parse(value);
    return Number.isNaN(timestamp) ? 0 : timestamp;
  }

  private parseJson<T>(body: string, label: string): T {
    try {
      return JSON.parse(body) as T;
    } catch (error) {
      throw new Error(`${label}响应不是有效 JSON：${error}`);
    }
  }

  private requireConfigured(): void {
    if (!this.isConfigured()) {
      throw new Error('AI 增强服务尚未配置，本地堆栈结果仍然可用');
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

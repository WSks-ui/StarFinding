import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { display } from '@kit.ArkUI';
import {
  HandFramePresentationProfile,
  HandFrameSourceProfile,
  HandFrameSourceState,
  HandLandmarkFrameSource
} from '../services/HandLandmarkAnalyzer';

interface CameraLeaseWaiter {
  ownerId: number;
  resolve: () => void;
}

/**
 * CameraKit 在同一进程中只能稳定地由一个预览会话占用。模式切换会销毁旧组件并立即创建
 * 新组件，实例内 generation 无法约束二者，因此这里用模块级租约把释放和下一次 open 串行化。
 */
class CameraPreviewCoordinator {
  private static nextOwnerId: number = 1;
  private static activeOwnerId: number = 0;
  private static waiters: CameraLeaseWaiter[] = [];

  static createOwnerId(): number {
    const ownerId: number = CameraPreviewCoordinator.nextOwnerId;
    CameraPreviewCoordinator.nextOwnerId++;
    return ownerId;
  }

  static async acquire(ownerId: number): Promise<void> {
    if (CameraPreviewCoordinator.activeOwnerId === 0 ||
      CameraPreviewCoordinator.activeOwnerId === ownerId) {
      CameraPreviewCoordinator.activeOwnerId = ownerId;
      return;
    }
    await new Promise<void>((resolve: () => void): void => {
      CameraPreviewCoordinator.waiters.push({ ownerId: ownerId, resolve: resolve });
    });
  }

  static release(ownerId: number): void {
    if (CameraPreviewCoordinator.activeOwnerId !== ownerId) {
      return;
    }
    const next: CameraLeaseWaiter | undefined = CameraPreviewCoordinator.waiters.shift();
    if (next === undefined) {
      CameraPreviewCoordinator.activeOwnerId = 0;
      return;
    }
    // 先登记下一位所有者再唤醒，避免两个等待者在同一事件循环内同时通过空闲判断。
    CameraPreviewCoordinator.activeOwnerId = next.ownerId;
    next.resolve();
  }
}

@Component
export struct DeviceCameraPreview {
  @Prop useFrontCamera: boolean = false;
  @Prop cornerRadius: number = 0;
  @Prop handFrameSource: HandLandmarkFrameSource | undefined = undefined;
  @State private cameraStatus: string = '等待相机';
  @State private previewStarted: boolean = false;

  private surfaceId: string = '';
  private componentVisible: boolean = false;
  private starting: boolean = false;
  private stopping: boolean = false;
  private restartRequested: boolean = false;
  private recoveryScheduled: boolean = false;
  private lifecycleGeneration: number = 0;
  private displaySubscribed: boolean = false;
  private displayRotation: camera.ImageRotation = camera.ImageRotation.ROTATION_0;
  private previewWidth: number = 1.0;
  private previewHeight: number = 1.0;
  private previewRotationDegrees: number = 0.0;
  private handAnalysisWarning: string = '';
  private readonly cameraOwnerId: number = CameraPreviewCoordinator.createOwnerId();
  private activeLeaseHeld: boolean = false;
  private controller: XComponentController = new XComponentController();
  private cameraInput?: camera.CameraInput;
  private previewOutput?: camera.PreviewOutput;
  private analysisOutput?: camera.PreviewOutput;
  private captureSession?: camera.PhotoSession;
  private readonly sessionErrorCallback = (error: BusinessError): void => {
    if (!this.activeLeaseHeld || this.recoveryScheduled) {
      return;
    }
    this.recoveryScheduled = true;
    this.previewStarted = false;
    this.cameraStatus = `相机预览中断（${error.code}），正在恢复`;
    this.lifecycleGeneration++;
    this.restartRequested = this.componentVisible && this.surfaceId.length > 0;
    // 官方不允许在 error 回调栈内直接 off；延迟到下一事件循环再完成注销、释放和重启。
    setTimeout(() => {
      this.recoveryScheduled = false;
      this.stopPreview();
    }, 0);
  };
  private readonly displayChangeCallback = (_displayId: number): void => {
    const previous: camera.ImageRotation = this.displayRotation;
    this.refreshDisplayRotation();
    if (previous === this.displayRotation || !this.componentVisible) {
      return;
    }
    this.applyDisplayRotationChange();
  };

  aboutToAppear(): void {
    this.componentVisible = true;
    this.lifecycleGeneration++;
    this.refreshDisplayRotation();
    if (!this.displaySubscribed) {
      try {
        display.on('change', this.displayChangeCallback);
        this.displaySubscribed = true;
      } catch (error) {
        this.displaySubscribed = false;
      }
    }
  }

  aboutToDisappear(): void {
    this.componentVisible = false;
    this.lifecycleGeneration++;
    this.restartRequested = false;
    this.surfaceId = '';
    if (this.displaySubscribed) {
      try {
        display.off('change', this.displayChangeCallback);
      } catch (error) {
      }
      this.displaySubscribed = false;
    }
    this.stopPreview();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: this.useFrontCamera ? 'gesture_camera_preview' : 'ar_camera_preview',
        type: XComponentType.TEXTURE,
        controller: this.controller
      })
        .width('100%')
        .height('100%')
        .backgroundColor('#05070B')
        .onLoad(() => {
          this.onSurfaceReady();
        })
        .onDestroy(() => {
          // Surface 可能在组件仍存在时被系统重建，先让旧异步启动流程失效；新 Surface
          // onLoad 后会以新的代次自动重启，避免旧会话继续向已销毁的 Surface 输出。
          this.lifecycleGeneration++;
          this.surfaceId = '';
          this.stopPreview();
        })

      if (!this.previewStarted) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color('#56C7FF')
          Text(this.cameraStatus)
            .fontSize(13)
            .fontColor('#AAB4C8')
        }
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.cornerRadius)
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      const height: number = Number(newValue.height);
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0.0 || height <= 0.0) {
        return;
      }
      this.previewWidth = width;
      this.previewHeight = height;
      this.updateHandPresentation();
    })
  }

  private onSurfaceReady(): void {
    try {
      if (!this.componentVisible) {
        return;
      }
      this.surfaceId = this.controller.getXComponentSurfaceId();
      if (this.surfaceId.length === 0) {
        this.cameraStatus = '预览画面未就绪';
        return;
      }
      const generation: number = ++this.lifecycleGeneration;
      this.startPreview(generation);
    } catch (error) {
      this.cameraStatus = '无法创建预览画面';
    }
  }

  private async requestCameraPermission(generation: number): Promise<boolean> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
      if (context === undefined) {
        if (this.isCurrentGeneration(generation)) {
          this.cameraStatus = '应用上下文未就绪';
        }
        return false;
      }
      const manager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.CAMERA'];
      const result = await manager.requestPermissionsFromUser(context, permissions);
      if (!this.isCurrentGeneration(generation)) {
        return false;
      }
      if (result.authResults.length === 0 || result.authResults[0] !== 0) {
        this.cameraStatus = '请授予相机权限';
        return false;
      }
      return true;
    } catch (error) {
      if (this.isCurrentGeneration(generation)) {
        this.cameraStatus = '相机权限请求失败';
      }
      return false;
    }
  }

  private async startPreview(generation: number): Promise<void> {
    if (!this.isCurrentGeneration(generation) || this.previewStarted) {
      return;
    }
    if (this.starting || this.stopping) {
      this.restartRequested = true;
      return;
    }
    this.starting = true;
    this.restartRequested = false;
    let input: camera.CameraInput | undefined = undefined;
    let output: camera.PreviewOutput | undefined = undefined;
    let analysisOutput: camera.PreviewOutput | undefined = undefined;
    let session: camera.PhotoSession | undefined = undefined;
    let resourcesTransferred: boolean = false;
    let leaseAcquired: boolean = false;
    try {
      if (!await this.requestCameraPermission(generation)) {
        if (this.isCurrentGeneration(generation)) {
          await this.rejectHandAnalysisStartup(this.cameraStatus);
        }
        return;
      }
      if (!this.isCurrentGeneration(generation)) {
        return;
      }
      const context = AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
      if (context === undefined) {
        this.cameraStatus = '相机上下文未就绪';
        await this.rejectHandAnalysisStartup(this.cameraStatus);
        return;
      }
      this.cameraStatus = this.useFrontCamera ? '正在启动前摄' : '正在启动后摄';
      const cameraManager = camera.getCameraManager(context);
      const device = this.selectCamera(cameraManager.getSupportedCameras());
      if (device === undefined) {
        this.cameraStatus = this.useFrontCamera ? '设备没有可用前摄' : '设备没有可用后摄';
        await this.rejectHandAnalysisStartup(this.cameraStatus);
        return;
      }
      const capability = cameraManager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      if (capability.previewProfiles.length === 0) {
        this.cameraStatus = '设备未提供预览规格';
        await this.rejectHandAnalysisStartup(this.cameraStatus);
        return;
      }

      this.cameraStatus = this.useFrontCamera ? '等待前摄资源' : '等待后摄资源';
      await CameraPreviewCoordinator.acquire(this.cameraOwnerId);
      leaseAcquired = true;
      if (!this.isCurrentGeneration(generation)) return;

      // 预览必须输出到 XComponent 的 Surface。模式切换时父组件销毁当前实例，
      // 资源在完整启动前只保存在局部变量。若权限弹窗或 open/commit/start 期间页面退出，
      // finally 会释放这组局部资源，不会把已经失效的会话挂回已销毁组件。
      input = cameraManager.createCameraInput(device);
      await input.open();
      if (!this.isCurrentGeneration(generation)) return;
      const displayProfile: camera.Profile = this.useFrontCamera ?
        this.selectDisplayPreviewProfile(capability.previewProfiles) :
        capability.previewProfiles[0];
      // 前摄同时承担用户预览与手势分析时，主预览使用中等规格即可；把最高规格留给
      // 相机服务会显著增加双路带宽和首帧延迟。后摄 AR 仍保留设备首选规格。
      output = cameraManager.createPreviewOutput(displayProfile, this.surfaceId);
      session = cameraManager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      session.on('error', this.sessionErrorCallback);
      session.beginConfig();
      session.addInput(input);
      session.addOutput(output);
      // 部分 HarmonyOS 6 真机只有在 PreviewOutput 绑定到 CaptureSession 后才能查询方向；
      // 提前调用会由 Camera Service 返回 session is nullptr，并导致 AR 与前摄同时无法启动。
      this.previewRotationDegrees = this.configurePreviewRotation(output);

      // PreviewOutput 的 frameStart/frameEnd 只表示时序，不包含像素。只有显式注入真实
      // HandLandmarkFrameSource 时，才尝试增加指向 ImageReceiver 的第二路 YUV Surface。
      // canAddOutput 会在真机上校验并发输出组合，失败时保留主预览且明确通知分析入口。
      if (this.useFrontCamera && this.handFrameSource !== undefined) {
        analysisOutput = await this.createHandAnalysisOutput(
          cameraManager, session, capability.previewProfiles, generation, this.previewRotationDegrees);
      }
      if (!this.isCurrentGeneration(generation)) return;
      await session.commitConfig();
      if (!this.isCurrentGeneration(generation)) return;
      await session.start();
      if (!this.isCurrentGeneration(generation)) return;

      // session.start() 成功后立即把资源移交给组件，再触发帧源状态回调。状态回调可能让
      // 上层关闭手势入口并同步卸载本组件；提前移交可保证 aboutToDisappear/stopPreview
      // 始终能看到并释放完整会话，而不是让局部变量中的相机资源悬空。
      this.cameraInput = input;
      this.previewOutput = output;
      this.analysisOutput = analysisOutput;
      this.captureSession = session;
      this.activeLeaseHeld = true;
      resourcesTransferred = true;
      this.previewStarted = true;
      this.cameraStatus = this.useFrontCamera ? '前摄运行中' : '后摄运行中';

      if (analysisOutput !== undefined && this.handFrameSource !== undefined) {
        this.handFrameSource.start();
        if (this.handFrameSource.getStatus().state !== HandFrameSourceState.RUNNING) {
          throw new Error(this.handFrameSource.getStatus().message);
        }
        if (!this.isCurrentGeneration(generation)) {
          // 状态回调已经触发组件卸载时，aboutToDisappear 会负责停止已移交的会话。
          return;
        }
      }
    } catch (error) {
      if (this.isCurrentGeneration(generation)) {
        this.cameraStatus = this.errorMessage(error,
          this.useFrontCamera && this.handFrameSource !== undefined ?
            '前摄手势分析启动失败' : '相机启动失败');
        if (resourcesTransferred) {
          // 已移交资源的失败必须统一走 stopPreview，避免 catch 只更新 UI 而泄漏会话。
          await this.stopPreview();
        } else {
          await this.rejectHandAnalysisStartup(this.cameraStatus);
        }
      }
    } finally {
      if (!resourcesTransferred) {
        await this.releasePreviewResources(session, output, analysisOutput, input);
        if (leaseAcquired) {
          CameraPreviewCoordinator.release(this.cameraOwnerId);
        }
      }
      this.starting = false;
      this.restartIfNeeded();
    }
  }

  private selectCamera(devices: camera.CameraDevice[]): camera.CameraDevice | undefined {
    const expected = this.useFrontCamera ? camera.CameraPosition.CAMERA_POSITION_FRONT :
      camera.CameraPosition.CAMERA_POSITION_BACK;
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].cameraPosition === expected) {
        return devices[index];
      }
    }
    return undefined;
  }

  private async createHandAnalysisOutput(cameraManager: camera.CameraManager, session: camera.PhotoSession,
    profiles: camera.Profile[], generation: number,
    rotationDegrees: number): Promise<camera.PreviewOutput> {
    const source: HandLandmarkFrameSource | undefined = this.handFrameSource;
    const profile: camera.Profile | undefined =
      this.selectHandAnalysisProfile(profiles, rotationDegrees);
    if (source === undefined) {
      throw new Error('未配置手势分析帧源');
    }
    if (profile === undefined) {
      const reason: string = '当前设备未提供手势分析所需的 YUV420 预览格式';
      await source.rejectCameraOutput(reason);
      throw new Error(reason);
    }
    let output: camera.PreviewOutput | undefined = undefined;
    try {
      const frameProfile: HandFrameSourceProfile = {
        width: profile.size.width,
        height: profile.size.height,
        cameraFormat: profile.format,
        mirrored: this.useFrontCamera,
        rotationDegrees: rotationDegrees,
        previewWidth: this.previewWidth,
        previewHeight: this.previewHeight,
        qualityWarning: this.handAnalysisWarning
      };
      const analysisSurfaceId: string = await source.prepare(frameProfile);
      if (!this.isCurrentGeneration(generation)) {
        await source.stop();
        throw new Error('前摄手势分析启动已取消');
      }
      output = cameraManager.createPreviewOutput(profile, analysisSurfaceId);
      if (!session.canAddOutput(output)) {
        await output.release();
        output = undefined;
        throw new Error('当前设备不支持显示预览与手势分析双路输出');
      }
      session.addOutput(output);
      return output;
    } catch (error) {
      if (output !== undefined) {
        try {
          await output.release();
        } catch (releaseError) {
        }
      }
      if (!this.isCurrentGeneration(generation)) {
        // 抽屉遮挡、页面切换或屏幕旋转造成的正常卸载不是模型故障，保持可重试的 IDLE。
        await source.stop();
        throw new Error('前摄手势分析启动已取消');
      }
      let reason: string = '手势分析入口不可用';
      if (error instanceof Error && error.message.length > 0) {
        reason = error.message;
      }
      await source.rejectCameraOutput(reason);
      throw new Error(reason);
    }
  }

  private selectHandAnalysisProfile(profiles: camera.Profile[],
    rotationDegrees: number): camera.Profile | undefined {
    const quarterTurns: number = ((Math.round(rotationDegrees / 90.0) % 4) + 4) % 4;
    const previewAspect: number = this.previewWidth / Math.max(1.0, this.previewHeight);
    let preferred: camera.Profile | undefined = undefined;
    let preferredPixels: number = Number.MAX_VALUE;
    let preferredAspectDelta: number = Number.MAX_VALUE;
    let fallback: camera.Profile | undefined = undefined;
    let fallbackPixels: number = Number.MAX_VALUE;
    for (let index: number = 0; index < profiles.length; index++) {
      const profile: camera.Profile = profiles[index];
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP) {
        continue;
      }
      const pixels: number = profile.size.width * profile.size.height;
      if (pixels < fallbackPixels) {
        fallback = profile;
        fallbackPixels = pixels;
      }
      // 320×240 已足够支撑手掌检测的 192/224 输入，优先使用最低像素数，
      // 只在像素数相同或非常接近时再用视口宽高比打破平局。
      if (profile.size.width < 320 || profile.size.height < 240) {
        continue;
      }
      const rotatedWidth: number = quarterTurns % 2 === 0 ? profile.size.width : profile.size.height;
      const rotatedHeight: number = quarterTurns % 2 === 0 ? profile.size.height : profile.size.width;
      const aspectDelta: number =
        Math.abs(rotatedWidth / Math.max(1.0, rotatedHeight) - previewAspect);
      if (pixels < preferredPixels ||
        (pixels === preferredPixels && aspectDelta < preferredAspectDelta)) {
        preferred = profile;
        preferredPixels = pixels;
        preferredAspectDelta = aspectDelta;
      }
    }
    if (preferred !== undefined) {
      this.handAnalysisWarning = '';
      return preferred;
    }
    if (fallback !== undefined) {
      this.handAnalysisWarning =
        `分析帧仅 ${fallback.size.width}×${fallback.size.height}，低于模型建议尺寸，识别精度可能下降`;
    } else {
      this.handAnalysisWarning = '';
    }
    return fallback;
  }

  private selectDisplayPreviewProfile(profiles: camera.Profile[]): camera.Profile {
    const targetWidth: number = 1280;
    const targetHeight: number = 720;
    const targetAspect: number = targetWidth / targetHeight;
    let selected: camera.Profile = profiles[0];
    let selectedScore: number = Number.MAX_VALUE;
    let selectedPixels: number = Number.MAX_VALUE;
    for (let index: number = 0; index < profiles.length; index++) {
      const profile: camera.Profile = profiles[index];
      const width: number = profile.size.width;
      const height: number = profile.size.height;
      if (width < 640 || height < 480) {
        continue;
      }
      const pixels: number = width * height;
      const aspect: number = width / Math.max(1.0, height);
      const aspectPenalty: number = Math.abs(aspect - targetAspect) * targetWidth;
      const sizePenalty: number = Math.abs(width - targetWidth) + Math.abs(height - targetHeight);
      const score: number = sizePenalty + aspectPenalty;
      if (score < selectedScore || (Math.abs(score - selectedScore) < 0.001 && pixels < selectedPixels)) {
        selected = profile;
        selectedScore = score;
        selectedPixels = pixels;
      }
    }
    return selected;
  }

  private async stopPreview(): Promise<void> {
    if (this.stopping) {
      return;
    }
    const session = this.captureSession;
    const output = this.previewOutput;
    const analysisOutput = this.analysisOutput;
    const input = this.cameraInput;
    const releaseActiveLease: boolean = this.activeLeaseHeld;
    this.captureSession = undefined;
    this.previewOutput = undefined;
    this.analysisOutput = undefined;
    this.cameraInput = undefined;
    this.activeLeaseHeld = false;
    this.previewStarted = false;
    this.stopping = true;
    try {
      await this.releasePreviewResources(session, output, analysisOutput, input);
    } finally {
      if (releaseActiveLease) {
        CameraPreviewCoordinator.release(this.cameraOwnerId);
      }
      this.stopping = false;
      this.restartIfNeeded();
    }
  }

  private async releasePreviewResources(session: camera.PhotoSession | undefined,
    output: camera.PreviewOutput | undefined, analysisOutput: camera.PreviewOutput | undefined,
    input: camera.CameraInput | undefined): Promise<void> {
    try {
      if (session !== undefined) session.off('error', this.sessionErrorCallback);
    } catch (error) {
    }
    try {
      if (session !== undefined) await session.stop();
    } catch (error) {
      // 页面销毁或启动中断时系统可能尚未启动、也可能已经回收会话，继续释放即可。
    }
    try {
      if (session !== undefined) await session.release();
    } catch (error) {
    }
    try {
      if (this.handFrameSource !== undefined) await this.handFrameSource.stop();
    } catch (error) {
    }
    try {
      if (analysisOutput !== undefined) await analysisOutput.release();
    } catch (error) {
    }
    try {
      if (output !== undefined) await output.release();
    } catch (error) {
    }
    try {
      if (input !== undefined) await input.close();
    } catch (error) {
    }
  }

  private async rejectHandAnalysisStartup(reason: string): Promise<void> {
    const source: HandLandmarkFrameSource | undefined = this.handFrameSource;
    if (!this.useFrontCamera || source === undefined ||
      source.getStatus().state === HandFrameSourceState.ERROR) {
      return;
    }
    try {
      await source.rejectCameraOutput(reason);
    } catch (error) {
      // 页面已经收到原始失败原因；状态回传本身失败时仍由本组件完成相机资源释放。
    }
  }

  private refreshDisplayRotation(): void {
    try {
      const rawRotation: number = Math.round(display.getDefaultDisplaySync().rotation);
      if (rawRotation === 90) {
        this.displayRotation = camera.ImageRotation.ROTATION_90;
      } else if (rawRotation === 180) {
        this.displayRotation = camera.ImageRotation.ROTATION_180;
      } else if (rawRotation === 270) {
        this.displayRotation = camera.ImageRotation.ROTATION_270;
      } else {
        // Display.rotation 在 API 22 中通常返回 0/1/2/3；同时兼容直接返回角度的设备实现。
        const normalized: number = ((rawRotation % 4) + 4) % 4;
        if (normalized === 1) {
          this.displayRotation = camera.ImageRotation.ROTATION_90;
        } else if (normalized === 2) {
          this.displayRotation = camera.ImageRotation.ROTATION_180;
        } else if (normalized === 3) {
          this.displayRotation = camera.ImageRotation.ROTATION_270;
        } else {
          this.displayRotation = camera.ImageRotation.ROTATION_0;
        }
      }
    } catch (error) {
      this.displayRotation = camera.ImageRotation.ROTATION_0;
    }
  }

  private configurePreviewRotation(output: camera.PreviewOutput): number {
    const previewRotation: camera.ImageRotation = output.getPreviewRotation(this.displayRotation);
    const rotationDegrees: number = Number(previewRotation);
    if (!Number.isFinite(rotationDegrees)) {
      throw new Error('相机未返回有效预览方向');
    }
    output.setPreviewRotation(previewRotation, false);
    return rotationDegrees;
  }

  private applyDisplayRotationChange(): void {
    if (this.starting) {
      // 启动中的输出仍保存在局部变量，无法原地更新；推进代次后由 finally 安全释放并重启。
      this.lifecycleGeneration++;
      this.restartRequested = this.surfaceId.length > 0;
      this.cameraStatus = '屏幕方向已变化，正在重启前摄';
      this.stopPreview();
      return;
    }
    const output: camera.PreviewOutput | undefined = this.previewOutput;
    if (output === undefined || !this.previewStarted) {
      return;
    }
    try {
      this.previewRotationDegrees = this.configurePreviewRotation(output);
      this.updateHandPresentation();
    } catch (error) {
      this.lifecycleGeneration++;
      this.restartRequested = this.componentVisible && this.surfaceId.length > 0;
      this.cameraStatus = '无法更新相机方向，正在重启';
      this.stopPreview();
    }
  }

  private updateHandPresentation(): void {
    const source: HandLandmarkFrameSource | undefined = this.handFrameSource;
    if (!this.useFrontCamera || source === undefined) {
      return;
    }
    const profile: HandFramePresentationProfile = {
      mirrored: true,
      rotationDegrees: this.previewRotationDegrees,
      previewWidth: this.previewWidth,
      previewHeight: this.previewHeight
    };
    source.updatePresentation(profile);
  }

  private isCurrentGeneration(generation: number): boolean {
    return this.componentVisible && this.surfaceId.length > 0 && generation === this.lifecycleGeneration;
  }

  private restartIfNeeded(): void {
    if (!this.restartRequested || this.starting || this.stopping || this.previewStarted ||
      !this.componentVisible || this.surfaceId.length === 0) {
      return;
    }
    this.restartRequested = false;
    this.startPreview(this.lifecycleGeneration);
  }

  private errorMessage(error: Object, fallback: string): string {
    if (error instanceof Error && error.message.length > 0) {
      return `${fallback}：${error.message}`;
    }
    return fallback;
  }
}

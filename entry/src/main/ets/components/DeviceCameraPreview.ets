import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import {
  HandFrameSourceProfile,
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

  aboutToAppear(): void {
    this.componentVisible = true;
    this.lifecycleGeneration++;
  }

  aboutToDisappear(): void {
    this.componentVisible = false;
    this.lifecycleGeneration++;
    this.restartRequested = false;
    this.surfaceId = '';
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
      if (!await this.requestCameraPermission(generation) || !this.isCurrentGeneration(generation)) {
        return;
      }
      const context = AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
      if (context === undefined) {
        this.cameraStatus = '相机上下文未就绪';
        return;
      }
      this.cameraStatus = this.useFrontCamera ? '正在启动前摄' : '正在启动后摄';
      const cameraManager = camera.getCameraManager(context);
      const device = this.selectCamera(cameraManager.getSupportedCameras());
      if (device === undefined) {
        this.cameraStatus = this.useFrontCamera ? '设备没有可用前摄' : '设备没有可用后摄';
        return;
      }
      const capability = cameraManager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      if (capability.previewProfiles.length === 0) {
        this.cameraStatus = '设备未提供预览规格';
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
      output = cameraManager.createPreviewOutput(capability.previewProfiles[0], this.surfaceId);
      session = cameraManager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      session.on('error', this.sessionErrorCallback);
      session.beginConfig();
      session.addInput(input);
      session.addOutput(output);

      // PreviewOutput 的 frameStart/frameEnd 只表示时序，不包含像素。只有显式注入真实
      // HandLandmarkFrameSource 时，才尝试增加指向 ImageReceiver 的第二路 YUV Surface。
      // canAddOutput 会在真机上校验并发输出组合，失败时保留主预览且明确通知分析入口。
      if (this.useFrontCamera && this.handFrameSource !== undefined) {
        analysisOutput = await this.createHandAnalysisOutput(
          cameraManager, session, capability.previewProfiles, generation);
      }
      if (!this.isCurrentGeneration(generation)) return;
      await session.commitConfig();
      if (!this.isCurrentGeneration(generation)) return;
      await session.start();
      if (!this.isCurrentGeneration(generation)) return;
      if (analysisOutput !== undefined && this.handFrameSource !== undefined) {
        this.handFrameSource.start();
      }

      // 只有完整启动且代次仍有效时才移交所有权；stopPreview 之后负责统一释放。
      this.cameraInput = input;
      this.previewOutput = output;
      this.analysisOutput = analysisOutput;
      this.captureSession = session;
      this.activeLeaseHeld = true;
      resourcesTransferred = true;
      this.previewStarted = true;
      this.cameraStatus = this.useFrontCamera ? '前摄运行中' : '后摄运行中';
    } catch (error) {
      if (this.isCurrentGeneration(generation)) {
        this.cameraStatus = '相机启动失败';
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
    profiles: camera.Profile[], generation: number): Promise<camera.PreviewOutput | undefined> {
    const source: HandLandmarkFrameSource | undefined = this.handFrameSource;
    const profile: camera.Profile | undefined = this.selectHandAnalysisProfile(profiles);
    if (source === undefined) {
      return undefined;
    }
    if (profile === undefined) {
      await source.rejectCameraOutput('当前设备未提供手势分析所需的 YUV420 预览格式');
      return undefined;
    }
    let output: camera.PreviewOutput | undefined = undefined;
    try {
      const frameProfile: HandFrameSourceProfile = {
        width: profile.size.width,
        height: profile.size.height,
        cameraFormat: profile.format,
        mirrored: true,
        rotationDegrees: 0
      };
      const analysisSurfaceId: string = await source.prepare(frameProfile);
      if (!this.isCurrentGeneration(generation)) {
        await source.stop();
        return undefined;
      }
      output = cameraManager.createPreviewOutput(profile, analysisSurfaceId);
      if (!session.canAddOutput(output)) {
        await output.release();
        await source.rejectCameraOutput('当前设备不支持显示预览与手势分析双路输出');
        return undefined;
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
      let reason: string = '手势分析入口不可用；前摄预览仍可继续';
      if (error instanceof Error && error.message.length > 0) {
        reason = error.message;
      }
      await source.rejectCameraOutput(reason);
      return undefined;
    }
  }

  private selectHandAnalysisProfile(profiles: camera.Profile[]): camera.Profile | undefined {
    let selected: camera.Profile | undefined = undefined;
    let selectedPixels: number = Number.MAX_VALUE;
    for (let index: number = 0; index < profiles.length; index++) {
      const profile: camera.Profile = profiles[index];
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP) {
        continue;
      }
      const pixels: number = profile.size.width * profile.size.height;
      if (pixels < selectedPixels) {
        selected = profile;
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
}

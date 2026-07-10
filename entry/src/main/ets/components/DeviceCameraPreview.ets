import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import {
  HandFrameSourceProfile,
  HandLandmarkFrameSource
} from '../services/HandLandmarkAnalyzer';

@Component
export struct DeviceCameraPreview {
  @Prop useFrontCamera: boolean = false;
  @Prop cornerRadius: number = 0;
  @Prop handFrameSource: HandLandmarkFrameSource | undefined = undefined;
  @State private cameraStatus: string = '等待相机';
  @State private previewStarted: boolean = false;

  private surfaceId: string = '';
  private starting: boolean = false;
  private controller: XComponentController = new XComponentController();
  private cameraInput?: camera.CameraInput;
  private previewOutput?: camera.PreviewOutput;
  private analysisOutput?: camera.PreviewOutput;
  private captureSession?: camera.Session;

  aboutToDisappear(): void {
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
      this.surfaceId = this.controller.getXComponentSurfaceId();
      if (this.surfaceId.length === 0) {
        this.cameraStatus = '预览画面未就绪';
        return;
      }
      this.startPreview();
    } catch (error) {
      this.cameraStatus = '无法创建预览画面';
    }
  }

  private async requestCameraPermission(): Promise<boolean> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
      if (context === undefined) {
        this.cameraStatus = '应用上下文未就绪';
        return false;
      }
      const manager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.CAMERA'];
      const result = await manager.requestPermissionsFromUser(context, permissions);
      if (result.authResults.length === 0 || result.authResults[0] !== 0) {
        this.cameraStatus = '请授予相机权限';
        return false;
      }
      return true;
    } catch (error) {
      this.cameraStatus = '相机权限请求失败';
      return false;
    }
  }

  private async startPreview(): Promise<void> {
    if (this.starting || this.previewStarted || this.surfaceId.length === 0) {
      return;
    }
    this.starting = true;
    try {
      if (!await this.requestCameraPermission()) {
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

      // 预览必须输出到 XComponent 的 Surface。模式切换时父组件销毁当前实例，
      // stopPreview 会按 Session -> Output -> Input 的顺序释放，避免前后摄互相抢占。
      this.cameraInput = cameraManager.createCameraInput(device);
      await this.cameraInput.open();
      this.previewOutput = cameraManager.createPreviewOutput(capability.previewProfiles[0], this.surfaceId);
      this.captureSession = cameraManager.createSession<camera.PhotoSession>(camera.SceneMode.NORMAL_PHOTO);
      this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);

      // PreviewOutput 的 frameStart/frameEnd 只表示时序，不包含像素。只有显式注入真实
      // HandLandmarkFrameSource 时，才尝试增加指向 ImageReceiver 的第二路 YUV Surface。
      // canAddOutput 会在真机上校验并发输出组合，失败时保留主预览且明确通知分析入口。
      if (this.useFrontCamera && this.handFrameSource !== undefined) {
        await this.tryAddHandAnalysisOutput(cameraManager, this.captureSession, capability.previewProfiles);
      }
      await this.captureSession.commitConfig();
      await this.captureSession.start();
      if (this.analysisOutput !== undefined && this.handFrameSource !== undefined) {
        this.handFrameSource.start();
      }
      this.previewStarted = true;
      this.cameraStatus = this.useFrontCamera ? '前摄运行中' : '后摄运行中';
    } catch (error) {
      this.cameraStatus = '相机启动失败';
      await this.stopPreview();
    } finally {
      this.starting = false;
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

  private async tryAddHandAnalysisOutput(cameraManager: camera.CameraManager, session: camera.Session,
    profiles: camera.Profile[]): Promise<void> {
    const source: HandLandmarkFrameSource | undefined = this.handFrameSource;
    const profile: camera.Profile | undefined = this.selectHandAnalysisProfile(profiles);
    if (source === undefined) {
      return;
    }
    if (profile === undefined) {
      await source.rejectCameraOutput('当前设备未提供手势分析所需的 YUV420 预览格式');
      return;
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
      output = cameraManager.createPreviewOutput(profile, analysisSurfaceId);
      if (!session.canAddOutput(output)) {
        await output.release();
        await source.rejectCameraOutput('当前设备不支持显示预览与手势分析双路输出');
        return;
      }
      session.addOutput(output);
      this.analysisOutput = output;
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
    const session = this.captureSession;
    const output = this.previewOutput;
    const analysisOutput = this.analysisOutput;
    const input = this.cameraInput;
    this.captureSession = undefined;
    this.previewOutput = undefined;
    this.analysisOutput = undefined;
    this.cameraInput = undefined;
    this.previewStarted = false;

    try {
      if (session !== undefined) {
        await session.stop();
        await session.release();
      }
    } catch (error) {
      // 页面销毁时系统可能已经回收会话，继续释放剩余对象即可。
    }
    try {
      if (this.handFrameSource !== undefined) {
        await this.handFrameSource.stop();
      }
    } catch (error) {
    }
    try {
      if (analysisOutput !== undefined) {
        await analysisOutput.release();
      }
    } catch (error) {
    }
    try {
      if (output !== undefined) {
        await output.release();
      }
    } catch (error) {
    }
    try {
      if (input !== undefined) {
        await input.close();
      }
    } catch (error) {
    }
  }
}

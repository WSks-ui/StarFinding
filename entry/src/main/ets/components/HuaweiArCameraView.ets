import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { arEngine, ARView, arViewController } from '@kit.AREngine';
import { Matrix4 } from '@kit.ArkUI';
import { Node, Scene } from '@kit.ArkGraphics3D';
import {
  ArEngineCapabilityResult,
  ArEngineErrorCategory,
  ArEngineFailure,
  HuaweiArCameraTrackingReason,
  HuaweiArCameraTrackingState,
  HuaweiArFrameListener,
  HuaweiArFrameSnapshot,
  HuaweiArQuaternion,
  HuaweiArStatusListener,
  HuaweiArViewPhase,
  HuaweiArViewStatus
} from '../models/HuaweiArModels';
import { ArEngineCapabilityService } from '../services/ArEngineCapabilityService';

const AR_NEAR_CLIP_METERS: number = 0.1;
const AR_FAR_CLIP_METERS: number = 1000.0;

@Component
export struct HuaweiArCameraView {
  @Prop cornerRadius: number = 0;
  @State private arContext?: arViewController.ARViewContext = undefined;
  @State private phase: HuaweiArViewPhase = HuaweiArViewPhase.IDLE;
  @State private statusMessage: string = '等待启动 AR 天穹';

  onFrameUpdate: HuaweiArFrameListener = (snapshot: HuaweiArFrameSnapshot): void => {
  };
  onStatusChange: HuaweiArStatusListener = (status: HuaweiArViewStatus): void => {
  };

  private mounted: boolean = false;
  private initializing: boolean = false;
  private destroying: boolean = false;
  private restartRequested: boolean = false;
  private lifecycleGeneration: number = 0;
  private activeContext?: arViewController.ARViewContext = undefined;
  private frameCallback?: HuaweiArViewCallback = undefined;
  private lastFrameErrorKey: string = '';

  aboutToAppear(): void {
    this.mounted = true;
    this.lifecycleGeneration++;
    this.startArView(this.lifecycleGeneration);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.lifecycleGeneration++;
    this.restartRequested = false;
    this.destroyArView();
  }

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      if (this.arContext) {
        ARView({ context: this.arContext })
          .width('100%')
          .height('100%')
      } else {
        Column({ space: 10 }) {
          if (this.phase !== HuaweiArViewPhase.UNSUPPORTED &&
            this.phase !== HuaweiArViewPhase.PERMISSION_REQUIRED &&
            this.phase !== HuaweiArViewPhase.FAILED) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color('#67D7FF')
          }
          Text(this.statusMessage)
            .fontSize(13)
            .fontColor('#D5E6F4')
            .textAlign(TextAlign.Center)
            .maxLines(2)
        }
        .padding(20)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#03060C')
    .borderRadius(this.cornerRadius)
    .clip(true)
  }

  private async startArView(generation: number): Promise<void> {
    if (this.initializing || this.destroying || this.activeContext !== undefined) {
      this.restartRequested = this.mounted && this.activeContext === undefined;
      return;
    }
    this.initializing = true;
    this.restartRequested = false;
    this.emitStatus(HuaweiArViewPhase.CHECKING, '正在检测 AR Engine 能力');

    let scene: Scene | undefined = undefined;
    let context: arViewController.ARViewContext | undefined = undefined;
    let callback: HuaweiArViewCallback | undefined = undefined;
    try {
      const capability: ArEngineCapabilityResult = ArEngineCapabilityService.inspect();
      if (!capability.available) {
        this.emitStatus(HuaweiArViewPhase.UNSUPPORTED, capability.message);
        return;
      }
      if (!await this.ensureArPermissions()) {
        const permissionFailure: ArEngineFailure = ArEngineCapabilityService.classifyCode(201,
          '用户未授予相机权限');
        this.emitStatus(HuaweiArViewPhase.PERMISSION_REQUIRED, permissionFailure.userMessage, permissionFailure);
        return;
      }
      if (!this.isCurrentGeneration(generation)) {
        return;
      }

      this.emitStatus(HuaweiArViewPhase.INITIALIZING, '正在启动 AR 天穹');
      scene = await Scene.load();
      if (!this.isCurrentGeneration(generation)) {
        scene.destroy();
        scene = undefined;
        return;
      }

      context = new arViewController.ARViewContext();
      callback = new HuaweiArViewCallback(
        (snapshot: HuaweiArFrameSnapshot): void => {
          this.handleFrameSnapshot(snapshot);
        },
        (failure: ArEngineFailure): void => {
          this.handleFrameFailure(failure);
        }
      );
      context.scene = scene;
      scene = undefined;
      context.callback = callback;
      context.config = {
        type: arEngine.ARType.WORLD,
        planeFindingMode: arEngine.ARPlaneFindingMode.DISABLED,
        powerMode: arEngine.ARPowerMode.POWER_SAVING,
        focusMode: arEngine.ARFocusMode.AUTO,
        semanticMode: arEngine.ARSemanticMode.NONE,
        poseMode: arEngine.ARPoseMode.GRAVITY_AND_HEADING,
        depthMode: arEngine.ARDepthMode.DISABLED,
        meshMode: arEngine.ARMeshMode.DISABLED,
        semanticDenseMode: arEngine.ARSemanticDenseMode.DISABLED
      };
      await context.init();

      if (!this.isCurrentGeneration(generation)) {
        await callback.stopAndWait();
        await context.destroy();
        context = undefined;
        callback = undefined;
        return;
      }
      this.activeContext = context;
      this.frameCallback = callback;
      this.arContext = context;
      context = undefined;
      callback = undefined;
      this.emitStatus(HuaweiArViewPhase.RUNNING, 'AR 天穹运行中');
    } catch (error) {
      if (callback !== undefined) {
        await callback.stopAndWait();
      }
      if (context !== undefined) {
        // ARViewContext.destroy 会一并销毁 ARSession 和 Scene，不能再手动 release session。
        try {
          await context.destroy();
        } catch (destroyError) {
        }
      } else if (scene !== undefined) {
        scene.destroy();
      }
      if (this.isCurrentGeneration(generation)) {
        const failure: ArEngineFailure = ArEngineCapabilityService.classifyError(error as Error);
        const phase: HuaweiArViewPhase = failure.category === ArEngineErrorCategory.DEVICE_UNSUPPORTED ?
          HuaweiArViewPhase.UNSUPPORTED : HuaweiArViewPhase.FAILED;
        this.emitStatus(phase, failure.userMessage, failure);
      }
    } finally {
      this.initializing = false;
      this.restartIfNeeded();
    }
  }

  private async ensureArPermissions(): Promise<boolean> {
    this.emitStatus(HuaweiArViewPhase.REQUESTING_PERMISSION, '正在确认相机权限');
    const abilityContext: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (abilityContext === undefined) {
      throw new Error('应用上下文尚未就绪，无法请求 AR 权限');
    }
    // 陀螺仪和加速度计属于 system_grant，不能放进运行时授权请求；这里只请求 user_grant 相机权限。
    const permissions: Permissions[] = ['ohos.permission.CAMERA'];
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(abilityContext, permissions);
      if (result.authResults.length !== permissions.length) {
        return false;
      }
      // authResults 与 permissions 使用相同顺序；相机未授权时不能调用 ARViewContext.init。
      for (let index: number = 0; index < permissions.length; index++) {
        if (result.authResults[index] !== 0) {
          return false;
        }
      }
      return true;
    } catch (error) {
      // 权限服务异常交给统一 init 错误路径分类，避免把系统故障误报为用户拒绝。
      throw error as Error;
    }
  }

  private async destroyArView(): Promise<void> {
    if (this.destroying) {
      return;
    }
    const context: arViewController.ARViewContext | undefined = this.activeContext;
    const callback: HuaweiArViewCallback | undefined = this.frameCallback;
    this.activeContext = undefined;
    this.frameCallback = undefined;
    this.arContext = undefined;
    if (context === undefined) {
      return;
    }

    this.destroying = true;
    try {
      if (callback !== undefined) {
        // 等待正在处理的帧释放 ARPose/ARFrame 后再销毁上下文，避免原生资源并发回收。
        await callback.stopAndWait();
      }
      await context.destroy();
      this.emitStatus(HuaweiArViewPhase.DESTROYED, 'AR 天穹已停止');
    } catch (error) {
      const failure: ArEngineFailure = ArEngineCapabilityService.classifyError(error as Error);
      this.emitStatus(HuaweiArViewPhase.FAILED, failure.userMessage, failure);
    } finally {
      this.destroying = false;
      this.restartIfNeeded();
    }
  }

  private restartIfNeeded(): void {
    if (!this.mounted || this.initializing || this.destroying || this.activeContext !== undefined) {
      return;
    }
    if (!this.restartRequested) {
      return;
    }
    this.restartRequested = false;
    this.startArView(this.lifecycleGeneration);
  }

  private isCurrentGeneration(generation: number): boolean {
    return this.mounted && generation === this.lifecycleGeneration;
  }

  private handleFrameSnapshot(snapshot: HuaweiArFrameSnapshot): void {
    if (!this.mounted) {
      return;
    }
    if (snapshot.displayQuaternion === undefined) {
      this.emitStatus(HuaweiArViewPhase.LIMITED, 'AR 跟踪暂时受限，请缓慢移动设备');
    } else if (this.phase === HuaweiArViewPhase.LIMITED) {
      this.lastFrameErrorKey = '';
      this.emitStatus(HuaweiArViewPhase.RUNNING, 'AR 天穹运行中');
    }
    try {
      this.onFrameUpdate(snapshot);
    } catch (error) {
      // 上层绘制回调异常不属于 AR Engine 故障，不能阻断后续帧及原生资源释放。
    }
  }

  private handleFrameFailure(failure: ArEngineFailure): void {
    if (!this.mounted) {
      return;
    }
    const errorKey: string = `${failure.code}:${failure.category}`;
    if (errorKey === this.lastFrameErrorKey) {
      return;
    }
    this.lastFrameErrorKey = errorKey;
    this.emitStatus(HuaweiArViewPhase.LIMITED, failure.userMessage, failure);
  }

  private emitStatus(phase: HuaweiArViewPhase, message: string, failure?: ArEngineFailure): void {
    if (this.phase === phase && this.statusMessage === message && failure === undefined) {
      return;
    }
    this.phase = phase;
    this.statusMessage = message;
    const status: HuaweiArViewStatus = {
      phase: phase,
      message: message,
      failure: failure
    };
    try {
      this.onStatusChange(status);
    } catch (error) {
      // 状态观察者不得影响 ARView 生命周期。
    }
  }
}

/**
 * ARView 的逐帧桥接器。帧数据必须复制后再交给上层，因为 ARFrame/ARPose 在回调结束前
 * 就会释放；布尔锁用于丢弃上一帧尚未完成释放时到达的新帧，避免异步重入堆积。
 */
class HuaweiArViewCallback extends arViewController.ARViewCallback {
  private processingFrame: boolean = false;
  private stopped: boolean = false;
  private idleWaiters: Array<() => void> = [];
  private readonly frameListener: HuaweiArFrameListener;
  private readonly failureListener: (failure: ArEngineFailure) => void;

  constructor(frameListener: HuaweiArFrameListener, failureListener: (failure: ArEngineFailure) => void) {
    super();
    this.frameListener = frameListener;
    this.failureListener = failureListener;
  }

  onAnchorAdd(ctx: arViewController.ARViewContext, node: Node, anchor: arEngine.ARAnchor): void {
  }

  onAnchorUpdate(ctx: arViewController.ARViewContext, node: Node, anchor: arEngine.ARAnchor): void {
  }

  async onFrameUpdate(ctx: arViewController.ARViewContext, sysBootTs: number): Promise<void> {
    if (this.stopped || this.processingFrame || ctx.session === undefined) {
      return;
    }
    this.processingFrame = true;
    let frame: arEngine.ARFrame | undefined = undefined;
    let pose: arEngine.ARPose | undefined = undefined;
    try {
      const session: arEngine.ARSession = ctx.session;
      frame = session.getFrame();
      const camera: arEngine.ARCamera = frame.getCamera();
      let displayQuaternion: HuaweiArQuaternion | undefined = undefined;
      if (camera.state === arEngine.ARTrackingState.TRACKING) {
        pose = camera.getDisplayOrientedPose();
        displayQuaternion = {
          x: pose.rotation.x,
          y: pose.rotation.y,
          z: pose.rotation.z,
          w: pose.rotation.w
        };
      }
      const snapshot: HuaweiArFrameSnapshot = {
        frameTimestampNs: frame.timestamp,
        systemBootTimestampNs: sysBootTs,
        cameraState: mapTrackingState(camera.state),
        cameraStateReason: mapTrackingReason(camera.stateReason),
        viewMatrix: copyMatrix(camera.viewMatrix),
        projectionMatrix: copyMatrix(camera.getProjectionMatrix(AR_NEAR_CLIP_METERS, AR_FAR_CLIP_METERS)),
        displayQuaternion: displayQuaternion
      };
      this.frameListener(snapshot);
    } catch (error) {
      this.failureListener(ArEngineCapabilityService.classifyError(error as Error));
    } finally {
      if (pose !== undefined) {
        try {
          await pose.release();
        } catch (releaseError) {
        }
      }
      if (frame !== undefined) {
        try {
          await frame.release();
        } catch (releaseError) {
        }
      }
      this.processingFrame = false;
      this.resolveIdleWaiters();
    }
  }

  async stopAndWait(): Promise<void> {
    this.stopped = true;
    if (!this.processingFrame) {
      return;
    }
    await new Promise<void>((resolve: () => void): void => {
      this.idleWaiters.push(resolve);
    });
  }

  private resolveIdleWaiters(): void {
    if (this.processingFrame || this.idleWaiters.length === 0) {
      return;
    }
    const waiters: Array<() => void> = this.idleWaiters;
    this.idleWaiters = [];
    for (let index: number = 0; index < waiters.length; index++) {
      waiters[index]();
    }
  }
}

function copyMatrix(source: Matrix4): Matrix4 {
  return [
    source[0], source[1], source[2], source[3],
    source[4], source[5], source[6], source[7],
    source[8], source[9], source[10], source[11],
    source[12], source[13], source[14], source[15]
  ];
}

function mapTrackingState(state: arEngine.ARTrackingState): HuaweiArCameraTrackingState {
  if (state === arEngine.ARTrackingState.TRACKING) return HuaweiArCameraTrackingState.TRACKING;
  if (state === arEngine.ARTrackingState.PAUSED) return HuaweiArCameraTrackingState.PAUSED;
  return HuaweiArCameraTrackingState.STOPPED;
}

function mapTrackingReason(reason: arEngine.ARTrackingStateReason): HuaweiArCameraTrackingReason {
  if (reason === arEngine.ARTrackingStateReason.NONE) return HuaweiArCameraTrackingReason.NONE;
  if (reason === arEngine.ARTrackingStateReason.EXCESSIVE_MOTION) {
    return HuaweiArCameraTrackingReason.EXCESSIVE_MOTION;
  }
  if (reason === arEngine.ARTrackingStateReason.INSUFFICIENT_FEATURES) {
    return HuaweiArCameraTrackingReason.INSUFFICIENT_FEATURES;
  }
  return HuaweiArCameraTrackingReason.UNKNOWN;
}

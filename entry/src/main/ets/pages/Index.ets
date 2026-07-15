import { common } from '@kit.AbilityKit';
import { ArSkyDome } from '../components/ArSkyDome';
import { DeviceCameraPreview } from '../components/DeviceCameraPreview';
import { DeviceWorkspace } from '../components/DeviceWorkspace';
import lazy { HuaweiArCameraView } from '../components/HuaweiArCameraView';
import { NormalSkyControls } from '../components/NormalSkyControls';
import { NormalSkyMap } from '../components/NormalSkyMap';
import { NormalSkyOrientationOverlay } from '../components/NormalSkyOrientationOverlay';
import { NormalSkyTimeControls } from '../components/NormalSkyTimeControls';
import { PostWorkspace } from '../components/PostWorkspace';
import { SkyWorkspace } from '../components/SkyWorkspace';
import { TaskWorkspace } from '../components/TaskWorkspace';
import { WorkspaceNavigationDock } from '../components/WorkspaceNavigationDock';
import { WorkspaceTransitionHost } from '../components/WorkspaceTransitionHost';
import { CelestialCatalog } from '../data';
import {
  ArCalibration,
  CameraCapabilities,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  ConnectionState,
  CaptureMode,
  CapturePlan,
  CaptureTask,
  DevicePose,
  EnhancementTask,
  EquatorialCoordinate,
  GestureFrame,
  HandGesture,
  HorizontalCoordinate,
  ImageFormat,
  MountState,
  MountTargetCoordinate,
  NormalSkyScene,
  NormalSkyPlaybackSpeed,
  NormalSkyTimeMode,
  NormalSkyTimeState,
  NormalSkyViewState,
  NormalSkyViewport,
  ObservationPlanningConstraints,
  ObservationPlanningResult,
  ObservationWindow,
  ObserverState,
  OutingRecommendation,
  ProjectedSkyObject,
  RefractionMode,
  SkyLayerVisibility,
  SkyGuideInsets,
  SkyMapOrientation,
  SkyMapSize,
  TrackingMode,
  TaskStatus,
  VisibilityStatus,
  WeatherDataStatus,
  WeatherForecast,
  WeatherHourlySample
} from '../models';
import { DEFAULT_SKY_LAYERS } from '../models/NormalSkyModels';
import {
  ArTrackingQuality,
  ArTrackingSource,
  Quaternion,
  SkyDomeFrame
} from '../models/ArSkyModels';
import type {
  HuaweiArFrameSnapshot,
  HuaweiArViewStatus
} from '../models/HuaweiArModels';
import { HuaweiArViewPhase } from '../models/HuaweiArModels';
import {
  AstronomyService,
  AIEnhancementClient,
  CameraHandFrameSource,
  CaptureWorkflowCoordinator,
  CaptureWorkflowProgress,
  CaptureWorkflowResult,
  DevicePoseService,
  EphemerisService,
  GatewayTask,
  GestureInterpreter,
  HandFrameSourceStatus,
  HandLandmarkAnalysisResult,
  NormalSkyGestureController,
  NormalSkyGestureUpdate,
  NormalSkyLayoutService,
  NormalSkyCatalogMetadata,
  NormalSkyCatalogService,
  NormalSkyProjectionService,
  NormalSkySceneService,
  NormalSkyTimeService,
  NormalSkyViewStateService,
  ObserverLocationResult,
  ObserverLocationService,
  OnStepLX200Client,
  ObservationPlanningService,
  RaspberryPiClient,
  VisibleStar,
  VisibleStarCatalogMetadata,
  VisibleStarCatalogService,
  WeatherForecastService,
  UnavailableHandLandmarkAnalyzer
} from '../services';
import { ArEngineCapabilityService } from '../services/ArEngineCapabilityService';
import { HuaweiArPoseAdapter } from '../services/HuaweiArPoseAdapter';
import { SkyDomeProjectionService } from '../services/SkyDomeProjectionService';
import { SkyDomeSceneService } from '../services/SkyDomeSceneService';
import { MotionTokens } from '../utils/MotionTokens';

/** 星图首屏只展示少量重点目标；详情、搜索和规划统一使用 CelestialCatalog 的规范 ID。 */
const FEATURED_TARGET_IDS: string[] = [
  'star-vega', 'star-altair', 'star-deneb', 'messier-31', 'messier-8', 'solar-moon'
];

interface PlannedTargetSummary {
  targetId: string;
  targetName: string;
  designation: string;
  windowText: string;
  scoreText: string;
  color: ResourceColor;
}

interface PlanningHeightBar {
  id: string;
  label: string;
  height: number;
  color: ResourceColor;
}

function emptyNormalSkyScene(): NormalSkyScene {
  return {
    objects: [],
    constellationLines: [],
    gridLines: [],
    eclipticLines: [],
    horizonLines: [],
    trajectoryLines: [],
    horizonMask: [],
    orientationSnapshot: {
      orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP,
      centerRaHours: 0.0,
      centerDecDegrees: 0.0,
      northScreenAngleDegrees: 0.0,
      eastScreenAngleDegrees: -90.0,
      markers: []
    },
    generatedAtMs: 0
  };
}

@Entry
@Component
struct Index {
  @State private activeSection: number = 0;
  @State private workspaceDirection: number = 1;
  @State private skyMode: number = 0;
  @State private selectedTargetId: string = 'star-vega';
  @State private targetSearch: string = '';
  @State private gestureEnabled: boolean = false;
  @State private gestureStatus: string = '未安装手势模型';
  @State private normalViewState: NormalSkyViewState = NormalSkyViewStateService.defaultState();
  // Canvas 与控件只读取该快照；所有交互必须通过 normalViewState 更新四元数长期姿态。
  @State private normalViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(
    NormalSkyViewStateService.defaultState());
  @State private normalScene: NormalSkyScene = emptyNormalSkyScene();
  @State private normalLayers: SkyLayerVisibility = DEFAULT_SKY_LAYERS;
  @State private normalTimeState: NormalSkyTimeState = NormalSkyTimeService.realtime();
  @State private normalLayerPanelOpen: boolean = false;
  @State private skyViewportWidth: number = 600;
  @State private skyViewportHeight: number = 500;
  // 非星图页面也需要知道可用宽度，避免手机和分屏窗口继续沿用 Pad 固定布局。
  @State private contentViewportWidth: number = 1024;
  @State private contentViewportHeight: number = 720;
  @State private calibrationEnabled: boolean = false;
  @State private calibrationText: string = '未校准';
  @State private calibrationFeedbackActive: boolean = false;
  @State private mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @State private gatewayConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @State private mountHomed: boolean = false;
  @State private mountCoordinatesTopocentric: boolean = false;
  @State private tracking: boolean = false;
  @State private captureMode: number = 0;
  @State private expertOpen: boolean = false;
  @State private exposureSeconds: number = 15;
  @State private frameCount: number = 20;
  @State private iso: number = 800;
  @State private intervalSeconds: number = 2;
  @State private showCapturePanel: boolean = false;
  @State private taskStatus: TaskStatus = TaskStatus.PENDING;
  @State private taskProgress: number = 0;
  @State private completedFrames: number = 0;
  @State private emergencyMessage: string = '';
  @State private operationMessage: string = '';
  @State private operationBusy: boolean = false;
  @State private locationText: string = '等待定位';
  @State private locationAccuracy: number = 0;
  @State private locationSynced: boolean = false;
  @State private poseHeading: number = 0;
  @State private posePitch: number = 0;
  @State private poseRoll: number = 0;
  @State private poseReady: boolean = false;
  @State private skyDomeRevealLevel: number = 2;
  @State private huaweiArViewEnabled: boolean = false;
  @State private arTrackingText: string = '传感器天穹';
  @State private skyDomeFrame: SkyDomeFrame = {
    timestampNs: 0,
    trackingQuality: ArTrackingQuality.INITIALIZING,
    trackingSource: ArTrackingSource.SENSOR_FUSION,
    viewport: { widthPixels: 600, heightPixels: 500 },
    markers: [],
    guideLines: []
  };
  @State private mountRaHours: number = 0;
  @State private mountDecDegrees: number = 0;
  @State private mountSlewing: boolean = false;
  @State private gatewayDetail: string = '10.42.0.1:8000';
  @State private taskStage: string = '等待创建';
  @State private activeTaskId: string = '';
  @State private catalogStatus: string = '星表加载中';
  @State private normalCatalogStatus: string = '星座线加载中';
  @State private plateSolveCount: number = 0;
  @State private correctionCount: number = 0;
  @State private stackFileUrl: string = '';
  @State private timelapseFileUrl: string = '';
  @State private workflowWarningText: string = '';
  @State private aiEndpoint: string = '';
  @State private aiToken: string = '';
  @State private aiStatus: string = '未配置';
  @State private aiFileUrl: string = '';
  @State private aiModelVersion: string = '';
  @State private planningDayOffset: number = 0;
  @State private plannedTargetIds: string[] = ['star-vega'];
  @State private plannedTargetSummaries: PlannedTargetSummary[] = [];
  @State private planningResult: ObservationPlanningResult | undefined = undefined;
  @State private planningBusy: boolean = false;
  @State private planningLocationSource: string = '等待定位';
  @State private manualLatitudeText: string = '';
  @State private manualLongitudeText: string = '';
  @State private weatherStatus: WeatherDataStatus = WeatherDataStatus.NOT_REQUESTED;
  @State private weatherMessage: string = '天气未获取 · 仅按天文条件规划';
  @State private observer: ObserverState | undefined = undefined;
  @State private skyOverlayPanel: number = 0;
  @State private skyChromeVisible: boolean = true;
  @State private planningLocationEditorOpen: boolean = false;

  private selectedCustomTarget: CelestialObject | undefined = undefined;
  private customPlanningTargets: CelestialObject[] = [];
  private calibration: ArCalibration | undefined = undefined;
  private cameraCapabilities: CameraCapabilities | undefined = undefined;
  private weatherForecast: WeatherForecast | undefined = undefined;
  private mountPollTimer: number = -1;
  private taskPollTimer: number = -1;
  private readonly mountClient: OnStepLX200Client = new OnStepLX200Client();
  private readonly gatewayClient: RaspberryPiClient = new RaspberryPiClient();
  private readonly aiClient: AIEnhancementClient = new AIEnhancementClient();
  private readonly weatherService: WeatherForecastService = new WeatherForecastService();
  private readonly captureWorkflow: CaptureWorkflowCoordinator =
    new CaptureWorkflowCoordinator(this.mountClient, this.gatewayClient);
  private readonly poseService: DevicePoseService = new DevicePoseService();
  private readonly visibleStarCatalog: VisibleStarCatalogService = new VisibleStarCatalogService();
  private readonly normalSkyCatalog: NormalSkyCatalogService = new NormalSkyCatalogService();
  private readonly normalSkySceneService: NormalSkySceneService =
    new NormalSkySceneService(this.visibleStarCatalog, this.normalSkyCatalog);
  private readonly skyDomeSceneService: SkyDomeSceneService = new SkyDomeSceneService();
  private readonly gestureInterpreter: GestureInterpreter = new GestureInterpreter();
  private readonly normalSkyGestureController: NormalSkyGestureController = new NormalSkyGestureController();
  private readonly handFrameSource: CameraHandFrameSource = new CameraHandFrameSource(
    new UnavailableHandLandmarkAnalyzer(),
    (result: HandLandmarkAnalysisResult) => { this.applyHandLandmarks(result); },
    (status: HandFrameSourceStatus) => {
      if (this.gestureEnabled) {
        this.gestureStatus = status.message;
      }
    });
  private lastProjectionAtMs: number = 0;
  private domeCatalogStars: VisibleStar[] = [];
  private lastSensorPose: DevicePose | undefined = undefined;
  private arEngineOrientation: Quaternion | undefined = undefined;
  private arEngineFrameTimestampNs: number = 0;
  // 系统定位与手动地点可能并发；代次变化后，旧定位结果不得覆盖用户刚确认的坐标。
  private locationRequestGeneration: number = 0;
  // 每次开始拍摄分配一个代次；取消或急停递增代次，使所有 await 之后的旧流程立即失效。
  private captureRunGeneration: number = 0;
  private normalSceneTimer: number = -1;
  private normalTimeLastTickMs: number = 0;
  private normalSceneUpdateTimer: number = -1;
  private normalInertiaTimer: number = -1;
  private normalFlyTimer: number = -1;
  private lastPanOffsetX: number = 0.0;
  private lastPanOffsetY: number = 0.0;
  aboutToAppear(): void {
    const arCapability = ArEngineCapabilityService.inspect();
    this.huaweiArViewEnabled = arCapability.available;
    this.arTrackingText = arCapability.available ? 'AR Engine 初始化' : '传感器天穹';
    try {
      this.poseService.start((pose: DevicePose) => {
        this.lastSensorPose = pose;
        // 传感器订阅保持常驻以便返回 AR 页面时迅速恢复，但非 AR 页面不写顶层 @State，
        // 避免设备、任务、后期和普通星图也被 50 Hz 姿态事件反复触发整页更新。
        if (this.activeSection !== 0 || this.skyMode !== 0 || this.arEngineOrientation !== undefined) {
          return;
        }
        this.poseHeading = pose.headingDegrees;
        this.posePitch = pose.pitchDegrees;
        this.poseRoll = pose.rollDegrees;
        this.poseReady = true;
        this.updateProjectedTargets();
      });
    } catch (error) {
      this.poseReady = false;
      this.operationMessage = `姿态传感器不可用：${error}`;
    }
    this.loadVisibleStarCatalog();
    this.loadNormalSkyCatalog();
    this.updateNormalScene();
    this.startNormalSceneTimer();
    this.updateProjectedTargets(true);
  }

  aboutToDisappear(): void {
    this.poseService.stop();
    this.clearMountPolling();
    this.clearTaskPolling();
    this.clearNormalMotion();
    this.clearNormalSceneTimer();
    this.visibleStarCatalog.clear();
    this.normalSkyCatalog.clear();
    this.domeCatalogStars = [];
    this.lastSensorPose = undefined;
    this.arEngineOrientation = undefined;
    this.arEngineFrameTimestampNs = 0;
    this.handFrameSource.close();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.activeSection === 0) {
        WorkspaceTransitionHost({
          motionDirection: this.workspaceDirection,
          content: (): void => { this.SkyWorkspace(); }
        })
      } else if (this.isPhoneWorkspace()) {
        WorkspaceTransitionHost({
          motionDirection: this.workspaceDirection,
          content: (): void => { this.PhoneWorkspaceShell(); }
        })
      } else {
        WorkspaceTransitionHost({
          motionDirection: this.workspaceDirection,
          content: (): void => { this.TabletWorkspaceShell(); }
        })
      }

      if (this.showCapturePanel) {
        this.CaptureOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background_primary'))
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      const height: number = Number(newValue.height);
      if (Number.isFinite(width) && width > 0) this.contentViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.contentViewportHeight = height;
    })
  }

  @Builder
  private ActiveWorkspaceContent() {
    this.Header()
    if (this.activeSection === 1) {
      DeviceWorkspace({
        compact: this.isCompactWorkspace(),
        pageMargin: this.workspacePageMargin(),
        mountConnection: this.mountConnection,
        gatewayConnection: this.gatewayConnection,
        gatewayDetail: this.gatewayDetail,
        mountHomed: this.mountHomed,
        coordinateModeCompatible: this.mountCoordinatesTopocentric,
        tracking: this.tracking,
        locationSynced: this.locationSynced,
        observerAvailable: this.observer !== undefined,
        locationText: this.locationText,
        mountRaHours: this.mountRaHours,
        mountDecDegrees: this.mountDecDegrees,
        mountSlewing: this.mountSlewing,
        onToggleMount: (): void => { this.toggleMountConnection(); },
        onToggleGateway: (): void => { this.toggleGatewayConnection(); },
        onHomeMount: (): void => { this.homeMount(); },
        onSyncObserver: (): void => { this.syncObserverToMount(); },
        onToggleTracking: (): void => { this.toggleTracking(); },
        onParkMount: (): void => { this.parkMount(); }
      })
        .transition(MotionTokens.page(this.workspaceDirection))
    } else if (this.activeSection === 2) {
      TaskWorkspace({
        compact: this.isCompactWorkspace(),
        pageMargin: this.workspacePageMargin(),
        taskStage: this.taskStage,
        targetName: this.selectedTarget().nameZh,
        captureMode: this.captureMode,
        exposureSeconds: this.exposureSeconds,
        frameCount: this.frameCount,
        iso: this.iso,
        taskStatus: this.taskStatus,
        taskProgress: this.taskProgress,
        completedFrames: this.completedFrames,
        workflowWarningText: this.workflowWarningText,
        plateSolveCount: this.plateSolveCount,
        correctionCount: this.correctionCount,
        stackFileUrl: this.stackFileUrl,
        timelapseFileUrl: this.timelapseFileUrl,
        aiFileUrl: this.aiFileUrl,
        onRefresh: (): void => { this.pollActiveTask(); },
        onCancel: (): void => { this.cancelActiveTask(); }
      })
        .transition(MotionTokens.page(this.workspaceDirection))
    } else {
      PostWorkspace({
        compact: this.isCompactWorkspace(),
        pageMargin: this.workspacePageMargin(),
        aiEndpoint: this.aiEndpoint,
        aiToken: this.aiToken,
        aiStatus: this.aiStatus,
        aiConfigured: this.aiClient.isConfigured(),
        stackFileUrl: this.stackFileUrl,
        aiFileUrl: this.aiFileUrl,
        aiModelVersion: this.aiModelVersion,
        timelapseFileUrl: this.timelapseFileUrl,
        plateSolveCount: this.plateSolveCount,
        correctionCount: this.correctionCount,
        completedFrames: this.completedFrames,
        onEndpointChange: (value: string): void => { this.aiEndpoint = value; },
        onTokenChange: (value: string): void => { this.aiToken = value; },
        onApplyConfiguration: (): void => { this.applyAiConfiguration(); }
      })
        .transition(MotionTokens.page(this.workspaceDirection))
    }
  }

  @Builder
  private WorkspaceRail() {
    Column() {
      if (this.activeSection === 1) {
        this.SharedNavigationDock(false, 1, 0)
      } else if (this.activeSection === 2) {
        this.SharedNavigationDock(false, 2, 0)
      } else {
        this.SharedNavigationDock(false, 3, 0)
      }
    }
    .width(104)
    .height('100%')
    .padding({ left: 16, right: 16, top: 24 })
    .backgroundColor($r('app.color.app_background_primary'))
  }

  @Builder
  private CompactBottomNavigation() {
    Column() {
      if (this.activeSection === 1) {
        this.SharedNavigationDock(true, 1, 0)
      } else if (this.activeSection === 2) {
        this.SharedNavigationDock(true, 2, 0)
      } else {
        this.SharedNavigationDock(true, 3, 0)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
    .backgroundColor($r('app.color.app_background_primary'))
  }

  @Builder
  private SharedNavigationDock(compact: boolean, activeSection: number, activeSkyPanel: number) {
    WorkspaceNavigationDock({
      compact: compact,
      veryNarrow: compact && this.contentViewportWidth < 360,
      activeSection: activeSection,
      activeSkyPanel: activeSkyPanel,
      showEmergency: this.mountConnection !== ConnectionState.DISCONNECTED ||
        this.gatewayConnection !== ConnectionState.DISCONNECTED || this.taskStatus === TaskStatus.RUNNING,
      onTarget: (): void => { this.navigateToSkyPanel(1); },
      onPlanning: (): void => { this.navigateToSkyPanel(2); },
      onDevice: (): void => { this.navigateToSection(1); },
      onTask: (): void => { this.navigateToSection(2); },
      onPost: (): void => { this.navigateToSection(3); },
      onImmersive: (): void => { this.navigateToImmersiveSky(); },
      onEmergency: (): void => { this.triggerEmergencyStop(); }
    })
  }

  @Builder
  private PhoneWorkspaceShell() {
    Column() {
      Column() {
        this.ActiveWorkspaceContent()
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor($r('app.color.app_background_primary'))
      this.CompactBottomNavigation()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private TabletWorkspaceShell() {
    Row() {
      this.WorkspaceRail()
      Column() {
        this.ActiveWorkspaceContent()
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor($r('app.color.app_background_primary'))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Header() {
    Row({ space: 16 }) {
      Column({ space: 3 }) {
        Text(this.sectionTitle())
          .fontSize(this.isPhoneWorkspace() ? 22 : $r('app.float.font_page_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .width('100%')
        Text(this.sectionSubtitle())
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.app_text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)

      if (this.activeSection === 0) {
        Row() {
          this.ModeButton('AR 星图', 0)
          this.ModeButton('普通星图', 1)
        }
        .padding(3)
        .height(40)
        .backgroundColor('#151922')
        .borderRadius(6)
      }

      if (this.isCompactWorkspace()) {
        this.HeaderStatus('状态', this.connectionText(this.mountConnection), this.connectionColor(this.mountConnection))
      } else {
        this.HeaderStatus('位置', this.locationText, this.observer === undefined ? '#F4BA58' : '#57C995')
        this.HeaderStatus('时间', this.currentTimeText(), '#72D3F5')
      }
    }
    .width('100%')
    .height(this.isPhoneWorkspace() ? 82 : 92)
    .padding({ left: this.isPhoneWorkspace() ? 16 : 32, right: this.isPhoneWorkspace() ? 16 : 32,
      top: this.isPhoneWorkspace() ? 16 : 20 })
    .border({ width: { bottom: 1 }, color: $r('app.color.app_divider') })
  }

  @Builder
  private ModeButton(label: string, mode: number) {
    Button(label)
      .height(40)
      .padding({ left: 16, right: 16 })
      .fontSize($r('app.float.font_body'))
      .fontWeight(this.skyMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.skyMode === mode ? $r('app.color.app_on_brand') : $r('app.color.app_text_secondary'))
      .backgroundColor(this.skyMode === mode ? $r('app.color.app_brand') : 'transparent')
      .borderRadius($r('app.float.corner_control'))
      .onClick(() => { this.selectSkyMode(mode); })
  }

  @Builder
  private HeaderStatus(label: string, value: string, color: ResourceColor) {
    Row({ space: 8 }) {
      Circle().width(7).height(7).fill(color)
      Column({ space: 1 }) {
        Text(label).fontSize(10).fontColor('#778397')
        Text(value).fontSize(12).fontColor('#DDE3EC')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(this.isCompactWorkspace() ? 112 : 160)
    .height(48)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private SkyWorkspace() {
    SkyWorkspace({
      skyMode: this.skyMode,
      chromeVisible: this.skyChromeVisible,
      overlayPanel: this.skyOverlayPanel,
      viewportWidth: this.skyViewportWidth,
      viewportHeight: this.skyViewportHeight,
      targetSearch: this.targetSearch,
      observerAvailable: this.observer !== undefined,
      locationText: this.locationText,
      currentTimeText: this.currentTimeText(),
      mountConnection: this.mountConnection,
      gatewayConnection: this.gatewayConnection,
      taskStatus: this.taskStatus,
      emergencyMessage: this.emergencyMessage,
      operationMessage: this.operationMessage,
      targetName: this.selectedTarget().nameZh,
      recommendationTitle: this.planningRecommendationTitle(),
      recommendationColor: this.planningRecommendationColor(),
      planningWindowText: this.planningPeekWindowText(),
      weatherSourceText: this.weatherSourceShortText(),
      poseReady: this.poseReady,
      poseHeading: this.poseHeading,
      posePitch: this.posePitch,
      calibrationText: this.calibrationText,
      calibrationEnabled: this.calibrationEnabled,
      calibrationFeedbackActive: this.calibrationFeedbackActive,
      arTrackingText: this.arTrackingText,
      domeRevealLevel: this.skyDomeRevealLevel,
      gestureEnabled: this.gestureEnabled,
      normalViewport: this.normalViewport,
      normalOrientationSnapshot: this.normalScene.orientationSnapshot,
      skyCanvas: (): void => { this.SkyCanvas(); },
      gesturePreview: (): void => { this.SkyGesturePreview(); },
      normalControls: (): void => { this.NormalSkyControlOverlay(); },
      normalTimeControls: (): void => { this.NormalSkyTimeOverlay(); },
      normalOrientation: (): void => { this.NormalSkyDirectionOverlay(); },
      targetDrawer: (): void => { this.SkyTargetDrawer(); },
      planningDrawer: (): void => { this.SkyPlanningDrawer(); },
      onViewportChange: (width: number, height: number): void => {
        this.skyViewportWidth = width;
        this.skyViewportHeight = height;
        this.updateNormalScene();
        this.updateProjectedTargets(true);
      },
      onSearchChange: (value: string): void => { this.targetSearch = value; },
      onSearchSubmit: (value: string): void => {
        this.targetSearch = value;
        this.performTargetSearch();
      },
      onOpenPanel: (panel: number): void => { this.openSkyPanel(panel); },
      onNavigate: (section: number): void => { this.navigateToSection(section); },
      onChromeVisibleChange: (visible: boolean): void => {
        this.getUIContext().animateTo(MotionTokens.standard(), () => { this.skyChromeVisible = visible; });
        if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
      },
      onNoticeDismiss: (): void => {
        this.emergencyMessage = '';
        this.operationMessage = '';
      },
      onModeChange: (mode: number): void => { this.selectSkyMode(mode); },
      onDomeRevealChange: (level: number): void => {
        this.getUIContext().animateTo(MotionTokens.quick(), () => { this.skyDomeRevealLevel = level; });
        this.updateProjectedTargets(true);
      },
      onEmergencyStop: (): void => { this.triggerEmergencyStop(); },
      onOpenPlanningLocation: (): void => {
        this.revealSkyPanel(2);
        this.getUIContext().animateTo(MotionTokens.standard(), () => {
          this.planningLocationEditorOpen = true;
        });
      }
    })
  }

  @Builder
  private SkyCanvas() {
    Stack() {
      if (this.skyMode === 0) {
        Stack() {
          if (this.huaweiArViewEnabled) {
            // 组件使用 import lazy；只有能力检测通过并进入此分支时才实例化 AR Engine 原生模块。
            HuaweiArCameraView({
              cornerRadius: 0,
              onFrameUpdate: (snapshot: HuaweiArFrameSnapshot): void => {
                this.handleHuaweiArFrame(snapshot);
              },
              onStatusChange: (status: HuaweiArViewStatus): void => {
                this.handleHuaweiArStatus(status);
              }
            })
          } else {
            DeviceCameraPreview({ useFrontCamera: false, cornerRadius: 0 })
          }
          ArSkyDome({
            frame: this.skyDomeFrame,
            widthPixels: this.skyViewportWidth,
            heightPixels: this.skyViewportHeight,
            onMarkerSelected: (markerId: string) => {
              this.selectSkyDomeMarker(markerId);
            }
          })
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
      } else {
        NormalSkyMap({
          scene: this.normalScene,
          widthPixels: this.skyViewportWidth,
          heightPixels: this.skyViewportHeight,
          onObjectSelected: (objectId: string): void => {
            this.selectNormalSkyObject(objectId);
          }
        })
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
      }

      if (this.skyMode === 0) {
        Text('+')
          .fontSize(24).fontColor($r('app.color.app_brand'))
          .width(30).height(30).textAlign(TextAlign.Center)
          .position({ x: this.skyViewportWidth / 2 - 15, y: this.skyViewportHeight / 2 - 15 })
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart(() => {
            this.stopNormalInertia();
            this.stopNormalFly();
            this.lastPanOffsetX = 0.0;
            this.lastPanOffsetY = 0.0;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.skyMode === 1) {
              const deltaX: number = event.offsetX - this.lastPanOffsetX;
              const deltaY: number = event.offsetY - this.lastPanOffsetY;
              this.lastPanOffsetX = event.offsetX;
              this.lastPanOffsetY = event.offsetY;
              this.applyNormalViewState(NormalSkyViewStateService.pan(
                this.normalViewState, this.normalSkySize(), deltaX, deltaY));
              this.scheduleNormalSceneUpdate();
            }
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.skyMode === 1) this.startNormalInertia(event.velocityX, event.velocityY);
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.stopNormalInertia();
            this.stopNormalFly();
            this.normalSkyGestureController.beginPointerScale();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.skyMode === 1) {
              const update: NormalSkyGestureUpdate = this.normalSkyGestureController.updatePointerScale(
                this.normalViewState, this.normalSkySize(), event.scale,
                this.normalGestureAnchorX(event.pinchCenterX), this.normalGestureAnchorY(event.pinchCenterY));
              if (update.changed) {
                this.applyNormalViewState(update.viewState);
                this.scheduleNormalSceneUpdate();
              }
            }
          })
          .onActionEnd(() => { this.normalSkyGestureController.endPointerScale(); }),
        RotationGesture({ fingers: 2 })
          .onActionStart(() => {
            this.stopNormalInertia();
            this.stopNormalFly();
            this.normalSkyGestureController.beginPointerRotation();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.skyMode === 1) {
              const update: NormalSkyGestureUpdate = this.normalSkyGestureController.updatePointerRotation(
                this.normalViewState, this.normalSkySize(), event.angle,
                this.normalGestureAnchorX(event.pinchCenterX), this.normalGestureAnchorY(event.pinchCenterY));
              if (update.changed) {
                this.applyNormalViewState(update.viewState);
                this.scheduleNormalSceneUpdate();
              }
            }
          })
          .onActionEnd(() => { this.normalSkyGestureController.endPointerRotation(); })
      )
    )
  }

  @Builder
  private NormalSkyControlOverlay() {
    NormalSkyControls({
      viewport: this.normalViewport,
      layers: this.normalLayers,
      panelOpen: this.normalLayerPanelOpen,
      viewportWidth: this.skyViewportWidth,
      viewportHeight: this.skyViewportHeight,
      catalogStatus: this.catalogStatus,
      lineCatalogStatus: this.normalCatalogStatus,
      onHome: (): void => { this.homeNormalSky(); },
      onResetNorth: (): void => { this.resetNormalSkyNorth(); },
      onZoomIn: (): void => { this.zoomNormalSky(1.35); },
      onZoomOut: (): void => { this.zoomNormalSky(0.74); },
      onToggleOrientation: (): void => { this.toggleNormalSkyOrientation(); },
      onTogglePanel: (): void => {
        this.normalLayerPanelOpen = !this.normalLayerPanelOpen;
        this.scheduleNormalSceneUpdate();
      },
      onFieldOfViewChange: (fieldOfViewDegrees: number): void => {
        this.setNormalSkyFieldOfView(fieldOfViewDegrees);
      },
      onLayerChange: (layer: number, enabled: boolean): void => { this.setNormalLayer(layer, enabled); }
    })
  }

  @Builder
  private NormalSkyTimeOverlay() {
    NormalSkyTimeControls({
      timeState: this.normalTimeState,
      viewportWidth: this.skyViewportWidth,
      viewportHeight: this.skyViewportHeight,
      compact: this.useSkyBottomSheet(),
      onReturnNow: (): void => { this.returnNormalSkyToRealtime(); },
      onTogglePlayback: (): void => { this.toggleNormalSkyPlayback(); },
      onTimeSelected: (timestampMs: number): void => { this.selectNormalSkyTime(timestampMs); },
      onSpeedSelected: (speed: NormalSkyPlaybackSpeed): void => {
        this.setNormalSkyPlaybackSpeed(speed);
      }
    })
  }

  @Builder
  private NormalSkyDirectionOverlay() {
    if (NormalSkyLayoutService.showCompass(this.skyViewportWidth, this.normalLayerPanelOpen)) {
      NormalSkyOrientationOverlay({
        snapshot: this.normalScene.orientationSnapshot,
        viewportWidth: this.skyViewportWidth,
        viewportHeight: this.skyViewportHeight,
        guideInsets: this.normalSkyGuideInsets(),
        compactDrawerOpen: this.useSkyBottomSheet() && this.skyOverlayPanel > 0,
        onResetNorth: (): void => { this.resetNormalSkyNorth(); }
      })
    }
  }

  @Builder
  private SkyGesturePreview() {
    Row({ space: 8 }) {
      DeviceCameraPreview({
        useFrontCamera: true,
        cornerRadius: 6,
        handFrameSource: this.handFrameSource
      })
        .width(this.useSkyBottomSheet() ? 108 : 132)
        .height(this.useSkyBottomSheet() ? 72 : 84)
      if (!this.useSkyBottomSheet()) {
        Column({ space: 4 }) {
          Text('手势').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          Text(this.gestureStatus).fontSize(10).fontColor('#72D3F5')
        }
      }
    }
    .padding(6).backgroundColor('#111720')
    .border({ width: 1, color: '#2D4657' }).borderRadius(8)
    .position({
      x: this.useSkyBottomSheet() ? 12 : 90,
      y: Math.max(76, this.skyBottomControlY() - (this.useSkyBottomSheet() ? 84 : 98))
    })
  }

  @Builder
  private SkyTargetDrawer() {
    Column({ space: 0 }) {
      if (this.useSkyBottomSheet()) {
        Rect().width(44).height(4).fill($r('app.color.sky_text_tertiary'))
          .borderRadius(2).margin({ top: 10, bottom: 8 })
      }
      Row() {
        Column({ space: 3 }) {
          Text('天体详情').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.sky_text_primary'))
          Text(this.selectedVisibilityText()).fontSize(12).fontColor(this.selectedVisibilityColor())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20).fontColor([$r('app.color.sky_text_secondary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
          .onClick(() => { this.openSkyPanel(1); })
      }.width('100%').padding({ left: 20, right: 14, top: 10, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 3 }) {
              Text(this.selectedTarget().nameZh)
                .fontSize(24).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.sky_text_primary')).width('100%')
              Text(`${this.selectedTarget().nameEn} · ${this.selectedTarget().constellation}`)
                .fontSize(12).fontColor($r('app.color.sky_text_secondary')).width('100%')
            }.layoutWeight(1)
            Text(this.selectedTarget().designation)
              .fontSize(12).fontColor($r('app.color.app_on_brand'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.app_warning')).borderRadius($r('app.float.corner_tag'))
          }.width('100%')

          Row() {
            this.TargetMetric('星等', this.magnitudeText())
            this.TargetMetric('高度', this.targetAltitudeText())
            this.TargetMetric('方位', this.targetAzimuthText())
          }
          .width('100%').height(64).backgroundColor($r('app.color.sky_background'))
          .borderRadius($r('app.float.corner_card'))

          Text(this.selectedTarget().description)
            .fontSize(14).lineHeight(22).fontColor($r('app.color.sky_text_secondary')).width('100%')

          Column({ space: 7 }) {
            this.InfoLine('目标类型', this.selectedTypeText())
            this.InfoLine('赤经 / 赤纬', this.coordinateText())
            this.InfoLine('角尺寸', this.angularSizeText())
            this.InfoLine('18mm 适配', this.selectedTarget().recommendedFor18mm ? '推荐广角拍摄' : '适合观测或环境构图')
          }.width('100%')

          Column({ space: 7 }) {
            Text('今晚观测').fontSize(12).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.sky_text_primary')).width('100%')
            this.InfoLine('升起 / 中天 / 落下', `${this.planningEventText('rise')} / ` +
              `${this.planningEventText('transit')} / ${this.planningEventText('set')}`)
            this.InfoLine('最佳窗口', this.planningPeekWindowText())
            this.InfoLine('天气', this.weatherSourceShortText())
          }
          .width('100%').padding(12).backgroundColor($r('app.color.sky_background'))
          .borderRadius($r('app.float.corner_card'))

          Row() {
            Text(this.selectedTarget().recommendedFor18mm ? '广角友好' : '目标尺寸较小')
              .fontSize(12).fontColor(this.selectedTarget().recommendedFor18mm ?
                $r('app.color.app_success') : $r('app.color.app_warning'))
            Blank()
            Text(this.selectedVisibilityText()).fontSize(10).fontColor(this.selectedVisibilityColor())
          }
          .width('100%').padding(12).backgroundColor($r('app.color.sky_surface_soft'))
          .borderRadius($r('app.float.corner_card'))

          if (this.skyMode === 0) {
            Row({ space: 8 }) {
              Button(this.calibrationEnabled ? '重新校准' : '一星校准')
                .layoutWeight(1).height(48).fontSize(14)
                .fontColor($r('app.color.sky_text_primary'))
                .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
                .onClick(() => { this.calibrateSelectedTarget(); })
              Button('定位')
                .layoutWeight(1).height(48).fontSize(14)
                .fontColor($r('app.color.sky_text_primary'))
                .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
                .onClick(() => { this.refreshLocation(); })
            }
          } else {
            Row() {
              Column({ space: 2 }) {
                Text('前摄手势').fontSize(14).fontColor($r('app.color.sky_text_secondary'))
                Text(this.gestureModelAvailable() ? this.gestureStatus : '未安装手势模型')
                  .fontSize(10).fontColor($r('app.color.sky_text_tertiary'))
              }.alignItems(HorizontalAlign.Start)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.gestureEnabled })
                .enabled(this.gestureModelAvailable())
                .selectedColor('#57C995')
                .onChange((value: boolean) => { this.setGestureEnabled(value); })
            }.width('100%').height(48)
          }
        }
        .width('100%').padding({ left: 14, right: 14, bottom: 12 })
      }
      .layoutWeight(1).width('100%')

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Button(this.isSelectedTargetPlanned() ? '已加入计划' : '加入计划')
            .layoutWeight(1).height(48).fontSize(14)
            .fontColor($r('app.color.sky_text_primary'))
            .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
            .onClick(() => { this.addSelectedTargetToPlan(false); })
          Button('查看规划')
            .layoutWeight(1).height(48).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(24)
            .onClick(() => { this.addSelectedTargetToPlan(true); })
        }.width('100%')
        Button('拍摄 / 观测')
          .width('100%').height(48).fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_tertiary')).borderRadius(24)
          .onClick(() => { this.setCapturePanelVisible(true); })
        Text(this.captureReadinessText())
          .fontSize(10).lineHeight(15).fontColor($r('app.color.sky_text_tertiary'))
          .width('100%').textAlign(TextAlign.Center).maxLines(2)
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .border({ width: { top: 1 }, color: $r('app.color.sky_border') })
    }
    .width(this.skyDrawerWidth()).height(this.skyDrawerHeight())
    .backgroundColor($r('app.color.sky_surface_strong'))
    .backgroundBlurStyle(BlurStyle.Thick)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_modal'))
    .position({ x: this.skyDrawerX(), y: this.skyDrawerY() })
    .transition(MotionTokens.drawer(this.useSkyBottomSheet()))
  }

  @Builder
  private SkyPlanningDrawer() {
    Column({ space: 0 }) {
      if (this.useSkyBottomSheet()) {
        Rect().width(44).height(4).fill($r('app.color.sky_text_tertiary'))
          .borderRadius(2).margin({ top: 10, bottom: 8 })
      }
      Row() {
        Column({ space: 2 }) {
          Text(this.planningDayOffset === 0 ? '今晚规划' : '明晚规划')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
          Text(`${this.plannedTargetIds.length} 个目标 · ${this.planningDayOffset === 0 ? '今晚' : '明晚'}`)
            .fontSize(12).fontColor($r('app.color.sky_text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20).fontColor([$r('app.color.sky_text_secondary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
          .onClick(() => { this.openSkyPanel(2); })
      }.width('100%').padding({ left: 20, right: 14, top: 10, bottom: 12 })

      Row({ space: 6 }) {
        this.PlanningDayButton('今晚', 0)
        this.PlanningDayButton('明晚', 1)
        Blank()
        Button('地点')
          .height(40).padding({ left: 14, right: 14 }).fontSize(12)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(20)
          .onClick(() => {
            this.getUIContext().animateTo(MotionTokens.standard(), () => {
              this.planningLocationEditorOpen = !this.planningLocationEditorOpen;
            });
          })
        Button(this.planningBusy ? '更新中' : '更新')
          .height(40).padding({ left: 14, right: 14 }).fontSize(12)
          .enabled(!this.planningBusy && this.observer !== undefined)
          .fontColor($r('app.color.sky_text_primary'))
          .backgroundColor($r('app.color.app_surface_primary')).borderRadius(20)
          .onClick(() => { this.refreshWeatherForecast(); })
      }
      .width('100%').padding({ left: 12, right: 12, bottom: 8 })

      if (this.planningLocationEditorOpen) {
        Column({ space: 7 }) {
          Row({ space: 7 }) {
            TextInput({ placeholder: '纬度', text: this.manualLatitudeText })
              .layoutWeight(1).height(44).fontSize(13).fontColor($r('app.color.sky_text_primary'))
              .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
              .onChange((value: string) => { this.manualLatitudeText = value; })
            TextInput({ placeholder: '经度', text: this.manualLongitudeText })
              .layoutWeight(1).height(44).fontSize(13).fontColor($r('app.color.sky_text_primary'))
              .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
              .onChange((value: string) => { this.manualLongitudeText = value; })
          }.width('100%')
          Row({ space: 7 }) {
            Button('应用坐标').layoutWeight(1).height(44).fontSize(13)
              .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(22)
              .onClick(() => {
                this.applyManualPlanningLocation();
                if (this.observer !== undefined) {
                  this.getUIContext().animateTo(MotionTokens.standard(), () => {
                    this.planningLocationEditorOpen = false;
                  });
                }
              })
            Button('系统定位').layoutWeight(1).height(44).fontSize(13)
              .fontColor($r('app.color.sky_text_primary'))
              .backgroundColor($r('app.color.app_surface_primary')).borderRadius(22)
              .onClick(() => { this.refreshLocation(); })
          }.width('100%')
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 10 })
        .backgroundColor($r('app.color.sky_surface_soft'))
        .transition(MotionTokens.drawer(true))
      }

      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 3 }) {
              Text(this.planningRecommendationTitle()).fontSize(10).fontWeight(FontWeight.Bold)
                .fontColor(this.planningRecommendationColor())
              Text(this.planningResult?.targetName ?? this.selectedTarget().nameZh)
                .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
              Text(this.planningResult?.summary ?? '设置观测地点后生成本地天文窗口')
                .fontSize(12).lineHeight(18).fontColor($r('app.color.sky_text_secondary')).maxLines(2)
            }.layoutWeight(1)
            Column({ space: 1 }) {
              Text(this.planningScoreText()).fontSize(25).fontWeight(FontWeight.Bold)
                .fontColor(this.planningRecommendationColor())
              Text(this.planningResult?.overallScore === undefined ? '参考天文分' : '参考综合分')
                .fontSize(12).fontColor($r('app.color.sky_text_tertiary'))
            }.width(70).alignItems(HorizontalAlign.Center)
          }
          .width('100%').padding(14).backgroundColor($r('app.color.sky_surface_soft'))
          .borderRadius($r('app.float.corner_card'))

          Row({ space: 6 }) {
            this.SkyPlanningMetric('升起', this.planningEventText('rise'))
            this.SkyPlanningMetric('中天', this.planningEventText('transit'))
            this.SkyPlanningMetric('落下', this.planningEventText('set'))
          }.width('100%')

          if (this.planningResult !== undefined && this.planningResult.samples.length > 0) {
            Column({ space: 6 }) {
              Row() {
                Text('高度趋势').fontSize(10).fontWeight(FontWeight.Bold).fontColor('#DCE4EE')
                Blank()
                Text('24h').fontSize(8).fontColor('#748195')
              }.width('100%')
              Row({ space: 3 }) {
                ForEach(this.planningHeightBars(), (bar: PlanningHeightBar) => {
                  Column({ space: 2 }) {
                    Blank()
                    Rect().width('100%').height(Math.max(3, bar.height * 0.62)).fill(bar.color).borderRadius(1)
                    Text(bar.label).fontSize(7).fontColor('#687689').height(10)
                  }.layoutWeight(1).height(70)
                }, (bar: PlanningHeightBar) => bar.id)
              }.width('100%').height(70)
            }
            .width('100%').height(98).padding(10).backgroundColor('#0B1016').borderRadius(6)
          }

          Column({ space: 5 }) {
            this.InfoLine('最佳窗口', this.planningBestWindowText())
            this.InfoLine('月光', this.planningMoonText())
            this.InfoLine('天气', this.weatherMessage)
            this.InfoLine('云 / 雨 / 风', `${this.planningWeatherMetric('cloud')} · ` +
              `${this.planningWeatherMetric('rain')} · ${this.planningWeatherMetric('wind')}`)
          }.width('100%').padding(10).backgroundColor('#0B1016').borderRadius(6)

          Row() {
            Text('计划目标').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#DCE4EE')
            Blank()
            Text('+').width(28).height(28).fontSize(17).textAlign(TextAlign.Center)
              .fontColor('#071017').backgroundColor('#72D3F5').borderRadius(5)
              .onClick(() => { this.addSelectedTargetToPlan(false); })
          }.width('100%')

          ForEach(this.plannedTargetSummaries, (summary: PlannedTargetSummary) => {
            Row({ space: 7 }) {
              Circle().width(7).height(7).fill(summary.color)
              Column({ space: 2 }) {
                Text(`${summary.targetName} · ${summary.designation}`)
                  .fontSize(10).fontWeight(FontWeight.Bold).fontColor('#E4EAF1').width('100%')
                Text(summary.windowText).fontSize(8).fontColor('#748195').width('100%')
              }.layoutWeight(1)
              Text(summary.scoreText).fontSize(9).fontColor(summary.color)
              Text('X').width(25).height(25).fontSize(11).textAlign(TextAlign.Center)
                .fontColor('#AAB4C2').backgroundColor('#242A34').borderRadius(4)
                .onClick(() => { this.removePlannedTarget(summary.targetId); })
            }
            .width('100%').height(44).padding({ left: 9, right: 6 })
            .backgroundColor(summary.targetId === this.selectedTargetId ? '#17222B' : '#0D1218')
            .borderRadius(5).onClick(() => { this.selectPlanningTarget(summary.targetId); })
          }, (summary: PlannedTargetSummary) => summary.targetId)
        }
        .width('100%').padding({ left: 12, right: 12, bottom: 12 })
      }
      .layoutWeight(1).width('100%')
    }
    .width(this.skyDrawerWidth()).height(this.skyDrawerHeight())
    .backgroundColor($r('app.color.sky_surface_strong'))
    .backgroundBlurStyle(BlurStyle.Thick)
    .border({ width: 1, color: $r('app.color.sky_border') })
    .borderRadius($r('app.float.corner_modal'))
    .position({ x: this.skyDrawerX(), y: this.skyDrawerY() })
    .transition(MotionTokens.drawer(this.useSkyBottomSheet()))
  }

  @Builder
  private SkyPlanningMetric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(12).fontColor($r('app.color.sky_text_tertiary'))
      Text(value).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1).height(58).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.sky_background')).borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private TargetMetric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(12).fontColor($r('app.color.sky_text_tertiary'))
      Text(value).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.sky_text_primary'))
    }.layoutWeight(1)
  }

  @Builder
  private InfoLine(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor($r('app.color.sky_text_tertiary'))
      Blank()
      Text(value).fontSize(12).fontColor($r('app.color.sky_text_secondary')).textAlign(TextAlign.End)
    }.width('100%')
  }

  @Builder
  private PlanningDayButton(label: string, offset: number) {
    Button(label)
      .height(40).padding({ left: 16, right: 16 }).fontSize(13)
      .fontWeight(this.planningDayOffset === offset ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.planningDayOffset === offset ?
        $r('app.color.app_on_brand') : $r('app.color.app_text_secondary'))
      .backgroundColor(this.planningDayOffset === offset ?
        $r('app.color.app_brand') : $r('app.color.app_surface_primary'))
      .borderRadius(20)
      .onClick(() => {
        this.getUIContext().animateTo(MotionTokens.quick(), () => { this.planningDayOffset = offset; });
        this.refreshPlanning();
      })
  }

  @Builder
  private CaptureOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Rect().width('100%').height('100%').fill('#000000').opacity(0.72)
        .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
        .onClick(() => { this.setCapturePanelVisible(false); })

      Scroll() {
        Column({ space: 14 }) {
          Row() {
            Column({ space: 3 }) {
              Text('拍摄方案 / 观测').fontSize(22).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.sky_text_primary')).width('100%')
              Text(this.selectedTarget().nameZh + ' · ' + this.selectedTarget().designation)
                .fontSize(13).fontColor($r('app.color.sky_text_secondary')).width('100%')
            }.layoutWeight(1)
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(20).fontColor([$r('app.color.sky_text_secondary')])
            }
              .width(48).height(48)
              .backgroundColor($r('app.color.app_surface_primary')).borderRadius(24)
              .onClick(() => { this.setCapturePanelVisible(false); })
          }.width('100%')

          Row({ space: 8 }) {
            this.CaptureModeButton('仅观测', 0)
            this.CaptureModeButton('智能长曝光', 1)
            this.CaptureModeButton('延时摄影', 2)
          }.width('100%')

          if (this.captureMode > 0) {
            Column({ space: 10 }) {
              this.NumberSetting('单帧曝光', this.exposureSeconds.toString() + ' 秒', -5, 5, 5, 30, 0)
              this.NumberSetting('拍摄张数', this.frameCount.toString() + ' 张', -5, 5, 5, 120, 1)
              this.NumberSetting('感光度', 'ISO ' + this.iso.toString(), -200, 200, 200, 3200, 2)
              if (this.captureMode === 2) {
                this.NumberSetting('拍摄间隔', this.intervalSeconds.toString() + ' 秒', -1, 1, 1, 60, 3)
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.sky_background'))
            .borderRadius($r('app.float.corner_card'))
            .transition(MotionTokens.drawer(true))
          }

          Row() {
            Text('专家参数').fontSize(14).fontColor($r('app.color.sky_text_secondary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.expertOpen })
              .selectedColor($r('app.color.app_success'))
              .onChange((value: boolean) => {
                this.getUIContext().animateTo(MotionTokens.standard(), () => { this.expertOpen = value; });
              })
          }.width('100%').height(34)

          if (this.expertOpen) {
            Text('RAW+JPEG · 拍摄后可提交板解析、堆栈、延时制片和受约束云端增强')
              .fontSize(13).fontColor($r('app.color.sky_text_secondary')).width('100%').lineHeight(20)
              .transition(MotionTokens.capsule())
          }

          if (!this.selectedTarget().recommendedFor18mm && this.captureMode > 0) {
            Text('当前目标角尺寸较小，18mm 广角照片中不会成为清晰主体。建议仅观测或选择银河区域。')
              .fontSize(13).fontColor($r('app.color.app_warning')).lineHeight(20).width('100%')
              .padding(12).backgroundColor('#33240F').borderRadius($r('app.float.corner_card'))
          }

          Button(this.captureMode === 0 ? 'GOTO 并开始观测' : 'GOTO 并创建拍摄任务')
            .width('100%').height(52).fontSize(15).fontWeight(FontWeight.Bold)
            .fontColor(this.canStartCapture() ?
              $r('app.color.app_on_brand') : $r('app.color.app_text_tertiary'))
            .backgroundColor(this.canStartCapture() ?
              $r('app.color.app_success') : $r('app.color.app_surface_primary'))
            .borderRadius(26)
            .onClick(() => {
              if (this.canStartCapture()) {
                this.startCaptureTask();
              }
            })
          Text(this.captureReadinessText())
            .fontSize(12).fontColor(this.canStartCapture() ?
              $r('app.color.app_success') : $r('app.color.sky_text_tertiary'))
            .width('100%').textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(24)
      }
      .width(this.captureOverlayWidth())
      .constraintSize({ maxHeight: this.captureOverlayMaxHeight() })
      .backgroundColor($r('app.color.sky_surface_strong'))
      .backgroundBlurStyle(BlurStyle.Thick)
      .border({ width: 1, color: $r('app.color.sky_border') })
      .borderRadius($r('app.float.corner_modal'))
      .transition(MotionTokens.modal())

      if (this.mountConnection !== ConnectionState.DISCONNECTED ||
        this.gatewayConnection !== ConnectionState.DISCONNECTED || this.taskStatus === TaskStatus.RUNNING) {
        Button() {
          SymbolGlyph($r('sys.symbol.stop_circle_fill'))
            .fontSize(24).fontColor([$r('app.color.sky_text_primary')])
        }
          .width(48).height(48)
          .backgroundColor($r('app.color.app_error_container')).borderRadius(24)
          .position({ x: 16, y: 16 })
          .onClick(() => { this.triggerEmergencyStop(); })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
    .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
  }

  @Builder
  private CaptureModeButton(label: string, mode: number) {
    Button(label)
      .layoutWeight(1).height(48).fontSize(14)
      .fontColor(this.captureMode === mode ?
        $r('app.color.app_on_brand') : $r('app.color.sky_text_secondary'))
      .backgroundColor(this.captureMode === mode ?
        $r('app.color.app_brand') : $r('app.color.app_surface_primary'))
      .borderRadius(24)
      .animation(MotionTokens.quick())
      .onClick(() => {
        this.getUIContext().animateTo(MotionTokens.standard(), () => { this.captureMode = mode; });
      })
  }

  @Builder
  private NumberSetting(label: string, value: string, minus: number, plus: number,
    minimum: number, maximum: number, setting: number) {
    Row() {
      Text(label).fontSize(13).fontColor($r('app.color.sky_text_secondary')).width(104)
      Text('-').width(40).height(40).fontSize(18).textAlign(TextAlign.Center)
        .fontColor($r('app.color.sky_text_primary'))
        .backgroundColor($r('app.color.app_surface_primary')).borderRadius(20)
        .onClick(() => { this.adjustSetting(setting, minus, minimum, maximum); })
      Text(value).fontSize(14).fontColor($r('app.color.sky_text_primary')).layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('+').width(40).height(40).fontSize(18).textAlign(TextAlign.Center)
        .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(20)
        .onClick(() => { this.adjustSetting(setting, plus, minimum, maximum); })
    }.width('100%').height(44)
  }

  private useSkyBottomSheet(): boolean {
    return this.skyViewportWidth < 840 || this.skyViewportHeight < 600;
  }

  private skyBottomControlY(): number {
    return Math.max(this.skyTopChromeY() + 60,
      this.skyViewportHeight - (this.useSkyBottomSheet() ? 156 : 76));
  }

  private skyDrawerWidth(): number {
    if (this.useSkyBottomSheet()) {
      return this.skyViewportWidth < 260 ? Math.max(0, this.skyViewportWidth - 16) :
        Math.max(240, this.skyViewportWidth - 24);
    }
    return this.skyOverlayPanel === 2 ? 420 : 350;
  }

  private skyDrawerY(): number {
    if (!this.useSkyBottomSheet()) return this.skyTopChromeY() + 60;
    if (this.skyViewportHeight < 360) return this.skyTopChromeY();
    return Math.max(this.skyTopChromeY() + 60, Math.min(190, this.skyViewportHeight * 0.30));
  }

  private skyDrawerHeight(): number {
    const y: number = this.skyDrawerY();
    if (this.useSkyBottomSheet()) return Math.max(0, this.skyViewportHeight - y -
      (this.skyViewportHeight < 360 ? 16 : 96));
    return Math.max(280, this.skyViewportHeight - y - 20);
  }

  private skyDrawerX(): number {
    if (this.useSkyBottomSheet()) return 12;
    return Math.max(90, this.skyViewportWidth - this.skyDrawerWidth() - 16);
  }

  private captureOverlayWidth(): number {
    return Math.min(480, Math.max(0, this.skyViewportWidth - 16));
  }

  private captureOverlayMaxHeight(): number {
    return Math.max(0, this.skyViewportHeight - 16);
  }

  private isCompactWorkspace(): boolean {
    return this.contentViewportWidth < 600;
  }

  private isPhoneWorkspace(): boolean {
    return this.contentViewportWidth < 600;
  }

  private workspacePageMargin(): number {
    return this.isPhoneWorkspace() ? 16 : 32;
  }

  private skyTopChromeY(): number {
    // 抽屉和手势预览仍由 Index 持有，必须与 SkyWorkspace 使用同一安全区计算。
    return this.skyViewportHeight < 420 ? 28 : 40;
  }

  private navigateToSection(section: number): void {
    this.changeActiveSection(section);
    if (section === 0) {
      this.skyChromeVisible = true;
      if (this.skyMode === 0) this.updateProjectedTargets(true);
    }
  }

  /** 从设备、任务或后期返回星图时直接打开指定抽屉，不能沿用星图内“再次点击关闭”的切换语义。 */
  private navigateToSkyPanel(panel: number): void {
    this.workspaceDirection = -1;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = panel;
    });
    if (panel === 2) this.refreshPlanning();
    if (this.skyMode === 0) this.updateProjectedTargets(true);
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  private navigateToImmersiveSky(): void {
    this.workspaceDirection = -1;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.activeSection = 0;
      this.skyOverlayPanel = 0;
      this.skyChromeVisible = false;
    });
    if (this.skyMode === 0) this.updateProjectedTargets(true);
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  private openSkyPanel(panel: number): void {
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = this.skyOverlayPanel === panel ? 0 : panel;
    });
    if (this.skyOverlayPanel === 2) this.refreshPlanning();
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  /** 点选和搜索必须显式打开面板，不能复用再次点击关闭的交互。 */
  private revealSkyPanel(panel: number): void {
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = panel;
    });
    if (panel === 2) this.refreshPlanning();
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  private selectSkyMode(mode: number): void {
    if (mode === this.skyMode) return;
    const leavingSimulatedTime: boolean = mode === 0 &&
      this.normalTimeState.mode === NormalSkyTimeMode.SIMULATED;
    if (leavingSimulatedTime) {
      this.normalTimeState = NormalSkyTimeService.realtime(Date.now());
      this.operationMessage = 'AR 星图始终使用真实当前时间，已自动退出模拟时间';
    } else if (mode === 1 && this.normalTimeState.mode === NormalSkyTimeMode.REALTIME) {
      this.normalTimeState = NormalSkyTimeService.realtime(Date.now());
    }
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.skyMode = mode;
    });
    if (mode === 0) {
      this.clearNormalMotion();
      this.setGestureEnabled(false);
      this.updateProjectedTargets(true);
    } else {
      this.updateNormalScene();
    }
  }

  private setCapturePanelVisible(visible: boolean): void {
    if (visible === this.showCapturePanel) return;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.showCapturePanel = visible;
    });
  }

  /** 工作区顺序只决定视觉方向；硬件连接、轮询和任务生命周期不进入动画事务。 */
  private changeActiveSection(section: number): void {
    if (section === this.activeSection) return;
    this.workspaceDirection = section > this.activeSection ? 1 : -1;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.activeSection = section;
    });
  }

  private setGestureEnabled(value: boolean): void {
    const analyzerAvailable: boolean = this.gestureModelAvailable();
    const enabled: boolean = value && this.skyMode === 1 && analyzerAvailable;
    this.gestureEnabled = enabled;
    if (value && !analyzerAvailable) {
      this.gestureStatus = '未安装手势模型';
      this.operationMessage = '手势控制未启动：当前版本未安装经过许可和精度验收的手部模型';
    } else {
      this.gestureStatus = enabled ? '正在启动前摄识别' : '未启用';
    }
    if (!enabled) this.gestureInterpreter.reset();
  }

  private gestureModelAvailable(): boolean {
    return this.handFrameSource.getStatus().analyzer.available &&
      this.handFrameSource.getStatus().analyzer.modelLoaded;
  }

  private selectedTarget(): CelestialObject {
    if (this.selectedCustomTarget !== undefined && this.selectedCustomTarget.id === this.selectedTargetId) {
      return this.selectedCustomTarget;
    }
    const catalogTarget: CelestialObject | undefined = CelestialCatalog.getById(this.selectedTargetId);
    if (catalogTarget !== undefined) {
      return catalogTarget;
    }
    const fallback: CelestialObject | undefined = CelestialCatalog.getById('star-vega');
    if (fallback === undefined) {
      throw new Error('离线目录缺少默认目标 star-vega');
    }
    return fallback;
  }

  private performTargetSearch(): void {
    const keyword: string = this.targetSearch.trim();
    if (keyword.length === 0) {
      this.operationMessage = '请输入天体名称、Messier 编号、HIP/HYG 标识或星座名';
      return;
    }
    const catalogMatches: CelestialObject[] = CelestialCatalog.search(keyword, 1);
    if (catalogMatches.length > 0) {
      this.selectedCustomTarget = catalogMatches[0];
      this.selectedTargetId = catalogMatches[0].id;
      this.operationMessage = `已从离线天体目录选择 ${catalogMatches[0].nameZh}`;
      this.focusNormalSkyOnSelected();
      this.refreshPlanning();
      this.revealSkyPanel(1);
      return;
    }
    if (this.visibleStarCatalog.isLoaded()) {
      const stars: VisibleStar[] = this.visibleStarCatalog.search(keyword, 1);
      if (stars.length > 0) {
        this.selectedCustomTarget = this.visibleStarCatalog.toCelestialObject(stars[0]);
        this.selectedTargetId = this.selectedCustomTarget.id;
        this.operationMessage = `已从 HYG 离线星表选择 ${this.selectedCustomTarget.nameZh}`;
        this.focusNormalSkyOnSelected();
        this.refreshPlanning();
        this.revealSkyPanel(1);
        return;
      }
    }
    this.operationMessage = this.visibleStarCatalog.isLoaded() ?
      `离线目录中未找到“${keyword}”` : `天体目录中未找到“${keyword}”，HYG 恒星表仍在加载`;
  }

  private selectedCoordinate(): EquatorialCoordinate | undefined {
    return EphemerisService.skyCoordinate(this.selectedTarget(), this.activeSkyTimestampMs());
  }

  private selectedHorizontal(): HorizontalCoordinate | undefined {
    if (this.observer === undefined) {
      return undefined;
    }
    const currentObserver: ObserverState = {
      latitudeDegrees: this.observer.latitudeDegrees,
      longitudeDegrees: this.observer.longitudeDegrees,
      elevationMeters: this.observer.elevationMeters,
      timestampMs: this.activeSkyTimestampMs()
    };
    return EphemerisService.horizontalCoordinate(
      this.selectedTarget(), currentObserver, currentObserver.timestampMs, RefractionMode.NORMAL);
  }

  private magnitudeText(): string {
    const magnitude = this.selectedTarget().magnitude;
    return magnitude === undefined ? '动态' : magnitude.toFixed(2);
  }

  private coordinateText(): string {
    const coordinate: EquatorialCoordinate | undefined = this.selectedCoordinate();
    if (coordinate === undefined) {
      return '按当前时间计算';
    }
    return coordinate.raHours.toFixed(3) + 'h / ' + coordinate.decDegrees.toFixed(2) + '°';
  }

  private targetAltitudeText(): string {
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    return horizontal === undefined ? '--' : `${horizontal.altitudeDegrees.toFixed(1)}°`;
  }

  private targetAzimuthText(): string {
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    return horizontal === undefined ? '--' : `${horizontal.azimuthDegrees.toFixed(1)}°`;
  }

  private angularSizeText(): string {
    const size = this.selectedTarget().angularSizeDegrees;
    if (size === undefined || size === 0) {
      return '恒星点源';
    }
    return size.toFixed(2) + '°';
  }

  private selectedVisibilityText(): string {
    if (this.observer === undefined) return '待设置地点';
    if (this.selectedCoordinate() === undefined) return '仅资料';
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined) return '待计算';
    if (horizontal.altitudeDegrees >= 20) return '当前适合';
    if (horizontal.altitudeDegrees >= 0) return '低空可见';
    return '地平线下';
  }

  private selectedVisibilityColor(): ResourceColor {
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined) return $r('app.color.app_text_secondary');
    if (horizontal.altitudeDegrees >= 20) return $r('app.color.app_success');
    if (horizontal.altitudeDegrees >= 0) return $r('app.color.app_warning');
    return $r('app.color.app_text_tertiary');
  }

  private isSelectedTargetPlanned(): boolean {
    return this.plannedTargetIds.includes(this.selectedTargetId);
  }

  private addSelectedTargetToPlan(openPlanning: boolean): void {
    const target: CelestialObject = this.selectedTarget();
    if (!this.plannedTargetIds.includes(target.id)) {
      this.plannedTargetIds = this.plannedTargetIds.concat([target.id]);
      if (CelestialCatalog.getById(target.id) === undefined) {
        this.customPlanningTargets.push(target);
      }
      this.operationMessage = `已把 ${target.nameZh} 加入观测计划`;
    }
    this.refreshPlanning();
    if (openPlanning) {
      this.workspaceDirection = -1;
      this.getUIContext().animateTo(MotionTokens.spring(), () => {
        this.activeSection = 0;
        this.skyChromeVisible = true;
        this.skyOverlayPanel = 2;
      });
    }
  }

  private addPlanningTarget(targetId: string): void {
    const target: CelestialObject | undefined = CelestialCatalog.getById(targetId);
    if (target === undefined) return;
    this.selectedCustomTarget = undefined;
    this.selectedTargetId = targetId;
    if (!this.plannedTargetIds.includes(targetId)) {
      this.plannedTargetIds = this.plannedTargetIds.concat([targetId]);
    }
    this.refreshPlanning();
  }

  private removePlannedTarget(targetId: string): void {
    const remaining: string[] = [];
    for (let index: number = 0; index < this.plannedTargetIds.length; index++) {
      if (this.plannedTargetIds[index] !== targetId) remaining.push(this.plannedTargetIds[index]);
    }
    this.plannedTargetIds = remaining;
    const customRemaining: CelestialObject[] = [];
    for (let index: number = 0; index < this.customPlanningTargets.length; index++) {
      if (this.customPlanningTargets[index].id !== targetId) {
        customRemaining.push(this.customPlanningTargets[index]);
      }
    }
    this.customPlanningTargets = customRemaining;
    this.refreshPlanning();
  }

  private selectPlanningTarget(targetId: string): void {
    const target: CelestialObject | undefined = this.planningTargetById(targetId);
    if (target === undefined) return;
    this.selectedTargetId = targetId;
    this.selectedCustomTarget = CelestialCatalog.getById(targetId) === undefined ? target : undefined;
    this.refreshPlanning();
  }

  private planningTargetById(targetId: string): CelestialObject | undefined {
    const catalogTarget: CelestialObject | undefined = CelestialCatalog.getById(targetId);
    if (catalogTarget !== undefined) return catalogTarget;
    for (let index: number = 0; index < this.customPlanningTargets.length; index++) {
      if (this.customPlanningTargets[index].id === targetId) return this.customPlanningTargets[index];
    }
    if (this.selectedCustomTarget !== undefined && this.selectedCustomTarget.id === targetId) {
      return this.selectedCustomTarget;
    }
    return undefined;
  }

  private planningRecommendations(): CelestialObject[] {
    const recommended: CelestialObject[] = CelestialCatalog.recommendedFor18mm();
    const result: CelestialObject[] = [];
    for (let index: number = 0; index < recommended.length && result.length < 5; index++) {
      const target: CelestialObject = recommended[index];
      if (target.type !== CelestialType.SUN && target.precision !== CatalogPrecision.INDEX_ONLY &&
        !this.plannedTargetIds.includes(target.id)) {
        result.push(target);
      }
    }
    return result;
  }

  private planningStartAtMs(): number {
    return Date.now() + this.planningDayOffset * 86400000;
  }

  private refreshPlanning(): void {
    if (this.observer === undefined) {
      this.planningResult = undefined;
      this.plannedTargetSummaries = [];
      return;
    }
    const constraints: ObservationPlanningConstraints = ObservationPlanningService.defaultConstraints();
    constraints.horizonHours = 24;
    const startAtMs: number = this.planningStartAtMs();
    try {
      this.planningResult = ObservationPlanningService.plan(
        this.selectedTarget(), this.observer, startAtMs, this.weatherForecast, constraints);
      this.refreshPlannedTargetSummaries(startAtMs, constraints);
    } catch (error) {
      this.planningResult = undefined;
      this.operationMessage = `观测规划失败：${error}`;
    }
  }

  private refreshPlannedTargetSummaries(startAtMs: number,
    constraints: ObservationPlanningConstraints): void {
    if (this.observer === undefined) {
      this.plannedTargetSummaries = [];
      return;
    }
    const summaries: PlannedTargetSummary[] = [];
    for (let index: number = 0; index < this.plannedTargetIds.length; index++) {
      const target: CelestialObject | undefined = this.planningTargetById(this.plannedTargetIds[index]);
      if (target === undefined) continue;
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        target, this.observer, startAtMs, this.weatherForecast, constraints);
      let windowText: string = '暂无暗夜窗口';
      let scoreText: string = '--';
      let color: ResourceColor = $r('app.color.app_text_tertiary');
      if (result.bestWindow !== undefined) {
        windowText = `${this.formatPlanningTime(result.bestWindow.startAtMs)} - ` +
          `${this.formatPlanningTime(result.bestWindow.endAtMs)}`;
        const score: number = result.overallScore === undefined ?
          result.bestWindow.astronomyScore : result.overallScore;
        scoreText = `${score.toFixed(0)} 分`;
        color = this.recommendationColor(result.recommendation);
      } else if (result.riseTransitSet.status === VisibilityStatus.COORDINATE_UNAVAILABLE) {
        windowText = '目录坐标待补充';
      }
      summaries.push({
        targetId: target.id,
        targetName: target.nameZh,
        designation: target.designation,
        windowText: windowText,
        scoreText: scoreText,
        color: color
      });
    }
    this.plannedTargetSummaries = summaries;
  }

  private applyManualPlanningLocation(): void {
    const latitude: number = Number(this.manualLatitudeText.trim());
    const longitude: number = Number(this.manualLongitudeText.trim());
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      this.operationMessage = '手动地点无效：纬度需在 -90 到 90，经度需在 -180 到 180';
      return;
    }
    this.locationRequestGeneration++;
    this.observer = {
      latitudeDegrees: latitude,
      longitudeDegrees: longitude,
      elevationMeters: 0,
      timestampMs: Date.now()
    };
    this.locationSynced = false;
    this.locationAccuracy = 0;
    this.locationText = `${latitude.toFixed(2)}, ${longitude.toFixed(2)}`;
    this.planningLocationSource = '手动坐标';
    this.weatherForecast = undefined;
    this.weatherStatus = WeatherDataStatus.NOT_REQUESTED;
    this.weatherMessage = '地点已改变 · 天气预报待更新';
    this.operationMessage = '手动观测地点已应用；赤道仪位置仍需单独同步';
    this.updateNormalScene();
    this.updateProjectedTargets(true);
    this.refreshPlanning();
  }

  private async refreshWeatherForecast(): Promise<void> {
    if (this.observer === undefined || this.planningBusy) return;
    const requestObserver: ObserverState = {
      latitudeDegrees: this.observer.latitudeDegrees,
      longitudeDegrees: this.observer.longitudeDegrees,
      elevationMeters: this.observer.elevationMeters,
      timestampMs: Date.now()
    };
    const previous: WeatherForecast | undefined = this.weatherForecast;
    this.planningBusy = true;
    this.weatherStatus = WeatherDataStatus.LOADING;
    this.weatherMessage = '正在更新预报 · 天文窗口仍可查看';
    try {
      const forecast: WeatherForecast = await this.weatherService.fetch(requestObserver);
      if (this.observer === undefined || Math.abs(this.observer.latitudeDegrees - requestObserver.latitudeDegrees) >
        0.0001 || Math.abs(this.observer.longitudeDegrees - requestObserver.longitudeDegrees) > 0.0001) {
        return;
      }
      this.weatherForecast = forecast;
      this.weatherStatus = WeatherDataStatus.LIVE;
      this.weatherMessage = `在线预报 · Open-Meteo · ${this.formatPlanningTime(forecast.fetchedAtMs)} 获取`;
    } catch (error) {
      const cacheUsable: boolean = previous !== undefined && Date.now() - previous.fetchedAtMs <= 86400000 &&
        Math.abs(previous.latitudeDegrees - requestObserver.latitudeDegrees) <= 0.2 &&
        Math.abs(previous.longitudeDegrees - requestObserver.longitudeDegrees) <= 0.2;
      if (cacheUsable && previous !== undefined) {
        this.weatherForecast = {
          status: WeatherDataStatus.CACHED,
          sourceName: previous.sourceName,
          sourceUrl: previous.sourceUrl,
          fetchedAtMs: previous.fetchedAtMs,
          latitudeDegrees: previous.latitudeDegrees,
          longitudeDegrees: previous.longitudeDegrees,
          timezone: previous.timezone,
          utcOffsetSeconds: previous.utcOffsetSeconds,
          forecastDays: previous.forecastDays,
          hourly: previous.hourly.slice(),
          errorMessage: `${error}`
        };
        this.weatherStatus = WeatherDataStatus.CACHED;
        this.weatherMessage = `使用本次会话 ${this.weatherAgeText(previous.fetchedAtMs)}前预报 · 出发前请更新`;
      } else {
        this.weatherForecast = undefined;
        this.weatherStatus = WeatherDataStatus.UNAVAILABLE;
        this.weatherMessage = '天气未获取 · 仅按天文条件规划';
      }
    } finally {
      this.planningBusy = false;
      this.refreshPlanning();
    }
  }

  private weatherStatusColor(): ResourceColor {
    if (this.weatherStatus === WeatherDataStatus.LIVE) return $r('app.color.app_brand');
    if (this.weatherStatus === WeatherDataStatus.CACHED || this.weatherStatus === WeatherDataStatus.LOADING) {
      return $r('app.color.app_warning');
    }
    return $r('app.color.app_text_secondary');
  }

  private planningWeatherSample(): WeatherHourlySample | undefined {
    if (this.weatherForecast === undefined || this.weatherForecast.hourly.length === 0) return undefined;
    let timestampMs: number = this.planningStartAtMs();
    if (this.planningResult !== undefined && this.planningResult.bestWindow !== undefined) {
      timestampMs = this.planningResult.bestWindow.peakAtMs;
    }
    let nearest: WeatherHourlySample = this.weatherForecast.hourly[0];
    let distance: number = Math.abs(nearest.timestampMs - timestampMs);
    for (let index: number = 1; index < this.weatherForecast.hourly.length; index++) {
      const candidate: WeatherHourlySample = this.weatherForecast.hourly[index];
      const candidateDistance: number = Math.abs(candidate.timestampMs - timestampMs);
      if (candidateDistance < distance) {
        nearest = candidate;
        distance = candidateDistance;
      }
    }
    return distance <= 5400000 ? nearest : undefined;
  }

  private planningWeatherMetric(kind: string): string {
    const sample: WeatherHourlySample | undefined = this.planningWeatherSample();
    if (sample === undefined) {
      if (kind === 'cloud') return '云量 --';
      if (kind === 'rain') return '降水 --';
      return '风速 --';
    }
    if (kind === 'cloud') return sample.cloudCoverPercent === undefined ? '云量 --' :
      `云量 ${sample.cloudCoverPercent.toFixed(0)}%`;
    if (kind === 'rain') return sample.precipitationProbabilityPercent === undefined ? '降水 --' :
      `降水 ${sample.precipitationProbabilityPercent.toFixed(0)}%`;
    return sample.windSpeedKph === undefined ? '风速 --' : `风速 ${sample.windSpeedKph.toFixed(0)} km/h`;
  }

  private planningRecommendationTitle(): string {
    if (this.planningResult === undefined) return '等待规划';
    if (this.weatherStatus === WeatherDataStatus.LOADING) return '正在更新预报';
    if (this.weatherStatus === WeatherDataStatus.NOT_REQUESTED ||
      this.weatherStatus === WeatherDataStatus.UNAVAILABLE) return '仅天文条件';
    if (this.weatherRequiresConfirmation()) return '天气待确认';
    if (this.planningResult.recommendation === OutingRecommendation.GOOD) return '今晚条件较好';
    if (this.planningResult.recommendation === OutingRecommendation.CAUTION) return '今晚条件一般';
    if (this.planningResult.recommendation === OutingRecommendation.POOR) return '今晚暂不推荐';
    if (this.planningResult.recommendation === OutingRecommendation.ASTRONOMY_ONLY) return '仅天文条件';
    return '暂无窗口';
  }

  private planningRecommendationColor(): ResourceColor {
    if (this.weatherStatus === WeatherDataStatus.LOADING || this.weatherRequiresConfirmation()) {
      return $r('app.color.app_warning');
    }
    return this.planningResult === undefined ? $r('app.color.app_text_secondary') :
      this.recommendationColor(this.planningResult.recommendation);
  }

  /**
   * Open-Meteo 提供的是逐小时预报，不是现场实况。缓存或获取超过三小时后仍可用于参考，
   * 但界面必须降级为“天气待确认”，避免给用户过度确定的出行建议。
   */
  private weatherRequiresConfirmation(): boolean {
    if (this.weatherForecast === undefined) return false;
    return this.weatherStatus === WeatherDataStatus.CACHED ||
      Date.now() - this.weatherForecast.fetchedAtMs > 3 * 60 * 60 * 1000;
  }

  private weatherAgeText(fetchedAtMs: number): string {
    const ageMinutes: number = Math.max(1, Math.floor((Date.now() - fetchedAtMs) / 60000));
    if (ageMinutes < 60) return `${ageMinutes} 分钟`;
    const ageHours: number = Math.floor(ageMinutes / 60);
    return `${ageHours} 小时`;
  }

  private weatherSourceShortText(): string {
    if (this.weatherStatus === WeatherDataStatus.LOADING) return '预报更新中';
    if (this.weatherForecast !== undefined && !this.weatherRequiresConfirmation()) return '在线预报';
    if (this.weatherForecast !== undefined) return '预报待更新';
    return '仅天文条件';
  }

  private planningPeekWindowText(): string {
    if (this.planningResult === undefined || this.planningResult.bestWindow === undefined) {
      return `${this.selectedVisibilityText()} · ${this.targetAltitudeText()}`;
    }
    return `${this.formatClockTime(this.planningResult.bestWindow.startAtMs)}–` +
      `${this.formatClockTime(this.planningResult.bestWindow.endAtMs)}`;
  }

  private recommendationColor(recommendation: OutingRecommendation): ResourceColor {
    if (recommendation === OutingRecommendation.GOOD) return $r('app.color.app_success');
    if (recommendation === OutingRecommendation.CAUTION ||
      recommendation === OutingRecommendation.ASTRONOMY_ONLY) return $r('app.color.app_warning');
    if (recommendation === OutingRecommendation.POOR) return $r('app.color.app_error');
    return $r('app.color.app_text_tertiary');
  }

  private planningScoreText(): string {
    if (this.planningResult === undefined) return '--';
    const score: number | undefined = this.planningResult.overallScore === undefined ?
      this.planningResult.astronomyScore : this.planningResult.overallScore;
    return score === undefined ? '--' : score.toFixed(0);
  }

  private planningEventText(kind: string): string {
    if (this.planningResult === undefined) return '--';
    if (kind === 'rise') {
      if (this.planningResult.riseTransitSet.status === VisibilityStatus.ALWAYS_ABOVE_HORIZON) return '整段可见';
      return this.formatPlanningTime(this.planningResult.riseTransitSet.riseAtMs);
    }
    if (kind === 'set') return this.formatPlanningTime(this.planningResult.riseTransitSet.setAtMs);
    return this.formatPlanningTime(this.planningResult.riseTransitSet.transitAtMs);
  }

  private planningMaximumAltitudeText(): string {
    if (this.planningResult === undefined || this.planningResult.riseTransitSet.maxAltitudeDegrees < -89) {
      return '--';
    }
    return `${this.planningResult.riseTransitSet.maxAltitudeDegrees.toFixed(1)}°`;
  }

  private planningHeightBars(): PlanningHeightBar[] {
    if (this.planningResult === undefined || this.planningResult.samples.length === 0) return [];
    const bars: PlanningHeightBar[] = [];
    const count: number = 12;
    for (let index: number = 0; index < count; index++) {
      const sampleIndex: number = Math.round(index * (this.planningResult.samples.length - 1) / (count - 1));
      const sample = this.planningResult.samples[sampleIndex];
      const height: number = this.clamp((sample.altitudeDegrees + 10) / 90 * 80, 4, 80);
      let color: ResourceColor = $r('app.color.app_text_tertiary');
      if (sample.altitudeDegrees >= 20 && sample.sunAltitudeDegrees <= -12) {
        color = $r('app.color.app_success');
      } else if (sample.altitudeDegrees >= 0) {
        color = $r('app.color.app_warning');
      }
      bars.push({
        id: sample.timestampMs.toString(),
        label: this.pad2(new Date(sample.timestampMs).getHours()),
        height: height,
        color: color
      });
    }
    return bars;
  }

  private planningBestWindowText(): string {
    if (this.planningResult === undefined || this.planningResult.bestWindow === undefined) return '暂无可用窗口';
    return `${this.formatPlanningTime(this.planningResult.bestWindow.startAtMs)} - ` +
      `${this.formatPlanningTime(this.planningResult.bestWindow.endAtMs)}`;
  }

  private planningBestWindowDetail(): string {
    if (this.planningResult === undefined || this.planningResult.bestWindow === undefined) {
      return '尝试更换日期、地点或目标';
    }
    const window: ObservationWindow = this.planningResult.bestWindow;
    const durationMinutes: number = Math.max(0, Math.round((window.endAtMs - window.startAtMs) / 60000));
    const weather: string = window.weatherScore === undefined ? '天气待确认' : `天气 ${window.weatherScore.toFixed(0)} 分`;
    return `${durationMinutes} 分钟 · 峰值 ${window.peakAltitudeDegrees.toFixed(1)}° · ${weather}`;
  }

  private planningMoonText(): string {
    if (this.planningResult === undefined) return '--';
    return `${this.planningResult.moonPhaseName} ${this.planningResult.moonIlluminationPercent.toFixed(0)}%`;
  }

  private planningMoonDetail(): string {
    if (this.planningResult === undefined || this.planningResult.moonSeparationDegrees === undefined) {
      return '目标月距 --';
    }
    return `目标月距 ${this.planningResult.moonSeparationDegrees.toFixed(0)}°`;
  }

  private formatPlanningTime(timestampMs?: number): string {
    if (timestampMs === undefined) return '--';
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private formatClockTime(timestampMs: number): string {
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private connectionText(state: ConnectionState): string {
    if (state === ConnectionState.CONNECTED) return '已连接';
    if (state === ConnectionState.CONNECTING) return '连接中';
    if (state === ConnectionState.ERROR) return '异常';
    if (state === ConnectionState.SIMULATED) return '模拟';
    return '未连接';
  }

  private connectionColor(state: ConnectionState): ResourceColor {
    if (state === ConnectionState.CONNECTED) return $r('app.color.app_success');
    if (state === ConnectionState.CONNECTING) return $r('app.color.app_warning');
    if (state === ConnectionState.ERROR) return $r('app.color.app_error');
    if (state === ConnectionState.SIMULATED) return $r('app.color.app_brand');
    return $r('app.color.app_text_tertiary');
  }

  private sectionTitle(): string {
    if (this.activeSection === 0) return this.skyMode === 0 ? 'AR 寻星' : '普通星图';
    if (this.activeSection === 4) return '观测规划';
    if (this.activeSection === 1) return '设备控制';
    if (this.activeSection === 2) return '拍摄任务';
    return '图像后期';
  }

  private sectionSubtitle(): string {
    if (this.activeSection === 0) return '定位、姿态与离线星表驱动的实时天空视图';
    if (this.activeSection === 4) return '目标可见窗口、月光与逐小时天气预报联合评估';
    if (this.activeSection === 1) return 'OnStepX 赤道仪与 EOS R7 网关';
    if (this.activeSection === 2) return '板解析、漂移校正、堆栈与延时视频';
    return '原片、堆栈和受约束 AI 结果可追溯对比';
  }

  private currentTimeText(): string {
    const date: Date = new Date(this.activeSkyTimestampMs());
    return this.pad2(date.getHours()) + ':' + this.pad2(date.getMinutes());
  }

  private activeSkyTimestampMs(): number {
    return this.skyMode === 1 ? this.normalTimeState.timestampMs : Date.now();
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  private canStartCapture(): boolean {
    if (this.operationBusy || this.mountConnection !== ConnectionState.CONNECTED ||
      !this.mountHomed || !this.mountCoordinatesTopocentric || !this.selectedTarget().gotoAllowed ||
      this.selectedTarget().id === 'solar-sun' ||
      (this.skyMode === 1 && this.normalTimeState.mode === NormalSkyTimeMode.SIMULATED)) {
      return false;
    }
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined || horizontal.altitudeDegrees < 10.0) {
      return false;
    }
    return this.captureMode === 0 || this.gatewayConnection === ConnectionState.CONNECTED;
  }

  private captureReadinessText(): string {
    if (this.operationBusy) return '正在执行设备操作，请稍候';
    if (this.mountConnection !== ConnectionState.CONNECTED) return '请先连接 OnStepX 赤道仪';
    if (this.skyMode === 1 && this.normalTimeState.mode === NormalSkyTimeMode.SIMULATED) {
      return '模拟时间只用于浏览和规划，立即观测/拍摄已禁用';
    }
    if (!this.mountCoordinatesTopocentric) return '固件坐标模式不是 TOPOCENTRIC(1)，自动运动已锁定';
    if (!this.mountHomed) return '自动运动前必须完成两轴回零';
    if (this.observer === undefined) return '需要系统定位才能计算目标方向';
    if (this.selectedTarget().id === 'solar-sun') return '太阳永久禁止普通 GOTO';
    if (!this.selectedTarget().gotoAllowed || this.selectedCoordinate() === undefined) return '目标缺少可靠坐标，禁止自动 GOTO';
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined || horizontal.altitudeDegrees < 10.0) return '目标当前低于 10° 安全高度';
    if (this.captureMode > 0 && this.gatewayConnection !== ConnectionState.CONNECTED) return '请先连接 EOS R7 相机网关';
    return this.locationSynced ? '目标方向与设备安全检查通过' : '准备就绪；开始前将自动同步地点和真实时间';
  }

  private adjustSetting(setting: number, delta: number, minimum: number, maximum: number): void {
    if (setting === 0) this.exposureSeconds = this.clamp(this.exposureSeconds + delta, minimum, maximum);
    if (setting === 1) this.frameCount = this.clamp(this.frameCount + delta, minimum, maximum);
    if (setting === 2) this.iso = this.clamp(this.iso + delta, minimum, maximum);
    if (setting === 3) this.intervalSeconds = this.clamp(this.intervalSeconds + delta, minimum, maximum);
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private async loadVisibleStarCatalog(): Promise<void> {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      this.catalogStatus = '星表上下文不可用';
      return;
    }
    try {
      const metadata: VisibleStarCatalogMetadata = await this.visibleStarCatalog.load(context);
      this.catalogStatus = `${metadata.loadedCount.toLocaleString()} 星 · 离线`;
      // 星表按星等排序，预先缓存天穹所需上限，姿态刷新时不再复制全部 8921 条记录。
      this.domeCatalogStars = this.visibleStarCatalog.filterByMagnitude(5.8, 860);
      this.updateNormalScene();
      this.updateProjectedTargets(true);
    } catch (error) {
      this.catalogStatus = '离线星表加载失败';
      this.operationMessage = `星表加载失败：${error}`;
    }
  }

  private selectedTypeText(): string {
    const type: CelestialType = this.selectedTarget().type;
    if (type === CelestialType.STAR) return '恒星';
    if (type === CelestialType.CONSTELLATION) return '星座';
    if (type === CelestialType.MESSIER) return 'Messier 深空天体';
    if (type === CelestialType.SUN) return '太阳';
    if (type === CelestialType.MOON) return '月球';
    if (type === CelestialType.PLANET) return '行星';
    return '天体';
  }

  private async loadNormalSkyCatalog(): Promise<void> {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      this.normalCatalogStatus = '星座线上下文不可用';
      return;
    }
    try {
      const metadata: NormalSkyCatalogMetadata = await this.normalSkyCatalog.load(context);
      this.normalCatalogStatus = `${metadata.constellationCount} 星座 · 离线`;
      this.updateNormalScene();
    } catch (error) {
      this.normalCatalogStatus = '离线星座线加载失败';
      this.operationMessage = `星座线加载失败：${error}`;
    }
  }

  private normalSkySize(): SkyMapSize {
    return {
      widthPixels: Math.max(1.0, this.skyViewportWidth),
      heightPixels: Math.max(1.0, this.skyViewportHeight)
    };
  }

  private applyNormalViewState(viewState: NormalSkyViewState): void {
    this.normalViewState = NormalSkyViewStateService.normalizeState(viewState);
    this.normalViewport = NormalSkyViewStateService.snapshot(this.normalViewState);
  }

  private normalObserver(timestampMs: number): ObserverState | undefined {
    if (this.observer === undefined) {
      return undefined;
    }
    return {
      latitudeDegrees: this.observer.latitudeDegrees,
      longitudeDegrees: this.observer.longitudeDegrees,
      elevationMeters: this.observer.elevationMeters,
      timestampMs: timestampMs
    };
  }

  private updateNormalScene(): void {
    this.clearScheduledNormalSceneUpdate();
    this.rebuildNormalScene();
  }

  private scheduleNormalSceneUpdate(): void {
    if (this.normalSceneUpdateTimer >= 0) return;
    this.normalSceneUpdateTimer = setTimeout(() => {
      this.normalSceneUpdateTimer = -1;
      this.rebuildNormalScene();
    }, 16);
  }

  private clearScheduledNormalSceneUpdate(): void {
    if (this.normalSceneUpdateTimer >= 0) {
      clearTimeout(this.normalSceneUpdateTimer);
      this.normalSceneUpdateTimer = -1;
    }
  }

  private rebuildNormalScene(): void {
    const timestampMs: number = this.normalTimeState.timestampMs;
    this.normalScene = this.normalSkySceneService.build({
      viewport: this.normalViewport,
      size: this.normalSkySize(),
      layers: this.normalLayers,
      selectedTargetId: this.selectedTargetId,
      timestampMs: timestampMs,
      observer: this.normalObserver(timestampMs),
      guideInsets: this.normalSkyGuideInsets(),
      showDirectionMarkers: NormalSkyLayoutService.showDirectionMarkers(
        this.useSkyBottomSheet(), this.skyOverlayPanel)
    });
  }

  private normalGestureAnchorX(value: number): number {
    return Number.isFinite(value) && value > 0.0 ? value : this.skyViewportWidth / 2.0;
  }

  private normalGestureAnchorY(value: number): number {
    return Number.isFinite(value) && value > 0.0 ? value : this.skyViewportHeight / 2.0;
  }

  private setNormalLayer(layer: number, enabled: boolean): void {
    const next: SkyLayerVisibility = {
      constellationLines: this.normalLayers.constellationLines,
      equatorialGrid: this.normalLayers.equatorialGrid,
      ecliptic: this.normalLayers.ecliptic,
      horizon: this.normalLayers.horizon,
      deepSky: this.normalLayers.deepSky,
      solarSystem: this.normalLayers.solarSystem,
      directionGuides: this.normalLayers.directionGuides
    };
    if (layer === 0) next.constellationLines = enabled;
    if (layer === 1) next.equatorialGrid = enabled;
    if (layer === 2) next.ecliptic = enabled;
    if (layer === 3) next.horizon = enabled;
    if (layer === 4) next.deepSky = enabled;
    if (layer === 5) next.solarSystem = enabled;
    if (layer === 6) next.directionGuides = enabled;
    this.normalLayers = next;
    this.updateNormalScene();
  }

  private normalSkyGuideInsets(): SkyGuideInsets {
    return NormalSkyLayoutService.guideInsets({
      viewportWidth: this.skyViewportWidth,
      viewportHeight: this.skyViewportHeight,
      chromeVisible: this.skyChromeVisible,
      compact: this.useSkyBottomSheet(),
      overlayPanel: this.skyOverlayPanel,
      drawerWidth: this.skyDrawerWidth(),
      layerPanelOpen: this.normalLayerPanelOpen
    });
  }

  private homeNormalSky(): void {
    this.clearNormalMotion();
    this.applyNormalViewState(NormalSkyViewStateService.home(
      this.normalObserver(this.normalTimeState.timestampMs), this.normalViewState.orientation));
    this.updateNormalScene();
  }

  private resetNormalSkyNorth(): void {
    this.clearNormalMotion();
    this.applyNormalViewState(NormalSkyViewStateService.resetNorth(
      this.normalViewState, this.normalObserver(this.normalTimeState.timestampMs)));
    this.updateNormalScene();
  }

  private toggleNormalSkyOrientation(): void {
    this.clearNormalMotion();
    const orientation: SkyMapOrientation =
      this.normalViewState.orientation === SkyMapOrientation.EQUATORIAL_NORTH_UP ?
        SkyMapOrientation.HORIZON_ZENITH : SkyMapOrientation.EQUATORIAL_NORTH_UP;
    this.applyNormalViewState(NormalSkyViewStateService.home(
      this.normalObserver(this.normalTimeState.timestampMs), orientation));
    if (orientation === SkyMapOrientation.HORIZON_ZENITH && this.observer === undefined) {
      this.operationMessage = '地平线需要观测地点；当前仍可浏览完整离线天球';
    } else {
      this.operationMessage = orientation === SkyMapOrientation.HORIZON_ZENITH ?
        '已切换为天顶居中的地平视图' : '已切换为北上东左的赤道视图';
    }
    this.updateNormalScene();
  }

  private returnNormalSkyToRealtime(): void {
    this.normalTimeState = NormalSkyTimeService.realtime(Date.now());
    this.operationMessage = '普通星图已回到真实当前时间';
    this.updateNormalScene();
  }

  private selectNormalSkyTime(timestampMs: number): void {
    this.clearNormalMotion();
    this.normalTimeState = NormalSkyTimeService.selectTime(
      this.normalTimeState, timestampMs);
    this.operationMessage = '已进入模拟时间；设备 GOTO、同步和拍摄保持禁用';
    this.updateNormalScene();
  }

  private toggleNormalSkyPlayback(): void {
    this.normalTimeState = NormalSkyTimeService.togglePlayback(this.normalTimeState);
    this.normalTimeLastTickMs = Date.now();
    this.operationMessage = this.normalTimeState.playing ?
      '模拟时间正在播放；设备操作保持禁用' : '模拟时间已暂停';
    this.updateNormalScene();
  }

  private setNormalSkyPlaybackSpeed(speed: NormalSkyPlaybackSpeed): void {
    this.normalTimeState = NormalSkyTimeService.setSpeed(this.normalTimeState, speed);
    this.normalTimeLastTickMs = Date.now();
    this.updateNormalScene();
  }

  private zoomNormalSky(scale: number): void {
    this.clearNormalMotion();
    this.applyNormalViewState(NormalSkyViewStateService.zoomAt(this.normalViewState,
      this.normalSkySize(), scale, this.skyViewportWidth / 2.0, this.skyViewportHeight / 2.0));
    this.scheduleNormalSceneUpdate();
  }

  private setNormalSkyFieldOfView(fieldOfViewDegrees: number): void {
    this.clearNormalMotion();
    const target: number = this.clamp(fieldOfViewDegrees,
      NormalSkyProjectionService.MIN_FIELD_OF_VIEW_DEGREES,
      NormalSkyProjectionService.MAX_FIELD_OF_VIEW_DEGREES);
    const scale: number = this.normalViewState.fieldOfViewDegrees / Math.max(0.001, target);
    this.applyNormalViewState(NormalSkyViewStateService.zoomAt(this.normalViewState,
      this.normalSkySize(), scale, this.skyViewportWidth / 2.0, this.skyViewportHeight / 2.0));
    this.scheduleNormalSceneUpdate();
  }

  private selectNormalSkyObject(objectId: string): void {
    let target: CelestialObject | undefined = CelestialCatalog.getById(objectId);
    if (target !== undefined) {
      this.selectedCustomTarget = undefined;
    } else {
      let projected: ProjectedSkyObject | undefined = undefined;
      for (let index: number = 0; index < this.normalScene.objects.length; index++) {
        if (this.normalScene.objects[index].id === objectId) {
          projected = this.normalScene.objects[index];
          break;
        }
      }
      if (projected !== undefined) {
        const star: VisibleStar | undefined = this.visibleStarCatalog.getById(projected.designation);
        if (star !== undefined) {
          target = this.visibleStarCatalog.toCelestialObject(star);
          this.selectedCustomTarget = target;
        }
      }
    }
    if (target === undefined) {
      return;
    }
    this.selectedTargetId = target.id;
    this.operationMessage = `已在普通星图中选择 ${target.nameZh}`;
    this.updateNormalScene();
    this.refreshPlanning();
    this.revealSkyPanel(1);
  }

  private focusNormalSkyOnSelected(): void {
    const coordinate: EquatorialCoordinate | undefined = this.selectedCoordinate();
    if (coordinate === undefined) {
      this.updateNormalScene();
      return;
    }
    const target: CelestialObject = this.selectedTarget();
    const targetField: number = target.type === CelestialType.CONSTELLATION ?
      this.clamp((target.angularSizeDegrees === undefined ? 35.0 : target.angularSizeDegrees) * 1.8,
        20.0, 90.0) : 30.0;
    const destination: NormalSkyViewState = NormalSkyViewStateService.flyTo(
      this.normalViewState, coordinate, targetField);
    if (this.skyMode !== 1) {
      this.applyNormalViewState(destination);
      this.updateNormalScene();
      return;
    }
    this.startNormalFly(destination);
  }

  private startNormalFly(destination: NormalSkyViewState): void {
    this.clearNormalMotion();
    const source: NormalSkyViewState = this.normalViewState;
    const startedAtMs: number = Date.now();
    this.normalFlyTimer = setInterval(() => {
      const elapsed: number = Date.now() - startedAtMs;
      const linearProgress: number = Math.min(1.0, elapsed / 350.0);
      const easedProgress: number = 1.0 - Math.pow(1.0 - linearProgress, 3.0);
      this.applyNormalViewState(NormalSkyViewStateService.interpolate(
        source, destination, easedProgress));
      this.scheduleNormalSceneUpdate();
      if (linearProgress >= 1.0) {
        this.stopNormalFly();
      }
    }, 16);
  }

  private startNormalInertia(velocityX: number, velocityY: number): void {
    this.stopNormalInertia();
    const initialVelocityX: number = Number.isFinite(velocityX) ? velocityX : 0.0;
    const initialVelocityY: number = Number.isFinite(velocityY) ? velocityY : 0.0;
    if (Math.abs(initialVelocityX) + Math.abs(initialVelocityY) < 120.0) {
      return;
    }
    const durationMs: number = 320.0;
    const startedAtMs: number = Date.now();
    let previousAtMs: number = startedAtMs;
    this.normalInertiaTimer = setInterval(() => {
      const currentAtMs: number = Date.now();
      const elapsedMs: number = currentAtMs - startedAtMs;
      const deltaSeconds: number = Math.max(0.0, currentAtMs - previousAtMs) / 1000.0;
      previousAtMs = currentAtMs;
      const progress: number = this.clamp(elapsedMs / durationMs, 0.0, 1.0);
      const decay: number = (1.0 - progress) * (1.0 - progress);
      this.applyNormalViewState(NormalSkyViewStateService.panWithVelocity(
        this.normalViewState, this.normalSkySize(),
        initialVelocityX * decay, initialVelocityY * decay, deltaSeconds));
      this.scheduleNormalSceneUpdate();
      if (progress >= 1.0) {
        this.stopNormalInertia();
      }
    }, 16);
  }

  private stopNormalInertia(): void {
    if (this.normalInertiaTimer >= 0) {
      clearInterval(this.normalInertiaTimer);
      this.normalInertiaTimer = -1;
    }
  }

  private stopNormalFly(): void {
    if (this.normalFlyTimer >= 0) {
      clearInterval(this.normalFlyTimer);
      this.normalFlyTimer = -1;
    }
  }

  private clearNormalMotion(): void {
    this.stopNormalInertia();
    this.stopNormalFly();
    this.normalSkyGestureController.reset();
  }

  private startNormalSceneTimer(): void {
    this.clearNormalSceneTimer();
    this.normalTimeLastTickMs = Date.now();
    this.normalSceneTimer = setInterval(() => {
      const nowMs: number = Date.now();
      if (this.activeSection !== 0 || this.skyMode !== 1) {
        this.normalTimeLastTickMs = nowMs;
        return;
      }
      const elapsedMs: number = Math.max(0.0, nowMs - this.normalTimeLastTickMs);
      this.normalTimeLastTickMs = nowMs;
      if (this.normalTimeState.mode === NormalSkyTimeMode.SIMULATED && this.normalTimeState.playing) {
        this.normalTimeState = NormalSkyTimeService.tick(
          this.normalTimeState, elapsedMs, nowMs);
        this.scheduleNormalSceneUpdate();
      } else if (this.normalTimeState.mode === NormalSkyTimeMode.REALTIME &&
        nowMs - this.normalTimeState.timestampMs >= 1000.0) {
        this.normalTimeState = NormalSkyTimeService.tick(
          this.normalTimeState, elapsedMs, nowMs);
        if (nowMs - this.normalScene.generatedAtMs >= 60000.0) this.scheduleNormalSceneUpdate();
      }
    }, 100);
  }

  private clearNormalSceneTimer(): void {
    this.clearScheduledNormalSceneUpdate();
    if (this.normalSceneTimer >= 0) {
      clearInterval(this.normalSceneTimer);
      this.normalSceneTimer = -1;
    }
    this.normalTimeLastTickMs = 0;
  }

  private applyHandLandmarks(result: HandLandmarkAnalysisResult): void {
    // 关闭开关或切换回 AR 后，丢弃已经在推理队列中的旧帧，避免异步回调继续移动普通星图。
    if (!this.gestureEnabled || this.skyMode !== 1) {
      this.gestureInterpreter.reset();
      this.normalSkyGestureController.endHandTransform();
      return;
    }
    const frame: GestureFrame = this.gestureInterpreter.interpret(
      result.hands, result.frameReceivedAtMs);
    let normalSkyChanged: boolean = false;
    if (frame.gesture === HandGesture.DRAG) {
      this.normalSkyGestureController.endHandTransform();
      this.applyNormalViewState(NormalSkyViewStateService.pan(
        this.normalViewState, this.normalSkySize(),
        frame.deltaX * this.skyViewportWidth, frame.deltaY * this.skyViewportHeight));
      normalSkyChanged = true;
      this.gestureStatus = '单掌拖拽';
    } else if (frame.gesture === HandGesture.ROTATE_SCALE) {
      const anchorX: number = frame.selectX * this.skyViewportWidth;
      const anchorY: number = frame.selectY * this.skyViewportHeight;
      const update: NormalSkyGestureUpdate = this.normalSkyGestureController.updateHandTransform(
        this.normalViewState, this.normalSkySize(), frame.scale, frame.rotationDegrees, anchorX, anchorY);
      if (update.changed) {
        this.applyNormalViewState(update.viewState);
        normalSkyChanged = true;
      }
      this.gestureStatus = '双掌旋转 / 缩放';
    } else if (frame.gesture === HandGesture.PINCH_SELECT) {
      this.normalSkyGestureController.endHandTransform();
      this.selectNearestGestureTarget(
        frame.selectX * this.skyViewportWidth, frame.selectY * this.skyViewportHeight);
      this.gestureStatus = '捏合选择';
    } else if (frame.gesture === HandGesture.FIST_RESET) {
      this.normalSkyGestureController.endHandTransform();
      this.applyNormalViewState(NormalSkyViewStateService.home(
        this.normalObserver(this.normalTimeState.timestampMs), this.normalViewState.orientation));
      normalSkyChanged = true;
      this.gestureStatus = '握拳复位';
    } else if (result.hands.length > 0) {
      this.normalSkyGestureController.endHandTransform();
      this.gestureStatus = '已检测手部';
    } else {
      this.normalSkyGestureController.endHandTransform();
      this.gestureStatus = '等待手部进入画面';
    }
    if (normalSkyChanged) {
      this.scheduleNormalSceneUpdate();
    }
  }

  private selectNearestGestureTarget(screenX: number, screenY: number): void {
    const nearest: ProjectedSkyObject | undefined = NormalSkyProjectionService.hitTest(
      this.normalScene.objects, screenX, screenY, 18.0);
    if (nearest !== undefined) {
      this.selectNormalSkyObject(nearest.id);
    }
  }

  private async refreshLocation(): Promise<void> {
    const requestGeneration: number = ++this.locationRequestGeneration;
    const previousObserver: ObserverState | undefined = this.observer;
    const previousLocationText: string = this.locationText;
    this.locationText = '正在定位';
    try {
      const result: ObserverLocationResult = await ObserverLocationService.current();
      if (requestGeneration !== this.locationRequestGeneration) return;
      this.observer = result.observer;
      this.locationAccuracy = result.accuracyMeters;
      this.locationSynced = false;
      this.locationText = `${result.observer.latitudeDegrees.toFixed(2)}, ${result.observer.longitudeDegrees.toFixed(2)}`;
      this.manualLatitudeText = result.observer.latitudeDegrees.toFixed(5);
      this.manualLongitudeText = result.observer.longitudeDegrees.toFixed(5);
      this.planningLocationSource = '系统定位';
      this.operationMessage = `定位精度约 ±${result.accuracyMeters.toFixed(0)} 米`;
      this.updateNormalScene();
      this.updateProjectedTargets(true);
      this.refreshPlanning();
      this.refreshWeatherForecast();
    } catch (error) {
      if (requestGeneration !== this.locationRequestGeneration) return;
      this.locationSynced = false;
      if (previousObserver === undefined) {
        this.observer = undefined;
        this.locationText = '定位不可用';
        this.planningLocationSource = '等待手动地点';
        this.operationMessage = `定位失败：${error}`;
        this.updateNormalScene();
      } else {
        this.observer = previousObserver;
        this.locationText = previousLocationText;
        this.operationMessage = `系统定位失败，已保留${this.planningLocationSource}：${error}`;
        this.updateNormalScene();
        this.refreshPlanning();
      }
    }
  }

  private handleHuaweiArFrame(snapshot: HuaweiArFrameSnapshot): void {
    if (snapshot.displayQuaternion === undefined) {
      const hadNativePose: boolean = this.arEngineOrientation !== undefined;
      this.arEngineOrientation = undefined;
      this.arEngineFrameTimestampNs = 0;
      this.applyLastSensorPose();
      if (hadNativePose) this.updateProjectedTargets(true);
      return;
    }
    const converted: Quaternion = HuaweiArPoseAdapter.toSkyDomeOrientation({
      x: snapshot.displayQuaternion.x,
      y: snapshot.displayQuaternion.y,
      z: snapshot.displayQuaternion.z,
      w: snapshot.displayQuaternion.w
    });
    this.arEngineOrientation = this.arEngineOrientation === undefined ? converted :
      SkyDomeProjectionService.slerpQuaternion(this.arEngineOrientation, converted, 0.72);
    this.arEngineFrameTimestampNs = snapshot.frameTimestampNs;
    this.updateProjectedTargets();
  }

  private handleHuaweiArStatus(status: HuaweiArViewStatus): void {
    this.arTrackingText = status.message;
    if (status.phase === HuaweiArViewPhase.RUNNING || status.phase === HuaweiArViewPhase.LIMITED ||
      status.phase === HuaweiArViewPhase.INITIALIZING || status.phase === HuaweiArViewPhase.CHECKING ||
      status.phase === HuaweiArViewPhase.REQUESTING_PERMISSION || status.phase === HuaweiArViewPhase.DESTROYED) {
      return;
    }
    if (status.phase === HuaweiArViewPhase.UNSUPPORTED ||
      status.phase === HuaweiArViewPhase.PERMISSION_REQUIRED || status.phase === HuaweiArViewPhase.FAILED) {
      // AR Engine 是增强链路而非页面前提；初始化失败时释放原生视图并回到 CameraKit + 传感器。
      this.arEngineOrientation = undefined;
      this.arEngineFrameTimestampNs = 0;
      this.huaweiArViewEnabled = false;
      this.arTrackingText = '传感器天穹';
      this.applyLastSensorPose();
      this.operationMessage = `${status.message}，已切换到传感器预览`;
      this.updateProjectedTargets(true);
    }
  }

  private applyLastSensorPose(): void {
    if (this.lastSensorPose === undefined) return;
    this.poseHeading = this.lastSensorPose.headingDegrees;
    this.posePitch = this.lastSensorPose.pitchDegrees;
    this.poseRoll = this.lastSensorPose.rollDegrees;
    this.poseReady = true;
  }

  private updateProjectedTargets(force: boolean = false): void {
    const now: number = Date.now();
    if (!force && now - this.lastProjectionAtMs < 20) {
      return;
    }
    this.lastProjectionAtMs = now;
    const pose: DevicePose = {
      // 传感器尚未输出时仍显示静态预览天穹；该姿态只影响视觉，不进入任何设备控制流程。
      headingDegrees: this.poseReady ? this.poseHeading : 180.0,
      pitchDegrees: this.poseReady ? this.posePitch : 35.0,
      rollDegrees: this.poseReady ? this.poseRoll : 0.0
    };
    try {
      const frame: SkyDomeFrame = this.skyDomeSceneService.createFrame({
        observer: this.domeObserver(now),
        pose: pose,
        viewport: {
          widthPixels: this.skyViewportWidth,
          heightPixels: this.skyViewportHeight
        },
        catalogStars: this.domeCatalogStars,
        featuredTargets: this.domeFeaturedTargets(),
        selectedTargetId: this.selectedTargetId,
        revealLevel: this.skyDomeRevealLevel,
        calibration: this.calibration,
        orientation: this.arEngineOrientation,
        trackingQuality: this.arEngineOrientation === undefined ?
          (this.poseReady ? ArTrackingQuality.NORMAL : ArTrackingQuality.INITIALIZING) : ArTrackingQuality.HIGH,
        trackingSource: this.arEngineOrientation === undefined ?
          ArTrackingSource.SENSOR_FUSION : ArTrackingSource.HUAWEI_AR_ENGINE,
        timestampNs: this.arEngineOrientation === undefined ? now * 1000000.0 : this.arEngineFrameTimestampNs
      });
      if (!this.poseReady && this.arEngineOrientation === undefined) {
        frame.trackingQuality = ArTrackingQuality.INITIALIZING;
      }
      this.skyDomeFrame = frame;
    } catch (error) {
      this.operationMessage = `天穹渲染数据更新失败：${error}`;
    }
  }

  /**
   * 无定位时仅为 AR 视觉预览使用上海城市坐标，使首次打开不会出现空白画面。
   * GOTO、拍摄安全检查、天气和观测规划始终直接读取 this.observer，不会消费该回退值。
   */
  private domeObserver(timestampMs: number): ObserverState {
    if (this.observer !== undefined) {
      return {
        latitudeDegrees: this.observer.latitudeDegrees,
        longitudeDegrees: this.observer.longitudeDegrees,
        elevationMeters: this.observer.elevationMeters,
        timestampMs: timestampMs
      };
    }
    return {
      latitudeDegrees: 31.2304,
      longitudeDegrees: 121.4737,
      elevationMeters: 12.0,
      timestampMs: timestampMs
    };
  }

  private domeFeaturedTargets(): CelestialObject[] {
    const targets: CelestialObject[] = [];
    for (let index: number = 0; index < FEATURED_TARGET_IDS.length; index++) {
      const target: CelestialObject | undefined = CelestialCatalog.getById(FEATURED_TARGET_IDS[index]);
      if (target !== undefined) {
        targets.push(target);
      }
    }
    if (this.selectedCustomTarget !== undefined) {
      targets.push(this.selectedCustomTarget);
    }
    return targets;
  }

  private selectSkyDomeMarker(markerId: string): void {
    if (markerId.startsWith('target:')) {
      const targetId: string = markerId.substring('target:'.length);
      const target: CelestialObject | undefined = CelestialCatalog.getById(targetId);
      if (target === undefined && (this.selectedCustomTarget === undefined ||
        this.selectedCustomTarget.id !== targetId)) {
        return;
      }
      if (target !== undefined) {
        this.selectedCustomTarget = undefined;
        this.selectedTargetId = target.id;
        this.operationMessage = `已在天穹中选择 ${target.nameZh}`;
      }
    } else if (markerId.startsWith('catalog:')) {
      const starId: string = markerId.substring('catalog:'.length);
      const star: VisibleStar | undefined = this.visibleStarCatalog.getById(starId);
      if (star === undefined) {
        return;
      }
      this.selectedCustomTarget = this.visibleStarCatalog.toCelestialObject(star);
      this.selectedTargetId = this.selectedCustomTarget.id;
      this.operationMessage = `已在天穹中选择 ${this.selectedCustomTarget.nameZh}`;
    } else {
      return;
    }
    this.revealSkyPanel(1);
    this.refreshPlanning();
    this.updateProjectedTargets(true);
  }

  private calibrateSelectedTarget(): void {
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (!this.poseReady || horizontal === undefined) {
      this.calibrationText = '需要定位与姿态';
      this.operationMessage = '请开启定位，将目标置于画面中心后再执行一星校准';
      return;
    }
    this.calibration = AstronomyService.calibrateFromAnchor(horizontal, {
      headingDegrees: this.poseHeading,
      pitchDegrees: this.posePitch,
      rollDegrees: this.poseRoll
    }, this.selectedTargetId, Date.now());
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.calibrationEnabled = true;
      this.calibrationFeedbackActive = true;
      this.calibrationText = `已校准 · ${this.selectedTarget().designation}`;
      this.operationMessage = '一星校准已应用；移动 Pad 检查叠加是否跟随目标';
    });
    setTimeout(() => {
      this.getUIContext().animateTo(MotionTokens.quick(), () => {
        this.calibrationFeedbackActive = false;
      });
    }, MotionTokens.EMPHASIZED_MS);
    this.updateProjectedTargets(true);
  }

  private async toggleMountConnection(): Promise<void> {
    if (this.operationBusy) {
      return;
    }
    this.operationBusy = true;
    this.emergencyMessage = '';
    try {
      if (this.mountConnection === ConnectionState.CONNECTED) {
        await this.mountClient.disconnect();
        this.clearMountPolling();
        this.mountConnection = ConnectionState.DISCONNECTED;
        this.mountHomed = false;
        this.mountCoordinatesTopocentric = false;
        this.locationSynced = false;
        this.tracking = false;
        this.operationMessage = '赤道仪已断开';
      } else {
        this.mountConnection = ConnectionState.CONNECTING;
        this.operationMessage = '正在连接 10.42.0.20:9999';
        await this.mountClient.connect();
        this.mountCoordinatesTopocentric = this.mountClient.isCoordinateModeCompatible();
        const state: MountState = await this.mountClient.refreshState();
        this.applyMountState(state);
        this.startMountPolling();
        this.operationMessage = this.mountCoordinatesTopocentric ?
          'OnStepX 已连接并确认 TOPOCENTRIC(1)；自动运动前请先回零' :
          `OnStepX 已连接，但 :GXEE# 返回 ${this.mountClient.getCoordinateModeResponse() || '空值'}；GOTO/SYNC 已锁定`;
      }
    } catch (error) {
      this.mountConnection = ConnectionState.ERROR;
      this.mountCoordinatesTopocentric = false;
      this.operationMessage = `赤道仪连接失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private async toggleGatewayConnection(): Promise<void> {
    if (this.operationBusy) {
      return;
    }
    if (this.gatewayConnection === ConnectionState.CONNECTED ||
      this.gatewayConnection === ConnectionState.SIMULATED) {
      this.gatewayConnection = ConnectionState.DISCONNECTED;
      this.cameraCapabilities = undefined;
      this.gatewayDetail = '10.42.0.1:8000';
      this.operationMessage = '相机网关已从当前页面断开';
      return;
    }
    this.operationBusy = true;
    this.gatewayConnection = ConnectionState.CONNECTING;
    try {
      const health = await this.gatewayClient.health();
      if (!health.online) {
        throw new Error('网关健康检查未通过');
      }
      const cameraState = await this.gatewayClient.cameraStatus();
      this.cameraCapabilities = await this.gatewayClient.cameraCapabilities();
      this.gatewayConnection = cameraState.connection;
      this.gatewayDetail = `${cameraState.cameraModel} · ${health.serviceVersion}`;
      this.operationMessage = cameraState.connection === ConnectionState.SIMULATED ?
        '网关正在使用模拟相机，真实拍摄保持禁用' : 'EOS R7 网关已连接';
    } catch (error) {
      this.gatewayConnection = ConnectionState.ERROR;
      this.gatewayDetail = '10.42.0.1:8000';
      this.operationMessage = `相机网关连接失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private startMountPolling(): void {
    this.clearMountPolling();
    this.mountPollTimer = setInterval(() => {
      this.pollMountState();
    }, 2000);
  }

  private clearMountPolling(): void {
    if (this.mountPollTimer >= 0) {
      clearInterval(this.mountPollTimer);
      this.mountPollTimer = -1;
    }
  }

  private async pollMountState(): Promise<void> {
    if (this.mountConnection !== ConnectionState.CONNECTED) {
      return;
    }
    try {
      this.applyMountState(await this.mountClient.refreshState());
    } catch (error) {
      this.operationMessage = `赤道仪状态轮询失败：${error}`;
    }
  }

  private applyMountState(state: MountState): void {
    this.mountConnection = state.connection;
    this.mountRaHours = state.rightAscensionHours;
    this.mountDecDegrees = state.declinationDegrees;
    this.mountSlewing = state.slewing;
    // :GU# 的 H 只表示“当前正在机械零位”。一旦可靠见到 H，本次连接周期内保留回零证明。
    if (state.homed) {
      this.mountHomed = true;
    }
    this.tracking = state.trackingMode !== TrackingMode.STOPPED &&
      state.trackingMode !== TrackingMode.UNKNOWN;
  }

  private async homeMount(): Promise<void> {
    if (this.operationBusy) return;
    this.operationBusy = true;
    this.mountHomed = false;
    try {
      await this.mountClient.home();
      this.operationMessage = '两轴正在寻找常闭原点开关；完成后状态将自动更新';
    } catch (error) {
      this.operationMessage = `回零失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private async syncObserverToMount(): Promise<void> {
    if (this.operationBusy || this.observer === undefined) return;
    this.operationBusy = true;
    try {
      const current: ObserverState = {
        latitudeDegrees: this.observer.latitudeDegrees,
        longitudeDegrees: this.observer.longitudeDegrees,
        elevationMeters: this.observer.elevationMeters,
        timestampMs: Date.now()
      };
      const utcFromLocalOffsetHours: number = new Date().getTimezoneOffset() / 60.0;
      await this.mountClient.setObserver(current, utcFromLocalOffsetHours);
      this.locationSynced = true;
      this.operationMessage = '系统定位、本机日期和时间已同步到 OnStepX';
    } catch (error) {
      this.locationSynced = false;
      this.operationMessage = `位置时间同步失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private async toggleTracking(): Promise<void> {
    if (this.operationBusy) return;
    this.operationBusy = true;
    try {
      if (this.tracking) {
        await this.mountClient.stopTracking();
        this.operationMessage = '恒星时跟踪已停止';
      } else {
        await this.mountClient.startTracking(TrackingMode.SIDEREAL);
        this.operationMessage = '恒星时跟踪已启动';
      }
      await this.pollMountState();
    } catch (error) {
      this.operationMessage = `跟踪控制失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private async parkMount(): Promise<void> {
    if (this.operationBusy) return;
    this.operationBusy = true;
    try {
      await this.mountClient.park();
      this.tracking = false;
      this.operationMessage = '赤道仪正在停放，请观察机械运动和物理限位';
    } catch (error) {
      this.operationMessage = `停放失败：${error}`;
    } finally {
      this.operationBusy = false;
    }
  }

  private buildCapturePlan(): CapturePlan {
    const mode: CaptureMode = this.captureMode === 2 ? CaptureMode.TIMELAPSE :
      (this.captureMode === 1 ? CaptureMode.SMART_LONG_EXPOSURE : CaptureMode.OBSERVE_ONLY);
    const warnings: string[] = [];
    if (!this.selectedTarget().recommendedFor18mm) {
      warnings.push('18mm 下目标不会成为清晰主体，仅适合作为环境星野的一部分。');
    }
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal !== undefined && horizontal.altitudeDegrees < 20.0) {
      warnings.push('目标高度低于 20°，城市光污染和大气消光会明显增加。');
    }
    return {
      id: `plan-${Date.now()}-${this.selectedTargetId}`,
      mode: mode,
      targetId: this.selectedTargetId,
      targetName: this.selectedTarget().nameZh,
      exposureSeconds: mode === CaptureMode.OBSERVE_ONLY ? 0 : this.exposureSeconds,
      frameCount: mode === CaptureMode.OBSERVE_ONLY ? 0 : this.frameCount,
      intervalSeconds: mode === CaptureMode.OBSERVE_ONLY ? 0 : this.intervalSeconds,
      iso: mode === CaptureMode.OBSERVE_ONLY ? 0 : this.iso,
      aperture: 4.0,
      imageFormat: this.cameraCapabilities !== undefined && !this.cameraCapabilities.rawSupported ?
        ImageFormat.JPEG : ImageFormat.RAW_JPEG,
      outputFps: 25,
      enablePlateSolve: mode === CaptureMode.SMART_LONG_EXPOSURE,
      enableDriftCorrection: mode === CaptureMode.SMART_LONG_EXPOSURE,
      enableLocalStack: mode === CaptureMode.SMART_LONG_EXPOSURE,
      enableCloudEnhancement: mode === CaptureMode.SMART_LONG_EXPOSURE,
      recommendationReason: '城市环境采用短子曝光；18mm 广角优先记录大尺度星野。',
      warnings: warnings
    };
  }

  private async startCaptureTask(): Promise<void> {
    if (!this.canStartCapture()) return;
    const target: CelestialObject = this.selectedTarget();
    if (target.id === 'solar-sun' || this.observer === undefined) return;
    // GOTO 之前冻结目标和相机参数；坐标必须在地点时间同步完成后按同一真实时刻重新计算。
    const capturePlan: CapturePlan = this.buildCapturePlan();
    const targetDesignation: string = target.designation;
    const runGeneration: number = ++this.captureRunGeneration;
    this.operationBusy = true;
    this.emergencyMessage = '';
    try {
      this.setCapturePanelVisible(false);
      const motionTimeMs: number = Date.now();
      const currentObserver: ObserverState = {
        latitudeDegrees: this.observer.latitudeDegrees,
        longitudeDegrees: this.observer.longitudeDegrees,
        elevationMeters: this.observer.elevationMeters,
        timestampMs: motionTimeMs
      };
      const geometricHorizontal: HorizontalCoordinate | undefined = EphemerisService.horizontalCoordinate(
        target, currentObserver, motionTimeMs, RefractionMode.NONE);
      if (geometricHorizontal === undefined || geometricHorizontal.altitudeDegrees < 10.0) {
        throw new Error('目标无折射几何高度低于 10°，禁止自动运动');
      }
      const utcFromLocalOffsetHours: number = new Date().getTimezoneOffset() / 60.0;
      await this.mountClient.setObserver(currentObserver, utcFromLocalOffsetHours);
      this.locationSynced = true;
      const mountCoordinate: MountTargetCoordinate | undefined = EphemerisService.topocentricCoordinate(
        target, currentObserver, motionTimeMs);
      const coordinate: EquatorialCoordinate | undefined = EphemerisService.skyCoordinate(target, motionTimeMs);
      if (mountCoordinate === undefined || coordinate === undefined) {
        throw new Error('无法生成带坐标帧的目标方向');
      }
      this.taskStage = `正在 GOTO ${targetDesignation}`;
      this.operationMessage = this.taskStage;
      await this.mountClient.gotoRaDec(mountCoordinate);
      this.throwIfCaptureRunCancelled(runGeneration);
      await this.waitForMountMotion(runGeneration);
      this.throwIfCaptureRunCancelled(runGeneration);
      await this.mountClient.startTracking(TrackingMode.SIDEREAL);
      this.throwIfCaptureRunCancelled(runGeneration);
      this.tracking = true;

      if (capturePlan.mode === CaptureMode.OBSERVE_ONLY) {
        this.changeActiveSection(1);
        this.taskStage = '仅观测模式未触发相机快门';
        this.operationMessage = `${capturePlan.targetName} 已到位，恒星时跟踪已启动`;
        return;
      }

      this.changeActiveSection(2);
      this.taskStatus = TaskStatus.RUNNING;
      this.taskProgress = 1;
      this.completedFrames = 0;
      this.plateSolveCount = 0;
      this.correctionCount = 0;
      this.stackFileUrl = '';
      this.timelapseFileUrl = '';
      this.aiFileUrl = '';
      this.aiModelVersion = '';
      this.workflowWarningText = '';
      const result: CaptureWorkflowResult = await this.captureWorkflow.run(
        capturePlan, coordinate, (progress: CaptureWorkflowProgress) => {
          if (runGeneration !== this.captureRunGeneration) {
            return;
          }
          this.taskProgress = progress.progressPercent;
          this.completedFrames = progress.completedFrames;
          this.taskStage = progress.stage;
          this.activeTaskId = progress.activeTaskId;
        });
      this.plateSolveCount = result.plateSolveCount;
      this.correctionCount = result.correctionCount;
      this.stackFileUrl = result.stackFile === undefined ? '' : result.stackFile.downloadUrl;
      this.timelapseFileUrl = result.timelapseFile === undefined ? '' : result.timelapseFile.downloadUrl;
      const warnings: string[] = result.warnings.slice();
      if (capturePlan.enableCloudEnhancement && this.stackFileUrl.length > 0) {
        if (this.aiClient.isConfigured()) {
          try {
            const enhancement: EnhancementTask = await this.enhanceStack(this.stackFileUrl, runGeneration);
            this.aiFileUrl = enhancement.resultFileUrl;
            this.aiModelVersion = enhancement.modelVersion;
          } catch (error) {
            warnings.push(`云增强跳过，本地堆栈仍可用：${error}`);
          }
        } else {
          this.aiStatus = '未配置 · 已保留本地结果';
        }
      }
      this.throwIfCaptureRunCancelled(runGeneration);
      this.taskStatus = TaskStatus.SUCCEEDED;
      this.taskProgress = 100;
      this.workflowWarningText = warnings.join('；');
      this.taskStage = warnings.length === 0 ? '拍摄、本地处理与可选增强流程完成' : '拍摄完成，部分后处理已降级';
      this.operationMessage = this.taskStage;
    } catch (error) {
      const cancelled: boolean = runGeneration !== this.captureRunGeneration ||
        this.taskStatus === TaskStatus.CANCELLED;
      if (cancelled) {
        this.taskStatus = TaskStatus.CANCELLED;
      } else {
        this.taskStatus = TaskStatus.FAILED;
      }
      this.taskStage = `${cancelled ? '任务已取消' : '任务失败'}：${error}`;
      this.operationMessage = this.taskStage;
    } finally {
      this.operationBusy = false;
    }
  }

  private async waitForMountMotion(runGeneration: number): Promise<void> {
    for (let attempt: number = 0; attempt < 75; attempt++) {
      this.throwIfCaptureRunCancelled(runGeneration);
      const state: MountState = await this.mountClient.refreshState();
      this.throwIfCaptureRunCancelled(runGeneration);
      this.applyMountState(state);
      if (!state.slewing) {
        return;
      }
      await this.delay(1000);
    }
    throw new Error('GOTO 超过 75 秒仍未完成，已禁止触发快门');
  }

  private throwIfCaptureRunCancelled(runGeneration: number): void {
    if (runGeneration !== this.captureRunGeneration) {
      throw new Error('拍摄流程已由用户取消或急停');
    }
  }

  private applyAiConfiguration(): void {
    const endpoint: string = this.aiEndpoint.trim();
    if (this.operationBusy || this.taskStatus === TaskStatus.RUNNING) {
      this.aiStatus = '任务进行中，暂不能修改';
      return;
    }
    if (!endpoint.startsWith('https://')) {
      // 云端令牌和图像都属于敏感数据；比赛主链路不允许降级到明文 HTTP。
      this.aiClient.clearEndpoint();
      this.aiStatus = '仅允许 HTTPS 地址';
      return;
    }
    this.aiClient.setEndpoint({
      baseUrl: endpoint,
      accessToken: this.aiToken.trim(),
      requestTimeoutMs: 120000
    });
    this.aiStatus = '已配置 · 等待堆栈';
  }

  private async enhanceStack(sourceUrl: string, runGeneration: number): Promise<EnhancementTask> {
    this.throwIfCaptureRunCancelled(runGeneration);
    this.aiStatus = '正在上传';
    this.taskStage = '正在把本地堆栈提交到受约束增强服务';
    this.taskProgress = 94;
    let task: EnhancementTask = await this.aiClient.create(sourceUrl, 0.65);
    for (let attempt: number = 0; attempt < 900; attempt++) {
      this.throwIfCaptureRunCancelled(runGeneration);
      if (task.status === TaskStatus.SUCCEEDED) {
        if (task.resultFileUrl.length === 0) {
          throw new Error('云端任务成功但没有返回结果文件');
        }
        this.aiStatus = '增强完成';
        return task;
      }
      if (task.status === TaskStatus.FAILED || task.status === TaskStatus.CANCELLED) {
        throw new Error(task.errorMessage.length > 0 ? task.errorMessage : '云端增强任务未成功');
      }
      this.aiStatus = task.status === TaskStatus.PENDING ? '云端排队中' : '云端处理中';
      await this.delay(1000);
      this.throwIfCaptureRunCancelled(runGeneration);
      task = await this.aiClient.get(task.id);
    }
    throw new Error('云端增强超过 15 分钟仍未完成');
  }

  private delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, milliseconds);
    });
  }

  private startTaskPolling(): void {
    this.clearTaskPolling();
    this.taskPollTimer = setInterval(() => {
      this.pollActiveTask();
    }, 1000);
  }

  private clearTaskPolling(): void {
    if (this.taskPollTimer >= 0) {
      clearInterval(this.taskPollTimer);
      this.taskPollTimer = -1;
    }
  }

  private async pollActiveTask(): Promise<void> {
    if (this.activeTaskId.length === 0) return;
    try {
      const task: GatewayTask = await this.gatewayClient.getTask(this.activeTaskId);
      this.taskStage = task.errorMessage.length > 0 ? task.errorMessage : task.message;
    } catch (error) {
      this.taskStage = `任务状态读取失败：${error}`;
    }
  }

  private applyCaptureTask(task: CaptureTask): void {
    this.taskStatus = task.status;
    this.taskProgress = task.progressPercent;
    this.completedFrames = task.completedFrames;
    this.taskStage = task.errorMessage.length > 0 ? task.errorMessage : task.currentStage;
  }

  private async cancelActiveTask(): Promise<void> {
    if (this.taskStatus !== TaskStatus.RUNNING) return;
    this.captureRunGeneration++;
    this.taskStatus = TaskStatus.CANCELLED;
    try {
      await this.captureWorkflow.cancel();
      this.clearTaskPolling();
      this.taskStage = '工作流已停止提交后续快门，当前网关任务正在取消';
      this.operationMessage = this.taskStage;
    } catch (error) {
      this.operationMessage = `取消任务失败：${error}`;
    }
  }

  private async triggerEmergencyStop(): Promise<void> {
    // 先同步废止当前拍摄代次并触发两条链路，再分别等待结果；任一链路失败都不能阻止另一条急停。
    this.captureRunGeneration++;
    this.emergencyMessage = '正在发送软件急停；物理急停仍需人工确认';
    this.tracking = false;
    const captureWasRunning: boolean = this.taskStatus === TaskStatus.RUNNING;
    if (captureWasRunning) {
      this.taskStatus = TaskStatus.CANCELLED;
      this.clearTaskPolling();
    }
    const workflowStop: Promise<void> = this.captureWorkflow.cancel();
    const mountStop: Promise<void> = this.mountClient.abort();
    const errors: string[] = [];
    try {
      await mountStop;
    } catch (error) {
      errors.push(`赤道仪：${error}`);
    }
    try {
      await workflowStop;
    } catch (error) {
      errors.push(`相机网关：${error}`);
    }
    if (errors.length === 0) {
      this.emergencyMessage = '软件急停已发送；请确认独立物理急停和电机状态';
    } else {
      this.emergencyMessage = `软件急停未获完整确认：${errors.join('；')}；立即使用物理急停`;
    }
  }

  private formatRa(raHours: number): string {
    const totalSeconds: number = Math.round(AstronomyService.normalizeHours(raHours) * 3600.0);
    const hours: number = Math.floor(totalSeconds / 3600) % 24;
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    return `${this.pad2(hours)}h ${this.pad2(minutes)}m ${this.pad2(seconds)}s`;
  }

  private formatDec(decDegrees: number): string {
    const sign: string = decDegrees >= 0 ? '+' : '-';
    const absolute: number = Math.abs(decDegrees);
    const degrees: number = Math.floor(absolute);
    const minutes: number = Math.floor((absolute - degrees) * 60.0);
    const seconds: number = Math.round((((absolute - degrees) * 60.0) - minutes) * 60.0);
    return `${sign}${degrees.toString()}° ${this.pad2(minutes)}′ ${this.pad2(seconds)}″`;
  }

  private taskStatusText(): string {
    if (this.taskStatus === TaskStatus.RUNNING) return '运行中';
    if (this.taskStatus === TaskStatus.SUCCEEDED) return '已完成';
    if (this.taskStatus === TaskStatus.FAILED) return '失败';
    if (this.taskStatus === TaskStatus.CANCELLED) return '已取消';
    return '等待创建';
  }

  private captureModeText(): string {
    if (this.captureMode === 2) return '延时摄影';
    if (this.captureMode === 1) return '智能长曝光';
    return '仅观测';
  }

  private taskStatusColor(): ResourceColor {
    if (this.taskStatus === TaskStatus.RUNNING) return $r('app.color.app_brand');
    if (this.taskStatus === TaskStatus.SUCCEEDED) return $r('app.color.app_success');
    if (this.taskStatus === TaskStatus.FAILED || this.taskStatus === TaskStatus.CANCELLED) {
      return $r('app.color.app_error');
    }
    return $r('app.color.app_text_secondary');
  }
}

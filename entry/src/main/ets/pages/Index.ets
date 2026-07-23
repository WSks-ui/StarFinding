import { common } from '@kit.AbilityKit';
import { FrameCallback } from '@kit.ArkUI';
import { ArSkyDome } from '../components/ArSkyDome';
import { DeviceCameraPreview } from '../components/DeviceCameraPreview';
import { DeviceWorkspace } from '../components/DeviceWorkspace';
import lazy { HuaweiArCameraView } from '../components/HuaweiArCameraView';
import { NormalSkyControls } from '../components/NormalSkyControls';
import { NormalSkyMap } from '../components/NormalSkyMap';
import { NormalSkyOrientationOverlay } from '../components/NormalSkyOrientationOverlay';
import { NormalSkyTimeControls } from '../components/NormalSkyTimeControls';
import { PlanningDrawer } from '../components/PlanningDrawer';
import { PostWorkspace } from '../components/PostWorkspace';
import {
  SkySurveyBackdropController,
  SkySurveyMeshBackdrop
} from '../components/SkySurveyMeshBackdrop';
import { SkyWorkspace } from '../components/SkyWorkspace';
import { TaskWorkspace } from '../components/TaskWorkspace';
import { WorkspaceNavigationDock } from '../components/WorkspaceNavigationDock';
import { WorkspaceTransitionHost } from '../components/WorkspaceTransitionHost';
import { CelestialCatalog } from '../data';
import {
  ArCalibration,
  CameraCapabilities,
  CameraPreflightResult,
  CameraState,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  ConnectionState,
  CaptureMode,
  CapturePlan,
  CaptureProduct,
  DevicePose,
  DevicePairingPreview,
  DevicePairingScanResult,
  DevicePairingScanState,
  DevicePairingValidationResult,
  DigitalTwinListener,
  DigitalTwinPhase,
  DigitalTwinSnapshot,
  EnhancementTask,
  EquatorialCoordinate,
  GestureFrame,
  GatewayHealth,
  HandGesture,
  HorizontalCoordinate,
  HarmonyFeatureSnapshot,
  ImageFormat,
  LiveObservationState,
  GatewaySubtaskKind,
  GatewayEndpointConfig,
  MountState,
  MountTargetCoordinate,
  NormalSkyScene,
  NormalSkyPlaybackSpeed,
  NormalSkyTimeMode,
  NormalSkyTimeState,
  NormalSkyViewState,
  NormalSkyViewport,
  ObservationNightPeriod,
  ObservationNightSelection,
  ObservationShareResult,
  ObservationRunMode,
  ObservationPlanningConstraints,
  ObservationPlanningResult,
  ObserverState,
  OutingRecommendation,
  PlanningPageState,
  PlanningSnapshot,
  PlanningTargetSummary,
  ProjectedSkyObject,
  RefractionMode,
  ReplayAssetSource,
  SkyLayerVisibility,
  SkyGuideInsets,
  SkyMapOrientation,
  SkyMapSize,
  SolarSystemAppearance,
  SessionKind,
  SessionStatus,
  TaskSession,
  TaskSessionStoreSnapshot,
  TaskTargetSnapshot,
  TrackingMode,
  TaskStatus,
  VisibilityStatus,
  WeatherDataStatus,
  WeatherForecast,
  WorkflowCheckpoint,
  WorkflowStage,
  WorkflowStepState
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
  CaptureWorkflowCancelledError,
  CaptureWorkflowProgress,
  CaptureWorkflowReconciliation,
  CaptureWorkflowResumeState,
  CaptureWorkflowResult,
  DevicePoseService,
  DeviceConnectionSettings,
  DeviceConnectionSettingsStore,
  DevicePairingScanner,
  DevicePairingService,
  DigitalTwinReplayService,
  EphemerisService,
  GatewayFile,
  GestureInterpreter,
  HarmonyFeatureCapabilityService,
  HandFrameSourceState,
  HandFrameSourceStatus,
  HandInferenceBackend,
  HandLandmarkAnalyzer,
  HandLandmarkAnalyzerState,
  HandLandmarkAnalyzerStatus,
  HandLandmarkAnalysisResult,
  MindSporeLiteHandLandmarkAnalyzer,
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
  ObserverLocationSequence,
  ObserverLocationSource,
  ObserverLocationService,
  OnStepLX200Client,
  ObservationExecutionPolicy,
  ObservationShareService,
  ObservationRunModePolicy,
  ObservationPlanningService,
  PlanningPeriodService,
  PlanningSnapshotService,
  RaspberryPiClient,
  LiveObservationService,
  SimulationEntryDecision,
  SimulationEntryState,
  SkyBackdropMode,
  SkySurveyBackdropStatus,
  TaskSessionStore,
  TaskSessionPresentationService,
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
const MAX_PLANNED_TARGETS: number = 8;

/**
 * EntryAbility 在加载页面前写入共享上下文；只有该上下文存在时才创建真实离线模型。
 * 异常启动路径必须诚实降级为不可用分析器，不能生成占位关键点冒充识别结果。
 */
function createHandLandmarkAnalyzer(): HandLandmarkAnalyzer {
  const context: common.UIAbilityContext | undefined =
    AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
  if (context === undefined) {
    return new UnavailableHandLandmarkAnalyzer('应用上下文未就绪，无法加载离线手势模型');
  }
  return new MindSporeLiteHandLandmarkAnalyzer(context);
}

interface PreparedSessionTarget {
  target: CelestialObject;
  coordinate: EquatorialCoordinate;
}

function emptyNormalSkyScene(): NormalSkyScene {
  return {
    viewportSnapshot: NormalSkyProjectionService.defaultViewport(),
    staticObjects: [],
    dynamicObjects: [],
    objects: [],
    constellationLines: [],
    gridLines: [],
    eclipticLines: [],
    galacticPlaneLines: [],
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
    staticRevision: 0,
    dynamicRevision: 0,
    generatedAtMs: 0
  };
}

/*
 * 完整目录场景在交互期间最多约 30fps。摄影底图拥有独立的显示帧快照，可继续按 VSync
 * 跟手；恒星筛选、星座线、标签和地平遮罩不再抢占每一个 60/120Hz 显示帧。
 */
const NORMAL_SCENE_MIN_FRAME_INTERVAL_NS: number = 33333333.0;

/**
 * 普通星图交互更新跟随 ArkUI 下一显示帧执行，避免固定 16ms 定时器等待时间与场景构建耗时相加。
 * 回调实例由页面长期复用，不在高频手势事件中分配临时对象。
 */
class NormalSceneFrameCallback extends FrameCallback {
  private readonly action: (frameTimeInNano: number) => void;

  constructor(action: (frameTimeInNano: number) => void) {
    super();
    this.action = action;
  }

  onFrame(frameTimeInNano: number): void {
    this.action(frameTimeInNano);
  }

  onIdle(_timeLeftInNano: number): void {
  }
}

@Entry
@Component
struct Index {
  @State private activeSection: number = 0;
  @State private workspaceDirection: number = 1;
  @State private observationRunMode: ObservationRunMode = ObservationRunMode.REAL;
  @State private digitalTwinSnapshot: DigitalTwinSnapshot | undefined = undefined;
  @State private digitalTwinPlaying: boolean = false;
  @State private digitalTwinPhaseText: string = '';
  @State private digitalTwinSourceText: string = '';
  @State private skyMode: number = 0;
  @State private selectedTargetId: string = 'star-vega';
  @State private targetSearch: string = '';
  @State private gestureEnabled: boolean = false;
  @State private gestureStatus: string = '手势模型尚未预热';
  @State private gestureModelLoading: boolean = false;
  @State private gestureModelReady: boolean = false;
  @State private gestureModelRunning: boolean = false;
  @State private gestureModelError: string = '';
  @State private gestureCameraActive: boolean = false;
  @State private gesturePerformanceText: string = '';
  private normalViewState: NormalSkyViewState = NormalSkyViewStateService.defaultState();
  /**
   * Canvas 与控件只读取该快照；所有交互必须通过 normalViewState 更新四元数长期姿态。
   * 该值不能声明为顶层 @State：手指移动事件可能达到 120 Hz，若每次都触发 Index 整页响应，
   * 会绕过下方 16 ms 场景节流并显著挤占 Canvas 的主线程帧预算。normalScene 更新时会让
   * 普通星图及其控件在同一渲染帧读取最新快照。
   */
  private normalViewport: NormalSkyViewport = NormalSkyViewStateService.snapshot(
    NormalSkyViewStateService.defaultState());
  @State private normalScene: NormalSkyScene = emptyNormalSkyScene();
  @State private normalLayers: SkyLayerVisibility = DEFAULT_SKY_LAYERS;
  @State private normalBackdropMode: SkyBackdropMode = SkyBackdropMode.NAVIGATION;
  /**
   * 全天摄影纹理由独立 Drawing Canvas 组件持有，页面只保留真实绘制状态。
   * READY 表示网格已经成功提交，NormalSkyMap 此时才隐藏重复星点并保持背景透明。
   */
  @State private skySurveyBackdropStatus: SkySurveyBackdropStatus =
    SkySurveyBackdropStatus.DISABLED;
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
  @State private gatewayServiceConnection: ConnectionState = ConnectionState.DISCONNECTED;
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
  @State private activeTaskSession: TaskSession | undefined = undefined;
  @State private taskHistory: TaskSession[] = [];
  @State private taskStoreReady: boolean = false;
  @State private taskStoreWarning: string = '';
  @State private taskStopRequested: boolean = false;
  @State private cameraPreflightResult: CameraPreflightResult | undefined = undefined;
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
  @State private mountUpdatedAtMs: number = 0;
  @State private gatewayUpdatedAtMs: number = 0;
  @State private mountDetail: string = '10.42.0.20:9999';
  @State private gatewayDetail: string = '10.42.0.1:8000';
  @State private connectionSettingsOpen: boolean = false;
  @State private mountHostInput: string = '10.42.0.20';
  @State private mountPortInput: string = '9999';
  @State private gatewayHostInput: string = '10.42.0.1';
  @State private gatewayPortInput: string = '8000';
  @State private pairingBusy: boolean = false;
  @State private pairingPreview: DevicePairingPreview | undefined = undefined;
  @State private harmonyFeatureSnapshot: HarmonyFeatureSnapshot =
    HarmonyFeatureCapabilityService.inspect();
  @State private gatewayServiceVersion: string = '';
  @State private deviceOperationMessage: string = '';
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
  @State private plannedTargetIds: string[] = [];
  @State private activePlanningTargetId: string = '';
  @State private plannedTargetSummaries: PlanningTargetSummary[] = [];
  @State private planningResult: ObservationPlanningResult | undefined = undefined;
  @State private activePlanningResult: ObservationPlanningResult | undefined = undefined;
  @State private activePlanningSnapshot: PlanningSnapshot | undefined = undefined;
  @State private planningBusy: boolean = false;
  @State private planningLocationBusy: boolean = false;
  @State private planningLocationProvisional: boolean = false;
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
  private planningGeneration: number = 0;
  private weatherRequestGeneration: number = 0;
  private mountPollTimer: number = -1;
  private gatewayPollTimer: number = -1;
  private taskPollTimer: number = -1;
  private taskSessionStore: TaskSessionStore | undefined = undefined;
  private deviceConnectionSettingsStore: DeviceConnectionSettingsStore | undefined = undefined;
  // 输入框内容可能尚未保存；真正发起连接时只能读取这一份已应用配置，避免误把半输入的地址发到现场。
  private deviceConnectionSettings: DeviceConnectionSettings = DeviceConnectionSettingsStore.defaults();
  private deviceConnectionSettingsLoading: boolean = false;
  private readonly devicePairingScanner: DevicePairingScanner = new DevicePairingScanner();
  private readonly digitalTwinReplayService: DigitalTwinReplayService = new DigitalTwinReplayService();
  private readonly digitalTwinListener: DigitalTwinListener = (snapshot: DigitalTwinSnapshot): void => {
    this.applyDigitalTwinSnapshot(snapshot);
  };
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
  private readonly handAnalyzer: HandLandmarkAnalyzer = createHandLandmarkAnalyzer();
  private readonly handFrameSource: CameraHandFrameSource = new CameraHandFrameSource(
    this.handAnalyzer,
    (result: HandLandmarkAnalysisResult) => { this.applyHandLandmarks(result); },
    (status: HandFrameSourceStatus) => {
      this.applyHandFrameSourceStatus(status);
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
  private normalSceneFramePending: boolean = false;
  private lastNormalSceneFrameTimeNs: number = 0.0;
  private normalViewportGeneration: number = 0;
  private lastBackdropViewportGeneration: number = -1;
  private lastBackdropInteractive: boolean = false;
  private readonly skySurveyBackdropController: SkySurveyBackdropController =
    new SkySurveyBackdropController();
  private readonly normalSceneFrameCallback: NormalSceneFrameCallback =
    new NormalSceneFrameCallback((frameTimeInNano: number): void => {
      this.flushNormalSceneFrame(frameTimeInNano);
    });
  private normalSceneSettleTimer: number = -1;
  private normalSceneInteractive: boolean = false;
  private normalInertiaTimer: number = -1;
  private normalFlyTimer: number = -1;
  private lastPanOffsetX: number = 0.0;
  private lastPanOffsetY: number = 0.0;
  private gestureModelGeneration: number = 0;
  private gestureSessionStartedAtMs: number = 0;
  private lastAcceptedGestureFrameAtMs: number = 0;
  private gestureSourceRunGeneration: number = 0;
  private handTransformActive: boolean = false;
  private lastGestureMetricsAtMs: number = 0;
  private pageVisible: boolean = false;
  aboutToAppear(): void {
    this.pageVisible = true;
    this.digitalTwinReplayService.subscribe(this.digitalTwinListener);
    this.initializeTaskSessions();
    this.initializeDeviceConnectionSettings();
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
    if (this.skyMode === 1) {
      // 只加载离线模型，不挂载前摄组件，因此这里不会触发相机权限请求。
      this.prewarmGestureModel();
    }
    if (this.mountConnection === ConnectionState.CONNECTED) this.startMountPolling();
    if (this.gatewayServiceConnection === ConnectionState.CONNECTED) this.startGatewayPolling();
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.digitalTwinReplayService.pause();
    this.digitalTwinReplayService.unsubscribe(this.digitalTwinListener);
    this.digitalTwinPlaying = false;
    this.gestureModelGeneration++;
    this.gestureCameraActive = false;
    this.gestureModelLoading = false;
    this.gestureModelReady = false;
    this.gestureModelRunning = false;
    this.invalidateGestureSession();
    this.poseService.stop();
    this.clearMountPolling();
    this.clearGatewayPolling();
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

      if (this.simulationActive()) {
        this.DigitalTwinWatermark()
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
  private DigitalTwinWatermark() {
    Row({ space: 7 }) {
      Circle().width(7).height(7).fill($r('app.color.app_brand'))
      Text($r('app.string.digital_twin_watermark'))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_on_brand'))
      Text(this.digitalTwinSourceText)
        .fontSize(9)
        .fontColor($r('app.color.app_on_brand'))
        .opacity(0.82)
    }
    .height(34)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.app_brand'))
    .borderRadius(17)
    .position({ x: Math.max(8, this.contentViewportWidth - 236), y: 8 })
    .zIndex(400)
  }

  @Builder
  private ActiveWorkspaceContent() {
    this.Header()
    if (this.activeSection === 1) {
      DeviceWorkspace({
        compact: this.contentViewportWidth < 900,
        pageMargin: this.workspacePageMargin(),
        runMode: this.observationRunMode,
        digitalTwinPlaying: this.digitalTwinPlaying,
        digitalTwinPhaseText: this.digitalTwinPhaseText,
        digitalTwinSourceText: this.digitalTwinSourceText,
        mountConnection: this.mountConnection,
        gatewayServiceConnection: this.gatewayServiceConnection,
        cameraConnection: this.gatewayConnection,
        mountDetail: this.mountDetail,
        gatewayDetail: this.gatewayDetail,
        connectionSettingsOpen: this.connectionSettingsOpen,
        connectionSettingsLocked: this.connectionSettingsLocked(),
        mountHostInput: this.mountHostInput,
        mountPortInput: this.mountPortInput,
        gatewayHostInput: this.gatewayHostInput,
        gatewayPortInput: this.gatewayPortInput,
        scanKitAvailable: this.harmonyFeatureSnapshot.scanKit.available,
        pairingBusy: this.pairingBusy,
        pairingPreview: this.pairingPreview,
        harmonyFeatures: this.harmonyFeatureSnapshot,
        mountHomed: this.mountHomed,
        coordinateModeCompatible: this.mountCoordinatesTopocentric,
        tracking: this.tracking,
        locationSynced: this.locationSynced,
        observerAvailable: this.observer !== undefined,
        simulatedTimeActive: this.simulatedDeviceTimeBlocked(),
        locationText: this.locationText,
        mountRaHours: this.mountRaHours,
        mountDecDegrees: this.mountDecDegrees,
        mountSlewing: this.mountSlewing,
        mountUpdatedAtMs: this.mountUpdatedAtMs,
        gatewayUpdatedAtMs: this.gatewayUpdatedAtMs,
        deviceMessage: this.deviceOperationMessage,
        emergencyMessage: this.emergencyMessage,
        onToggleMount: (): void => { this.toggleMountConnection(); },
        onToggleGateway: (): void => { this.toggleGatewayConnection(); },
        onEnterSimulation: (): void => { this.enterDigitalTwinMode(); },
        onExitSimulation: (): void => { this.exitDigitalTwinMode(); },
        onToggleSimulationPlayback: (): void => { this.toggleDigitalTwinPlayback(); },
        onRestartSimulation: (): void => { this.restartDigitalTwinPlayback(); },
        onToggleConnectionSettings: (): void => { this.toggleConnectionSettings(); },
        onMountHostChange: (value: string): void => { this.mountHostInput = value; },
        onMountPortChange: (value: string): void => { this.mountPortInput = value; },
        onGatewayHostChange: (value: string): void => { this.gatewayHostInput = value; },
        onGatewayPortChange: (value: string): void => { this.gatewayPortInput = value; },
        onSaveConnectionSettings: (): void => { this.saveDeviceConnectionSettings(); },
        onRestoreConnectionDefaults: (): void => { this.restoreDeviceConnectionDefaults(); },
        onScanDeviceCode: (): void => { this.scanDevicePairingCode(); },
        onConfirmPairing: (): void => { this.confirmDevicePairing(); },
        onCancelPairing: (): void => { this.cancelDevicePairing(); },
        onRefreshHarmonyFeatures: (): void => {
          this.harmonyFeatureSnapshot = HarmonyFeatureCapabilityService.inspect();
        },
        onHomeMount: (): void => { this.homeMount(); },
        onSyncObserver: (): void => { this.syncObserverToMount(); },
        onToggleTracking: (): void => { this.toggleTracking(); },
        onParkMount: (): void => { this.parkMount(); }
      })
        .transition(MotionTokens.page(this.workspaceDirection))
    } else if (this.activeSection === 2) {
      TaskWorkspace({
        compact: TaskSessionPresentationService.resolveLayout(this.contentViewportWidth).compact,
        pageMargin: TaskSessionPresentationService.resolveLayout(this.contentViewportWidth).pageMargin,
        runMode: this.observationRunMode,
        replayManifest: this.digitalTwinSnapshot === undefined ? undefined :
          this.digitalTwinSnapshot.assetManifest,
        digitalTwinPlaying: this.digitalTwinPlaying,
        activeSession: this.displayedTaskSession(),
        history: this.taskHistory,
        storeReady: this.simulationActive() ? true : this.taskStoreReady,
        storeWarning: this.simulationActive() ? '' : this.taskStoreWarning,
        stopRequested: this.taskStopRequested,
        mountConnection: this.mountConnection,
        cameraConnection: this.gatewayConnection,
        mountHomed: this.mountHomed,
        coordinateModeCompatible: this.mountCoordinatesTopocentric,
        locationSynced: this.locationSynced,
        preflight: this.cameraPreflightResult,
        liveObservation: this.currentLiveObservation(),
        onGoToSky: (): void => { this.navigateToImmersiveSky(); },
        onRefresh: (): void => { this.refreshActiveTaskSession(); },
        onStop: (): void => { this.cancelActiveTask(); },
        onContinue: (): void => { this.continueActiveTaskSession(); },
        onArchive: (): void => { this.archiveInterruptedTaskSession(); },
        onEndObservation: (): void => { this.endObservationSession(); },
        onOpenProducts: (): void => { this.navigateToSection(3); },
        onToggleSimulationPlayback: (): void => { this.toggleDigitalTwinPlayback(); },
        onRestartSimulation: (): void => { this.restartDigitalTwinPlayback(); },
        onExitSimulation: (): void => { this.exitDigitalTwinMode(); },
        onShareReport: (): void => { this.shareDisplayedTaskReport(); }
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
      gestureCameraActive: this.gestureCameraActive,
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
      onImmersive: (): void => { this.navigateToImmersiveSky(); },
      onChromeVisibleChange: (visible: boolean): void => {
        this.getUIContext().animateTo(MotionTokens.standard(), () => { this.skyChromeVisible = visible; });
        this.updateGestureCameraActivity();
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
        Stack() {
          SkySurveyMeshBackdrop({
            controller: this.skySurveyBackdropController,
            widthPixels: this.skyViewportWidth,
            heightPixels: this.skyViewportHeight,
            backdropActive: this.normalBackdropMode === SkyBackdropMode.VISIBLE_PHOTOGRAPHY,
            onStatusChange: (status: SkySurveyBackdropStatus, message: string): void => {
              this.applySkySurveyBackdropStatus(status, message);
            }
          })
          NormalSkyMap({
            scene: this.normalScene,
            widthPixels: this.skyViewportWidth,
            heightPixels: this.skyViewportHeight,
            photographyBackdropVisible: this.hasVisibleSkySurveyBackdrop(),
            onObjectSelected: (objectId: string): void => {
              /*
               * 摄影层按显示帧跟手，而目录对象为控制负载最多约 30fps 更新。交互尚未
               * 收敛时两层可能短暂相差一两帧，此时忽略点击比使用旧屏幕坐标误选更安全。
               * 停手后的精确场景重建完成后，正常点击会立即恢复。
               */
              if (this.normalSceneInteractive) {
                return;
              }
              this.selectNormalSkyObject(objectId);
            }
          })
          .width('100%')
          .height('100%')
        }
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
              this.scheduleNormalSceneUpdate(true);
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
                this.scheduleNormalSceneUpdate(true);
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
                this.normalRotationAnchorX(event), this.normalRotationAnchorY(event));
              if (update.changed) {
                this.applyNormalViewState(update.viewState);
                this.scheduleNormalSceneUpdate(true);
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
      backdropMode: this.normalBackdropMode,
      backdropStatus: this.skySurveyBackdropStatus,
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
      onLayerChange: (layer: number, enabled: boolean): void => { this.setNormalLayer(layer, enabled); },
      onBackdropModeChange: (mode: SkyBackdropMode): void => {
        this.setNormalSkyBackdropMode(mode);
      }
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
          if (this.gesturePerformanceText.length > 0) {
            Text(this.gesturePerformanceText).fontSize(9).fontColor('#9BB4C4')
          }
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
            if (this.selectedTarget().precision === CatalogPrecision.DYNAMIC) {
              this.InfoLine('实时外观', this.solarSystemAppearanceText())
              this.InfoLine('当前距离', this.solarSystemDistanceText())
            }
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
                Text(this.gestureCapabilityText())
                  .fontSize(10).fontColor($r('app.color.sky_text_tertiary'))
              }.alignItems(HorizontalAlign.Start)
              Blank()
              if (this.gestureModelLoading) {
                LoadingProgress().width(20).height(20).color($r('app.color.app_brand'))
              }
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
            .onClick(() => { this.addSelectedTargetToPlan(); })
          Button('查看规划')
            .layoutWeight(1).height(48).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_on_brand')).backgroundColor($r('app.color.app_brand')).borderRadius(24)
            .onClick(() => { this.openPlanningForSelectedTarget(); })
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
    PlanningDrawer({
      drawerWidth: this.skyDrawerWidth(),
      drawerHeight: this.skyDrawerHeight(),
      drawerX: this.skyDrawerX(),
      drawerY: this.skyDrawerY(),
      bottomSheet: this.useSkyBottomSheet(),
      pageState: this.planningPageState(),
      period: this.planningPeriod(),
      dayOffset: this.planningDayOffset,
      activeTargetId: this.activePlanningTarget().id,
      activeTargetName: this.activePlanningTarget().nameZh,
      activeDesignation: this.activePlanningTarget().designation,
      activeTargetIncluded: this.plannedTargetIds.includes(this.activePlanningTarget().id),
      targetCount: this.plannedTargetIds.length,
      snapshot: this.activePlanningSnapshot,
      targetSummaries: this.plannedTargetSummaries,
      weatherMessage: this.weatherMessage,
      weatherDetailsText: this.weatherDetailsText(),
      locationText: this.locationText,
      locationSource: this.planningLocationSource,
      locationEditorOpen: this.planningLocationEditorOpen,
      manualLatitudeText: this.manualLatitudeText,
      manualLongitudeText: this.manualLongitudeText,
      busy: this.planningBusy || this.planningLocationBusy,
      onClose: (): void => { this.openSkyPanel(2); },
      onDayChange: (dayOffset: number): void => { this.selectPlanningDay(dayOffset); },
      onToggleLocationEditor: (): void => { this.togglePlanningLocationEditor(); },
      onLatitudeChange: (value: string): void => { this.manualLatitudeText = value; },
      onLongitudeChange: (value: string): void => { this.manualLongitudeText = value; },
      onApplyManualLocation: (): void => { this.applyManualPlanningLocation(); },
      onUseCurrentLocation: (): void => { this.refreshLocation(); },
      onRefreshWeather: (): void => { this.refreshWeatherForecast(); },
      onSharePlan: (): void => { this.shareActivePlanningSnapshot(); },
      onAddActiveTarget: (): void => { this.addActivePlanningTargetToPlan(); },
      onSelectTarget: (targetId: string): void => { this.selectPlanningTarget(targetId); },
      onRemoveTarget: (targetId: string): void => { this.removePlannedTarget(targetId); }
    })
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
      this.updateGestureCameraActivity();
      if (this.skyMode === 0) this.updateProjectedTargets(true);
      if (this.skyMode === 1) {
        this.prewarmGestureModel();
        // 从其他工作区返回时立即恢复精确目录与摄影底图，不能等待下一次触摸或分钟定时器。
        this.updateNormalScene();
      }
    }
  }

  /** 从设备、任务或后期返回星图时直接打开指定抽屉，不能沿用星图内“再次点击关闭”的切换语义。 */
  private navigateToSkyPanel(panel: number): void {
    if (panel === 2) this.ensureActivePlanningTarget();
    this.workspaceDirection = -1;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = panel;
    });
    this.updateGestureCameraActivity();
    if (panel === 2) this.refreshPlanningAndWeather();
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
    this.updateGestureCameraActivity();
    if (this.skyMode === 0) this.updateProjectedTargets(true);
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  private openSkyPanel(panel: number): void {
    if (panel === 2 && this.skyOverlayPanel !== 2) this.ensureActivePlanningTarget();
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = this.skyOverlayPanel === panel ? 0 : panel;
    });
    this.updateGestureCameraActivity();
    if (this.skyOverlayPanel === 2) this.refreshPlanningAndWeather();
    if (this.skyMode === 1) this.scheduleNormalSceneUpdate();
  }

  /** 点选和搜索必须显式打开面板，不能复用再次点击关闭的交互。 */
  private revealSkyPanel(panel: number): void {
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = panel;
    });
    this.updateGestureCameraActivity();
    if (panel === 2) this.refreshPlanningAndWeather();
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
      /*
       * AR 能力检测属于 AR 页面上下文。此前在启动时记录的“设备不支持
       * AR Engine”会一直挂在普通星图上，遮挡天体并让用户误以为普通星图
       * 也不可用。切入普通星图时清理这类一次性提示；普通星图自身的
       * 定位、星表或规划错误仍会在对应操作中重新显示。
       */
      this.operationMessage = '';
    }
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.skyMode = mode;
    });
    if (mode === 0) {
      this.clearNormalMotion();
      this.finishNormalSceneInteraction();
      this.setGestureEnabled(false);
      this.updateProjectedTargets(true);
    } else {
      this.prewarmGestureModel();
      this.updateGestureCameraActivity();
      this.updateNormalScene();
    }
  }

  private setCapturePanelVisible(visible: boolean): void {
    if (visible === this.showCapturePanel) return;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.showCapturePanel = visible;
    });
    this.updateGestureCameraActivity();
  }

  /** 工作区顺序只决定视觉方向；硬件连接、轮询和任务生命周期不进入动画事务。 */
  private changeActiveSection(section: number): void {
    if (section === this.activeSection) return;
    if (this.activeSection === 0 && section !== 0 && this.skyMode === 1) {
      this.clearNormalMotion();
      this.finishNormalSceneInteraction();
    }
    this.workspaceDirection = section > this.activeSection ? 1 : -1;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.activeSection = section;
    });
    this.updateGestureCameraActivity();
  }

  private setGestureEnabled(value: boolean): void {
    if (!value) {
      this.gestureEnabled = false;
      this.updateGestureCameraActivity();
      this.gestureStatus = this.gestureModelReady ? '手势模型已就绪' : this.gestureCapabilityText();
      return;
    }
    // 相机输出或一次推理失败不代表模型文件失效；模型仍就绪时允许用户显式重试。
    if (this.gestureModelReady) this.gestureModelError = '';
    if (this.skyMode !== 1 || !this.gestureModelAvailable()) {
      this.gestureEnabled = false;
      this.updateGestureCameraActivity();
      if (!this.gestureModelLoading) this.prewarmGestureModel();
      this.operationMessage = this.gestureModelLoading ?
        '手势模型正在预热，请稍后再开启' : `手势控制未启动：${this.gestureCapabilityText()}`;
      return;
    }
    this.gestureEnabled = true;
    this.gestureModelError = '';
    this.updateGestureCameraActivity();
  }

  private gestureModelAvailable(): boolean {
    return this.gestureModelReady && !this.gestureModelLoading;
  }

  private gestureCapabilityText(): string {
    if (this.gestureModelLoading) return '正在预热手势模型';
    if (this.gestureModelError.length > 0) return this.gestureModelError;
    if (this.gestureModelReady) return this.gestureStatus;
    return '手势模型尚未就绪';
  }

  private gestureBackendText(status: HandLandmarkAnalyzerStatus): string {
    if (status.inferenceBackend === HandInferenceBackend.NNRT_ACCELERATOR) {
      return status.backendDeviceName.length > 0 ?
        `NNRT Accelerator 已启用 · ${status.backendDeviceName}` : 'NNRT Accelerator 已启用';
    }
    if (status.inferenceBackend === HandInferenceBackend.NNRT_GPU) {
      return status.backendDeviceName.length > 0 ?
        `NNRT GPU 已启用 · ${status.backendDeviceName}` : 'NNRT GPU 已启用';
    }
    if (status.inferenceBackend === HandInferenceBackend.CPU_DIAGNOSTIC) {
      return 'CPU 诊断模式（不建议实时使用）';
    }
    return '当前设备没有可用手势加速';
  }

  /**
   * 模型预热只读取 HAP 内的离线模型并创建推理会话，不创建 CameraKit 会话，
   * 因此进入普通星图不会提前弹出相机权限。用户明确开启手势后才挂载前摄组件。
   */
  private async prewarmGestureModel(): Promise<void> {
    if (this.gestureModelReady || this.gestureModelLoading || !this.pageVisible) return;
    const generation: number = ++this.gestureModelGeneration;
    this.gestureModelLoading = true;
    this.gestureModelError = '';
    this.gestureStatus = '正在预热手势模型';
    try {
      const status: HandLandmarkAnalyzerStatus = await this.handFrameSource.prewarm();
      if (!this.pageVisible || generation !== this.gestureModelGeneration) return;
      const ready: boolean = status.available && status.modelLoaded &&
        (status.state === HandLandmarkAnalyzerState.READY ||
          status.state === HandLandmarkAnalyzerState.ANALYZING);
      this.gestureModelReady = ready;
      if (ready) {
        this.gestureModelError = '';
        this.gestureStatus = this.gestureBackendText(status);
      } else {
        this.gestureModelError = status.message.length > 0 ? status.message : '手势模型初始化失败';
        this.gestureStatus = this.gestureModelError;
        this.gestureEnabled = false;
      }
    } catch (error) {
      if (!this.pageVisible || generation !== this.gestureModelGeneration) return;
      this.gestureModelReady = false;
      this.gestureEnabled = false;
      this.gestureModelError = error instanceof Error && error.message.length > 0 ?
        error.message : '手势模型初始化失败';
      this.gestureStatus = this.gestureModelError;
    } finally {
      if (this.pageVisible && generation === this.gestureModelGeneration) {
        this.gestureModelLoading = false;
        this.updateGestureCameraActivity();
      }
    }
  }

  /**
   * “模型已就绪”和“前摄正在运行”是两件事。抽屉、拍摄面板或其他工作区出现时，
   * 保留用户开关但卸载前摄；恢复时建立新的帧时间边界，旧推理回调不能进入视口。
   */
  private updateGestureCameraActivity(): void {
    const shouldRun: boolean = this.pageVisible && this.gestureEnabled && this.gestureModelAvailable() &&
      this.activeSection === 0 && this.skyMode === 1 && this.skyOverlayPanel === 0 &&
      this.skyChromeVisible && !this.showCapturePanel;
    const activityChanged: boolean = shouldRun !== this.gestureCameraActive;
    if (activityChanged) {
      this.gestureCameraActive = shouldRun;
      this.gestureModelRunning = false;
      this.invalidateGestureSession();
    }
    if (shouldRun) {
      if (activityChanged) {
        this.gestureSessionStartedAtMs = Date.now();
        this.gestureStatus = '正在启动前摄识别';
      }
    } else if (this.gestureEnabled && this.gestureModelReady) {
      if (this.activeSection !== 0 || this.skyMode !== 1) {
        this.gestureStatus = '已暂停：返回普通星图后恢复';
      } else if (this.showCapturePanel) {
        this.gestureStatus = '已暂停：关闭拍摄面板后恢复';
      } else if (this.skyOverlayPanel !== 0) {
        this.gestureStatus = '已暂停：关闭抽屉后恢复';
      } else if (!this.skyChromeVisible) {
        this.gestureStatus = '已暂停：显示界面控件后恢复';
      } else {
        this.gestureStatus = this.gestureBackendText(this.handFrameSource.getStatus().analyzer);
      }
    }
  }

  private invalidateGestureSession(): void {
    this.gestureSessionStartedAtMs = 0;
    this.lastAcceptedGestureFrameAtMs = 0;
    this.gestureSourceRunGeneration = 0;
    this.handTransformActive = false;
    this.gestureInterpreter.reset();
    this.normalSkyGestureController.endHandTransform();
  }

  private applyHandFrameSourceStatus(status: HandFrameSourceStatus): void {
    if (!this.pageVisible) return;
    const analyzerReady: boolean = status.analyzer.available && status.analyzer.modelLoaded &&
      (status.analyzer.state === HandLandmarkAnalyzerState.READY ||
        status.analyzer.state === HandLandmarkAnalyzerState.ANALYZING);
    this.gestureModelReady = analyzerReady;
    this.gestureModelRunning = this.gestureCameraActive && status.state === HandFrameSourceState.RUNNING;
    if (this.gestureCameraActive && (status.state === HandFrameSourceState.PREPARING ||
      status.state === HandFrameSourceState.READY || status.state === HandFrameSourceState.RUNNING)) {
      this.gestureSourceRunGeneration = status.runGeneration;
    }
    const failed: boolean = status.state === HandFrameSourceState.ERROR ||
      status.analyzer.state === HandLandmarkAnalyzerState.ERROR ||
      status.analyzer.state === HandLandmarkAnalyzerState.UNAVAILABLE;
    if (failed) {
      this.gestureModelError = status.message.length > 0 ? status.message : status.analyzer.message;
      this.gestureStatus = this.gestureModelError;
      this.gestureEnabled = false;
      this.gestureCameraActive = false;
      this.invalidateGestureSession();
      return;
    }
    if (analyzerReady) this.gestureModelError = '';
    if (this.gestureCameraActive) {
      this.gestureStatus = status.message;
    } else if (!this.gestureEnabled && analyzerReady) {
      this.gestureStatus = '手势模型已就绪';
    }
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
    const appearance: SolarSystemAppearance | undefined = this.selectedAppearance();
    if (appearance !== undefined) return appearance.magnitude.toFixed(2);
    const magnitude: number | undefined = this.selectedTarget().magnitude;
    return magnitude === undefined ? '--' : magnitude.toFixed(2);
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
    const appearance: SolarSystemAppearance | undefined = this.selectedAppearance();
    if (appearance !== undefined && appearance.angularDiameterArcSeconds > 0.0) {
      if (appearance.angularDiameterArcSeconds >= 60.0) {
        return (appearance.angularDiameterArcSeconds / 60.0).toFixed(2) + '\'';
      }
      return appearance.angularDiameterArcSeconds.toFixed(1) + '"';
    }
    const size: number | undefined = this.selectedTarget().angularSizeDegrees;
    if (size === undefined || size === 0) {
      return '恒星点源';
    }
    return size.toFixed(2) + '°';
  }

  private selectedAppearance(): SolarSystemAppearance | undefined {
    return EphemerisService.appearance(this.selectedTarget(), this.activeSkyTimestampMs());
  }

  private solarSystemAppearanceText(): string {
    const appearance: SolarSystemAppearance | undefined = this.selectedAppearance();
    if (appearance === undefined) return '按当前时刻计算';
    if (appearance.objectId === 'solar-sun') return '完整日面 · 普通 GOTO 永久禁用';
    let result: string = `照明 ${(appearance.illuminatedFraction * 100.0).toFixed(1)}%`;
    if (appearance.objectId === 'solar-moon' && appearance.moonPhaseDegrees !== undefined) {
      result = `${this.moonPhaseLabel(appearance.moonPhaseDegrees)} · ${result}`;
    }
    if (appearance.ringTiltDegrees !== undefined) {
      const sign: string = appearance.ringTiltDegrees >= 0.0 ? '+' : '';
      result += ` · 环倾角 ${sign}${appearance.ringTiltDegrees.toFixed(1)}°`;
    } else if (appearance.objectId === 'solar-moon' || appearance.objectId === 'planet-mercury' ||
      appearance.objectId === 'planet-venus') {
      result += ` · 相位角 ${appearance.phaseAngleDegrees.toFixed(1)}°`;
    }
    return result;
  }

  private solarSystemDistanceText(): string {
    const appearance: SolarSystemAppearance | undefined = this.selectedAppearance();
    if (appearance === undefined) return '--';
    if (appearance.objectId === 'solar-moon') {
      return `${(appearance.distanceAu * 149597870.7).toFixed(0)} km`;
    }
    return `${appearance.distanceAu.toFixed(4)} AU`;
  }

  private moonPhaseLabel(phaseDegrees: number): string {
    const normalized: number = AstronomyService.normalizeDegrees(phaseDegrees);
    if (normalized < 22.5 || normalized >= 337.5) return '朔月';
    if (normalized < 67.5) return '娥眉月';
    if (normalized < 112.5) return '上弦月';
    if (normalized < 157.5) return '盈凸月';
    if (normalized < 202.5) return '满月';
    if (normalized < 247.5) return '亏凸月';
    if (normalized < 292.5) return '下弦月';
    return '残月';
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

  private addSelectedTargetToPlan(): void {
    const target: CelestialObject = this.selectedTarget();
    this.activePlanningTargetId = target.id;
    this.addTargetToPlan(target);
    this.refreshPlanning();
  }

  /** 查看规划只切换规划上下文，不得隐式修改用户的目标清单。 */
  private openPlanningForSelectedTarget(): void {
    const target: CelestialObject = this.selectedTarget();
    this.activePlanningTargetId = target.id;
    this.rememberPlanningTarget(target);
    this.refreshPlanningAndWeather();
    this.workspaceDirection = -1;
    this.getUIContext().animateTo(MotionTokens.spring(), () => {
      this.activeSection = 0;
      this.skyChromeVisible = true;
      this.skyOverlayPanel = 2;
    });
    this.updateGestureCameraActivity();
  }

  private addActivePlanningTargetToPlan(): void {
    const target: CelestialObject = this.activePlanningTarget();
    this.addTargetToPlan(target);
    this.refreshPlanning();
  }

  private addTargetToPlan(target: CelestialObject): void {
    if (this.plannedTargetIds.includes(target.id)) {
      this.operationMessage = `${target.nameZh} 已在观测计划中`;
      return;
    }
    if (this.plannedTargetIds.length >= MAX_PLANNED_TARGETS) {
      this.operationMessage = `观测计划最多保留 ${MAX_PLANNED_TARGETS} 个目标`;
      return;
    }
    this.rememberPlanningTarget(target);
    this.plannedTargetIds = this.plannedTargetIds.concat([target.id]);
    this.operationMessage = `已把 ${target.nameZh} 加入观测计划`;
  }

  private removePlannedTarget(targetId: string): void {
    const removedTarget: CelestialObject | undefined = this.planningTargetById(targetId);
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
    if (this.activePlanningTargetId === targetId) {
      this.activePlanningTargetId = remaining.length > 0 ? remaining[0] : this.selectedTargetId;
    }
    if (removedTarget !== undefined) {
      this.operationMessage = `已从观测计划移除 ${removedTarget.nameZh}`;
    }
    this.refreshPlanning();
  }

  private selectPlanningTarget(targetId: string): void {
    const target: CelestialObject | undefined = this.planningTargetById(targetId);
    if (target === undefined) return;
    this.activePlanningTargetId = targetId;
    this.refreshPlanning();
  }

  private ensureActivePlanningTarget(): void {
    if (this.activePlanningTargetId.length > 0 &&
      this.planningTargetById(this.activePlanningTargetId) !== undefined) return;
    const target: CelestialObject = this.selectedTarget();
    this.activePlanningTargetId = target.id;
    this.rememberPlanningTarget(target);
  }

  private activePlanningTarget(): CelestialObject {
    const target: CelestialObject | undefined = this.planningTargetById(this.activePlanningTargetId);
    return target === undefined ? this.selectedTarget() : target;
  }

  private rememberPlanningTarget(target: CelestialObject): void {
    if (CelestialCatalog.getById(target.id) !== undefined) return;
    for (let index: number = 0; index < this.customPlanningTargets.length; index++) {
      if (this.customPlanningTargets[index].id === target.id) return;
    }
    this.customPlanningTargets.push(target);
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

  private planningStartAtMs(): number {
    return this.planningPeriod().startAtMs;
  }

  private planningPeriod(): ObservationNightPeriod {
    return PlanningPeriodService.resolve(Date.now(), this.planningDayOffset);
  }

  private planningPageState(): PlanningPageState {
    if (this.observer === undefined) return PlanningPageState.NEEDS_LOCATION;
    if (this.planningBusy || this.weatherStatus === WeatherDataStatus.LOADING) {
      return PlanningPageState.WEATHER_LOADING;
    }
    if (this.weatherStatus === WeatherDataStatus.LIVE || this.weatherStatus === WeatherDataStatus.CACHED) {
      return PlanningPageState.READY;
    }
    if (this.weatherStatus === WeatherDataStatus.UNAVAILABLE) return PlanningPageState.WEATHER_UNAVAILABLE;
    return PlanningPageState.ASTRONOMY_ONLY;
  }

  private refreshPlanningAndWeather(): void {
    const period: ObservationNightPeriod = this.planningPeriod();
    this.refreshPlanning(period);
    if (this.observer !== undefined && !this.planningBusy &&
      (this.weatherForecast === undefined ||
        Date.now() - this.weatherForecast.fetchedAtMs > 30 * 60 * 1000)) {
      this.refreshWeatherForecast();
    }
  }

  private selectPlanningDay(dayOffset: number): void {
    if (dayOffset === this.planningDayOffset || dayOffset < 0 || dayOffset > 1) return;
    const period: ObservationNightPeriod = PlanningPeriodService.resolve(Date.now(), dayOffset);
    // 业务日期先直接提交，再使用同一个 period 生成快照；动画不能参与规划数据的时序。
    this.planningDayOffset = dayOffset;
    this.refreshPlanning(period);
  }

  private togglePlanningLocationEditor(): void {
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.planningLocationEditorOpen = !this.planningLocationEditorOpen;
    });
  }

  private refreshPlanning(period?: ObservationNightPeriod): void {
    if (this.observer === undefined) {
      this.planningResult = undefined;
      this.activePlanningResult = undefined;
      this.activePlanningSnapshot = undefined;
      this.refreshPlannedTargetSummaries();
      return;
    }
    const constraints: ObservationPlanningConstraints = ObservationPlanningService.defaultConstraints();
    constraints.horizonHours = 24;
    const resolvedPeriod: ObservationNightPeriod = period === undefined ? this.planningPeriod() : period;
    const startAtMs: number = resolvedPeriod.startAtMs;
    try {
      this.planningResult = ObservationPlanningService.plan(
        this.selectedTarget(), this.observer, startAtMs, this.weatherForecast, constraints);
      const planningTarget: CelestialObject = this.activePlanningTarget();
      this.activePlanningResult = planningTarget.id === this.selectedTargetId ? this.planningResult :
        ObservationPlanningService.plan(
          planningTarget, this.observer, startAtMs, this.weatherForecast, constraints);
      if (this.activePlanningResult.startAtMs !== resolvedPeriod.startAtMs ||
        this.activePlanningResult.endAtMs !== resolvedPeriod.endAtMs) {
        throw new Error('规划结果与当前观测夜不一致');
      }
      this.planningGeneration++;
      this.activePlanningSnapshot = PlanningSnapshotService.create(
        this.planningGeneration,
        resolvedPeriod.selection === ObservationNightSelection.TONIGHT ? 0 : 1,
        resolvedPeriod,
        planningTarget.id,
        this.observer,
        this.planningLocationSource,
        this.planningLocationProvisional,
        this.activePlanningResult);
      this.refreshPlannedTargetSummaries(startAtMs, constraints);
    } catch (error) {
      this.planningResult = undefined;
      this.activePlanningResult = undefined;
      this.activePlanningSnapshot = undefined;
      this.operationMessage = `观测规划失败：${error}`;
    }
  }

  private refreshPlannedTargetSummaries(startAtMs?: number,
    constraints?: ObservationPlanningConstraints): void {
    const summaries: PlanningTargetSummary[] = [];
    for (let index: number = 0; index < this.plannedTargetIds.length; index++) {
      const target: CelestialObject | undefined = this.planningTargetById(this.plannedTargetIds[index]);
      if (target === undefined) continue;
      const summary: PlanningTargetSummary = {
        targetId: target.id,
        targetName: target.nameZh,
        designation: target.designation,
        included: true,
        recommendation: OutingRecommendation.UNAVAILABLE,
        unavailableReason: '设置地点后计算'
      };
      if (this.observer === undefined || startAtMs === undefined || constraints === undefined) {
        summaries.push(summary);
        continue;
      }
      const result: ObservationPlanningResult = ObservationPlanningService.plan(
        target, this.observer, startAtMs, this.weatherForecast, constraints);
      summary.recommendation = result.recommendation;
      summary.unavailableReason = '本夜无可用窗口';
      if (result.bestWindow !== undefined) {
        summary.bestWindowStartAtMs = result.bestWindow.startAtMs;
        summary.bestWindowEndAtMs = result.bestWindow.endAtMs;
        summary.astronomyScore = result.bestWindow.astronomyScore;
        if (result.overallScore !== undefined) summary.overallScore = result.overallScore;
        summary.unavailableReason = '';
      } else if (result.riseTransitSet.status === VisibilityStatus.COORDINATE_UNAVAILABLE) {
        summary.unavailableReason = '目录坐标待补充';
      }
      summaries.push(summary);
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
    this.planningLocationBusy = false;
    this.weatherRequestGeneration++;
    this.planningBusy = false;
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
    this.planningLocationProvisional = false;
    this.weatherForecast = undefined;
    this.weatherStatus = WeatherDataStatus.NOT_REQUESTED;
    this.weatherMessage = '地点已改变 · 天气预报待更新';
    this.operationMessage = '手动观测地点已应用；赤道仪位置仍需单独同步';
    this.updateNormalScene();
    this.updateProjectedTargets(true);
    this.refreshPlanning();
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.planningLocationEditorOpen = false;
    });
    this.refreshWeatherForecast();
  }

  private async refreshWeatherForecast(): Promise<void> {
    if (this.observer === undefined || this.planningBusy) return;
    const requestGeneration: number = ++this.weatherRequestGeneration;
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
      if (requestGeneration !== this.weatherRequestGeneration || this.observer === undefined ||
        Math.abs(this.observer.latitudeDegrees - requestObserver.latitudeDegrees) >
        0.0001 || Math.abs(this.observer.longitudeDegrees - requestObserver.longitudeDegrees) > 0.0001) {
        return;
      }
      this.weatherForecast = forecast;
      this.weatherStatus = WeatherDataStatus.LIVE;
      this.weatherMessage = `预报更新于 ${this.formatClockTime(forecast.fetchedAtMs)}`;
    } catch (error) {
      if (requestGeneration !== this.weatherRequestGeneration) return;
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
        this.weatherMessage = `使用 ${this.weatherAgeText(previous.fetchedAtMs)}前的缓存预报`;
      } else {
        this.weatherForecast = undefined;
        this.weatherStatus = WeatherDataStatus.UNAVAILABLE;
        this.weatherMessage = '天气未获取 · 仅按天文条件规划';
      }
    } finally {
      if (requestGeneration === this.weatherRequestGeneration) {
        this.planningBusy = false;
        this.refreshPlanning();
      }
    }
  }

  private weatherStatusColor(): ResourceColor {
    if (this.weatherStatus === WeatherDataStatus.LIVE) return $r('app.color.app_brand');
    if (this.weatherStatus === WeatherDataStatus.CACHED || this.weatherStatus === WeatherDataStatus.LOADING) {
      return $r('app.color.app_warning');
    }
    return $r('app.color.app_text_secondary');
  }

  private planningRecommendationTitle(): string {
    if (this.planningResult === undefined) return '等待规划';
    if (this.weatherStatus === WeatherDataStatus.LOADING) return '正在更新预报';
    if (this.weatherStatus === WeatherDataStatus.NOT_REQUESTED ||
      this.weatherStatus === WeatherDataStatus.UNAVAILABLE) return '仅天文条件';
    if (this.weatherRequiresConfirmation()) return '天气待确认';
    const nightLabel: string = this.planningDayOffset === 0 ? '今晚' : '明晚';
    if (this.planningResult.recommendation === OutingRecommendation.GOOD) return `${nightLabel}条件较好`;
    if (this.planningResult.recommendation === OutingRecommendation.CAUTION) return `${nightLabel}条件一般`;
    if (this.planningResult.recommendation === OutingRecommendation.POOR) return `${nightLabel}暂不推荐`;
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
    if (this.planningResult === undefined) {
      return `${this.selectedVisibilityText()} · ${this.targetAltitudeText()}`;
    }
    if (this.planningResult.recommendedCaptureWindow !== undefined) {
      return `${this.formatClockTime(this.planningResult.recommendedCaptureWindow.startAtMs)}–` +
        `${this.formatClockTime(this.planningResult.recommendedCaptureWindow.endAtMs)}`;
    }
    if (this.planningResult.bestWindow !== undefined) {
      return `天文 ${this.formatClockTime(this.planningResult.bestWindow.startAtMs)}–` +
        `${this.formatClockTime(this.planningResult.bestWindow.endAtMs)}`;
    }
    return `${this.selectedVisibilityText()} · ${this.targetAltitudeText()}`;
  }

  private recommendationColor(recommendation: OutingRecommendation): ResourceColor {
    if (recommendation === OutingRecommendation.GOOD) return $r('app.color.app_success');
    if (recommendation === OutingRecommendation.CAUTION ||
      recommendation === OutingRecommendation.ASTRONOMY_ONLY) return $r('app.color.app_warning');
    if (recommendation === OutingRecommendation.POOR) return $r('app.color.app_error');
    return $r('app.color.app_text_tertiary');
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
    // 只有普通星图允许显示模拟时间；设备、任务和后期页始终使用真实设备时钟。
    const timestampMs: number = this.activeSection === 0 ? this.activeSkyTimestampMs() : Date.now();
    const date: Date = new Date(timestampMs);
    return this.pad2(date.getHours()) + ':' + this.pad2(date.getMinutes());
  }

  private weatherDetailsText(): string {
    if (this.weatherForecast === undefined) return '';
    const freshness: string = this.weatherRequiresConfirmation() ? '预报待确认' : '逐小时预报';
    return `${this.weatherForecast.sourceName} · ${this.weatherForecast.timezone} · ` +
      `${this.weatherForecast.forecastDays} 天${freshness}`;
  }

  private activeSkyTimestampMs(): number {
    return this.skyMode === 1 ? this.normalTimeState.timestampMs : Date.now();
  }

  private simulatedDeviceTimeBlocked(): boolean {
    return ObservationExecutionPolicy.blocksDeviceTime(
      this.skyMode === 1, this.normalTimeState.mode);
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  private canStartCapture(): boolean {
    if (this.simulationActive() || !this.taskStoreReady || this.activeTaskSession !== undefined || this.operationBusy ||
      this.mountConnection !== ConnectionState.CONNECTED ||
      !this.mountHomed || !this.mountCoordinatesTopocentric || !this.selectedTarget().gotoAllowed ||
      this.selectedTarget().id === 'solar-sun' ||
      this.simulatedDeviceTimeBlocked()) {
      return false;
    }
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined || horizontal.altitudeDegrees < 10.0) {
      return false;
    }
    return this.captureMode === 0 || this.gatewayConnection === ConnectionState.CONNECTED;
  }

  private captureReadinessText(): string {
    if (this.simulationActive()) return '演练模式只播放数字孪生流程；退出后才能执行真实观测';
    if (!this.taskStoreReady) return '正在读取任务会话，请稍候';
    if (this.activeTaskSession !== undefined) return '已有进行中的会话，请先在任务中心结束或继续';
    if (this.operationBusy) return '正在执行设备操作，请稍候';
    if (this.mountConnection !== ConnectionState.CONNECTED) return '请先连接 OnStepX 赤道仪';
    if (this.simulatedDeviceTimeBlocked()) {
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
    this.normalViewportGeneration++;
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
    this.syncNormalBackdropViewport();
    this.rebuildNormalScene();
  }

  private scheduleNormalSceneUpdate(interactive: boolean = false): void {
    if (interactive) {
      this.markNormalSceneInteractive();
      /*
       * 恢复手势接入前验证过的稳定链路：每个显示帧最多重建一次交互场景。
       * NormalSkySceneService 会在 interactive=true 时减少标签和地平遮罩采样，
       * 但仍使用真实球面投影，因此拖动、旋转、缩放不会累积 Canvas 仿射误差。
       */
      if (this.normalSceneFramePending) return;
      this.normalSceneFramePending = true;
      this.getUIContext().postFrameCallback(this.normalSceneFrameCallback);
      return;
    }
    if (this.normalSceneUpdateTimer >= 0) return;
    this.normalSceneUpdateTimer = setTimeout(() => {
      this.normalSceneUpdateTimer = -1;
      this.syncNormalBackdropViewport();
      this.rebuildNormalScene();
    }, 16);
  }

  private flushNormalSceneFrame(frameTimeInNano: number): void {
    if (!this.normalSceneFramePending) {
      return;
    }
    this.normalSceneFramePending = false;
    if (this.activeSection !== 0 || this.skyMode !== 1) {
      return;
    }

    /*
     * 摄影层先消费最新四元数快照，目录层是否达到重建间隔不会阻塞它。
     * 这样拖动、旋转和缩放的视觉反馈不再等待恒星查询及标签避让完成。
     */
    this.syncNormalBackdropViewport();
    if (this.lastNormalSceneFrameTimeNs > 0.0 &&
      frameTimeInNano - this.lastNormalSceneFrameTimeNs < NORMAL_SCENE_MIN_FRAME_INTERVAL_NS) {
      // 未达到目录层重建间隔时继续等待下一 VSync，但摄影背景已经完成本帧更新。
      this.normalSceneFramePending = true;
      this.getUIContext().postFrameCallback(this.normalSceneFrameCallback);
      return;
    }
    this.lastNormalSceneFrameTimeNs = frameTimeInNano;
    this.rebuildNormalScene();
  }

  private markNormalSceneInteractive(): void {
    if (!this.normalSceneInteractive) {
      this.normalSceneInteractive = true;
    }
    if (this.normalSceneSettleTimer >= 0) {
      clearTimeout(this.normalSceneSettleTimer);
    }
    // 停手后再恢复完整星等、标签和细地平遮罩，避免精细重建抢占最后几帧惯性动画。
    this.normalSceneSettleTimer = setTimeout(() => {
      this.normalSceneSettleTimer = -1;
      this.normalSceneInteractive = false;
      if (this.activeSection === 0 && this.skyMode === 1) {
        this.updateNormalScene();
      }
    }, 140);
  }

  private clearScheduledNormalSceneUpdate(): void {
    // postFrameCallback 没有取消接口；清除 pending 后，已入队回调会安全地空操作。
    this.normalSceneFramePending = false;
    this.lastNormalSceneFrameTimeNs = 0.0;
    if (this.normalSceneUpdateTimer >= 0) {
      clearTimeout(this.normalSceneUpdateTimer);
      this.normalSceneUpdateTimer = -1;
    }
  }

  private syncNormalBackdropViewport(force: boolean = false): void {
    if (!force &&
      this.lastBackdropViewportGeneration === this.normalViewportGeneration &&
      this.lastBackdropInteractive === this.normalSceneInteractive) {
      return;
    }
    this.skySurveyBackdropController.update(
      this.normalViewport, this.normalSceneInteractive);
    this.lastBackdropViewportGeneration = this.normalViewportGeneration;
    this.lastBackdropInteractive = this.normalSceneInteractive;
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
      interactive: this.normalSceneInteractive,
      showDirectionMarkers: NormalSkyLayoutService.showDirectionMarkers(
        this.useSkyBottomSheet(), this.skyOverlayPanel)
    });
  }

  private isPhotographyBackdropActive(): boolean {
    return this.pageVisible && this.activeSection === 0 && this.skyMode === 1 &&
      this.normalBackdropMode === SkyBackdropMode.VISIBLE_PHOTOGRAPHY;
  }

  /**
   * 只有 Drawing Canvas 已经成功提交全天网格时，才隐藏导航背景和重复 HYG 星点。
   * 首次解码期间继续显示完整导航星图，避免摄影层尚未就绪时出现黑屏。
   */
  private hasVisibleSkySurveyBackdrop(): boolean {
    return this.isPhotographyBackdropActive() &&
      this.skySurveyBackdropStatus === SkySurveyBackdropStatus.READY;
  }

  private applySkySurveyBackdropStatus(status: SkySurveyBackdropStatus, message: string): void {
    if (status === this.skySurveyBackdropStatus) {
      return;
    }
    this.skySurveyBackdropStatus = status;
    if (status === SkySurveyBackdropStatus.FAILED && message.length > 0) {
      this.operationMessage = message;
    }
  }

  private normalGestureAnchorX(value: number): number {
    const width: number = Math.max(1.0, this.skyViewportWidth);
    const safeValue: number = Number.isFinite(value) ? value : width / 2.0;
    return this.clamp(safeValue, 0.0, width);
  }

  private normalGestureAnchorY(value: number): number {
    const height: number = Math.max(1.0, this.skyViewportHeight);
    const safeValue: number = Number.isFinite(value) ? value : height / 2.0;
    return this.clamp(safeValue, 0.0, height);
  }

  /**
   * RotationGestureEvent 没有 pinchCenterX/Y；旋转中心必须由当前参与手势的
   * fingerList 计算。此前读取捏合事件专属字段会在真机上得到 0，导致整个
   * 天球绕左上角而不是双指中心旋转。
   */
  private normalRotationAnchorX(event: GestureEvent): number {
    let totalX: number = 0.0;
    let validFingerCount: number = 0;
    for (let index: number = 0; index < event.fingerList.length; index++) {
      const localX: number = event.fingerList[index].localX;
      if (!Number.isFinite(localX)) continue;
      totalX += localX;
      validFingerCount++;
    }
    if (validFingerCount < 2) return Math.max(1.0, this.skyViewportWidth) / 2.0;
    return this.normalGestureAnchorX(totalX / validFingerCount);
  }

  private normalRotationAnchorY(event: GestureEvent): number {
    let totalY: number = 0.0;
    let validFingerCount: number = 0;
    for (let index: number = 0; index < event.fingerList.length; index++) {
      const localY: number = event.fingerList[index].localY;
      if (!Number.isFinite(localY)) continue;
      totalY += localY;
      validFingerCount++;
    }
    if (validFingerCount < 2) return Math.max(1.0, this.skyViewportHeight) / 2.0;
    return this.normalGestureAnchorY(totalY / validFingerCount);
  }

  private setNormalLayer(layer: number, enabled: boolean): void {
    const next: SkyLayerVisibility = {
      galacticPlane: this.normalLayers.galacticPlane,
      constellationLines: this.normalLayers.constellationLines,
      equatorialGrid: this.normalLayers.equatorialGrid,
      ecliptic: this.normalLayers.ecliptic,
      horizon: this.normalLayers.horizon,
      deepSky: this.normalLayers.deepSky,
      solarSystem: this.normalLayers.solarSystem,
      directionGuides: this.normalLayers.directionGuides
    };
    if (layer === 0) next.galacticPlane = enabled;
    if (layer === 1) next.constellationLines = enabled;
    if (layer === 2) next.equatorialGrid = enabled;
    if (layer === 3) next.ecliptic = enabled;
    if (layer === 4) next.horizon = enabled;
    if (layer === 5) next.deepSky = enabled;
    if (layer === 6) next.solarSystem = enabled;
    if (layer === 7) next.directionGuides = enabled;
    this.normalLayers = next;
    this.updateNormalScene();
  }

  private setNormalSkyBackdropMode(mode: SkyBackdropMode): void {
    if (mode === this.normalBackdropMode) {
      return;
    }
    this.normalBackdropMode = mode;
    if (mode === SkyBackdropMode.NAVIGATION) {
      this.skySurveyBackdropStatus = SkySurveyBackdropStatus.DISABLED;
      this.operationMessage = '已切换为导航星图';
    } else {
      this.operationMessage = '已切换为摄影底图；仅作视觉参考，不参与定位或设备控制';
    }
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
    this.normalSkySceneService.invalidateForTimeSelection();
    this.operationMessage = '普通星图已回到真实当前时间';
    this.updateNormalScene();
  }

  private selectNormalSkyTime(timestampMs: number): void {
    this.clearNormalMotion();
    this.normalTimeState = NormalSkyTimeService.selectTime(
      this.normalTimeState, timestampMs);
    this.normalSkySceneService.invalidateForTimeSelection();
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
    // 视场滑块会连续回调，必须走交互帧限流；停手 140ms 后再恢复完整目录精度。
    this.scheduleNormalSceneUpdate(true);
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
      this.scheduleNormalSceneUpdate(true);
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
      this.scheduleNormalSceneUpdate(true);
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
    this.finishNormalSceneInteraction();
    if (this.normalSceneTimer >= 0) {
      clearInterval(this.normalSceneTimer);
      this.normalSceneTimer = -1;
    }
    this.normalTimeLastTickMs = 0;
  }

  /**
   * 统一结束普通星图的高频交互事务。
   *
   * 页面切换、模式切换和 Ability 退出都必须清除待处理帧、惯性收敛定时器，并把摄影
   * 控制器恢复为精细网格；否则返回星图后可能长期停留在上一段交互的粗网格和旧命中场景。
   */
  private finishNormalSceneInteraction(): void {
    this.clearScheduledNormalSceneUpdate();
    if (this.normalSceneSettleTimer >= 0) {
      clearTimeout(this.normalSceneSettleTimer);
      this.normalSceneSettleTimer = -1;
    }
    this.normalSceneInteractive = false;
    this.syncNormalBackdropViewport(true);
  }

  private applyHandLandmarks(result: HandLandmarkAnalysisResult): void {
    // 相机卸载前可能仍有一帧推理在途；会话起始时间和单调帧时间共同阻止旧回调修改视口。
    if (!this.gestureCameraActive || !this.gestureModelRunning || !this.gestureEnabled ||
      this.activeSection !== 0 ||
      this.skyMode !== 1 || this.skyOverlayPanel !== 0 || !this.skyChromeVisible ||
      this.showCapturePanel ||
      this.gestureSourceRunGeneration <= 0 ||
      result.runGeneration !== this.gestureSourceRunGeneration ||
      !Number.isFinite(result.frameReceivedAtMs) ||
      result.frameReceivedAtMs < this.gestureSessionStartedAtMs ||
      result.frameReceivedAtMs <= this.lastAcceptedGestureFrameAtMs) {
      return;
    }
    this.lastAcceptedGestureFrameAtMs = result.frameReceivedAtMs;
    this.updateGesturePerformanceText(result);
    const frame: GestureFrame = this.gestureInterpreter.interpret(
      result.hands, result.frameReceivedAtMs);
    let normalSkyChanged: boolean = false;
    // 选择和复位优先于张掌三轴变换，保持闭合期间不会继续拖动或缩放。
    if (frame.gesture === HandGesture.PINCH_SELECT) {
      this.endSingleHandTransform();
      this.selectNearestGestureTarget(
        frame.selectX * this.skyViewportWidth, frame.selectY * this.skyViewportHeight);
      this.gestureStatus = '捏合选择';
    } else if (frame.gesture === HandGesture.FIST_RESET) {
      this.endSingleHandTransform();
      this.applyNormalViewState(NormalSkyViewStateService.home(
        this.normalObserver(this.normalTimeState.timestampMs), this.normalViewState.orientation));
      normalSkyChanged = true;
      this.gestureStatus = '握拳复位';
    } else if (frame.gesture === HandGesture.SINGLE_HAND_TRANSFORM) {
      const update: NormalSkyGestureUpdate =
        this.normalSkyGestureController.updateSingleHandTransform(
          this.normalViewState, this.normalSkySize(), frame.transform);
      if (update.changed) {
        if (!this.handTransformActive) {
          // 手部接管视口时只终止旧的触控动画，不能调用 clearNormalMotion，
          // 否则会把刚建立的单掌事务连同控制器状态一起重置。
          this.stopNormalInertia();
          this.stopNormalFly();
          this.handTransformActive = true;
        }
        // 三个轴由控制器合成为一个候选姿态；本帧只写一次视口并只安排一次场景更新。
        this.applyNormalViewState(update.viewState);
        normalSkyChanged = true;
      }
      this.gestureStatus = this.singleHandTransformStatus(update);
    } else if (result.hands.length > 0) {
      this.endSingleHandTransform();
      this.gestureStatus = '已检测手部';
    } else {
      this.endSingleHandTransform();
      this.gestureStatus = '等待手部进入画面';
    }
    if (normalSkyChanged) {
      this.scheduleNormalSceneUpdate(true);
    }
  }

  private updateGesturePerformanceText(result: HandLandmarkAnalysisResult): void {
    const nowMs: number = Date.now();
    if (nowMs - this.lastGestureMetricsAtMs < 500.0) {
      return;
    }
    this.lastGestureMetricsAtMs = nowMs;
    const sourceStatus: HandFrameSourceStatus = this.handFrameSource.getStatus();
    const analyzerStatus: HandLandmarkAnalyzerStatus = sourceStatus.analyzer;
    const backend: string = this.gestureBackendText(analyzerStatus);
    // 相机 imageArrival 与页面可能位于不同 ArkTS 运行时。耗时统计随结果快照传回，
    // 不再从 UI 线程重新读取分析器内部计数，避免真机显示 0ms / 0fps 的假指标。
    const average: string = result.averageInferenceMs.toFixed(0);
    const p95: string = result.p95InferenceMs.toFixed(0);
    const fps: string = result.inferenceFps.toFixed(1);
    this.gesturePerformanceText =
      `${backend} · ${average}ms / P95 ${p95}ms · ${fps}fps · 丢帧${result.droppedFrameCount}`;
  }

  private endSingleHandTransform(): void {
    this.handTransformActive = false;
    this.normalSkyGestureController.endHandTransform();
  }

  private singleHandTransformStatus(update: NormalSkyGestureUpdate): string {
    const names: string[] = [];
    if (update.translationChanged) names.push('平移');
    if (update.rotationChanged) names.push('旋转');
    if (update.scaleChanged) names.push('缩放');
    return names.length > 0 ? `单掌${names.join(' / ')}` : '单掌已稳定';
  }

  private selectNearestGestureTarget(screenX: number, screenY: number): void {
    const nearest: ProjectedSkyObject | undefined = NormalSkyProjectionService.hitTest(
      this.normalScene.objects, screenX, screenY, 18.0);
    if (nearest !== undefined) {
      this.selectNormalSkyObject(nearest.id);
    }
  }

  private async refreshLocation(): Promise<void> {
    if (this.planningLocationBusy) return;
    const requestGeneration: number = ++this.locationRequestGeneration;
    const previousObserver: ObserverState | undefined = this.observer;
    const previousLocationText: string = this.locationText;
    const previousLocationSource: string = this.planningLocationSource;
    const previousProvisional: boolean = this.planningLocationProvisional;
    this.planningLocationBusy = true;
    this.locationText = '正在定位';
    this.planningLocationSource = '正在精确定位';
    try {
      const sequence: ObserverLocationSequence = await ObserverLocationService.begin();
      if (requestGeneration !== this.locationRequestGeneration) return;
      if (sequence.provisional !== undefined) {
        this.applySystemPlanningLocation(sequence.provisional);
        this.operationMessage = `已使用最近位置生成临时规划，正在后台提高精度`;
        if (this.weatherForecast === undefined) this.refreshWeatherForecast();
      }
      const preciseResult: ObserverLocationResult = await sequence.precise;
      if (requestGeneration !== this.locationRequestGeneration) return;
      const previousLatitude: number | undefined =
        this.observer === undefined ? undefined : this.observer.latitudeDegrees;
      const previousLongitude: number | undefined =
        this.observer === undefined ? undefined : this.observer.longitudeDegrees;
      this.applySystemPlanningLocation(preciseResult);
      this.operationMessage = `定位精度约 ±${preciseResult.accuracyMeters.toFixed(0)} 米`;
      const weatherLocationChanged: boolean = previousLatitude === undefined || previousLongitude === undefined ||
        Math.abs(previousLatitude - preciseResult.observer.latitudeDegrees) > 0.2 ||
        Math.abs(previousLongitude - preciseResult.observer.longitudeDegrees) > 0.2;
      if (weatherLocationChanged) {
        this.weatherRequestGeneration++;
        this.planningBusy = false;
        this.weatherForecast = undefined;
        this.weatherStatus = WeatherDataStatus.NOT_REQUESTED;
      }
      if (this.weatherForecast === undefined) this.refreshWeatherForecast();
    } catch (error) {
      if (requestGeneration !== this.locationRequestGeneration) return;
      this.locationSynced = false;
      if (previousObserver === undefined) {
        if (this.observer === undefined) {
          this.locationText = '定位不可用';
          this.planningLocationSource = '等待手动地点';
          this.planningLocationProvisional = false;
          this.operationMessage = `定位失败：${error}`;
          this.updateNormalScene();
        } else {
          this.operationMessage = `高精度定位失败，继续使用最近位置：${error}`;
        }
      } else {
        this.observer = previousObserver;
        this.locationText = previousLocationText;
        this.planningLocationSource = previousLocationSource;
        this.planningLocationProvisional = previousProvisional;
        this.operationMessage = `系统定位失败，已保留${previousLocationSource}：${error}`;
        this.updateNormalScene();
        this.refreshPlanning();
      }
    } finally {
      if (requestGeneration === this.locationRequestGeneration) {
        this.planningLocationBusy = false;
      }
    }
  }

  /**
   * 系统最近位置和高精度位置共用一条应用路径。这里只更新软件规划地点，
   * locationSynced 始终保持 false，避免把 Pad 定位误认为已经同步到赤道仪。
   */
  private applySystemPlanningLocation(result: ObserverLocationResult): void {
    this.observer = result.observer;
    this.locationAccuracy = result.accuracyMeters;
    this.locationSynced = false;
    this.locationText =
      `${result.observer.latitudeDegrees.toFixed(2)}, ${result.observer.longitudeDegrees.toFixed(2)}`;
    this.manualLatitudeText = result.observer.latitudeDegrees.toFixed(5);
    this.manualLongitudeText = result.observer.longitudeDegrees.toFixed(5);
    this.planningLocationSource = result.source === ObserverLocationSource.LAST_KNOWN ?
      '最近位置（精度校正中）' : '系统定位';
    this.planningLocationProvisional = result.provisional;
    this.getUIContext().animateTo(MotionTokens.standard(), () => {
      this.planningLocationEditorOpen = false;
    });
    this.updateNormalScene();
    this.updateProjectedTargets(true);
    this.refreshPlanning();
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

  private simulationActive(): boolean {
    return this.observationRunMode === ObservationRunMode.SIMULATION;
  }

  private displayedTaskSession(): TaskSession | undefined {
    if (this.simulationActive() && this.digitalTwinSnapshot !== undefined) {
      return this.digitalTwinSnapshot.session;
    }
    return this.activeTaskSession;
  }

  /**
   * 系统实况窗需要额外权益，因此比赛版先把 TaskSession 映射为可信的应用内实况状态。
   * 数字孪生使用脚本 sequence；真实会话使用更新时间作为更新标识，两者都不会控制硬件。
   */
  private currentLiveObservation(): LiveObservationState | undefined {
    const session: TaskSession | undefined = this.displayedTaskSession();
    const sequence: number = this.simulationActive() && this.digitalTwinSnapshot !== undefined ?
      this.digitalTwinSnapshot.sequence : (session === undefined ? 0 : session.updatedAtMs);
    return LiveObservationService.fromSession(session, this.observationRunMode, sequence);
  }

  /** 分享当前规划原子快照，不读取或附带任何设备 IP、端口、令牌和调试日志。 */
  private async shareActivePlanningSnapshot(): Promise<void> {
    if (!this.harmonyFeatureSnapshot.systemShare.available) {
      this.operationMessage = '当前设备没有可用的系统分享能力';
      return;
    }
    const snapshot: PlanningSnapshot | undefined = this.activePlanningSnapshot;
    if (snapshot === undefined || !PlanningSnapshotService.isConsistent(snapshot)) {
      this.operationMessage = '规划结果仍在更新，暂时不能分享';
      return;
    }
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      this.operationMessage = '无法取得系统分享上下文';
      return;
    }
    const target: CelestialObject = this.activePlanningTarget();
    const result: ObservationShareResult = await ObservationShareService.share(context,
      ObservationShareService.createPlanningPayload({
        snapshot: snapshot,
        targetName: target.nameZh,
        designation: target.designation
      }));
    this.operationMessage = result.message;
  }

  /**
   * 分享任务报告时只使用冻结会话与演练素材清单。
   * 演练模式强制添加“模拟素材 · 非现场实拍”，避免比赛材料把脚本回放误写成现场实拍。
   */
  private async shareDisplayedTaskReport(): Promise<void> {
    if (!this.harmonyFeatureSnapshot.systemShare.available) {
      this.operationMessage = '当前设备没有可用的系统分享能力';
      return;
    }
    const session: TaskSession | undefined = this.displayedTaskSession();
    if (session === undefined) {
      this.operationMessage = '当前没有可分享的观测会话';
      return;
    }
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      this.operationMessage = '无法取得系统分享上下文';
      return;
    }
    const result: ObservationShareResult = await ObservationShareService.share(context,
      ObservationShareService.createTaskReportPayload({
        session: session,
        replayManifest: this.simulationActive() && this.digitalTwinSnapshot !== undefined ?
          this.digitalTwinSnapshot.assetManifest : undefined
      }));
    this.operationMessage = result.message;
  }

  /**
   * 所有真实设备入口必须经过同一运行域检查。演练模式下即使 UI 状态误显示为可点击，
   * 此处仍会阻断 TCP、HTTP、GOTO、同步、跟踪和快门链路。
   */
  private allowRealHardwareAction(actionName: string): boolean {
    if (ObservationRunModePolicy.allowsHardwareAccess(this.observationRunMode)) return true;
    this.reportDeviceOperation(`演练模式已阻止“${actionName}”；未访问任何真实设备`);
    return false;
  }

  private enterDigitalTwinMode(): void {
    if (this.simulationActive()) return;
    const entryState: SimulationEntryState = {
      mountDisconnected: this.mountConnection === ConnectionState.DISCONNECTED,
      gatewayDisconnected: this.gatewayServiceConnection === ConnectionState.DISCONNECTED &&
        this.gatewayConnection === ConnectionState.DISCONNECTED,
      realSessionInactive: this.activeTaskSession === undefined,
      operationIdle: !this.operationBusy
    };
    const decision: SimulationEntryDecision =
      ObservationRunModePolicy.evaluateSimulationEntry(entryState);
    if (!decision.allowed) {
      this.reportDeviceOperation(decision.reason);
      return;
    }

    this.clearMountPolling();
    this.clearGatewayPolling();
    this.clearTaskPolling();
    this.captureRunGeneration++;
    this.observationRunMode = ObservationRunMode.SIMULATION;
    this.digitalTwinSnapshot = undefined;
    this.digitalTwinPlaying = false;
    this.cameraPreflightResult = undefined;
    this.resetMountUiState(ConnectionState.DISCONNECTED);
    this.gatewayServiceConnection = ConnectionState.DISCONNECTED;
    this.gatewayConnection = ConnectionState.DISCONNECTED;
    this.gatewayUpdatedAtMs = 0;
    this.gatewayServiceVersion = '';

    const target: CelestialObject = this.selectedTarget();
    const targetSnapshot: TaskTargetSnapshot = {
      id: target.id,
      name: target.nameZh,
      designation: target.designation,
      type: target.type,
      coordinate: target.coordinate,
      precision: target.precision,
      gotoAllowed: target.gotoAllowed
    };
    const plan: CapturePlan = this.buildDigitalTwinPlan(target);
    this.digitalTwinReplayService.loadStandardDemo(plan, targetSnapshot);
    this.digitalTwinReplayService.play(4.0);
    this.digitalTwinPlaying = true;
    this.changeActiveSection(1);
    this.reportDeviceOperation('已进入数字孪生演练；当前状态、任务和素材均与真实设备隔离');
  }

  private exitDigitalTwinMode(): void {
    if (!this.simulationActive()) return;
    this.digitalTwinReplayService.pause();
    this.digitalTwinPlaying = false;
    this.digitalTwinSnapshot = undefined;
    this.digitalTwinPhaseText = '';
    this.digitalTwinSourceText = '';
    this.observationRunMode = ObservationRunMode.REAL;
    // 演练产生的回零、同步、跟踪和连接证明不能带回真实运行域。
    this.resetMountUiState(ConnectionState.DISCONNECTED);
    this.gatewayServiceConnection = ConnectionState.DISCONNECTED;
    this.gatewayConnection = ConnectionState.DISCONNECTED;
    this.gatewayUpdatedAtMs = 0;
    this.gatewayServiceVersion = '';
    this.mountDetail = this.mountEndpointText();
    this.gatewayDetail = this.gatewayEndpointText();
    this.taskStatus = TaskStatus.PENDING;
    this.taskProgress = 0;
    this.completedFrames = 0;
    this.taskStage = '等待创建';
    this.activeTaskId = '';
    this.taskStopRequested = false;
    this.emergencyMessage = '';
    this.reportDeviceOperation('已退出演练模式；真实设备保持断开，需重新连接、自检、回零和同步');
  }

  private toggleDigitalTwinPlayback(): void {
    if (!this.simulationActive()) return;
    if (this.digitalTwinPlaying) {
      this.digitalTwinReplayService.pause();
      this.digitalTwinPlaying = false;
      this.reportDeviceOperation('数字孪生演练已暂停');
      return;
    }
    if (this.digitalTwinSnapshot !== undefined &&
      (this.digitalTwinSnapshot.phase === DigitalTwinPhase.COMPLETE ||
        this.digitalTwinSnapshot.phase === DigitalTwinPhase.STOPPED)) {
      this.restartDigitalTwinPlayback();
      return;
    }
    this.digitalTwinReplayService.play(4.0);
    this.digitalTwinPlaying = true;
    this.reportDeviceOperation('数字孪生演练继续播放');
  }

  private restartDigitalTwinPlayback(): void {
    if (!this.simulationActive()) return;
    // 清除上一轮序号后再从 sequence=1 开始，避免正常重播被误判为乱序快照。
    this.digitalTwinSnapshot = undefined;
    this.digitalTwinReplayService.restart(4.0);
    this.digitalTwinPlaying = true;
    this.reportDeviceOperation('数字孪生演练已从设备发现阶段重新开始');
  }

  private buildDigitalTwinPlan(target: CelestialObject): CapturePlan {
    return {
      id: `digital-twin-plan-${Date.now()}-${target.id}`,
      mode: CaptureMode.SMART_LONG_EXPOSURE,
      targetId: target.id,
      targetName: target.nameZh,
      exposureSeconds: Math.max(10, this.exposureSeconds),
      frameCount: Math.max(8, this.frameCount),
      intervalSeconds: Math.max(2, this.intervalSeconds),
      iso: Math.max(800, this.iso),
      aperture: 4.0,
      imageFormat: ImageFormat.RAW_JPEG,
      outputFps: 25,
      enablePlateSolve: true,
      enableDriftCorrection: true,
      enableLocalStack: true,
      enableCloudEnhancement: true,
      recommendationReason: '数字孪生演练使用冻结参数展示完整观测状态机。',
      warnings: ['演练计划不会发送到赤道仪、相机或 Linux 网关']
    };
  }

  private applyDigitalTwinSnapshot(snapshot: DigitalTwinSnapshot): void {
    if (!this.simulationActive()) return;
    if (this.digitalTwinSnapshot !== undefined &&
      snapshot.sequence < this.digitalTwinSnapshot.sequence) {
      return;
    }
    this.digitalTwinSnapshot = snapshot;
    this.digitalTwinPhaseText = snapshot.note;
    this.digitalTwinSourceText = snapshot.dataSource === ReplayAssetSource.REAL_CAPTURE_REPLAY ?
      '真实设备历史素材 · 非实时' : '模拟素材 · 非现场实拍';
    this.mountConnection = snapshot.mount.connection;
    this.gatewayServiceConnection = ConnectionState.SIMULATED;
    this.gatewayConnection = snapshot.camera.connection;
    this.mountHomed = snapshot.mount.homed;
    this.mountCoordinatesTopocentric = snapshot.phase !== DigitalTwinPhase.DEVICE_DISCOVERY;
    this.locationSynced = snapshot.phase !== DigitalTwinPhase.DEVICE_DISCOVERY &&
      snapshot.phase !== DigitalTwinPhase.CAMERA_PREFLIGHT &&
      snapshot.phase !== DigitalTwinPhase.GOTO;
    this.tracking = snapshot.mount.trackingMode !== TrackingMode.STOPPED &&
      snapshot.mount.trackingMode !== TrackingMode.UNKNOWN;
    this.mountSlewing = snapshot.mount.slewing;
    this.mountRaHours = snapshot.mount.rightAscensionHours;
    this.mountDecDegrees = snapshot.mount.declinationDegrees;
    this.mountUpdatedAtMs = snapshot.mount.updatedAtMs;
    this.gatewayUpdatedAtMs = snapshot.camera.updatedAtMs;
    this.mountDetail = '数字孪生脚本 · 未连接 OnStepX';
    this.gatewayDetail = `${snapshot.camera.cameraModel} · 未访问 Linux 网关`;
    this.taskProgress = snapshot.session.progressPercent;
    this.completedFrames = snapshot.session.completedFrames;
    this.taskStage = snapshot.session.statusDetail;
    this.activeTaskId = snapshot.session.id;
    this.taskStatus = this.digitalTwinTaskStatus(snapshot.session.status);
    this.deviceOperationMessage = `${snapshot.note}；${snapshot.warning}`;
    this.operationMessage = this.deviceOperationMessage;
    if (snapshot.phase === DigitalTwinPhase.COMPLETE ||
      snapshot.phase === DigitalTwinPhase.STOPPED) {
      this.digitalTwinPlaying = false;
    }
  }

  private digitalTwinTaskStatus(status: SessionStatus): TaskStatus {
    if (status === SessionStatus.SUCCEEDED) return TaskStatus.SUCCEEDED;
    if (status === SessionStatus.FAILED || status === SessionStatus.INTERRUPTED) {
      return TaskStatus.FAILED;
    }
    if (status === SessionStatus.CANCELLED) return TaskStatus.CANCELLED;
    if (status === SessionStatus.PREPARING) return TaskStatus.PENDING;
    return TaskStatus.RUNNING;
  }

  /**
   * 启动时仅恢复用户上次明确保存的地址。此过程不连接 Socket、不查询网关，
   * 因此应用重启后不会因为地址恢复而改变赤道仪或相机状态。
   */
  private async initializeDeviceConnectionSettings(): Promise<void> {
    if (this.deviceConnectionSettingsStore !== undefined || this.deviceConnectionSettingsLoading) return;
    this.deviceConnectionSettingsLoading = true;
    try {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('无法取得设备地址存储上下文');
      const store: DeviceConnectionSettingsStore = new DeviceConnectionSettingsStore(context);
      const settings: DeviceConnectionSettings = await store.initialize();
      this.deviceConnectionSettingsStore = store;
      this.applyDeviceConnectionSettings(settings);
    } catch (error) {
      // 存储不可用不能影响离线星图；继续使用 StarScope 默认地址并把原因放入设备页反馈。
      this.reportDeviceOperation(`设备地址存储不可用，已使用默认地址：${error}`);
    } finally {
      this.deviceConnectionSettingsLoading = false;
    }
  }

  private connectionSettingsLocked(): boolean {
    if (this.simulationActive()) return true;
    const mountBusy: boolean = this.mountConnection === ConnectionState.CONNECTED ||
      this.mountConnection === ConnectionState.CONNECTING;
    const gatewayBusy: boolean = this.gatewayServiceConnection === ConnectionState.CONNECTED ||
      this.gatewayServiceConnection === ConnectionState.CONNECTING;
    const taskActive: boolean = this.activeTaskSession !== undefined &&
      !TaskSessionStore.isTerminal(this.activeTaskSession.status);
    return mountBusy || gatewayBusy || this.operationBusy || taskActive;
  }

  private toggleConnectionSettings(): void {
    if (this.connectionSettingsLocked()) {
      this.reportDeviceOperation('请先断开设备并结束活动会话，再修改网络地址');
      return;
    }
    this.connectionSettingsOpen = !this.connectionSettingsOpen;
  }

  private restoreDeviceConnectionDefaults(): void {
    if (this.connectionSettingsLocked()) {
      this.reportDeviceOperation('设备连接中，不能修改网络地址');
      return;
    }
    const defaults: DeviceConnectionSettings = DeviceConnectionSettingsStore.defaults();
    // 恢复默认只回填输入框；再次点击“保存并应用”前，当前现场连接地址不会改变。
    this.mountHostInput = defaults.mountHost;
    this.mountPortInput = defaults.mountPort.toString();
    this.gatewayHostInput = defaults.gatewayHost;
    this.gatewayPortInput = defaults.gatewayPort.toString();
    this.reportDeviceOperation('已回填 StarScope 默认地址；保存后才会应用');
  }

  /**
   * 调起 Scan Kit 后只生成安全预览。二维码原文可能含 token，因此只在本方法的局部变量中
   * 短暂存在，不写入 @State、不记录日志，也不会因为扫码成功而自动连接任何设备。
   */
  private async scanDevicePairingCode(): Promise<void> {
    if (!this.allowRealHardwareAction('扫描并应用真实设备配置')) return;
    if (this.connectionSettingsLocked()) {
      this.reportDeviceOperation('请先断开设备并结束活动会话，再扫描设备码');
      return;
    }
    if (!this.harmonyFeatureSnapshot.scanKit.available) {
      this.reportDeviceOperation('当前设备不支持 Scan Kit，请使用手动地址配置');
      return;
    }
    if (this.pairingBusy) return;
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.reportDeviceOperation('无法取得扫码页面上下文，请使用手动地址配置');
      return;
    }
    this.pairingBusy = true;
    try {
      const scanResult: DevicePairingScanResult = await this.devicePairingScanner.scan(context);
      if (scanResult.state !== DevicePairingScanState.SUCCESS) {
        if (scanResult.message.length > 0) {
          this.reportDeviceOperation(scanResult.message);
        }
        return;
      }
      const validation: DevicePairingValidationResult = DevicePairingService.validateCode(
        scanResult.originalValue, this.deviceConnectionSettings, Date.now());
      if (!validation.success || validation.preview === undefined) {
        this.pairingPreview = undefined;
        this.reportDeviceOperation(`设备码未通过安全校验：${validation.message}`);
        return;
      }
      this.pairingPreview = validation.preview;
      this.reportDeviceOperation('设备码校验通过；确认保存前不会修改地址或连接硬件');
    } finally {
      this.pairingBusy = false;
    }
  }

  private cancelDevicePairing(): void {
    this.pairingPreview = undefined;
    this.reportDeviceOperation('已取消设备码导入，当前连接配置保持不变');
  }

  /**
   * 用户确认后才原子写入 Preferences。保存成功仅更新客户端终点，仍需要用户手动点击
   * “连接并自检/检测网关”，从而保证扫码不会触发 GOTO、同步、跟踪或拍摄。
   */
  private async confirmDevicePairing(): Promise<void> {
    if (!this.allowRealHardwareAction('保存真实设备配置')) return;
    const preview: DevicePairingPreview | undefined = this.pairingPreview;
    if (preview === undefined || this.pairingBusy) return;
    if (this.connectionSettingsLocked()) {
      this.reportDeviceOperation('设备连接或会话进行中，不能应用扫码配置');
      return;
    }
    this.pairingBusy = true;
    try {
      if (this.deviceConnectionSettingsStore === undefined) {
        await this.initializeDeviceConnectionSettings();
      }
      const store: DeviceConnectionSettingsStore | undefined = this.deviceConnectionSettingsStore;
      if (store === undefined) {
        throw new Error('设备地址存储尚未准备好，请稍后重试');
      }
      const settings: DeviceConnectionSettings = new DeviceConnectionSettings(
        preview.configuration.mountHost,
        preview.configuration.mountPort,
        preview.configuration.gatewayHost,
        preview.configuration.gatewayPort);
      await store.save(settings);
      this.applyDeviceConnectionSettings(settings);
      this.pairingPreview = undefined;
      this.connectionSettingsOpen = false;
      this.reportDeviceOperation(
        `已保存 ${preview.deviceName} 配置；请手动执行连接检测`);
    } catch (error) {
      // 保留预览以便用户重试，存储失败时 Store 仍保持上一份完整配置。
      this.reportDeviceOperation(`扫码配置未保存：${error}`);
    } finally {
      this.pairingBusy = false;
    }
  }

  private async saveDeviceConnectionSettings(): Promise<void> {
    if (!this.allowRealHardwareAction('保存真实设备地址')) return;
    if (this.connectionSettingsLocked()) {
      this.reportDeviceOperation('设备连接中，不能修改网络地址');
      return;
    }
    this.operationBusy = true;
    try {
      const settings: DeviceConnectionSettings = DeviceConnectionSettingsStore.createFromText(
        this.mountHostInput, this.mountPortInput, this.gatewayHostInput, this.gatewayPortInput);
      if (this.deviceConnectionSettingsStore === undefined) {
        await this.initializeDeviceConnectionSettings();
      }
      const store: DeviceConnectionSettingsStore | undefined = this.deviceConnectionSettingsStore;
      if (store === undefined) throw new Error('设备地址存储尚未准备好，请稍后重试');
      await store.save(settings);
      this.applyDeviceConnectionSettings(settings);
      this.connectionSettingsOpen = false;
      this.reportDeviceOperation(`已应用赤道仪 ${this.mountEndpointText()}，网关 ${this.gatewayEndpointText()}；请手动执行连接检测`);
    } catch (error) {
      this.reportDeviceOperation(`设备地址未保存：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private applyDeviceConnectionSettings(settings: DeviceConnectionSettings): void {
    this.deviceConnectionSettings = DeviceConnectionSettingsStore.copy(settings);
    this.mountHostInput = this.deviceConnectionSettings.mountHost;
    this.mountPortInput = this.deviceConnectionSettings.mountPort.toString();
    this.gatewayHostInput = this.deviceConnectionSettings.gatewayHost;
    this.gatewayPortInput = this.deviceConnectionSettings.gatewayPort.toString();
    this.mountDetail = this.mountEndpointText();
    this.gatewayDetail = this.gatewayEndpointText();
    const gatewayEndpoint: GatewayEndpointConfig = {
      baseUrl: `http://${this.deviceConnectionSettings.gatewayHost}:${this.deviceConnectionSettings.gatewayPort}`,
      requestTimeoutMs: 5000,
      readTimeoutMs: 30000
    };
    this.gatewayClient.setEndpoint(gatewayEndpoint);
  }

  private mountEndpointText(): string {
    return `${this.deviceConnectionSettings.mountHost}:${this.deviceConnectionSettings.mountPort}`;
  }

  private gatewayEndpointText(): string {
    return `${this.deviceConnectionSettings.gatewayHost}:${this.deviceConnectionSettings.gatewayPort}`;
  }

  private async toggleMountConnection(): Promise<void> {
    if (!this.allowRealHardwareAction('连接赤道仪')) return;
    if (this.operationBusy) {
      return;
    }
    this.operationBusy = true;
    this.emergencyMessage = '';
    try {
      if (this.mountConnection === ConnectionState.CONNECTED) {
        await this.mountClient.disconnect();
        this.clearMountPolling();
        this.resetMountUiState(ConnectionState.DISCONNECTED);
        this.reportDeviceOperation('赤道仪已断开');
      } else {
        this.mountConnection = ConnectionState.CONNECTING;
        this.reportDeviceOperation(`正在连接 ${this.mountEndpointText()} 并执行坐标模式自检`);
        await this.mountClient.connect(this.deviceConnectionSettings.mountHost,
          this.deviceConnectionSettings.mountPort);
        this.mountCoordinatesTopocentric = this.mountClient.isCoordinateModeCompatible();
        const state: MountState = await this.mountClient.refreshState();
        this.applyMountState(state);
        this.startMountPolling();
        this.reportDeviceOperation(this.mountCoordinatesTopocentric ?
          'OnStepX 已连接并确认 TOPOCENTRIC(1)；自动运动前请先回零' :
          `OnStepX 已连接，但 :GXEE# 返回 ${this.mountClient.getCoordinateModeResponse() || '空值'}；GOTO/SYNC 已锁定`);
      }
    } catch (error) {
      this.clearMountPolling();
      await this.mountClient.disconnect();
      this.resetMountUiState(ConnectionState.ERROR);
      this.reportDeviceOperation(`赤道仪连接失败：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private async toggleGatewayConnection(): Promise<void> {
    if (!this.allowRealHardwareAction('连接相机网关')) return;
    if (this.operationBusy) {
      return;
    }
    if (this.gatewayServiceConnection === ConnectionState.CONNECTED) {
      this.clearGatewayPolling();
      this.gatewayServiceConnection = ConnectionState.DISCONNECTED;
      this.gatewayConnection = ConnectionState.DISCONNECTED;
      this.cameraCapabilities = undefined;
      this.gatewayDetail = this.gatewayEndpointText();
      this.gatewayServiceVersion = '';
      this.gatewayUpdatedAtMs = 0;
      this.reportDeviceOperation('已停止相机网关与 EOS R7 状态检测');
      return;
    }
    this.operationBusy = true;
    this.gatewayServiceConnection = ConnectionState.CONNECTING;
    this.gatewayConnection = ConnectionState.DISCONNECTED;
    this.reportDeviceOperation(`正在检测 ${this.gatewayEndpointText()} 相机网关`);
    try {
      const health: GatewayHealth = await this.gatewayClient.health();
      if (!health.online) {
        throw new Error('网关健康检查未通过');
      }
      this.gatewayServiceConnection = ConnectionState.CONNECTED;
      this.gatewayServiceVersion = health.serviceVersion;
      const cameraState: CameraState = await this.gatewayClient.cameraStatus();
      this.applyGatewayCameraState(cameraState);
      if (cameraState.connection === ConnectionState.CONNECTED ||
        cameraState.connection === ConnectionState.SIMULATED) {
        this.cameraCapabilities = await this.gatewayClient.cameraCapabilities();
      } else {
        this.cameraCapabilities = undefined;
      }
      this.startGatewayPolling();
      if (cameraState.connection === ConnectionState.SIMULATED) {
        this.reportDeviceOperation('网关在线，但正在使用模拟相机；真实拍摄保持禁用');
      } else if (cameraState.connection === ConnectionState.CONNECTED) {
        this.reportDeviceOperation('相机网关在线并检测到真实 EOS R7');
      } else {
        this.reportDeviceOperation('相机网关在线，但尚未检测到 EOS R7 USB 连接');
      }
    } catch (error) {
      this.clearGatewayPolling();
      this.gatewayServiceConnection = ConnectionState.ERROR;
      this.gatewayConnection = ConnectionState.DISCONNECTED;
      this.cameraCapabilities = undefined;
      this.gatewayDetail = this.gatewayEndpointText();
      this.gatewayServiceVersion = '';
      this.gatewayUpdatedAtMs = 0;
      this.reportDeviceOperation(`相机网关检测失败：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private startMountPolling(): void {
    if (!ObservationRunModePolicy.allowsHardwareAccess(this.observationRunMode)) return;
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
    if (!ObservationRunModePolicy.allowsHardwareAccess(this.observationRunMode)) return;
    if (this.mountConnection !== ConnectionState.CONNECTED) {
      return;
    }
    try {
      this.applyMountState(await this.mountClient.refreshState());
    } catch (error) {
      this.clearMountPolling();
      await this.mountClient.disconnect();
      this.resetMountUiState(ConnectionState.ERROR);
      this.reportDeviceOperation(`赤道仪连接已中断，安全状态已撤销：${error}`);
    }
  }

  private applyMountState(state: MountState): void {
    this.mountConnection = state.connection;
    this.mountRaHours = state.rightAscensionHours;
    this.mountDecDegrees = state.declinationDegrees;
    this.mountSlewing = state.slewing;
    this.mountUpdatedAtMs = state.updatedAtMs;
    // :GU# 的 H 只表示“当前正在机械零位”。一旦可靠见到 H，本次连接周期内保留回零证明。
    if (state.homed) {
      this.mountHomed = true;
    }
    this.tracking = state.trackingMode !== TrackingMode.STOPPED &&
      state.trackingMode !== TrackingMode.UNKNOWN;
  }

  private startGatewayPolling(): void {
    if (!ObservationRunModePolicy.allowsHardwareAccess(this.observationRunMode)) return;
    this.clearGatewayPolling();
    this.gatewayPollTimer = setInterval(() => {
      this.pollGatewayState();
    }, 3000);
  }

  private clearGatewayPolling(): void {
    if (this.gatewayPollTimer >= 0) {
      clearInterval(this.gatewayPollTimer);
      this.gatewayPollTimer = -1;
    }
  }

  private async pollGatewayState(): Promise<void> {
    if (!ObservationRunModePolicy.allowsHardwareAccess(this.observationRunMode)) return;
    if (this.gatewayServiceConnection !== ConnectionState.CONNECTED) return;
    try {
      const previousConnection: ConnectionState = this.gatewayConnection;
      const cameraState: CameraState = await this.gatewayClient.cameraStatus();
      this.applyGatewayCameraState(cameraState);
      if (this.cameraCapabilities === undefined &&
        (cameraState.connection === ConnectionState.CONNECTED ||
          cameraState.connection === ConnectionState.SIMULATED)) {
        this.cameraCapabilities = await this.gatewayClient.cameraCapabilities();
      }
      if (previousConnection !== cameraState.connection) {
        if (cameraState.connection === ConnectionState.CONNECTED) {
          this.reportDeviceOperation('已检测到真实 EOS R7，拍摄功能可以进行安全检查');
        } else if (cameraState.connection === ConnectionState.SIMULATED) {
          this.reportDeviceOperation('检测到模拟相机，真实拍摄保持禁用');
        } else {
          this.cameraCapabilities = undefined;
          this.reportDeviceOperation('EOS R7 USB 已断开，新的拍摄任务已禁用');
        }
      }
    } catch (error) {
      this.clearGatewayPolling();
      this.gatewayServiceConnection = ConnectionState.ERROR;
      this.gatewayConnection = ConnectionState.DISCONNECTED;
      this.cameraCapabilities = undefined;
      this.gatewayDetail = this.gatewayEndpointText();
      this.gatewayServiceVersion = '';
      this.gatewayUpdatedAtMs = 0;
      this.reportDeviceOperation(`相机网关连接已中断：${error}`);
    }
  }

  private applyGatewayCameraState(state: CameraState): void {
    this.gatewayConnection = state.connection;
    this.gatewayUpdatedAtMs = state.updatedAtMs;
    const serviceLabel: string = this.gatewayServiceVersion.length > 0 ?
      this.gatewayServiceVersion : 'StarFinding Gateway';
    const deviceDetail: string = state.cameraModel.length > 0 ?
      `${state.cameraModel} · ${serviceLabel}` : serviceLabel;
    // 保留实际网关地址，方便 Windows/安卓热点下现场排障，不能只显示相机型号而隐藏连接目标。
    this.gatewayDetail = `${this.gatewayEndpointText()} · ${deviceDetail}`;
  }

  private resetMountUiState(connection: ConnectionState): void {
    this.mountConnection = connection;
    this.mountHomed = false;
    this.mountCoordinatesTopocentric = false;
    this.locationSynced = false;
    this.tracking = false;
    this.mountSlewing = false;
    this.mountRaHours = 0;
    this.mountDecDegrees = 0;
    this.mountUpdatedAtMs = 0;
  }

  private reportDeviceOperation(message: string): void {
    this.deviceOperationMessage = message;
    this.operationMessage = message;
  }

  private async homeMount(): Promise<void> {
    if (!this.allowRealHardwareAction('赤道仪回零')) return;
    if (this.operationBusy) return;
    if (this.mountConnection !== ConnectionState.CONNECTED || !this.mountCoordinatesTopocentric) {
      this.reportDeviceOperation('请先连接赤道仪并通过 TOPOCENTRIC 坐标模式自检');
      return;
    }
    this.operationBusy = true;
    this.mountHomed = false;
    try {
      await this.mountClient.home();
      this.reportDeviceOperation('两轴正在寻找常闭原点开关；完成后状态将自动更新');
    } catch (error) {
      this.reportDeviceOperation(`回零失败：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private async syncObserverToMount(): Promise<void> {
    if (!this.allowRealHardwareAction('同步地点和时间')) return;
    if (this.operationBusy || this.observer === undefined) return;
    if (this.mountConnection !== ConnectionState.CONNECTED || !this.mountCoordinatesTopocentric) {
      this.reportDeviceOperation('赤道仪尚未完成连接自检，不能同步地点和时间');
      return;
    }
    if (this.simulatedDeviceTimeBlocked()) {
      this.reportDeviceOperation('模拟时间只用于浏览和规划，已阻止同步设备时间');
      return;
    }
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
      this.reportDeviceOperation('系统定位、本机日期和时间已同步到 OnStepX');
    } catch (error) {
      this.locationSynced = false;
      this.reportDeviceOperation(`位置时间同步失败：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private async toggleTracking(): Promise<void> {
    if (!this.allowRealHardwareAction('控制恒星时跟踪')) return;
    if (this.operationBusy) return;
    if (this.mountConnection !== ConnectionState.CONNECTED || !this.mountCoordinatesTopocentric ||
      !this.mountHomed || !this.locationSynced) {
      this.reportDeviceOperation('完成连接自检、两轴回零和地点时间同步后才能控制跟踪');
      return;
    }
    this.operationBusy = true;
    try {
      if (this.tracking) {
        await this.mountClient.stopTracking();
        this.reportDeviceOperation('恒星时跟踪已停止');
      } else {
        await this.mountClient.startTracking(TrackingMode.SIDEREAL);
        this.reportDeviceOperation('恒星时跟踪已启动');
      }
      await this.pollMountState();
    } catch (error) {
      this.reportDeviceOperation(`跟踪控制失败：${error}`);
    } finally {
      this.operationBusy = false;
    }
  }

  private async parkMount(): Promise<void> {
    if (!this.allowRealHardwareAction('停放赤道仪')) return;
    if (this.operationBusy) return;
    if (this.mountConnection !== ConnectionState.CONNECTED || !this.mountHomed) {
      this.reportDeviceOperation('赤道仪连接并完成回零后才能执行停放');
      return;
    }
    this.operationBusy = true;
    try {
      await this.mountClient.park();
      this.tracking = false;
      this.reportDeviceOperation('赤道仪正在停放，请观察机械运动和物理限位');
    } catch (error) {
      this.reportDeviceOperation(`停放失败：${error}`);
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

  private async initializeTaskSessions(): Promise<void> {
    if (this.taskStoreReady || this.taskSessionStore !== undefined) return;
    try {
      const context: common.Context | undefined = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('无法取得任务会话存储上下文');
      const store: TaskSessionStore = new TaskSessionStore(context);
      this.taskSessionStore = store;
      const snapshot: TaskSessionStoreSnapshot = await store.initialize();
      this.applyTaskStoreSnapshot(snapshot);
      this.taskStoreReady = true;
      if (this.activeTaskSession !== undefined) {
        const interrupted: TaskSession = TaskSessionStore.copySession(this.activeTaskSession);
        interrupted.status = SessionStatus.INTERRUPTED;
        interrupted.statusDetail = '应用重新启动，仅恢复记录并对账；未发送设备指令';
        interrupted.updatedAtMs = Date.now();
        await store.saveActive(interrupted);
        this.activeTaskSession = interrupted;
        await this.refreshActiveTaskSession();
      }
    } catch (error) {
      this.taskStoreReady = false;
      this.taskStoreWarning = `任务会话存储不可用：${error}`;
    }
  }

  private applyTaskStoreSnapshot(snapshot: TaskSessionStoreSnapshot): void {
    this.activeTaskSession = snapshot.activeSession === undefined ? undefined :
      TaskSessionStore.copySession(snapshot.activeSession);
    const history: TaskSession[] = [];
    for (let index: number = 0; index < snapshot.history.length; index++) {
      history.push(TaskSessionStore.copySession(snapshot.history[index]));
    }
    this.taskHistory = history;
    this.taskStoreWarning = snapshot.warning;
    if (this.activeTaskSession !== undefined) this.applyLegacyTaskState(this.activeTaskSession);
  }

  private createTaskSession(plan: CapturePlan, target: CelestialObject): TaskSession {
    const now: number = Date.now();
    const targetSnapshot: TaskTargetSnapshot = {
      id: target.id,
      name: target.nameZh,
      designation: target.designation,
      type: target.type,
      coordinate: target.coordinate,
      precision: target.precision,
      gotoAllowed: target.gotoAllowed
    };
    const kind: SessionKind = plan.mode === CaptureMode.OBSERVE_ONLY ? SessionKind.OBSERVATION :
      (plan.mode === CaptureMode.SMART_LONG_EXPOSURE ? SessionKind.SMART_LONG_EXPOSURE :
        SessionKind.TIMELAPSE);
    return {
      id: `session-${now}-${target.id}`,
      kind: kind,
      status: SessionStatus.PREPARING,
      stage: WorkflowStage.SAFETY_CHECK,
      progressPercent: 1,
      completedFrames: 0,
      plan: plan,
      target: targetSnapshot,
      checkpoint: {
        stage: WorkflowStage.SAFETY_CHECK,
        stepState: WorkflowStepState.ACTIVE,
        childKind: GatewaySubtaskKind.NONE,
        operationKey: '',
        childTaskId: '',
        requestStartedAtMs: now,
        responseReceivedAtMs: 0,
        requiresManualContinue: false,
        detail: '正在重新检查真实设备安全条件'
      },
      gatewayTaskIds: [],
      jpegFileIds: [],
      rawFileIds: [],
      plateSolveCount: 0,
      correctionCount: 0,
      products: [],
      warnings: plan.warnings.slice(),
      statusDetail: '正在重新检查真实设备安全条件',
      errorMessage: '',
      createdAtMs: now,
      startedAtMs: now,
      updatedAtMs: now,
      completedAtMs: 0
    };
  }

  private async saveActiveTaskSession(session: TaskSession): Promise<void> {
    const store: TaskSessionStore | undefined = this.taskSessionStore;
    if (store === undefined) throw new Error('任务会话存储尚未初始化');
    await store.saveActive(session);
    this.activeTaskSession = TaskSessionStore.copySession(session);
    this.applyLegacyTaskState(session);
  }

  private async archiveTaskSession(session: TaskSession): Promise<void> {
    const store: TaskSessionStore | undefined = this.taskSessionStore;
    if (store === undefined) throw new Error('任务会话存储尚未初始化');
    await store.archive(session);
    const snapshot: TaskSessionStoreSnapshot = store.getSnapshot();
    this.applyTaskStoreSnapshot(snapshot);
    this.applyLegacyTaskState(session);
    this.taskStopRequested = false;
    this.clearTaskPolling();
  }

  private applyLegacyTaskState(session: TaskSession): void {
    if (session.status === SessionStatus.SUCCEEDED) this.taskStatus = TaskStatus.SUCCEEDED;
    else if (session.status === SessionStatus.FAILED) this.taskStatus = TaskStatus.FAILED;
    else if (session.status === SessionStatus.CANCELLED) this.taskStatus = TaskStatus.CANCELLED;
    else if (session.status === SessionStatus.PREPARING || session.status === SessionStatus.RUNNING) {
      this.taskStatus = TaskStatus.RUNNING;
    } else {
      this.taskStatus = TaskStatus.PENDING;
    }
    this.taskProgress = session.progressPercent;
    this.completedFrames = session.completedFrames;
    this.taskStage = session.statusDetail;
    this.activeTaskId = session.checkpoint.childTaskId;
    this.plateSolveCount = session.plateSolveCount;
    this.correctionCount = session.correctionCount;
    this.workflowWarningText = session.warnings.join('；');
    this.applySessionProducts(session.products);
  }

  private applySessionProducts(products: CaptureProduct[]): void {
    for (let index: number = 0; index < products.length; index++) {
      const product: CaptureProduct = products[index];
      if (product.kind === 'stack') this.stackFileUrl = product.downloadUrl;
      if (product.kind === 'timelapse') this.timelapseFileUrl = product.downloadUrl;
      if (product.kind === 'ai') this.aiFileUrl = product.downloadUrl;
    }
  }

  private async updateSessionStage(sessionId: string, stage: WorkflowStage, state: WorkflowStepState,
    detail: string, status: SessionStatus, progressPercent: number): Promise<void> {
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.id !== sessionId) throw new Error('活动会话已变化');
    const updated: TaskSession = TaskSessionStore.copySession(active);
    updated.stage = stage;
    updated.status = status;
    updated.progressPercent = progressPercent;
    updated.statusDetail = detail;
    updated.updatedAtMs = Date.now();
    updated.checkpoint = {
      stage: stage,
      stepState: state,
      childKind: GatewaySubtaskKind.NONE,
      operationKey: '',
      childTaskId: '',
      requestStartedAtMs: updated.updatedAtMs,
      responseReceivedAtMs: updated.updatedAtMs,
      requiresManualContinue: false,
      detail: detail
    };
    await this.saveActiveTaskSession(updated);
  }

  private async persistWorkflowCheckpoint(sessionId: string, checkpoint: WorkflowCheckpoint): Promise<void> {
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.id !== sessionId) throw new Error('活动会话已结束，拒绝继续网关请求');
    const updated: TaskSession = TaskSessionStore.copySession(active);
    updated.stage = checkpoint.stage;
    updated.checkpoint = checkpoint;
    updated.status = SessionStatus.RUNNING;
    updated.statusDetail = checkpoint.detail;
    updated.updatedAtMs = Date.now();
    if (checkpoint.childTaskId.length > 0 && !updated.gatewayTaskIds.includes(checkpoint.childTaskId)) {
      updated.gatewayTaskIds.push(checkpoint.childTaskId);
    }
    await this.saveActiveTaskSession(updated);
  }

  private applyWorkflowProgress(sessionId: string, progress: CaptureWorkflowProgress): void {
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.id !== sessionId) return;
    const updated: TaskSession = TaskSessionStore.copySession(active);
    updated.stage = progress.stage;
    updated.progressPercent = progress.progressPercent;
    updated.completedFrames = progress.completedFrames;
    updated.status = SessionStatus.RUNNING;
    updated.statusDetail = progress.stageText;
    updated.checkpoint = progress.checkpoint;
    updated.jpegFileIds = progress.jpegFileIds.slice();
    updated.rawFileIds = progress.rawFileIds.slice();
    updated.plateSolveCount = progress.plateSolveCount;
    updated.correctionCount = progress.correctionCount;
    updated.updatedAtMs = Date.now();
    if (progress.activeTaskId.length > 0 && !updated.gatewayTaskIds.includes(progress.activeTaskId)) {
      updated.gatewayTaskIds.push(progress.activeTaskId);
    }
    this.activeTaskSession = updated;
    this.applyLegacyTaskState(updated);
  }

  private async startCaptureTask(): Promise<void> {
    if (!this.allowRealHardwareAction('创建真实观测会话')) return;
    if (this.simulatedDeviceTimeBlocked()) {
      this.operationMessage = '模拟时间只用于浏览和规划，未发送任何设备指令';
      return;
    }
    if (!this.canStartCapture()) return;
    const target: CelestialObject = this.selectedTarget();
    if (target.id === 'solar-sun' || this.observer === undefined) return;
    const capturePlan: CapturePlan = this.buildCapturePlan();
    const runGeneration: number = ++this.captureRunGeneration;
    this.operationBusy = true;
    this.emergencyMessage = '';
    this.taskStopRequested = false;
    let sessionId: string = '';
    try {
      // 相机设置必须先读取并通过，失败时不创建会话，更不会同步或移动赤道仪。
      if (capturePlan.mode !== CaptureMode.OBSERVE_ONLY) {
        this.cameraPreflightResult = await this.gatewayClient.cameraPreflight(capturePlan);
        if (!this.cameraPreflightResult.ready) {
          this.setCapturePanelVisible(false);
          this.changeActiveSection(2);
          this.operationMessage = `EOS R7 预检未通过：${this.cameraPreflightResult.blockers.join('、')}`;
          return;
        }
      } else {
        this.cameraPreflightResult = undefined;
      }

      const session: TaskSession = this.createTaskSession(capturePlan, target);
      sessionId = session.id;
      await this.saveActiveTaskSession(session);
      this.setCapturePanelVisible(false);
      this.changeActiveSection(2);
      const prepared: PreparedSessionTarget = await this.prepareMountForSession(sessionId, target, runGeneration);
      if (capturePlan.mode === CaptureMode.OBSERVE_ONLY) {
        await this.updateSessionStage(sessionId, WorkflowStage.TRACKING, WorkflowStepState.ACTIVE,
          `${capturePlan.targetName} 已到位，恒星时跟踪已启动`, SessionStatus.RUNNING, 75);
        this.operationMessage = `${capturePlan.targetName} 已到位，恒星时跟踪已启动`;
        return;
      }
      await this.runCameraSession(sessionId, prepared.coordinate, runGeneration, undefined);
    } catch (error) {
      await this.finishActiveSessionFromError(sessionId, runGeneration, error);
    } finally {
      this.operationBusy = false;
    }
  }

  private async prepareMountForSession(sessionId: string, target: CelestialObject,
    runGeneration: number): Promise<PreparedSessionTarget> {
    if (!this.allowRealHardwareAction('准备赤道仪观测')) {
      throw new Error('演练模式禁止准备真实赤道仪');
    }
    if (this.observer === undefined) throw new Error('缺少真实观测地点');
    if (this.mountConnection !== ConnectionState.CONNECTED || !this.mountHomed ||
      !this.mountCoordinatesTopocentric) {
      throw new Error('赤道仪连接、回零或站心坐标模式不满足安全条件');
    }
    await this.updateSessionStage(sessionId, WorkflowStage.SAFETY_CHECK, WorkflowStepState.ACTIVE,
      '正在同步真实地点和设备时间', SessionStatus.PREPARING, 4);
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
    await this.mountClient.setObserver(currentObserver, new Date().getTimezoneOffset() / 60.0);
    this.throwIfCaptureRunCancelled(runGeneration);
    this.locationSynced = true;
    const mountCoordinate: MountTargetCoordinate = ObservationExecutionPolicy.buildMountTarget(
      target, currentObserver, motionTimeMs);
    const coordinate: EquatorialCoordinate | undefined = EphemerisService.skyCoordinate(target, motionTimeMs);
    if (coordinate === undefined) throw new Error('无法生成带坐标帧的目标方向');
    await this.updateSessionStage(sessionId, WorkflowStage.GOTO, WorkflowStepState.ACTIVE,
      `正在 GOTO ${target.designation}`, SessionStatus.PREPARING, 10);
    this.operationMessage = `正在 GOTO ${target.designation}`;
    await this.mountClient.gotoRaDec(mountCoordinate);
    this.throwIfCaptureRunCancelled(runGeneration);
    await this.waitForMountMotion(runGeneration);
    this.throwIfCaptureRunCancelled(runGeneration);
    await this.mountClient.startTracking(TrackingMode.SIDEREAL);
    this.throwIfCaptureRunCancelled(runGeneration);
    this.tracking = true;
    await this.updateSessionStage(sessionId, WorkflowStage.TRACKING, WorkflowStepState.SUCCEEDED,
      '目标已到位，恒星时跟踪已启动', SessionStatus.RUNNING, 14);
    return { target: target, coordinate: coordinate };
  }

  private async runCameraSession(sessionId: string, coordinate: EquatorialCoordinate,
    runGeneration: number, resumeState: CaptureWorkflowResumeState | undefined): Promise<void> {
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.id !== sessionId) throw new Error('活动会话不存在');
    const plan: CapturePlan = active.plan;
    this.taskStatus = TaskStatus.RUNNING;
    this.stackFileUrl = '';
    this.timelapseFileUrl = '';
    this.aiFileUrl = '';
    this.aiModelVersion = '';
    const result: CaptureWorkflowResult = await this.captureWorkflow.run(
      plan, coordinate, (progress: CaptureWorkflowProgress) => {
        if (runGeneration === this.captureRunGeneration || this.taskStopRequested) {
          this.applyWorkflowProgress(sessionId, progress);
        }
      }, async (checkpoint: WorkflowCheckpoint): Promise<void> => {
        await this.persistWorkflowCheckpoint(sessionId, checkpoint);
      }, resumeState);

    let completed: TaskSession | undefined = this.activeTaskSession;
    if (completed === undefined || completed.id !== sessionId) throw new Error('活动会话已结束');
    completed = TaskSessionStore.copySession(completed);
    completed.plateSolveCount = result.plateSolveCount;
    completed.correctionCount = result.correctionCount;
    completed.warnings = this.mergeStrings(completed.warnings, result.warnings);
    this.appendGatewayProducts(completed, result.captureFiles);
    if (result.stackFile !== undefined) this.appendGatewayProduct(completed, result.stackFile);
    if (result.timelapseFile !== undefined) this.appendGatewayProduct(completed, result.timelapseFile);
    this.stackFileUrl = result.stackFile === undefined ? '' : result.stackFile.downloadUrl;
    this.timelapseFileUrl = result.timelapseFile === undefined ? '' : result.timelapseFile.downloadUrl;

    if (plan.enableCloudEnhancement && this.stackFileUrl.length > 0) {
      if (this.aiClient.isConfigured()) {
        try {
          await this.saveActiveTaskSession(completed);
          await this.updateSessionStage(sessionId, WorkflowStage.CLOUD_ENHANCEMENT, WorkflowStepState.ACTIVE,
            '正在提交受约束云增强', SessionStatus.RUNNING, 94);
          const enhancement: EnhancementTask = await this.enhanceStack(this.stackFileUrl, runGeneration);
          this.aiFileUrl = enhancement.resultFileUrl;
          this.aiModelVersion = enhancement.modelVersion;
          completed = this.activeTaskSession === undefined ? completed :
            TaskSessionStore.copySession(this.activeTaskSession);
          completed.products.push({
            kind: 'ai',
            fileName: 'AI 增强结果',
            downloadUrl: enhancement.resultFileUrl,
            createdAtMs: enhancement.updatedAtMs
          });
        } catch (error) {
          completed.warnings.push(`云增强跳过，本地堆栈仍可用：${error}`);
        }
      } else {
        this.aiStatus = '未配置 · 已保留本地结果';
      }
    }
    this.throwIfCaptureRunCancelled(runGeneration);
    completed.status = SessionStatus.SUCCEEDED;
    completed.stage = WorkflowStage.COMPLETE;
    completed.progressPercent = 100;
    completed.statusDetail = completed.warnings.length === 0 ? '拍摄、本地处理与可选增强流程完成' :
      '拍摄完成，部分后处理已降级';
    completed.errorMessage = '';
    completed.updatedAtMs = Date.now();
    completed.completedAtMs = completed.updatedAtMs;
    completed.checkpoint.stage = WorkflowStage.COMPLETE;
    completed.checkpoint.stepState = WorkflowStepState.SUCCEEDED;
    completed.checkpoint.detail = completed.statusDetail;
    this.operationMessage = completed.statusDetail;
    await this.archiveTaskSession(completed);
  }

  private async finishActiveSessionFromError(sessionId: string, runGeneration: number,
    error: Object): Promise<void> {
    const active: TaskSession | undefined = this.activeTaskSession;
    if (sessionId.length === 0 || active === undefined || active.id !== sessionId) {
      this.operationMessage = `任务未创建：${error}`;
      return;
    }
    const failed: TaskSession = TaskSessionStore.copySession(active);
    const cancelled: boolean = runGeneration !== this.captureRunGeneration || this.taskStopRequested ||
      error instanceof CaptureWorkflowCancelledError;
    failed.status = cancelled ? SessionStatus.CANCELLED : SessionStatus.INTERRUPTED;
    failed.checkpoint.stepState = cancelled ? WorkflowStepState.CANCELLED : WorkflowStepState.FAILED;
    failed.errorMessage = `${error}`;
    failed.statusDetail = cancelled ? `会话已取消：${error}` : `会话已中断，等待人工重试：${error}`;
    failed.updatedAtMs = Date.now();
    this.operationMessage = failed.statusDetail;
    try {
      if (cancelled) {
        failed.completedAtMs = failed.updatedAtMs;
        await this.archiveTaskSession(failed);
      } else {
        await this.saveActiveTaskSession(failed);
      }
    } catch (storageError) {
      this.taskStoreWarning = `终态会话保存失败：${storageError}`;
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
      this.refreshActiveTaskSession();
    }, 2000);
  }

  private clearTaskPolling(): void {
    if (this.taskPollTimer >= 0) {
      clearInterval(this.taskPollTimer);
      this.taskPollTimer = -1;
    }
  }

  private async refreshActiveTaskSession(): Promise<void> {
    if (!this.allowRealHardwareAction('刷新真实网关子任务')) return;
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined) return;
    try {
      const reconciliation: CaptureWorkflowReconciliation =
        await this.captureWorkflow.reconcile(active.checkpoint);
      const updated: TaskSession = TaskSessionStore.copySession(active);
      const previousJpegCount: number = updated.jpegFileIds.length;
      updated.checkpoint = reconciliation.checkpoint;
      updated.stage = reconciliation.checkpoint.stage;
      updated.status = reconciliation.sessionStatus === SessionStatus.FAILED ? SessionStatus.INTERRUPTED :
        reconciliation.sessionStatus;
      updated.statusDetail = reconciliation.detail;
      updated.updatedAtMs = Date.now();
      if (reconciliation.childTask !== undefined) {
        updated.progressPercent = Math.max(updated.progressPercent,
          reconciliation.childTask.progressPercent);
        if (!updated.gatewayTaskIds.includes(reconciliation.childTask.taskId)) {
          updated.gatewayTaskIds.push(reconciliation.childTask.taskId);
        }
      }
      this.appendGatewayProducts(updated, reconciliation.files);
      const addedJpegCount: number = Math.max(0, updated.jpegFileIds.length - previousJpegCount);
      if (reconciliation.checkpoint.childKind === GatewaySubtaskKind.CAPTURE &&
        reconciliation.sessionStatus === SessionStatus.WAITING_FOR_USER && addedJpegCount > 0) {
        updated.completedFrames = Math.min(updated.plan.frameCount, updated.completedFrames + 1);
      }
      if (reconciliation.sessionStatus === SessionStatus.CANCELLED) {
        updated.status = SessionStatus.CANCELLED;
        updated.completedAtMs = updated.updatedAtMs;
        await this.archiveTaskSession(updated);
        return;
      }
      await this.saveActiveTaskSession(updated);
      if (reconciliation.monitoring) this.startTaskPolling();
      else this.clearTaskPolling();
    } catch (error) {
      const current: TaskSession | undefined = this.activeTaskSession;
      if (current === undefined) return;
      const interrupted: TaskSession = TaskSessionStore.copySession(current);
      interrupted.status = SessionStatus.INTERRUPTED;
      interrupted.statusDetail = `网关状态读取失败：${error}`;
      interrupted.updatedAtMs = Date.now();
      try {
        await this.saveActiveTaskSession(interrupted);
      } catch (storageError) {
        this.taskStoreWarning = `恢复状态保存失败：${storageError}`;
      }
    }
  }

  private async continueActiveTaskSession(): Promise<void> {
    if (!this.allowRealHardwareAction('继续真实观测会话')) return;
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || this.operationBusy) return;
    const target: CelestialObject = this.sessionTarget(active);
    if (target.id === 'solar-sun') {
      this.operationMessage = '太阳永久禁止普通 GOTO';
      return;
    }
    const runGeneration: number = ++this.captureRunGeneration;
    this.operationBusy = true;
    this.taskStopRequested = false;
    try {
      const remainingCapture: boolean = active.kind !== SessionKind.OBSERVATION &&
        active.completedFrames < active.plan.frameCount;
      if (remainingCapture) {
        this.cameraPreflightResult = await this.gatewayClient.cameraPreflight(active.plan);
        if (!this.cameraPreflightResult.ready) {
          const blocked: TaskSession = TaskSessionStore.copySession(active);
          blocked.status = SessionStatus.INTERRUPTED;
          blocked.statusDetail = `EOS R7 预检未通过：${this.cameraPreflightResult.blockers.join('、')}`;
          blocked.updatedAtMs = Date.now();
          await this.saveActiveTaskSession(blocked);
          return;
        }
      }
      let coordinate: EquatorialCoordinate | undefined = EphemerisService.skyCoordinate(target, Date.now());
      if (remainingCapture || active.kind === SessionKind.OBSERVATION) {
        const prepared: PreparedSessionTarget = await this.prepareMountForSession(active.id, target, runGeneration);
        coordinate = prepared.coordinate;
      }
      if (active.kind === SessionKind.OBSERVATION) {
        await this.updateSessionStage(active.id, WorkflowStage.TRACKING, WorkflowStepState.ACTIVE,
          `${active.target.name} 已恢复观测，恒星时跟踪已启动`, SessionStatus.RUNNING, 75);
        return;
      }
      if (coordinate === undefined) throw new Error('无法恢复目标坐标');
      const resumeState: CaptureWorkflowResumeState = await this.buildResumeState(active);
      await this.runCameraSession(active.id, coordinate, runGeneration, resumeState);
    } catch (error) {
      await this.finishActiveSessionFromError(active.id, runGeneration, error);
    } finally {
      this.operationBusy = false;
    }
  }

  private async buildResumeState(session: TaskSession): Promise<CaptureWorkflowResumeState> {
    const files: GatewayFile[] = [];
    const seen: Set<string> = new Set<string>();
    for (let taskIndex: number = 0; taskIndex < session.gatewayTaskIds.length; taskIndex++) {
      const taskFiles: GatewayFile[] = await this.gatewayClient.listFiles(session.gatewayTaskIds[taskIndex], 20);
      for (let fileIndex: number = 0; fileIndex < taskFiles.length; fileIndex++) {
        const file: GatewayFile = taskFiles[fileIndex];
        if (!seen.has(file.id)) {
          files.push(file);
          seen.add(file.id);
        }
      }
    }
    return {
      completedFrames: session.completedFrames,
      captureFiles: files,
      jpegFileIds: session.jpegFileIds.slice(),
      rawFileIds: session.rawFileIds.slice(),
      plateSolveCount: session.plateSolveCount,
      correctionCount: session.correctionCount,
      warnings: session.warnings.slice()
    };
  }

  private sessionTarget(session: TaskSession): CelestialObject {
    const catalogTarget: CelestialObject | undefined = CelestialCatalog.getById(session.target.id);
    if (catalogTarget !== undefined) return catalogTarget;
    return {
      id: session.target.id,
      type: session.target.type,
      nameZh: session.target.name,
      nameEn: session.target.designation,
      designation: session.target.designation,
      constellation: '',
      coordinate: session.target.coordinate,
      description: '从冻结任务会话恢复的目标',
      tags: [session.target.name, session.target.designation],
      precision: session.target.precision,
      gotoAllowed: session.target.gotoAllowed,
      recommendedFor18mm: true
    };
  }

  private appendGatewayProducts(session: TaskSession, files: GatewayFile[]): void {
    for (let index: number = 0; index < files.length; index++) {
      this.appendGatewayProduct(session, files[index]);
    }
  }

  private appendGatewayProduct(session: TaskSession, file: GatewayFile): void {
    let exists: boolean = false;
    for (let index: number = 0; index < session.products.length; index++) {
      if (session.products[index].downloadUrl === file.downloadUrl) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      session.products.push({
        kind: file.kind,
        fileName: file.name,
        downloadUrl: file.downloadUrl,
        createdAtMs: file.createdAtMs
      });
    }
    const lowerName: string = file.name.toLowerCase();
    if ((file.mimeType.toLowerCase() === 'image/jpeg' || lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg')) && !session.jpegFileIds.includes(file.id)) {
      session.jpegFileIds.push(file.id);
    }
    if ((file.kind === 'raw' || lowerName.endsWith('.cr3')) && !session.rawFileIds.includes(file.id)) {
      session.rawFileIds.push(file.id);
    }
  }

  private mergeStrings(left: string[], right: string[]): string[] {
    const result: string[] = left.slice();
    for (let index: number = 0; index < right.length; index++) {
      if (!result.includes(right[index])) result.push(right[index]);
    }
    return result;
  }

  private async endObservationSession(): Promise<void> {
    if (!this.allowRealHardwareAction('结束真实观测会话')) return;
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.kind !== SessionKind.OBSERVATION ||
      active.status !== SessionStatus.RUNNING || this.operationBusy) return;
    this.operationBusy = true;
    const completed: TaskSession = TaskSessionStore.copySession(active);
    try {
      if (this.mountConnection === ConnectionState.CONNECTED) {
        await this.mountClient.stopTracking();
        this.tracking = false;
      }
      completed.status = SessionStatus.SUCCEEDED;
      completed.stage = WorkflowStage.COMPLETE;
      completed.progressPercent = 100;
      completed.statusDetail = '观测会话已结束并归档';
      completed.errorMessage = '';
      completed.checkpoint.stage = WorkflowStage.COMPLETE;
      completed.checkpoint.stepState = WorkflowStepState.SUCCEEDED;
      completed.checkpoint.detail = completed.statusDetail;
    } catch (error) {
      completed.status = SessionStatus.FAILED;
      completed.statusDetail = `观测会话结束时停止跟踪失败：${error}`;
      completed.errorMessage = `${error}`;
      completed.checkpoint.stepState = WorkflowStepState.FAILED;
    }
    completed.updatedAtMs = Date.now();
    completed.completedAtMs = completed.updatedAtMs;
    await this.archiveTaskSession(completed);
    this.operationBusy = false;
  }

  private async archiveInterruptedTaskSession(): Promise<void> {
    if (this.simulationActive()) {
      this.reportDeviceOperation('演练会话不会写入真实历史，无需归档');
      return;
    }
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || (active.status !== SessionStatus.INTERRUPTED &&
      active.status !== SessionStatus.WAITING_FOR_USER) || this.operationBusy) return;
    const archived: TaskSession = TaskSessionStore.copySession(active);
    archived.status = SessionStatus.FAILED;
    archived.checkpoint.stepState = WorkflowStepState.FAILED;
    archived.statusDetail = archived.errorMessage.length > 0 ? archived.statusDetail :
      '用户结束了未完成会话';
    archived.errorMessage = archived.errorMessage.length > 0 ? archived.errorMessage : '会话由用户结束并归档';
    archived.updatedAtMs = Date.now();
    archived.completedAtMs = archived.updatedAtMs;
    await this.archiveTaskSession(archived);
  }

  private async cancelActiveTask(): Promise<void> {
    if (!this.allowRealHardwareAction('停止真实拍摄任务')) return;
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active === undefined || active.kind === SessionKind.OBSERVATION ||
      (active.status !== SessionStatus.PREPARING && active.status !== SessionStatus.RUNNING) ||
      this.taskStopRequested) return;
    this.taskStopRequested = true;
    try {
      if (active.stage === WorkflowStage.SAFETY_CHECK || active.stage === WorkflowStage.GOTO ||
        active.stage === WorkflowStage.TRACKING) {
        this.captureRunGeneration++;
        await this.mountClient.abort();
      } else {
        await this.captureWorkflow.cancel();
      }
      const current: TaskSession | undefined = this.activeTaskSession;
      if (current !== undefined) {
        const stopping: TaskSession = TaskSessionStore.copySession(current);
        stopping.statusDetail = '正在完成当前曝光，后续帧已停止';
        stopping.updatedAtMs = Date.now();
        await this.saveActiveTaskSession(stopping);
      }
      this.operationMessage = '正在完成当前曝光，后续帧已停止';
    } catch (error) {
      this.operationMessage = `停止后续曝光未获完整确认：${error}`;
    }
  }

  private async triggerEmergencyStop(): Promise<void> {
    if (this.simulationActive()) {
      // 演练急停只能终止内存回放，绝不复用真实急停客户端。
      this.digitalTwinReplayService.stop();
      this.digitalTwinPlaying = false;
      this.tracking = false;
      this.mountSlewing = false;
      this.emergencyMessage = '演练回放已停止；未向赤道仪、相机或网关发送急停指令';
      this.deviceOperationMessage = this.emergencyMessage;
      this.operationMessage = this.emergencyMessage;
      return;
    }
    // 先同步废止当前拍摄代次并触发两条链路，再分别等待结果；任一链路失败都不能阻止另一条急停。
    this.captureRunGeneration++;
    this.emergencyMessage = '正在发送软件急停；物理急停仍需人工确认';
    this.tracking = false;
    const captureWasRunning: boolean = this.taskStatus === TaskStatus.RUNNING;
    if (captureWasRunning) {
      this.taskStatus = TaskStatus.CANCELLED;
      this.taskStopRequested = true;
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
    const active: TaskSession | undefined = this.activeTaskSession;
    if (active !== undefined && active.kind === SessionKind.OBSERVATION) {
      const cancelled: TaskSession = TaskSessionStore.copySession(active);
      cancelled.status = SessionStatus.CANCELLED;
      cancelled.checkpoint.stepState = WorkflowStepState.CANCELLED;
      cancelled.statusDetail = '观测会话已由软件急停结束；请确认物理急停';
      cancelled.errorMessage = errors.join('；');
      cancelled.updatedAtMs = Date.now();
      cancelled.completedAtMs = cancelled.updatedAtMs;
      try {
        await this.archiveTaskSession(cancelled);
      } catch (storageError) {
        this.taskStoreWarning = `急停会话保存失败：${storageError}`;
      }
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

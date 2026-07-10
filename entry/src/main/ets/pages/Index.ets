import { common } from '@kit.AbilityKit';
import { DeviceCameraPreview } from '../components/DeviceCameraPreview';
import { CelestialCatalog } from '../data';
import {
  ArCalibration,
  CameraCapabilities,
  CameraViewport,
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
  ObserverState,
  ScreenProjection,
  TrackingMode,
  TaskStatus
} from '../models';
import {
  AstronomyService,
  AIEnhancementClient,
  CameraHandFrameSource,
  CaptureWorkflowCoordinator,
  CaptureWorkflowProgress,
  CaptureWorkflowResult,
  DevicePoseService,
  GatewayTask,
  GestureInterpreter,
  HandFrameSourceStatus,
  HandLandmarkAnalysisResult,
  ObserverLocationResult,
  ObserverLocationService,
  OnStepLX200Client,
  ProjectedVisibleStar,
  RaspberryPiClient,
  VisibleStar,
  VisibleStarCatalogMetadata,
  VisibleStarCatalogService,
  UnavailableHandLandmarkAnalyzer
} from '../services';

interface NavigationItem {
  id: number;
  icon: string;
  label: string;
}

interface DisplayStar {
  id: string;
  name: string;
  x: number;
  y: number;
  size: number;
  color: string;
  catalogStar?: VisibleStar;
}

interface DeviceLine {
  name: string;
  detail: string;
  state: string;
  color: string;
}

interface ProjectedTarget {
  targetId: string;
  x: number;
  y: number;
}

const UI_TARGETS: CelestialObject[] = [
  {
    id: 'vega', type: CelestialType.STAR, nameZh: '织女星', nameEn: 'Vega', designation: 'α Lyr',
    constellation: '天琴座', coordinate: { raHours: 18.616, decDegrees: 38.783, epoch: 2000 }, magnitude: 0.03,
    angularSizeDegrees: 0, description: '夏季大三角中最明亮的恒星，适合作为 AR 和赤道仪同步基准。',
    tags: ['亮星', '校准'], precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: true
  },
  {
    id: 'altair', type: CelestialType.STAR, nameZh: '牛郎星', nameEn: 'Altair', designation: 'α Aql',
    constellation: '天鹰座', coordinate: { raHours: 19.846, decDegrees: 8.868, epoch: 2000 }, magnitude: 0.77,
    angularSizeDegrees: 0, description: '距离太阳约 16.7 光年，是夏季大三角的南侧顶点。',
    tags: ['亮星', '广角'], precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: true
  },
  {
    id: 'deneb', type: CelestialType.STAR, nameZh: '天津四', nameEn: 'Deneb', designation: 'α Cyg',
    constellation: '天鹅座', coordinate: { raHours: 20.691, decDegrees: 45.280, epoch: 2000 }, magnitude: 1.25,
    angularSizeDegrees: 0, description: '天鹅座最亮星，位于银河背景中，适合 18mm 广角构图。',
    tags: ['银河', '广角'], precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: true
  },
  {
    id: 'm31', type: CelestialType.MESSIER, nameZh: '仙女座星系', nameEn: 'Andromeda Galaxy', designation: 'M31',
    constellation: '仙女座', coordinate: { raHours: 0.712, decDegrees: 41.269, epoch: 2000 }, magnitude: 3.44,
    angularSizeDegrees: 3.17, description: '距离银河系最近的大型旋涡星系，广角照片中呈现为小型椭圆光斑。',
    tags: ['星系', '秋季'], precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: false
  },
  {
    id: 'm8', type: CelestialType.MESSIER, nameZh: '礁湖星云', nameEn: 'Lagoon Nebula', designation: 'M8',
    constellation: '人马座', coordinate: { raHours: 18.063, decDegrees: -24.386, epoch: 2000 }, magnitude: 6.0,
    angularSizeDegrees: 1.5, description: '银河中心方向的大型发射星云，可与周围银河共同进行广角构图。',
    tags: ['星云', '银河'], precision: CatalogPrecision.EXACT, gotoAllowed: true, recommendedFor18mm: true
  },
  {
    id: 'moon', type: CelestialType.MOON, nameZh: '月球', nameEn: 'Moon', designation: 'Moon',
    constellation: '动态位置', magnitude: -10.4, angularSizeDegrees: 0.5,
    description: '月球位置随观测时间动态计算；月光会显著影响城市星空长曝光。', tags: ['太阳系', '动态'],
    precision: CatalogPrecision.DYNAMIC, gotoAllowed: true, recommendedFor18mm: true
  }
];

const DISPLAY_STARS: DisplayStar[] = [
  { id: 's1', name: '织女星', x: 378, y: 138, size: 9, color: '#FFFFFF' },
  { id: 's2', name: '天津四', x: 468, y: 204, size: 7, color: '#D8ECFF' },
  { id: 's3', name: '牛郎星', x: 315, y: 346, size: 8, color: '#FFF3D1' },
  { id: 's4', name: '', x: 185, y: 110, size: 4, color: '#B9D5F0' },
  { id: 's5', name: '', x: 118, y: 260, size: 3, color: '#D8ECFF' },
  { id: 's6', name: '', x: 535, y: 92, size: 4, color: '#B9D5F0' },
  { id: 's7', name: '', x: 565, y: 318, size: 3, color: '#FFF3D1' },
  { id: 's8', name: '', x: 242, y: 414, size: 3, color: '#B9D5F0' },
  { id: 's9', name: '', x: 92, y: 72, size: 2, color: '#D8ECFF' },
  { id: 's10', name: '', x: 505, y: 432, size: 3, color: '#D8ECFF' }
];

@Entry
@Component
struct Index {
  @State private activeSection: number = 0;
  @State private skyMode: number = 0;
  @State private selectedTargetId: string = 'vega';
  @State private targetSearch: string = '';
  @State private gestureEnabled: boolean = false;
  @State private gestureStatus: string = '未启用';
  @State private mapOffsetX: number = 0;
  @State private mapOffsetY: number = 0;
  @State private mapScale: number = 1;
  @State private mapRotation: number = 0;
  @State private skyViewportWidth: number = 600;
  @State private skyViewportHeight: number = 500;
  @State private calibrationEnabled: boolean = false;
  @State private calibrationText: string = '未校准';
  @State private mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @State private gatewayConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @State private mountHomed: boolean = false;
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
  @State private mountRaHours: number = 0;
  @State private mountDecDegrees: number = 0;
  @State private mountSlewing: boolean = false;
  @State private gatewayDetail: string = '10.42.0.1:8000';
  @State private taskStage: string = '等待创建';
  @State private activeTaskId: string = '';
  @State private projectedTargets: ProjectedTarget[] = [];
  @State private projectedStars: DisplayStar[] = [];
  @State private normalStars: DisplayStar[] = [];
  @State private normalTargets: ProjectedTarget[] = [];
  @State private catalogStatus: string = '星表加载中';
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

  private observer: ObserverState | undefined = undefined;
  private selectedCustomTarget: CelestialObject | undefined = undefined;
  private calibration: ArCalibration | undefined = undefined;
  private cameraCapabilities: CameraCapabilities | undefined = undefined;
  private mountPollTimer: number = -1;
  private taskPollTimer: number = -1;
  private readonly mountClient: OnStepLX200Client = new OnStepLX200Client();
  private readonly gatewayClient: RaspberryPiClient = new RaspberryPiClient();
  private readonly aiClient: AIEnhancementClient = new AIEnhancementClient();
  private readonly captureWorkflow: CaptureWorkflowCoordinator =
    new CaptureWorkflowCoordinator(this.mountClient, this.gatewayClient);
  private readonly poseService: DevicePoseService = new DevicePoseService();
  private readonly visibleStarCatalog: VisibleStarCatalogService = new VisibleStarCatalogService();
  private readonly gestureInterpreter: GestureInterpreter = new GestureInterpreter();
  private readonly handFrameSource: CameraHandFrameSource = new CameraHandFrameSource(
    new UnavailableHandLandmarkAnalyzer(),
    (result: HandLandmarkAnalysisResult) => { this.applyHandLandmarks(result); },
    (status: HandFrameSourceStatus) => {
      if (this.gestureEnabled) {
        this.gestureStatus = status.message;
      }
    });
  private lastProjectionAtMs: number = 0;
  // 每次开始拍摄分配一个代次；取消或急停递增代次，使所有 await 之后的旧流程立即失效。
  private captureRunGeneration: number = 0;
  private panStartOffsetX: number = 0;
  private panStartOffsetY: number = 0;
  private pinchStartScale: number = 1;
  private rotationStartAngle: number = 0;
  private readonly arViewport: CameraViewport = {
    widthPixels: 600,
    heightPixels: 500,
    horizontalFovDegrees: 66,
    verticalFovDegrees: 44
  };

  private navigation: NavigationItem[] = [
    { id: 0, icon: '✦', label: '星图' },
    { id: 1, icon: '⌁', label: '设备' },
    { id: 2, icon: '◉', label: '任务' },
    { id: 3, icon: '▧', label: '后期' }
  ];

  aboutToAppear(): void {
    try {
      this.poseService.start((pose: DevicePose) => {
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
    this.refreshLocation();
    this.loadVisibleStarCatalog();
  }

  aboutToDisappear(): void {
    this.poseService.stop();
    this.clearMountPolling();
    this.clearTaskPolling();
    this.visibleStarCatalog.clear();
    this.handFrameSource.close();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        this.Sidebar()

        Column() {
          this.Header()
          if (this.activeSection === 0) {
            this.SkyWorkspace()
          } else if (this.activeSection === 1) {
            this.DeviceWorkspace()
          } else if (this.activeSection === 2) {
            this.TaskWorkspace()
          } else {
            this.PostWorkspace()
          }
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor('#080A10')
      }
      .width('100%')
      .height('100%')

      if (this.showCapturePanel) {
        this.CaptureOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#080A10')
  }

  @Builder
  private Sidebar() {
    Column() {
      Column({ space: 3 }) {
        Text('StarFinding')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4F7FB')
          .width('100%')
        Text('星空智控')
          .fontSize(12)
          .fontColor('#7F8A9E')
          .width('100%')
      }
      .margin({ bottom: 28 })

      ForEach(this.navigation, (item: NavigationItem) => {
        Row({ space: 11 }) {
          Text(item.icon)
            .fontSize(17)
            .fontColor(this.activeSection === item.id ? '#061017' : '#93A0B5')
            .width(24)
            .textAlign(TextAlign.Center)
          Text(item.label)
            .fontSize(15)
            .fontWeight(this.activeSection === item.id ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.activeSection === item.id ? '#061017' : '#C9D1DF')
        }
        .width('100%')
        .height(46)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .backgroundColor(this.activeSection === item.id ? '#72D3F5' : 'transparent')
        .onClick(() => {
          this.activeSection = item.id;
        })
      }, (item: NavigationItem) => item.id.toString())

      Blank()

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Circle().width(8).height(8).fill(this.connectionColor(this.mountConnection))
          Text('赤道仪').fontSize(12).fontColor('#AAB4C8')
          Blank()
          Text(this.connectionText(this.mountConnection)).fontSize(12).fontColor('#E5E9F0')
        }.width('100%')
        Row({ space: 8 }) {
          Circle().width(8).height(8).fill(this.connectionColor(this.gatewayConnection))
          Text('相机网关').fontSize(12).fontColor('#AAB4C8')
          Blank()
          Text(this.connectionText(this.gatewayConnection)).fontSize(12).fontColor('#E5E9F0')
        }.width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#14171D')
      .borderRadius(6)
      .margin({ bottom: 12 })

      Button('■  全局急停')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#C83D47')
        .borderRadius(6)
        .onClick(() => {
          this.triggerEmergencyStop();
        })
      if (this.emergencyMessage.length > 0) {
        Text(this.emergencyMessage)
          .fontSize(10)
          .lineHeight(15)
          .fontColor('#FF9DA4')
          .width('100%')
          .margin({ top: 8 })
      } else if (this.operationMessage.length > 0) {
        Text(this.operationMessage)
          .fontSize(10)
          .lineHeight(15)
          .fontColor('#8FA0B6')
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width(178)
    .height('100%')
    .padding({ left: 18, right: 16, top: 22, bottom: 18 })
    .backgroundColor('#0E1117')
    .border({ width: { right: 1 }, color: '#242A34' })
  }

  @Builder
  private Header() {
    Row({ space: 16 }) {
      Column({ space: 3 }) {
        Text(this.sectionTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4F7FB')
          .width('100%')
        Text(this.sectionSubtitle())
          .fontSize(12)
          .fontColor('#8793A7')
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

      this.HeaderStatus('位置', this.locationText, this.observer === undefined ? '#F4BA58' : '#57C995')
      this.HeaderStatus('时间', this.currentTimeText(), '#72D3F5')
    }
    .width('100%')
    .height(76)
    .padding({ left: 20, right: 20 })
    .border({ width: { bottom: 1 }, color: '#20252E' })
  }

  @Builder
  private ModeButton(label: string, mode: number) {
    Button(label)
      .height(34)
      .padding({ left: 16, right: 16 })
      .fontSize(13)
      .fontWeight(this.skyMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.skyMode === mode ? '#061017' : '#AAB4C8')
      .backgroundColor(this.skyMode === mode ? '#72D3F5' : 'transparent')
      .borderRadius(4)
      .onClick(() => {
        this.skyMode = mode;
        if (mode === 0) {
          this.gestureEnabled = false;
          this.gestureStatus = '未启用';
          this.gestureInterpreter.reset();
        }
      })
  }

  @Builder
  private HeaderStatus(label: string, value: string, color: string) {
    Row({ space: 8 }) {
      Circle().width(7).height(7).fill(color)
      Column({ space: 1 }) {
        Text(label).fontSize(10).fontColor('#778397').width('100%')
        Text(value).fontSize(12).fontColor('#DDE3EC').width('100%')
      }
    }
    .height(40)
    .padding({ left: 11, right: 11 })
    .backgroundColor('#131720')
    .borderRadius(5)
  }

  @Builder
  private SkyWorkspace() {
    Row({ space: 14 }) {
      Stack() {
        if (this.skyMode === 0) {
          DeviceCameraPreview({ useFrontCamera: false, cornerRadius: 7 })
        } else {
          Rect().width('100%').height('100%').fill('#05070B')
          this.NormalMapLayer()
        }

        if (this.skyMode === 0) {
          ForEach(this.projectedStars, (star: DisplayStar) => {
            this.StarPoint(star)
          }, (star: DisplayStar) => star.id)
          ForEach(this.projectedTargets, (projected: ProjectedTarget) => {
            this.TargetMarker(this.targetById(projected.targetId), projected.x, projected.y)
          }, (projected: ProjectedTarget) => projected.targetId)
        }

        Text('+')
          .fontSize(24)
          .fontColor('#72D3F5')
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .position({ x: this.skyViewportWidth / 2.0 - 15.0, y: this.skyViewportHeight / 2.0 - 15.0 })

        Row({ space: 8 }) {
          Text(this.skyMode === 0 ? '后摄 AR' : '天球投影')
            .fontSize(11).fontColor('#DDE3EC')
          Text(this.poseReady ? `方位 ${this.poseHeading.toFixed(0)}°` : '方位 --')
            .fontSize(11).fontColor('#8D99AD')
          Text(this.poseReady ? `高度 ${this.posePitch.toFixed(0)}°` : '高度 --')
            .fontSize(11).fontColor('#8D99AD')
          Blank()
          Text(this.calibrationText)
            .fontSize(11)
            .fontColor(this.calibrationEnabled ? '#57C995' : '#F4BA58')
          Text(this.catalogStatus).fontSize(10).fontColor('#6F7D91')
        }
        .width('100%')
        .height(38)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#0B0E14')
        .position({ x: 0, y: this.skyViewportHeight })

        if (this.skyMode === 1 && this.gestureEnabled) {
          Row({ space: 10 }) {
            DeviceCameraPreview({
              useFrontCamera: true,
              cornerRadius: 5,
              handFrameSource: this.handFrameSource
            })
              .width(150)
              .height(96)
            Column({ space: 5 }) {
              Text('手势控制').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              Text(this.gestureStatus).fontSize(11).fontColor('#72D3F5')
              Text('模型接入后启用；触控始终可用').fontSize(10).fontColor('#8D99AD')
            }
          }
          .padding(7)
          .backgroundColor('#111720')
          .border({ width: 1, color: '#2D4657' })
          .borderRadius(6)
          .position({ x: 14, y: Math.max(14, this.skyViewportHeight - 112) })
        }
      }
      .layoutWeight(1)
      .height('100%')
      .constraintSize({ minWidth: 560 })
      .backgroundColor('#05070B')
      .borderRadius(7)
      .clip(true)
      .border({ width: 1, color: '#202731' })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width);
        const fullHeight: number = Number(newValue.height);
        const contentHeight: number = fullHeight - 38.0;
        if (!Number.isFinite(width) || !Number.isFinite(contentHeight) || width < 1.0 || contentHeight < 1.0) {
          return;
        }
        if (Math.abs(width - this.skyViewportWidth) < 0.5 &&
          Math.abs(contentHeight - this.skyViewportHeight) < 0.5) {
          return;
        }
        // 投影坐标必须跟随真实布局尺寸；FOV 仍需在具体 Pad 上用后摄标定值替换默认值。
        this.skyViewportWidth = width;
        this.skyViewportHeight = contentHeight;
        this.arViewport.widthPixels = width;
        this.arViewport.heightPixels = contentHeight;
        this.updateNormalMap();
        this.updateProjectedTargets(true);
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture({ fingers: 1, direction: PanDirection.All })
            .onActionStart(() => {
              this.panStartOffsetX = this.mapOffsetX;
              this.panStartOffsetY = this.mapOffsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.skyMode === 1) {
                this.mapOffsetX = this.panStartOffsetX + event.offsetX;
                this.mapOffsetY = this.panStartOffsetY + event.offsetY;
              }
            }),
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.pinchStartScale = this.mapScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.skyMode === 1) {
                this.mapScale = Math.max(0.6, Math.min(3, this.pinchStartScale * event.scale));
              }
            }),
          RotationGesture({ fingers: 2 })
            .onActionStart(() => {
              this.rotationStartAngle = this.mapRotation;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.skyMode === 1) {
                this.mapRotation = this.rotationStartAngle + event.angle;
              }
            })
        )
      )

      this.TargetPanel()
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 18 })
  }

  @Builder
  private NormalMapLayer() {
    Stack() {
      ForEach([1, 2, 3, 4], (item: number) => {
        Circle()
          .width(item * 118)
          .height(item * 118)
          .fill('transparent')
          .stroke('#1D2731')
          .strokeWidth(1)
          .position({
            x: this.skyViewportWidth / 2.0 - item * 59,
            y: this.skyViewportHeight / 2.0 - item * 59
          })
      })
      Rect().width(1).height(Math.max(1, this.skyViewportHeight - 20)).fill('#1D2731')
        .position({ x: this.skyViewportWidth / 2.0, y: 10 })
      Rect().width(Math.max(1, this.skyViewportWidth - 30)).height(1).fill('#1D2731')
        .position({ x: 15, y: this.skyViewportHeight / 2.0 })

      ForEach(this.normalStars, (star: DisplayStar) => {
        this.StarPoint(star)
      }, (star: DisplayStar) => star.id)
      ForEach(this.normalTargets, (projected: ProjectedTarget) => {
        this.TargetMarker(this.targetById(projected.targetId), projected.x, projected.y)
      }, (projected: ProjectedTarget) => projected.targetId)
    }
    .width('100%')
    .height('100%')
    .translate({ x: this.mapOffsetX, y: this.mapOffsetY })
    .scale({ x: this.mapScale, y: this.mapScale })
    .rotate({ angle: this.mapRotation })
  }

  @Builder
  private StarPoint(star: DisplayStar) {
    Column({ space: 2 }) {
      Circle().width(star.size).height(star.size).fill(star.color)
      if (star.name.length > 0) {
        Text(star.name).fontSize(9).fontColor('#BFC9D8')
      }
    }
    .position({ x: star.x, y: star.y })
    .onClick(() => {
      if (star.catalogStar === undefined) {
        return;
      }
      this.selectedCustomTarget = this.visibleStarCatalog.toCelestialObject(star.catalogStar);
      this.selectedTargetId = this.selectedCustomTarget.id;
      this.operationMessage = `已选择 ${this.selectedCustomTarget.nameZh}`;
      if (this.skyMode === 1) {
        this.updateNormalMap();
      }
    })
  }

  @Builder
  private TargetMarker(target: CelestialObject, x: number, y: number) {
    Row({ space: 5 }) {
      Circle()
        .width(target.id === this.selectedTargetId ? 12 : 8)
        .height(target.id === this.selectedTargetId ? 12 : 8)
        .fill(target.id === this.selectedTargetId ? '#72D3F5' : '#F4BA58')
        .stroke('#071017')
        .strokeWidth(2)
      Text(target.designation)
        .fontSize(11)
        .fontWeight(target.id === this.selectedTargetId ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(target.id === this.selectedTargetId ? '#72D3F5' : '#E4E9F1')
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .backgroundColor('#10141B')
        .borderRadius(3)
    }
    .position({ x: x - 4, y: y - 4 })
    .onClick(() => {
      this.selectedCustomTarget = undefined;
      this.selectedTargetId = target.id;
      this.updateNormalMap();
    })
  }

  @Builder
  private TargetPanel() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索天体、星座或编号', text: this.targetSearch })
          .layoutWeight(1)
          .height(38)
          .fontSize(12)
          .fontColor('#F0F3F8')
          .placeholderColor('#667287')
          .backgroundColor('#0C1016')
          .border({ width: 1, color: '#2A313C' })
          .borderRadius(5)
          .onChange((value: string) => {
            this.targetSearch = value;
          })
        Button('⌕')
          .width(38).height(38).fontSize(18)
          .fontColor('#091118').backgroundColor('#72D3F5').borderRadius(5)
          .onClick(() => { this.performTargetSearch(); })
      }

      Column({ space: 4 }) {
        Row() {
          Text(this.selectedTarget().nameZh)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#F4F7FB')
          Blank()
          Text(this.selectedTarget().designation)
            .fontSize(12).fontColor('#061017')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#F4BA58').borderRadius(4)
        }.width('100%')
        Text(this.selectedTarget().nameEn + ' · ' + this.selectedTarget().constellation)
          .fontSize(12).fontColor('#8995A8').width('100%')
      }.width('100%')

      Row() {
        this.TargetMetric('星等', this.magnitudeText())
        this.TargetMetric('高度', this.targetAltitudeText())
        this.TargetMetric('方位', this.targetAzimuthText())
      }
      .width('100%')
      .height(55)
      .backgroundColor('#0D1118')
      .borderRadius(5)

      Text(this.selectedTarget().description)
        .fontSize(12)
        .lineHeight(19)
        .fontColor('#BCC5D3')
        .width('100%')

      Column({ space: 8 }) {
        this.InfoLine('赤经 / 赤纬', this.coordinateText())
        this.InfoLine('角尺寸', this.angularSizeText())
        this.InfoLine('18mm 适配', this.selectedTarget().recommendedFor18mm ? '推荐广角拍摄' : '可观测，不建议作为广角主体')
        this.InfoLine('建议参数', this.selectedTarget().recommendedFor18mm ? '15s · ISO 800 · 20 张' : '仅 GOTO 观测')
      }
      .width('100%')

      Row() {
        Text(this.selectedTarget().recommendedFor18mm ? '适合当前设备' : '目标尺寸较小')
          .fontSize(11)
          .fontColor(this.selectedTarget().recommendedFor18mm ? '#57C995' : '#F4BA58')
        Blank()
        Text('实时可见').fontSize(11).fontColor('#72D3F5')
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#111820')
      .borderRadius(5)

      if (this.skyMode === 0) {
        Row({ space: 8 }) {
          Button(this.calibrationEnabled ? '重新一星校准' : '一星校准')
            .layoutWeight(1).height(38).fontSize(12)
            .fontColor('#DDE3EC').backgroundColor('#242A34').borderRadius(5)
            .onClick(() => { this.calibrateSelectedTarget(); })
          Button('重新定位')
            .layoutWeight(1).height(38).fontSize(12)
            .fontColor('#DDE3EC').backgroundColor('#242A34').borderRadius(5)
            .onClick(() => { this.refreshLocation(); })
        }
      } else {
        Row() {
          Text('前摄手势控制').fontSize(12).fontColor('#C6CEDA')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.gestureEnabled })
            .selectedColor('#57C995')
            .onChange((value: boolean) => {
              this.gestureEnabled = value;
              // 当前仓库没有经过授权和精度验收的手部关键点模型，不能把前摄预览冒充为识别结果。
              this.gestureStatus = value ? '等待手部模型' : '未启用';
              if (!value) {
                this.gestureInterpreter.reset();
              }
            })
        }.width('100%').height(38)
      }

      Blank()

      Button('拍摄 / 观测')
        .width('100%').height(46)
        .fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor('#061017').backgroundColor('#72D3F5').borderRadius(6)
        .onClick(() => {
          this.showCapturePanel = true;
        })
    }
    .width(322)
    .height('100%')
    .padding(16)
    .backgroundColor('#11141A')
    .borderRadius(7)
    .border({ width: 1, color: '#252B34' })
  }

  @Builder
  private TargetMetric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(10).fontColor('#778397')
      Text(value).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#E9EDF3')
    }.layoutWeight(1)
  }

  @Builder
  private InfoLine(label: string, value: string) {
    Row() {
      Text(label).fontSize(11).fontColor('#788497')
      Blank()
      Text(value).fontSize(11).fontColor('#D3DAE5').textAlign(TextAlign.End)
    }.width('100%')
  }

  @Builder
  private DeviceWorkspace() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 14 }) {
          this.ConnectionPanel('赤道仪', 'OnStepX · TCP 9999', this.mountConnection, () => {
            this.toggleMountConnection();
          })
          this.ConnectionPanel('相机网关', this.gatewayDetail, this.gatewayConnection, () => {
            this.toggleGatewayConnection();
          })
        }.width('100%')

        Row({ space: 14 }) {
          Column({ space: 14 }) {
            this.PanelTitle('赤道仪操作', '自动运动前必须完成两轴回零和位置时间同步')
            Row({ space: 10 }) {
              this.ActionButton('⌂', '两轴回零', this.mountConnection === ConnectionState.CONNECTED, () => {
                this.homeMount();
              })
              this.ActionButton('◎', '同步位置', this.mountConnection === ConnectionState.CONNECTED &&
                this.observer !== undefined, () => { this.syncObserverToMount(); })
              this.ActionButton('▶', this.tracking ? '停止跟踪' : '恒星跟踪',
                this.mountHomed && this.locationSynced, () => {
                this.toggleTracking();
              })
              this.ActionButton('P', '停放设备', this.mountHomed, () => {
                this.parkMount();
              })
            }.width('100%')

            Column({ space: 9 }) {
              ForEach(this.deviceLines(), (line: DeviceLine) => {
                Row({ space: 10 }) {
                  Circle().width(8).height(8).fill(line.color)
                  Text(line.name).fontSize(12).fontColor('#AEB8C8').width(100)
                  Text(line.detail).fontSize(12).fontColor('#E2E7EE').layoutWeight(1)
                  Text(line.state).fontSize(11).fontColor(line.color)
                }.width('100%').height(34)
              }, (line: DeviceLine) => line.name)
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#0C1016')
            .borderRadius(5)
          }
          .layoutWeight(1)
          .height(300)
          .padding(16)
          .backgroundColor('#11141A')
          .borderRadius(7)
          .border({ width: 1, color: '#252B34' })

          Column({ space: 14 }) {
            this.PanelTitle('实时遥测', '软件软限位不会替代物理急停')
            this.TelemetryLine('赤经', this.formatRa(this.mountRaHours))
            this.TelemetryLine('赤纬', this.formatDec(this.mountDecDegrees))
            this.TelemetryLine('运动状态', this.mountSlewing ? '转动中' : '静止')
            this.TelemetryLine('位置同步', this.locationSynced ? '已同步' : '未同步')
            this.TelemetryLine('跟踪模式', this.tracking ? '恒星时' : '已停止')
            this.TelemetryLine('安全状态', this.mountHomed ? '软限位有效' : '等待回零')
          }
          .width(330)
          .height(300)
          .padding(16)
          .backgroundColor('#11141A')
          .borderRadius(7)
          .border({ width: 1, color: '#252B34' })
        }
      }
      .width('100%')
      .padding(18)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private ConnectionPanel(title: string, subtitle: string, state: ConnectionState, action: () => void) {
    Row({ space: 14 }) {
      Circle().width(14).height(14).fill(this.connectionColor(state))
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F2F5F9').width('100%')
        Text(subtitle).fontSize(11).fontColor('#8390A4').width('100%')
      }.layoutWeight(1)
      Text(this.connectionText(state)).fontSize(12).fontColor(this.connectionColor(state))
      Button(state === ConnectionState.CONNECTED || state === ConnectionState.SIMULATED ? '断开' : '连接')
        .height(36).padding({ left: 16, right: 16 }).fontSize(12)
        .fontColor('#071017').backgroundColor('#72D3F5').borderRadius(5)
        .onClick(action)
    }
    .layoutWeight(1)
    .height(82)
    .padding({ left: 16, right: 14 })
    .backgroundColor('#11141A')
    .border({ width: 1, color: '#252B34' })
    .borderRadius(7)
  }

  @Builder
  private PanelTitle(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F0F3F8').width('100%')
      Text(subtitle).fontSize(11).fontColor('#7E899B').width('100%')
    }.width('100%')
  }

  @Builder
  private ActionButton(icon: string, label: string, enabled: boolean, action: () => void) {
    Column({ space: 6 }) {
      Text(icon).fontSize(18).fontWeight(FontWeight.Bold).fontColor(enabled ? '#72D3F5' : '#505968')
      Text(label).fontSize(11).fontColor(enabled ? '#D9E0EA' : '#697386')
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#191E27')
    .borderRadius(5)
    .opacity(enabled ? 1 : 0.65)
    .onClick(() => {
      if (enabled) {
        action();
      }
    })
  }

  @Builder
  private TelemetryLine(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor('#7E899B')
      Blank()
      Text(value).fontSize(12).fontColor('#E4E9F1')
    }.width('100%').height(27)
  }

  @Builder
  private TaskWorkspace() {
    Row({ space: 14 }) {
      Column({ space: 14 }) {
        this.PanelTitle('当前拍摄任务', this.taskStage)
        Row() {
          Column({ space: 4 }) {
            Text(this.selectedTarget().nameZh + ' · ' + this.captureModeText())
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#F0F3F8').width('100%')
            Text(this.exposureSeconds.toString() + 's × ' + this.frameCount.toString() + ' · ISO ' + this.iso.toString())
              .fontSize(12).fontColor('#8995A8').width('100%')
          }.layoutWeight(1)
          Text(this.taskStatusText()).fontSize(12).fontColor(this.taskStatusColor())
        }.width('100%')

        Progress({ value: this.taskProgress, total: 100, type: ProgressType.Linear })
          .width('100%').height(8).color('#57C995').backgroundColor('#242A34')
        Row() {
          Text(this.completedFrames.toString() + ' / ' + this.frameCount.toString() + ' 帧')
            .fontSize(11).fontColor('#AAB4C8')
          Blank()
          Text(this.taskProgress.toFixed(0) + '%').fontSize(11).fontColor('#57C995')
        }.width('100%')

        if (this.workflowWarningText.length > 0) {
          Text(this.workflowWarningText)
            .fontSize(10).fontColor('#F4BA58').lineHeight(16).width('100%').maxLines(2)
        }

        Row({ space: 10 }) {
          Button('刷新状态').layoutWeight(1).height(38).fontSize(12)
            .fontColor('#D8DEE8').backgroundColor('#242A34').borderRadius(5)
            .onClick(() => { this.pollActiveTask(); })
          Button('取消任务').layoutWeight(1).height(38).fontSize(12)
            .fontColor('#FFFFFF').backgroundColor('#8D343B').borderRadius(5)
            .onClick(() => { this.cancelActiveTask(); })
        }.width('100%')
      }
      .layoutWeight(1)
      .height(280)
      .padding(18)
      .backgroundColor('#11141A')
      .borderRadius(7)
      .border({ width: 1, color: '#252B34' })

      Column({ space: 12 }) {
        this.PanelTitle('处理流水线', 'RAW 原片始终保留在相机存储卡')
        this.PipelineStep('1', '拍摄与下载', this.taskProgress > 0)
        this.PipelineStep('2', `板解析 ${this.plateSolveCount} 次 · 修正 ${this.correctionCount} 次`,
          this.plateSolveCount > 0)
        this.PipelineStep('3', this.captureMode === 2 ? '1080p 延时制片' : '星点配准、坏帧剔除与堆栈',
          this.stackFileUrl.length > 0 || this.timelapseFileUrl.length > 0)
        this.PipelineStep('4', '华为云受约束增强（可选）', this.aiFileUrl.length > 0)
      }
      .width(340)
      .padding(18)
      .backgroundColor('#11141A')
      .borderRadius(7)
      .border({ width: 1, color: '#252B34' })
    }
    .layoutWeight(1)
    .width('100%')
    .padding(18)
  }

  @Builder
  private PipelineStep(number: string, label: string, active: boolean) {
    Row({ space: 10 }) {
      Text(active ? '✓' : number)
        .fontSize(11).fontWeight(FontWeight.Bold)
        .fontColor(active ? '#071017' : '#A7B1C1')
        .width(24).height(24).textAlign(TextAlign.Center)
        .backgroundColor(active ? '#57C995' : '#242A34').borderRadius(12)
      Text(label).fontSize(12).fontColor(active ? '#E7ECF3' : '#7B879A')
    }.width('100%').height(34)
  }

  @Builder
  private PostWorkspace() {
    Column({ space: 14 }) {
      Row() {
        this.PanelTitle('可信图像后期', 'AI 只处理背景噪声与光污染，不生成、删除或移动星体')
        Blank()
        Button('导出处理记录')
          .height(36).padding({ left: 14, right: 14 }).fontSize(12)
          .fontColor('#DDE3EC').backgroundColor('#242A34').borderRadius(5)
      }.width('100%')

      Row({ space: 8 }) {
        TextInput({ placeholder: '云增强服务地址，例如 https://example.com', text: this.aiEndpoint })
          .layoutWeight(1).height(36).fontSize(11).fontColor('#E8EDF4')
          .backgroundColor('#11141A').borderRadius(5)
          .onChange((value: string) => { this.aiEndpoint = value; })
        TextInput({ placeholder: '访问令牌（服务未启用鉴权时可空）', text: this.aiToken })
          .width(230).height(36).fontSize(11).fontColor('#E8EDF4')
          .type(InputType.Password)
          .backgroundColor('#11141A').borderRadius(5)
          .onChange((value: string) => { this.aiToken = value; })
        Button('应用云配置')
          .height(36).padding({ left: 12, right: 12 }).fontSize(11)
          .fontColor('#071017').backgroundColor('#72D3F5').borderRadius(5)
          .onClick(() => { this.applyAiConfiguration(); })
        Text(this.aiStatus).width(82).fontSize(10).fontColor(this.aiClient.isConfigured() ? '#57C995' : '#F4BA58')
      }.width('100%')

      Row({ space: 12 }) {
        this.ImageResultPanel('本地堆栈', this.stackFileUrl.length > 0 ? '树莓派处理结果' : '等待真实任务文件',
          '#17202A', this.stackFileUrl)
        Column({ space: 8 }) {
          Text('⇄').fontSize(22).fontColor('#72D3F5')
          Text('拖动对比').fontSize(10).fontColor('#778397')
        }.width(58).alignItems(HorizontalAlign.Center)
        this.ImageResultPanel('AI 增强', this.aiFileUrl.length > 0 ?
          `模型 ${this.aiModelVersion.length > 0 ? this.aiModelVersion : '已记录'}` : '等待云端处理记录',
          '#101D1A', this.aiFileUrl)
      }
      .layoutWeight(1)
      .width('100%')

      if (this.timelapseFileUrl.length > 0) {
        Video({ src: this.timelapseFileUrl })
          .width('100%')
          .height(180)
          .controls(true)
          .autoPlay(false)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#05070B')
          .borderRadius(6)
      }

      Row({ space: 14 }) {
        this.PostMetric('板解析', `${this.plateSolveCount} 次`, '#57C995')
        this.PostMetric('漂移修正', `${this.correctionCount} 次`, '#72D3F5')
        this.PostMetric('光污染梯度', this.stackFileUrl.length > 0 ? '已校正' : '待处理', '#F4BA58')
        this.PostMetric('原片证据', this.completedFrames > 0 ? `${this.completedFrames} 帧 + 日志` : '等待任务', '#E5E9F0')
      }.width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .padding(18)
  }

  @Builder
  private ImageResultPanel(title: string, subtitle: string, fillColor: string, sourceUrl: string) {
    Column() {
      if (sourceUrl.length > 0) {
        Image(sourceUrl)
          .layoutWeight(1).width('100%').objectFit(ImageFit.Contain).backgroundColor('#05070B')
      } else {
        Stack() {
          Rect().width('100%').height('100%').fill(fillColor)
          Text('等待真实图像').fontSize(13).fontColor('#6F7B8D')
        }.layoutWeight(1).width('100%')
      }
      Row() {
        Column({ space: 3 }) {
          Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#F0F3F8').width('100%')
          Text(subtitle).fontSize(10).fontColor('#7F8A9D').width('100%')
        }.layoutWeight(1)
        Text('4K JPEG').fontSize(10).fontColor('#72D3F5')
      }.width('100%').height(58).padding({ left: 14, right: 14 })
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor('#11141A')
    .borderRadius(7)
    .clip(true)
    .border({ width: 1, color: '#252B34' })
  }

  @Builder
  private PostMetric(label: string, value: string, color: string) {
    Row() {
      Column({ space: 3 }) {
        Text(label).fontSize(10).fontColor('#7E899B').width('100%')
        Text(value).fontSize(13).fontWeight(FontWeight.Bold).fontColor(color).width('100%')
      }.layoutWeight(1)
    }
    .layoutWeight(1)
    .height(58)
    .padding({ left: 14, right: 14 })
    .backgroundColor('#11141A')
    .borderRadius(6)
    .border({ width: 1, color: '#252B34' })
  }

  @Builder
  private CaptureOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Rect().width('100%').height('100%').fill('#000000').opacity(0.72)
        .onClick(() => { this.showCapturePanel = false; })

      Column({ space: 14 }) {
        Row() {
          Column({ space: 3 }) {
            Text('拍摄 / 观测').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#F4F7FB').width('100%')
            Text(this.selectedTarget().nameZh + ' · ' + this.selectedTarget().designation)
              .fontSize(11).fontColor('#8793A7').width('100%')
          }.layoutWeight(1)
          Button('×').width(34).height(34).fontSize(18)
            .fontColor('#C8D0DC').backgroundColor('#242A34').borderRadius(5)
            .onClick(() => { this.showCapturePanel = false; })
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
          .padding(12)
          .backgroundColor('#0D1118')
          .borderRadius(5)
        }

        Row() {
          Text('专家参数').fontSize(12).fontColor('#C6CFDB')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.expertOpen })
            .selectedColor('#57C995')
            .onChange((value: boolean) => { this.expertOpen = value; })
        }.width('100%').height(34)

        if (this.expertOpen) {
          Text('RAW+JPEG · 拍摄后可提交板解析、堆栈、延时制片和受约束云端增强')
            .fontSize(11).fontColor('#91A0B3').width('100%').lineHeight(18)
        }

        if (!this.selectedTarget().recommendedFor18mm && this.captureMode > 0) {
          Text('当前目标角尺寸较小，18mm 广角照片中不会成为清晰主体。建议仅观测或选择银河区域。')
            .fontSize(11).fontColor('#F4BA58').lineHeight(18).width('100%')
            .padding(10).backgroundColor('#211A10').borderRadius(5)
        }

        Button(this.captureMode === 0 ? 'GOTO 并开始观测' : 'GOTO 并创建拍摄任务')
          .width('100%').height(44).fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(this.canStartCapture() ? '#071017' : '#707A89')
          .backgroundColor(this.canStartCapture() ? '#57C995' : '#262B33')
          .borderRadius(6)
          .onClick(() => {
            if (this.canStartCapture()) {
              this.startCaptureTask();
            }
          })
        Text(this.captureReadinessText())
          .fontSize(10).fontColor(this.canStartCapture() ? '#57C995' : '#8B96A7')
          .width('100%').textAlign(TextAlign.Center)
      }
      .width(480)
      .padding(18)
      .backgroundColor('#12151B')
      .border({ width: 1, color: '#303743' })
      .borderRadius(7)
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }

  @Builder
  private CaptureModeButton(label: string, mode: number) {
    Button(label)
      .layoutWeight(1).height(40).fontSize(12)
      .fontColor(this.captureMode === mode ? '#071017' : '#B5BFCD')
      .backgroundColor(this.captureMode === mode ? '#72D3F5' : '#242A34')
      .borderRadius(5)
      .onClick(() => { this.captureMode = mode; })
  }

  @Builder
  private NumberSetting(label: string, value: string, minus: number, plus: number,
    minimum: number, maximum: number, setting: number) {
    Row() {
      Text(label).fontSize(11).fontColor('#8B97AA').width(92)
      Button('−').width(30).height(28).fontSize(15)
        .fontColor('#DDE3EC').backgroundColor('#242A34').borderRadius(4)
        .onClick(() => { this.adjustSetting(setting, minus, minimum, maximum); })
      Text(value).fontSize(12).fontColor('#EDF1F6').layoutWeight(1).textAlign(TextAlign.Center)
      Button('+').width(30).height(28).fontSize(15)
        .fontColor('#071017').backgroundColor('#72D3F5').borderRadius(4)
        .onClick(() => { this.adjustSetting(setting, plus, minimum, maximum); })
    }.width('100%').height(30)
  }

  private selectedTarget(): CelestialObject {
    if (this.selectedCustomTarget !== undefined && this.selectedCustomTarget.id === this.selectedTargetId) {
      return this.selectedCustomTarget;
    }
    for (let index = 0; index < UI_TARGETS.length; index++) {
      if (UI_TARGETS[index].id === this.selectedTargetId) {
        return UI_TARGETS[index];
      }
    }
    return UI_TARGETS[0];
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
      this.updateNormalMap();
      return;
    }
    if (this.visibleStarCatalog.isLoaded()) {
      const stars: VisibleStar[] = this.visibleStarCatalog.search(keyword, 1);
      if (stars.length > 0) {
        this.selectedCustomTarget = this.visibleStarCatalog.toCelestialObject(stars[0]);
        this.selectedTargetId = this.selectedCustomTarget.id;
        this.operationMessage = `已从 HYG 离线星表选择 ${this.selectedCustomTarget.nameZh}`;
        this.updateNormalMap();
        return;
      }
    }
    this.operationMessage = `离线目录中未找到“${keyword}”`;
  }

  private targetById(id: string): CelestialObject {
    for (let index: number = 0; index < UI_TARGETS.length; index++) {
      if (UI_TARGETS[index].id === id) {
        return UI_TARGETS[index];
      }
    }
    return UI_TARGETS[0];
  }

  private selectedCoordinate(): EquatorialCoordinate | undefined {
    return AstronomyService.resolveCoordinate(this.selectedTarget(), Date.now());
  }

  private selectedHorizontal(): HorizontalCoordinate | undefined {
    const coordinate: EquatorialCoordinate | undefined = this.selectedCoordinate();
    if (coordinate === undefined || this.observer === undefined) {
      return undefined;
    }
    const currentObserver: ObserverState = {
      latitudeDegrees: this.observer.latitudeDegrees,
      longitudeDegrees: this.observer.longitudeDegrees,
      elevationMeters: this.observer.elevationMeters,
      timestampMs: Date.now()
    };
    return AstronomyService.equatorialToHorizontal(coordinate, currentObserver);
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

  private connectionText(state: ConnectionState): string {
    if (state === ConnectionState.CONNECTED) return '已连接';
    if (state === ConnectionState.CONNECTING) return '连接中';
    if (state === ConnectionState.ERROR) return '异常';
    if (state === ConnectionState.SIMULATED) return '模拟';
    return '未连接';
  }

  private connectionColor(state: ConnectionState): string {
    if (state === ConnectionState.CONNECTED) return '#57C995';
    if (state === ConnectionState.CONNECTING) return '#F4BA58';
    if (state === ConnectionState.ERROR) return '#E05B64';
    if (state === ConnectionState.SIMULATED) return '#72D3F5';
    return '#566172';
  }

  private sectionTitle(): string {
    if (this.activeSection === 0) return this.skyMode === 0 ? 'AR 寻星' : '普通星图';
    if (this.activeSection === 1) return '设备控制';
    if (this.activeSection === 2) return '拍摄任务';
    return '图像后期';
  }

  private sectionSubtitle(): string {
    if (this.activeSection === 0) return '定位、姿态与离线星表驱动的实时天空视图';
    if (this.activeSection === 1) return 'OnStepX 赤道仪与 EOS R7 网关';
    if (this.activeSection === 2) return '板解析、漂移校正、堆栈与延时视频';
    return '原片、堆栈和受约束 AI 结果可追溯对比';
  }

  private currentTimeText(): string {
    const now = new Date();
    return this.pad2(now.getHours()) + ':' + this.pad2(now.getMinutes());
  }

  private pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  private deviceLines(): DeviceLine[] {
    return [
      { name: '网络', detail: 'StarScope · 10.42.0.20:9999', state: this.connectionText(this.mountConnection), color: this.connectionColor(this.mountConnection) },
      { name: '机械零位', detail: 'AUX3 / AUX4 常闭原点开关', state: this.mountHomed ? '已回零' : '未回零', color: this.mountHomed ? '#57C995' : '#F4BA58' },
      { name: '位置时间', detail: this.locationText, state: this.locationSynced ? '已同步' : '待同步', color: this.locationSynced ? '#57C995' : '#F4BA58' },
      { name: '物理急停', detail: '独立切断电机电源', state: '需人工确认', color: '#E05B64' }
    ];
  }

  private canStartCapture(): boolean {
    if (this.operationBusy || this.mountConnection !== ConnectionState.CONNECTED ||
      !this.mountHomed || !this.locationSynced || !this.selectedTarget().gotoAllowed) {
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
    if (!this.mountHomed) return '自动运动前必须完成两轴回零';
    if (this.observer === undefined) return '需要系统定位才能计算目标方向';
    if (!this.locationSynced) return '请先把位置和时间同步到 OnStepX';
    if (!this.selectedTarget().gotoAllowed || this.selectedCoordinate() === undefined) return '目标缺少可靠坐标，禁止自动 GOTO';
    const horizontal: HorizontalCoordinate | undefined = this.selectedHorizontal();
    if (horizontal === undefined || horizontal.altitudeDegrees < 10.0) return '目标当前低于 10° 安全高度';
    if (this.captureMode > 0 && this.gatewayConnection !== ConnectionState.CONNECTED) return '请先连接 EOS R7 相机网关';
    return '目标方向与设备安全检查通过';
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
      this.updateNormalMap();
      this.updateProjectedTargets(true);
    } catch (error) {
      this.catalogStatus = '离线星表加载失败';
      this.operationMessage = `星表加载失败：${error}`;
    }
  }

  private applyHandLandmarks(result: HandLandmarkAnalysisResult): void {
    // 关闭开关或切换回 AR 后，丢弃已经在推理队列中的旧帧，避免异步回调继续移动普通星图。
    if (!this.gestureEnabled || this.skyMode !== 1) {
      this.gestureInterpreter.reset();
      return;
    }
    const frame: GestureFrame = this.gestureInterpreter.interpret(
      result.hands, result.frameReceivedAtMs);
    if (frame.gesture === HandGesture.DRAG) {
      this.mapOffsetX += frame.deltaX * this.skyViewportWidth;
      this.mapOffsetY += frame.deltaY * this.skyViewportHeight;
      this.gestureStatus = '单掌拖拽';
    } else if (frame.gesture === HandGesture.ROTATE_SCALE) {
      this.mapRotation += frame.rotationDegrees;
      this.mapScale = this.clamp(this.mapScale * frame.scale, 0.6, 3.0);
      this.gestureStatus = '双掌旋转 / 缩放';
    } else if (frame.gesture === HandGesture.PINCH_SELECT) {
      this.selectNearestGestureTarget(
        frame.selectX * this.skyViewportWidth, frame.selectY * this.skyViewportHeight);
      this.gestureStatus = '捏合选择';
    } else if (frame.gesture === HandGesture.FIST_RESET) {
      this.mapOffsetX = 0;
      this.mapOffsetY = 0;
      this.mapScale = 1;
      this.mapRotation = 0;
      this.gestureStatus = '握拳复位';
    } else if (result.hands.length > 0) {
      this.gestureStatus = '已检测手部';
    } else {
      this.gestureStatus = '等待手部进入画面';
    }
  }

  private selectNearestGestureTarget(screenX: number, screenY: number): void {
    let nearest: ProjectedTarget | undefined = undefined;
    let nearestDistance: number = Number.MAX_VALUE;
    const centerX: number = this.skyViewportWidth / 2.0;
    const centerY: number = this.skyViewportHeight / 2.0;
    const radians: number = this.mapRotation * Math.PI / 180.0;
    const cosine: number = Math.cos(radians);
    const sine: number = Math.sin(radians);
    for (let index: number = 0; index < this.normalTargets.length; index++) {
      const target: ProjectedTarget = this.normalTargets[index];
      const scaledX: number = (target.x - centerX) * this.mapScale;
      const scaledY: number = (target.y - centerY) * this.mapScale;
      const transformedX: number = scaledX * cosine - scaledY * sine + centerX + this.mapOffsetX;
      const transformedY: number = scaledX * sine + scaledY * cosine + centerY + this.mapOffsetY;
      const deltaX: number = transformedX - screenX;
      const deltaY: number = transformedY - screenY;
      const distance: number = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
      if (distance < nearestDistance) {
        nearest = target;
        nearestDistance = distance;
      }
    }
    if (nearest !== undefined && nearestDistance <= 70.0) {
      this.selectedCustomTarget = undefined;
      this.selectedTargetId = nearest.targetId;
      this.updateNormalMap();
    }
  }

  private updateNormalMap(): void {
    if (!this.visibleStarCatalog.isLoaded()) {
      return;
    }
    const center: EquatorialCoordinate | undefined = this.selectedCoordinate();
    if (center === undefined) {
      return;
    }
    const widthDegrees: number = 110.0;
    const heightDegrees: number = 80.0;
    const stars: VisibleStar[] = this.visibleStarCatalog.filterEquatorialViewport({
      centerRaHours: center.raHours,
      centerDecDegrees: center.decDegrees,
      widthDegrees: widthDegrees,
      heightDegrees: heightDegrees,
      maxMagnitude: 5.8,
      maxResults: 500
    });
    const cosine: number = Math.max(0.05, Math.cos(center.decDegrees * Math.PI / 180.0));
    const viewportWidth: number = this.skyViewportWidth;
    const viewportHeight: number = this.skyViewportHeight;
    const displayStars: DisplayStar[] = [];
    for (let index: number = 0; index < stars.length; index++) {
      const star: VisibleStar = stars[index];
      const raDifference: number = AstronomyService.normalizeSignedDegrees(
        star.raHours * 15.0 - center.raHours * 15.0) * cosine;
      const x: number = viewportWidth / 2.0 - raDifference / widthDegrees * viewportWidth;
      const y: number = viewportHeight / 2.0 -
        (star.decDegrees - center.decDegrees) / heightDegrees * viewportHeight;
      if (x >= 0.0 && x <= viewportWidth && y >= 0.0 && y <= viewportHeight) {
        displayStars.push({
          id: `normal-${star.id}`,
          name: star.name.length > 0 && star.magnitude <= 2.5 ? star.name : '',
          x: x,
          y: y,
          size: this.starSize(star.magnitude),
          color: this.starColor(star.spectralType),
          catalogStar: star
        });
      }
    }
    this.normalStars = displayStars;

    const targets: ProjectedTarget[] = [];
    for (let index: number = 0; index < UI_TARGETS.length; index++) {
      const coordinate: EquatorialCoordinate | undefined =
        AstronomyService.resolveCoordinate(UI_TARGETS[index], Date.now());
      if (coordinate === undefined) continue;
      const raDifference: number = AstronomyService.normalizeSignedDegrees(
        coordinate.raHours * 15.0 - center.raHours * 15.0) * cosine;
      const x: number = viewportWidth / 2.0 - raDifference / widthDegrees * viewportWidth;
      const y: number = viewportHeight / 2.0 -
        (coordinate.decDegrees - center.decDegrees) / heightDegrees * viewportHeight;
      if (x >= 0.0 && x <= viewportWidth && y >= 0.0 && y <= viewportHeight) {
        targets.push({ targetId: UI_TARGETS[index].id, x: x, y: y });
      }
    }
    this.normalTargets = targets;
  }

  private starSize(magnitude: number): number {
    return this.clamp(6.5 - (magnitude + 1.0) * 0.75, 1.5, 7.0);
  }

  private starColor(spectralType: string): string {
    if (spectralType.startsWith('O') || spectralType.startsWith('B')) return '#B9D8FF';
    if (spectralType.startsWith('A')) return '#E3EDFF';
    if (spectralType.startsWith('F')) return '#FFF8E8';
    if (spectralType.startsWith('G')) return '#FFF0B8';
    if (spectralType.startsWith('K')) return '#FFD0A3';
    if (spectralType.startsWith('M')) return '#FFB0A5';
    return '#E5EAF2';
  }

  private async refreshLocation(): Promise<void> {
    this.locationText = '正在定位';
    try {
      const result: ObserverLocationResult = await ObserverLocationService.current();
      this.observer = result.observer;
      this.locationAccuracy = result.accuracyMeters;
      this.locationSynced = false;
      this.locationText = `${result.observer.latitudeDegrees.toFixed(2)}, ${result.observer.longitudeDegrees.toFixed(2)}`;
      this.operationMessage = `定位精度约 ±${result.accuracyMeters.toFixed(0)} 米`;
      this.updateProjectedTargets(true);
    } catch (error) {
      this.observer = undefined;
      this.locationSynced = false;
      this.locationText = '定位不可用';
      this.operationMessage = `定位失败：${error}`;
    }
  }

  private updateProjectedTargets(force: boolean = false): void {
    const now: number = Date.now();
    if (!force && now - this.lastProjectionAtMs < 100) {
      return;
    }
    this.lastProjectionAtMs = now;
    if (!this.poseReady || this.observer === undefined) {
      this.projectedTargets = [];
      this.projectedStars = [];
      return;
    }
    const observer: ObserverState = {
      latitudeDegrees: this.observer.latitudeDegrees,
      longitudeDegrees: this.observer.longitudeDegrees,
      elevationMeters: this.observer.elevationMeters,
      timestampMs: Date.now()
    };
    const pose: DevicePose = {
      headingDegrees: this.poseHeading,
      pitchDegrees: this.posePitch,
      rollDegrees: this.poseRoll
    };
    const projected: ProjectedTarget[] = [];
    for (let index: number = 0; index < UI_TARGETS.length; index++) {
      const coordinate: EquatorialCoordinate | undefined =
        AstronomyService.resolveCoordinate(UI_TARGETS[index], observer.timestampMs);
      if (coordinate === undefined) {
        continue;
      }
      const horizontal: HorizontalCoordinate = AstronomyService.equatorialToHorizontal(coordinate, observer);
      const screen: ScreenProjection = AstronomyService.projectToViewport(
        horizontal, pose, this.arViewport, this.calibration);
      if (screen.inViewport) {
        projected.push({ targetId: UI_TARGETS[index].id, x: screen.xPixels, y: screen.yPixels });
      }
    }
    this.projectedTargets = projected;

    if (this.visibleStarCatalog.isLoaded()) {
      const catalogProjection: ProjectedVisibleStar[] = this.visibleStarCatalog.projectViewport({
        observer: observer,
        pose: pose,
        viewport: this.arViewport,
        calibration: this.calibration,
        maxMagnitude: 5.5,
        minAltitudeDegrees: 0,
        maxResults: 350
      });
      const visible: DisplayStar[] = [];
      for (let index: number = 0; index < catalogProjection.length; index++) {
        const item: ProjectedVisibleStar = catalogProjection[index];
        visible.push({
          id: `ar-${item.star.id}`,
          name: item.star.name.length > 0 && item.star.magnitude <= 1.5 ? item.star.name : '',
          x: item.projection.xPixels,
          y: item.projection.yPixels,
          size: this.starSize(item.star.magnitude),
          color: this.starColor(item.star.spectralType),
          catalogStar: item.star
        });
      }
      this.projectedStars = visible;
    }
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
    this.calibrationEnabled = true;
    this.calibrationText = `已校准 · ${this.selectedTarget().designation}`;
    this.operationMessage = '一星校准已应用；移动 Pad 检查叠加是否跟随目标';
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
        this.locationSynced = false;
        this.tracking = false;
        this.operationMessage = '赤道仪已断开';
      } else {
        this.mountConnection = ConnectionState.CONNECTING;
        this.operationMessage = '正在连接 10.42.0.20:9999';
        await this.mountClient.connect();
        const state: MountState = await this.mountClient.refreshState();
        this.applyMountState(state);
        this.startMountPolling();
        this.operationMessage = 'OnStepX 已连接；自动运动前请先回零并同步位置';
      }
    } catch (error) {
      this.mountConnection = ConnectionState.ERROR;
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
    const selectedCoordinate: EquatorialCoordinate | undefined = this.selectedCoordinate();
    if (selectedCoordinate === undefined) return;
    // GOTO 之前冻结目标、模式和相机参数，避免等待机械运动期间修改 UI 导致拍摄对象与任务元数据错配。
    const coordinate: EquatorialCoordinate = {
      raHours: selectedCoordinate.raHours,
      decDegrees: selectedCoordinate.decDegrees,
      epoch: selectedCoordinate.epoch
    };
    const capturePlan: CapturePlan = this.buildCapturePlan();
    const targetDesignation: string = this.selectedTarget().designation;
    const runGeneration: number = ++this.captureRunGeneration;
    this.operationBusy = true;
    this.emergencyMessage = '';
    try {
      this.showCapturePanel = false;
      this.taskStage = `正在 GOTO ${targetDesignation}`;
      this.operationMessage = this.taskStage;
      await this.mountClient.gotoRaDec(coordinate);
      this.throwIfCaptureRunCancelled(runGeneration);
      await this.waitForMountMotion(runGeneration);
      this.throwIfCaptureRunCancelled(runGeneration);
      await this.mountClient.startTracking(TrackingMode.SIDEREAL);
      this.throwIfCaptureRunCancelled(runGeneration);
      this.tracking = true;

      if (capturePlan.mode === CaptureMode.OBSERVE_ONLY) {
        this.activeSection = 1;
        this.taskStage = '仅观测模式未触发相机快门';
        this.operationMessage = `${capturePlan.targetName} 已到位，恒星时跟踪已启动`;
        return;
      }

      this.activeSection = 2;
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

  private taskStatusColor(): string {
    if (this.taskStatus === TaskStatus.RUNNING) return '#72D3F5';
    if (this.taskStatus === TaskStatus.SUCCEEDED) return '#57C995';
    if (this.taskStatus === TaskStatus.FAILED || this.taskStatus === TaskStatus.CANCELLED) return '#E05B64';
    return '#8995A8';
  }
}

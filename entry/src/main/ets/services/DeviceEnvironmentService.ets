import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { geoLocationManager } from '@kit.LocationKit';
import { sensor } from '@kit.SensorServiceKit';
import { DevicePose, ObserverState } from '../models/DomainModels';
import type { Quaternion } from '../models/ArSkyModels';
import { AstronomyService } from './AstronomyService';
import { ObserverLocationPolicy } from './ObserverLocationPolicy';
import { SkyDomeEulerOrientation, SkyDomeProjectionService } from './SkyDomeProjectionService';

export interface ObserverLocationResult {
  observer: ObserverState;
  accuracyMeters: number;
  source: ObserverLocationSource;
  locationTimestampMs: number;
  provisional: boolean;
}

export enum ObserverLocationSource {
  LAST_KNOWN = 'last_known',
  CURRENT = 'current',
  MANUAL = 'manual'
}

export interface ObserverLocationSequence {
  provisional?: ObserverLocationResult;
  precise: Promise<ObserverLocationResult>;
}

export type DevicePoseListener = (pose: DevicePose) => void;

/**
 * 读取系统定位。这里不静默回退到固定城市坐标，因为错误位置会直接造成星图投影和 GOTO 偏差。
 * 比赛回放如需固定位置，应由明确标注的模拟服务注入，而不是混入真实设备链路。
 */
export class ObserverLocationService {
  /**
   * 先同步读取系统最近位置，再在后台等待高精度结果。最近位置只用于立即生成临时规划，
   * 高精度结果返回后必须由页面使用同一请求代次校正，不能覆盖用户随后输入的手动地点。
   */
  static async begin(): Promise<ObserverLocationSequence> {
    const context: common.UIAbilityContext | undefined =
      AppStorage.get<common.UIAbilityContext>('uiAbilityContext');
    if (context === undefined) {
      throw new Error('应用上下文尚未就绪');
    }

    const permissions: Permissions[] = [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ];
    const permissionResult = await abilityAccessCtrl.createAtManager()
      .requestPermissionsFromUser(context, permissions);
    let granted: boolean = false;
    for (let index: number = 0; index < permissionResult.authResults.length; index++) {
      if (permissionResult.authResults[index] === 0) {
        granted = true;
      }
    }
    if (!granted) {
      throw new Error('未授予定位权限');
    }
    if (!geoLocationManager.isLocationEnabled()) {
      throw new Error('系统定位服务未开启');
    }

    let provisional: ObserverLocationResult | undefined = undefined;
    try {
      const lastLocation: geoLocationManager.Location = geoLocationManager.getLastLocation();
      provisional = ObserverLocationService.mapLastLocation(lastLocation);
    } catch (error) {
      // 设备没有历史位置或能力受限时继续请求当前定位，不能把快速路径失败当成整体失败。
    }
    const sequence: ObserverLocationSequence = {
      precise: ObserverLocationService.requestPreciseLocation()
    };
    if (provisional !== undefined) sequence.provisional = provisional;
    return sequence;
  }

  /** 保留原有单结果入口，供不需要快速路径的调用方使用。 */
  static async current(): Promise<ObserverLocationResult> {
    const sequence: ObserverLocationSequence = await ObserverLocationService.begin();
    return sequence.precise;
  }

  private static async requestPreciseLocation(): Promise<ObserverLocationResult> {
    const location: geoLocationManager.Location = await geoLocationManager.getCurrentLocation({
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      maxAccuracy: 500,
      timeoutMs: 12000
    });
    return ObserverLocationService.mapLocation(
      location, ObserverLocationSource.CURRENT, false);
  }

  private static mapLastLocation(location: geoLocationManager.Location): ObserverLocationResult | undefined {
    const timestampMs: number = ObserverLocationService.locationTimestamp(location);
    if (!ObserverLocationPolicy.isUsable(Date.now(), timestampMs, location.accuracy)) {
      return undefined;
    }
    return ObserverLocationService.mapLocation(
      location, ObserverLocationSource.LAST_KNOWN, true);
  }

  private static mapLocation(location: geoLocationManager.Location, source: ObserverLocationSource,
    provisional: boolean): ObserverLocationResult {
    if (!Number.isFinite(location.latitude) || location.latitude < -90 || location.latitude > 90 ||
      !Number.isFinite(location.longitude) || location.longitude < -180 || location.longitude > 180) {
      throw new Error('系统返回的定位坐标无效');
    }
    const timestampMs: number = ObserverLocationService.locationTimestamp(location);
    return {
      observer: {
        latitudeDegrees: location.latitude,
        longitudeDegrees: location.longitude,
        elevationMeters: Number.isFinite(location.altitude) ? location.altitude : 0,
        timestampMs: timestampMs
      },
      accuracyMeters: Number.isFinite(location.accuracy) && location.accuracy >= 0 ?
        location.accuracy : 0,
      source: source,
      locationTimestampMs: timestampMs,
      provisional: provisional
    };
  }

  private static locationTimestamp(location: geoLocationManager.Location): number {
    if (Number.isFinite(location.timeStamp) && location.timeStamp > 0) return location.timeStamp;
    return Date.now();
  }
}

/** 将 HarmonyOS 旋转向量转换成当前屏幕后摄镜头的方位/高度/横滚。 */
export class DevicePoseService {
  private listener: DevicePoseListener | undefined = undefined;
  private running: boolean = false;
  private usingRotationVector: boolean = false;
  private displaySubscribed: boolean = false;
  private displayRotation: number = 0;
  private smoothedOrientation: Quaternion | undefined = undefined;
  private smoothedPose: DevicePose | undefined = undefined;
  private lastTimestampNs: number = 0;
  private readonly rotationVectorCallback = (value: sensor.RotationVectorResponse): void => {
    if (this.listener === undefined) return;
    const deviceOrientation: Quaternion = {
      x: value.x,
      y: value.y,
      z: value.z,
      w: value.w
    };
    const cameraOrientation: Quaternion = SkyDomeProjectionService.cameraOrientationFromDeviceOrientation(
      deviceOrientation, this.displayRotation);
    const smoothing: number = this.smoothingForTimestamp(value.timestamp);
    this.smoothedOrientation = this.smoothedOrientation === undefined ? cameraOrientation :
      SkyDomeProjectionService.slerpQuaternion(this.smoothedOrientation, cameraOrientation, smoothing);
    const euler: SkyDomeEulerOrientation = SkyDomeProjectionService.headingPitchRollFromQuaternion(
      this.smoothedOrientation, this.smoothedPose === undefined ? 0.0 : this.smoothedPose.headingDegrees);
    this.smoothedPose = {
      headingDegrees: euler.headingDegrees,
      pitchDegrees: euler.pitchDegrees,
      rollDegrees: euler.rollDegrees
    };
    this.listener(this.smoothedPose);
  };

  /**
   * 极少数设备没有旋转向量时保留 ORIENTATION 回退。OrientationResponse 本身已经是度，
   * 旧实现再次乘 180/π 会放大约 57.3 倍；此处只做欧拉角平滑，不再重复换算。
   */
  private readonly orientationCallback = (value: sensor.OrientationResponse): void => {
    if (this.listener === undefined) {
      return;
    }
    const rawPose: DevicePose = {
      headingDegrees: AstronomyService.normalizeDegrees(value.alpha),
      pitchDegrees: Math.max(-90.0, Math.min(90.0, value.beta - 90.0)),
      rollDegrees: AstronomyService.normalizeSignedDegrees(value.gamma - this.displayRotation * 90.0)
    };
    const smoothing: number = this.smoothingForTimestamp(value.timestamp);
    if (this.smoothedPose === undefined) {
      this.smoothedPose = rawPose;
    } else {
      this.smoothedPose = {
        headingDegrees: AstronomyService.normalizeDegrees(this.smoothedPose.headingDegrees +
          AstronomyService.normalizeSignedDegrees(rawPose.headingDegrees - this.smoothedPose.headingDegrees) * smoothing),
        pitchDegrees: this.smoothedPose.pitchDegrees +
          (rawPose.pitchDegrees - this.smoothedPose.pitchDegrees) * smoothing,
        rollDegrees: AstronomyService.normalizeSignedDegrees(this.smoothedPose.rollDegrees +
          AstronomyService.normalizeSignedDegrees(rawPose.rollDegrees - this.smoothedPose.rollDegrees) * smoothing)
      };
    }
    this.listener(this.smoothedPose);
  };
  private readonly displayChangeCallback = (_displayId: number): void => {
    const previousRotation: number = this.displayRotation;
    this.refreshDisplayRotation();
    if (previousRotation !== this.displayRotation) {
      // 系统旋转界面时坐标基底瞬间改变，不能把 90 度轴变换当成真实设备运动做插值。
      this.smoothedOrientation = undefined;
      this.smoothedPose = undefined;
      this.lastTimestampNs = 0;
    }
  };

  start(listener: DevicePoseListener): void {
    this.stop();
    this.refreshDisplayRotation();
    try {
      display.on('change', this.displayChangeCallback);
      this.displaySubscribed = true;
    } catch (error) {
      this.displaySubscribed = false;
    }
    this.smoothedOrientation = undefined;
    this.smoothedPose = undefined;
    this.lastTimestampNs = 0;
    this.listener = listener;
    try {
      // getSingleSensorSync 只用于能力探测；回调本身已经直接给出 x/y/z/w，无需异步 getQuaternion。
      sensor.getSingleSensorSync(sensor.SensorId.ROTATION_VECTOR);
      sensor.on(sensor.SensorId.ROTATION_VECTOR, this.rotationVectorCallback, { interval: 'game' });
      this.usingRotationVector = true;
      this.running = true;
    } catch (rotationVectorError) {
      try {
        sensor.on(sensor.SensorId.ORIENTATION, this.orientationCallback, { interval: 'game' });
        this.usingRotationVector = false;
        this.running = true;
      } catch (orientationError) {
        this.listener = undefined;
        if (this.displaySubscribed) {
          try {
            display.off('change', this.displayChangeCallback);
          } catch (displayError) {
          }
          this.displaySubscribed = false;
        }
        throw orientationError as Error;
      }
    }
  }

  stop(): void {
    if (this.running) {
      if (this.usingRotationVector) {
        sensor.off(sensor.SensorId.ROTATION_VECTOR, this.rotationVectorCallback);
      } else {
        sensor.off(sensor.SensorId.ORIENTATION, this.orientationCallback);
      }
    }
    if (this.displaySubscribed) {
      try {
        display.off('change', this.displayChangeCallback);
      } catch (error) {
      }
    }
    this.running = false;
    this.usingRotationVector = false;
    this.displaySubscribed = false;
    this.listener = undefined;
    this.smoothedOrientation = undefined;
    this.smoothedPose = undefined;
    this.lastTimestampNs = 0;
  }

  private refreshDisplayRotation(): void {
    try {
      const rotation: number = display.getDefaultDisplaySync().rotation;
      this.displayRotation = ((Math.round(rotation) % 4) + 4) % 4;
    } catch (error) {
      this.displayRotation = 0;
    }
  }

  private smoothingForTimestamp(timestampNs: number): number {
    const elapsedMs: number = this.lastTimestampNs > 0 && timestampNs > this.lastTimestampNs ?
      (timestampNs - this.lastTimestampNs) / 1000000.0 : 20.0;
    this.lastTimestampNs = timestampNs;
    // 约 38 ms 时间常数能抑制细碎抖动，同时保留快速扫动时的响应；slerp 自动处理四元数短路径。
    return Math.max(0.2, Math.min(0.72, 1.0 - Math.exp(-elapsedMs / 38.0)));
  }
}

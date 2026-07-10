import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { sensor } from '@kit.SensorServiceKit';
import { DevicePose, ObserverState } from '../models/DomainModels';
import { AstronomyService } from './AstronomyService';

export interface ObserverLocationResult {
  observer: ObserverState;
  accuracyMeters: number;
}

export type DevicePoseListener = (pose: DevicePose) => void;

/**
 * 读取系统定位。这里不静默回退到固定城市坐标，因为错误位置会直接造成星图投影和 GOTO 偏差。
 * 比赛回放如需固定位置，应由明确标注的模拟服务注入，而不是混入真实设备链路。
 */
export class ObserverLocationService {
  static async current(): Promise<ObserverLocationResult> {
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

    const location: geoLocationManager.Location = await geoLocationManager.getCurrentLocation({
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      maxAccuracy: 500,
      timeoutMs: 12000
    });
    return {
      observer: {
        latitudeDegrees: location.latitude,
        longitudeDegrees: location.longitude,
        elevationMeters: location.altitude,
        timestampMs: Date.now()
      },
      accuracyMeters: location.accuracy
    };
  }
}

/**
 * 将 HarmonyOS 姿态传感器转换成后摄镜头中心的近似方位/高度/横滚。
 * 不同 Pad 的横竖屏轴向可能不同，因此最终精度由 AR 一星校准消除固定安装偏差。
 */
export class DevicePoseService {
  private listener: DevicePoseListener | undefined = undefined;
  private running: boolean = false;
  private readonly orientationCallback = (value: sensor.OrientationResponse): void => {
    if (this.listener === undefined) {
      return;
    }
    const radiansToDegrees: number = 180.0 / Math.PI;
    const alpha: number = value.alpha * radiansToDegrees;
    const beta: number = value.beta * radiansToDegrees;
    const gamma: number = value.gamma * radiansToDegrees;
    this.listener({
      headingDegrees: AstronomyService.normalizeDegrees(alpha),
      pitchDegrees: Math.max(-90.0, Math.min(90.0, beta - 90.0)),
      rollDegrees: AstronomyService.normalizeSignedDegrees(gamma)
    });
  };

  start(listener: DevicePoseListener): void {
    this.stop();
    this.listener = listener;
    sensor.on(sensor.SensorId.ORIENTATION, this.orientationCallback, { interval: 'ui' });
    this.running = true;
  }

  stop(): void {
    if (this.running) {
      sensor.off(sensor.SensorId.ORIENTATION, this.orientationCallback);
    }
    this.running = false;
    this.listener = undefined;
  }
}

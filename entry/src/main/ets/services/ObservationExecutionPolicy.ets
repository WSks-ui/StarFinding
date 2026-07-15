import {
  CelestialObject,
  MountTargetCoordinate,
  NormalSkyTimeMode,
  ObserverState
} from '../models';
import { EphemerisService } from './EphemerisService';

/**
 * 观测执行与离线浏览之间的安全边界。
 * 模拟时间可以用于星图和规划，但不得被转换成设备时间、GOTO 或拍摄指令。
 */
export class ObservationExecutionPolicy {
  static blocksDeviceTime(normalSkyActive: boolean, timeMode: NormalSkyTimeMode): boolean {
    return normalSkyActive && timeMode === NormalSkyTimeMode.SIMULATED;
  }

  static requireRealtime(normalSkyActive: boolean, timeMode: NormalSkyTimeMode,
    operationName: string): void {
    if (ObservationExecutionPolicy.blocksDeviceTime(normalSkyActive, timeMode)) {
      throw new Error(`模拟时间只用于浏览和规划，禁止${operationName}`);
    }
  }

  /** 动态目标必须在真正运动前重新按真实时刻生成站心当日坐标。 */
  static buildMountTarget(target: CelestialObject, observer: ObserverState,
    executionAtMs: number): MountTargetCoordinate {
    if (target.id === 'solar-sun') {
      throw new Error('太阳永久禁止普通 GOTO');
    }
    const timedObserver: ObserverState = {
      latitudeDegrees: observer.latitudeDegrees,
      longitudeDegrees: observer.longitudeDegrees,
      elevationMeters: observer.elevationMeters,
      timestampMs: executionAtMs
    };
    const coordinate: MountTargetCoordinate | undefined = EphemerisService.topocentricCoordinate(
      target, timedObserver, executionAtMs);
    if (coordinate === undefined) {
      throw new Error('无法生成站心当日目标坐标');
    }
    return coordinate;
  }
}

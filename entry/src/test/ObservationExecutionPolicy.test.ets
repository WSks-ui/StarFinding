import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CelestialObject,
  EquatorialCoordinate,
  EquatorialFrame,
  MountTargetCoordinate,
  NormalSkyTimeMode,
  ObserverState
} from '../main/ets/models';
import { AstronomyService } from '../main/ets/services/AstronomyService';
import { EphemerisService } from '../main/ets/services/EphemerisService';
import { ObservationExecutionPolicy } from '../main/ets/services/ObservationExecutionPolicy';

function executionTarget(id: string): CelestialObject {
  const target: CelestialObject | undefined = CelestialCatalog.getById(id);
  if (target === undefined) throw new Error(`执行策略测试缺少 ${id}`);
  return target;
}

function executionObserver(timestampMs: number): ObserverState {
  return {
    latitudeDegrees: 34.75,
    longitudeDegrees: 113.62,
    elevationMeters: 100.0,
    timestampMs: timestampMs
  };
}

export default function observationExecutionPolicyTest(): void {
  describe('观测设备执行门禁', () => {
    it('普通星图模拟时间在方法入口阻止设备指令', 0, () => {
      let commandCount: number = 0;
      if (!ObservationExecutionPolicy.blocksDeviceTime(true, NormalSkyTimeMode.SIMULATED)) {
        commandCount++;
      }
      expect(commandCount).assertEqual(0);
      expect(ObservationExecutionPolicy.blocksDeviceTime(
        true, NormalSkyTimeMode.REALTIME)).assertFalse();
      expect(ObservationExecutionPolicy.blocksDeviceTime(
        false, NormalSkyTimeMode.SIMULATED)).assertFalse();
    });

    it('模拟时间的强制检查在执行前抛出明确错误', 0, () => {
      let rejected: boolean = false;
      try {
        ObservationExecutionPolicy.requireRealtime(
          true, NormalSkyTimeMode.SIMULATED, '同步设备时间');
      } catch (error) {
        rejected = error instanceof Error && error.message.includes('禁止同步设备时间');
      }
      expect(rejected).assertTrue();
    });

    it('动态目标忽略浏览时刻并按真实执行时刻重算站心坐标', 0, () => {
      const simulatedAtMs: number = Date.UTC(2025, 0, 1, 0, 0, 0);
      const executionAtMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const mars: CelestialObject = executionTarget('planet-mars');
      const simulated: MountTargetCoordinate | undefined = EphemerisService.topocentricCoordinate(
        mars, executionObserver(simulatedAtMs), simulatedAtMs);
      if (simulated === undefined) {
        expect(false).assertTrue();
        return;
      }
      const execution: MountTargetCoordinate = ObservationExecutionPolicy.buildMountTarget(
        mars, executionObserver(simulatedAtMs), executionAtMs);
      const simulatedEqj: EquatorialCoordinate = EphemerisService.topocentricOfDateToEqj(simulated);
      const executionEqj: EquatorialCoordinate = EphemerisService.topocentricOfDateToEqj(execution);
      expect(execution.calculatedAtMs).assertEqual(executionAtMs);
      expect(execution.frame).assertEqual(EquatorialFrame.TOPOCENTRIC_OF_DATE);
      expect(execution.observerKey).assertEqual(
        EphemerisService.observerKey(executionObserver(executionAtMs)));
      expect(AstronomyService.angularSeparation(simulatedEqj, executionEqj) > 1.0).assertTrue();
    });

    it('执行坐标生成层同样永久拒绝太阳', 0, () => {
      let rejected: boolean = false;
      try {
        ObservationExecutionPolicy.buildMountTarget(
          executionTarget('solar-sun'), executionObserver(Date.UTC(2026, 6, 15)),
          Date.UTC(2026, 6, 15));
      } catch (error) {
        rejected = error instanceof Error && error.message.includes('太阳');
      }
      expect(rejected).assertTrue();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  ArPoseSample,
  ArTrackingQuality,
  ArTrackingSource,
  Quaternion,
  SkyDomeMarker,
  SkyDomeRenderOptions,
  SkyDomeStarInput,
  SkyDomeViewport
} from '../main/ets/models/ArSkyModels';
import { SkyDomeProjectionService } from '../main/ets/services/SkyDomeProjectionService';

function closeTo(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

function quaternionEquivalent(actual: Quaternion, expected: Quaternion, tolerance: number): boolean {
  const dot: number = actual.x * expected.x + actual.y * expected.y +
    actual.z * expected.z + actual.w * expected.w;
  return Math.abs(Math.abs(dot) - 1.0) <= tolerance;
}

function pose(headingDegrees: number, pitchDegrees: number, rollDegrees: number): ArPoseSample {
  return {
    orientation: SkyDomeProjectionService.quaternionFromHeadingPitchRoll(
      headingDegrees, pitchDegrees, rollDegrees),
    timestampNs: 123456789,
    quality: ArTrackingQuality.NORMAL,
    source: ArTrackingSource.SIMULATION
  };
}

function star(id: string, azimuthDegrees: number, altitudeDegrees: number): SkyDomeStarInput {
  return {
    id: id,
    label: id,
    azimuthDegrees: azimuthDegrees,
    altitudeDegrees: altitudeDegrees,
    magnitude: 1.0
  };
}

function viewport(): SkyDomeViewport {
  return { widthPixels: 1000.0, heightPixels: 800.0 };
}

function options(): SkyDomeRenderOptions {
  const value: SkyDomeRenderOptions = SkyDomeProjectionService.defaultRenderOptions();
  value.domeFieldOfViewDegrees = 170.0;
  value.minimumAltitudeDegrees = -10.0;
  return value;
}

export default function skyDomeProjectionServiceTest(): void {
  describe('AR 天穹投影', () => {
    it('镜头中心天体投影到视口中心', 0, () => {
      const marker: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('center', 30.0, 40.0), pose(30.0, 40.0, 0.0), viewport(), options());
      expect(closeTo(marker.xPixels, 500.0, 0.001)).assertTrue();
      expect(closeTo(marker.yPixels, 400.0, 0.001)).assertTrue();
      expect(marker.inViewport).assertTrue();
    });

    it('东西方向分别落在画面左右', 0, () => {
      const currentPose: ArPoseSample = pose(0.0, 30.0, 0.0);
      const east: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('east', 18.0, 30.0), currentPose, viewport(), options());
      const west: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('west', 342.0, 30.0), currentPose, viewport(), options());
      expect(east.xPixels > 500.0).assertTrue();
      expect(west.xPixels < 500.0).assertTrue();
    });

    it('高低方向分别落在画面上下', 0, () => {
      const currentPose: ArPoseSample = pose(90.0, 35.0, 0.0);
      const upper: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('upper', 90.0, 50.0), currentPose, viewport(), options());
      const lower: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('lower', 90.0, 20.0), currentPose, viewport(), options());
      expect(upper.yPixels < 400.0).assertTrue();
      expect(lower.yPixels > 400.0).assertTrue();
    });

    it('输出地平线及 30/60 度高度弧', 0, () => {
      const frame = SkyDomeProjectionService.createFrame([], pose(180.0, 40.0, 0.0), viewport(), options());
      let hasHorizon: boolean = false;
      let hasThirty: boolean = false;
      let hasSixty: boolean = false;
      for (let index: number = 0; index < frame.guideLines.length; index++) {
        const altitude: number = frame.guideLines[index].altitudeDegrees;
        hasHorizon = hasHorizon || altitude === 0.0;
        hasThirty = hasThirty || altitude === 30.0;
        hasSixty = hasSixty || altitude === 60.0;
      }
      expect(hasHorizon).assertTrue();
      expect(hasThirty).assertTrue();
      expect(hasSixty).assertTrue();
    });

    it('359 到 1 度沿短路径插值', 0, () => {
      expect(closeTo(SkyDomeProjectionService.shortestAngleDeltaDegrees(359.0, 1.0), 2.0, 0.0001))
        .assertTrue();
      expect(closeTo(SkyDomeProjectionService.interpolateAngleDegrees(359.0, 1.0, 0.5), 0.0, 0.0001))
        .assertTrue();
    });

    it('四元数球面插值跨北向时保持短路径和单位长度', 0, () => {
      const first = SkyDomeProjectionService.quaternionFromHeadingPitchRoll(350.0, 30.0, 0.0);
      const second = SkyDomeProjectionService.quaternionFromHeadingPitchRoll(10.0, 30.0, 0.0);
      const midpoint = SkyDomeProjectionService.slerpQuaternion(first, second, 0.5);
      const midpointLength: number = Math.sqrt(midpoint.x * midpoint.x + midpoint.y * midpoint.y +
        midpoint.z * midpoint.z + midpoint.w * midpoint.w);
      const midpointPose: ArPoseSample = {
        orientation: midpoint,
        timestampNs: 123456790,
        quality: ArTrackingQuality.NORMAL,
        source: ArTrackingSource.SIMULATION
      };
      const marker: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('north', 0.0, 30.0), midpointPose, viewport(), options());
      expect(closeTo(midpointLength, 1.0, 0.000001)).assertTrue();
      expect(closeTo(marker.xPixels, 500.0, 0.001)).assertTrue();
      expect(closeTo(marker.yPixels, 400.0, 0.001)).assertTrue();
    });

    it('方位高度横滚与四元数往返保持一致', 0, () => {
      const orientation = SkyDomeProjectionService.quaternionFromHeadingPitchRoll(123.0, 37.0, -28.0);
      const euler = SkyDomeProjectionService.headingPitchRollFromQuaternion(orientation);
      expect(Math.abs(SkyDomeProjectionService.shortestAngleDeltaDegrees(123.0, euler.headingDegrees)) < 0.0001)
        .assertTrue();
      expect(closeTo(euler.pitchDegrees, 37.0, 0.0001)).assertTrue();
      expect(Math.abs(SkyDomeProjectionService.shortestAngleDeltaDegrees(-28.0, euler.rollDegrees)) < 0.0001)
        .assertTrue();
    });

    it('四种屏幕旋转都正确映射后摄坐标', 0, () => {
      const halfSqrt: number = Math.SQRT1_2;
      const deviceOrientation: Quaternion = { x: halfSqrt, y: 0.0, z: 0.0, w: halfSqrt };
      const expected: Quaternion[] = [
        { x: halfSqrt, y: 0.0, z: 0.0, w: -halfSqrt },
        { x: 0.5, y: 0.5, z: 0.5, w: -0.5 },
        { x: 0.0, y: halfSqrt, z: halfSqrt, w: 0.0 },
        { x: 0.5, y: -0.5, z: -0.5, w: -0.5 }
      ];
      for (let rotation: number = 0; rotation < 4; rotation++) {
        const actual = SkyDomeProjectionService.cameraOrientationFromDeviceOrientation(
          deviceOrientation, rotation);
        expect(quaternionEquivalent(actual, expected[rotation], 0.000001)).assertTrue();
      }
    });

    it('点击选择命中范围内最近星体', 0, () => {
      const currentPose: ArPoseSample = pose(0.0, 30.0, 0.0);
      const first: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('near', 1.0, 30.0), currentPose, viewport(), options());
      const second: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('far', 5.0, 30.0), currentPose, viewport(), options());
      const selected: SkyDomeMarker | undefined = SkyDomeProjectionService.findNearestMarker(
        [second, first], first.xPixels + 2.0, first.yPixels, 80.0);
      expect(selected !== undefined && selected.id === 'near').assertTrue();
      expect(SkyDomeProjectionService.findNearestMarker(
        [first, second], 0.0, 0.0, 10.0) === undefined).assertTrue();
    });

    it('规范目标与目录星重叠时优先选择规范目标', 0, () => {
      const currentPose: ArPoseSample = pose(0.0, 30.0, 0.0);
      const target: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('target:star-vega', 0.0, 30.0), currentPose, viewport(), options());
      const catalog: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        star('catalog:hyg-hip91262', 0.0, 30.0), currentPose, viewport(), options());
      const selected: SkyDomeMarker | undefined = SkyDomeProjectionService.findNearestMarker(
        [target, catalog], target.xPixels, target.yPixels, 40.0);
      expect(selected !== undefined && selected.id === 'target:star-vega').assertTrue();
    });
  });
}

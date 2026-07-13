import { describe, expect, it } from '@ohos/hypium';
import {
  ArPoseSample,
  ArTrackingQuality,
  ArTrackingSource,
  Quaternion,
  SkyDomeMarker,
  SkyDomeStarInput
} from '../main/ets/models/ArSkyModels';
import { HuaweiArPoseAdapter } from '../main/ets/services/HuaweiArPoseAdapter';
import { SkyDomeProjectionService } from '../main/ets/services/SkyDomeProjectionService';

export default function huaweiArPoseAdapterTest(): void {
  describe('AR Engine 坐标适配', () => {
    it('单位 AR 姿态的镜头方向映射到 ENU 西向', 0, () => {
      const orientation: Quaternion = HuaweiArPoseAdapter.toSkyDomeOrientation({
        x: 0.0, y: 0.0, z: 0.0, w: 1.0
      });
      const pose: ArPoseSample = {
        orientation: orientation,
        timestampNs: 1,
        quality: ArTrackingQuality.HIGH,
        source: ArTrackingSource.HUAWEI_AR_ENGINE
      };
      const west: SkyDomeStarInput = {
        id: 'west', label: '西', azimuthDegrees: 270.0, altitudeDegrees: 0.0, magnitude: 1.0
      };
      const marker: SkyDomeMarker = SkyDomeProjectionService.projectStar(
        west, pose, { widthPixels: 1000.0, heightPixels: 800.0 });
      expect(Math.abs(marker.xPixels - 500.0) < 0.001).assertTrue();
      expect(Math.abs(marker.yPixels - 400.0) < 0.001).assertTrue();
    });

    it('输出四元数保持单位长度', 0, () => {
      const orientation: Quaternion = HuaweiArPoseAdapter.toSkyDomeOrientation({
        x: 0.2, y: -0.3, z: 0.1, w: 0.9
      });
      const length: number = Math.sqrt(orientation.x * orientation.x + orientation.y * orientation.y +
        orientation.z * orientation.z + orientation.w * orientation.w);
      expect(Math.abs(length - 1.0) < 0.000001).assertTrue();
    });
  });
}

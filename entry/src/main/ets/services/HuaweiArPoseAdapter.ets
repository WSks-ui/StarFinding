import { Quaternion } from '../models/ArSkyModels';
import { SkyDomeProjectionService } from './SkyDomeProjectionService';

interface Vector3 {
  x: number;
  y: number;
  z: number;
}

/**
 * 将 AR Engine 的 DisplayOrientedPose 转为天穹统一姿态。
 *
 * AR Engine 相机局部坐标为“右、上、后”，镜头朝向 -Z；北向世界坐标为“北、上、东”。
 * 天穹内部约定为相机“右、下、前”到 ENU“东、北、天”，因此必须同时完成局部轴翻转和
 * 世界轴循环置换。该适配器是唯一允许了解两套坐标约定的模块。
 */
export class HuaweiArPoseAdapter {
  static toSkyDomeOrientation(value: Quaternion): Quaternion {
    const normalized: Quaternion = SkyDomeProjectionService.normalizeQuaternion(value);
    const arRight: Vector3 = HuaweiArPoseAdapter.rotate(normalized, { x: 1.0, y: 0.0, z: 0.0 });
    const arUp: Vector3 = HuaweiArPoseAdapter.rotate(normalized, { x: 0.0, y: 1.0, z: 0.0 });
    const arBack: Vector3 = HuaweiArPoseAdapter.rotate(normalized, { x: 0.0, y: 0.0, z: 1.0 });

    const right: Vector3 = HuaweiArPoseAdapter.arWorldToEnu(arRight);
    const down: Vector3 = HuaweiArPoseAdapter.arWorldToEnu({ x: -arUp.x, y: -arUp.y, z: -arUp.z });
    const forward: Vector3 = HuaweiArPoseAdapter.arWorldToEnu({
      x: -arBack.x,
      y: -arBack.y,
      z: -arBack.z
    });
    return HuaweiArPoseAdapter.quaternionFromBasis(right, down, forward);
  }

  private static arWorldToEnu(value: Vector3): Vector3 {
    return {
      // AR 世界的 +Z=东、+X=北、+Y=天。
      x: value.z,
      y: value.x,
      z: value.y
    };
  }

  private static rotate(rotation: Quaternion, vector: Vector3): Vector3 {
    const twiceCross: Vector3 = {
      x: 2.0 * (rotation.y * vector.z - rotation.z * vector.y),
      y: 2.0 * (rotation.z * vector.x - rotation.x * vector.z),
      z: 2.0 * (rotation.x * vector.y - rotation.y * vector.x)
    };
    const secondCross: Vector3 = HuaweiArPoseAdapter.cross(
      { x: rotation.x, y: rotation.y, z: rotation.z }, twiceCross);
    return {
      x: vector.x + rotation.w * twiceCross.x + secondCross.x,
      y: vector.y + rotation.w * twiceCross.y + secondCross.y,
      z: vector.z + rotation.w * twiceCross.z + secondCross.z
    };
  }

  private static quaternionFromBasis(right: Vector3, down: Vector3, forward: Vector3): Quaternion {
    const m00: number = right.x;
    const m01: number = down.x;
    const m02: number = forward.x;
    const m10: number = right.y;
    const m11: number = down.y;
    const m12: number = forward.y;
    const m20: number = right.z;
    const m21: number = down.z;
    const m22: number = forward.z;
    const trace: number = m00 + m11 + m22;
    let result: Quaternion;
    if (trace > 0.0) {
      const scale: number = Math.sqrt(trace + 1.0) * 2.0;
      result = {
        x: (m21 - m12) / scale,
        y: (m02 - m20) / scale,
        z: (m10 - m01) / scale,
        w: 0.25 * scale
      };
    } else if (m00 > m11 && m00 > m22) {
      const scale: number = Math.sqrt(1.0 + m00 - m11 - m22) * 2.0;
      result = {
        x: 0.25 * scale,
        y: (m01 + m10) / scale,
        z: (m02 + m20) / scale,
        w: (m21 - m12) / scale
      };
    } else if (m11 > m22) {
      const scale: number = Math.sqrt(1.0 + m11 - m00 - m22) * 2.0;
      result = {
        x: (m01 + m10) / scale,
        y: 0.25 * scale,
        z: (m12 + m21) / scale,
        w: (m02 - m20) / scale
      };
    } else {
      const scale: number = Math.sqrt(1.0 + m22 - m00 - m11) * 2.0;
      result = {
        x: (m02 + m20) / scale,
        y: (m12 + m21) / scale,
        z: 0.25 * scale,
        w: (m10 - m01) / scale
      };
    }
    return SkyDomeProjectionService.normalizeQuaternion(result);
  }

  private static cross(first: Vector3, second: Vector3): Vector3 {
    return {
      x: first.y * second.z - first.z * second.y,
      y: first.z * second.x - first.x * second.z,
      z: first.x * second.y - first.y * second.x
    };
  }
}

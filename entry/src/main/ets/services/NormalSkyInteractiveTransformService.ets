import {
  InteractiveSkyTransform,
  NormalSkyViewport,
  SkyMapSize
} from '../models/NormalSkyModels';
import { EquatorialCoordinate, EquatorialFrame } from '../models/DomainModels';
import { NormalSkyProjectionService } from './NormalSkyProjectionService';

/**
 * 将精确场景与当前交互视口之间的差异压缩为 Canvas affine 变换。
 *
 * 这不是天球重新投影：它只在拖拽/缩放/旋转的短事务中使用，保证恒星目录不因
 * 每个手势帧而重新筛选。事务结束后由 NormalSkySceneService 重新做球面投影。
 */
export class NormalSkyInteractiveTransformService {
  static identity(size: SkyMapSize, revision: number = 0): InteractiveSkyTransform {
    return {
      revision: revision,
      active: false,
      translateXPixels: 0.0,
      translateYPixels: 0.0,
      scale: 1.0,
      rotationDegrees: 0.0,
      originXPixels: Math.max(1.0, size.widthPixels) / 2.0,
      originYPixels: Math.max(1.0, size.heightPixels) / 2.0
    };
  }

  static fromViewports(base: NormalSkyViewport, current: NormalSkyViewport,
    size: SkyMapSize, revision: number): InteractiveSkyTransform {
    const width: number = Math.max(1.0, size.widthPixels);
    const height: number = Math.max(1.0, size.heightPixels);
    const baseFieldRadians: number = base.fieldOfViewDegrees * Math.PI / 360.0;
    const currentFieldRadians: number = current.fieldOfViewDegrees * Math.PI / 360.0;
    const basePlane: number = Math.max(0.000001, Math.tan(baseFieldRadians / 2.0));
    const currentPlane: number = Math.max(0.000001, Math.tan(currentFieldRadians / 2.0));
    const scale: number = NormalSkyInteractiveTransformService.clamp(
      basePlane / currentPlane, 0.35, 3.0);
    const rotationDegrees: number =
      NormalSkyInteractiveTransformService.normalizeSignedDegrees(
        current.rotationDegrees - base.rotationDegrees);
    const anchor: EquatorialCoordinate = {
      raHours: base.centerRaHours,
      decDegrees: base.centerDecDegrees,
      frame: EquatorialFrame.ICRS_J2000
    };
    const projected = NormalSkyProjectionService.project(anchor, current, {
        widthPixels: width,
        heightPixels: height
      });
    let translateX: number = 0.0;
    let translateY: number = 0.0;
    if (Number.isFinite(projected.xPixels) && Number.isFinite(projected.yPixels) &&
      Math.abs(projected.xPixels) < 100000.0 && Math.abs(projected.yPixels) < 100000.0) {
      translateX = projected.xPixels - width / 2.0;
      translateY = projected.yPixels - height / 2.0;
    }
    const active: boolean = Math.abs(translateX) > 0.25 ||
      Math.abs(translateY) > 0.25 || Math.abs(rotationDegrees) > 0.1 ||
      Math.abs(scale - 1.0) > 0.002;
    return {
      revision: revision,
      active: active,
      translateXPixels: translateX,
      translateYPixels: translateY,
      scale: scale,
      rotationDegrees: rotationDegrees,
      originXPixels: width / 2.0,
      originYPixels: height / 2.0
    };
  }

  private static normalizeSignedDegrees(value: number): number {
    let result: number = value % 360.0;
    if (result > 180.0) result -= 360.0;
    if (result < -180.0) result += 360.0;
    return result;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

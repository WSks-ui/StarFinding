import { NormalSkyPreparedProjection } from './NormalSkyProjectionService';

/**
 * 全天摄影底图使用的赤道 J2000 单位方向。该类型刻意只保存数值，
 * 使 Worker、Canvas 及后续原生渲染路径可以复用同一套坐标计算。
 */
export interface SkySurveyDirection {
  x: number;
  y: number;
  z: number;
}

/** IAU J2000 银河坐标，银河经度范围为 [0, 360)，银河纬度范围为 [-90, 90]。 */
export interface SkySurveyGalacticCoordinate {
  longitudeDegrees: number;
  latitudeDegrees: number;
}

/**
 * 2:1 等距柱状全天图的纹理坐标。
 * u=0.5 对应银河中心，银河经度增加方向朝图像左侧；v=0 是银河北极。
 */
export interface SkySurveyEquirectangularUv {
  u: number;
  v: number;
}

/**
 * 真实全天摄影底图的纯数学服务。
 *
 * 图像本身不会参与天体命中、规划或设备控制；这里仅负责将普通星图的
 * 赤道 J2000 方向稳定映射到经过坐标校准的全天巡天纹理坐标。
 */
export class SkySurveyBackdropMath {
  private static readonly EPSILON: number = 0.0000001;

  /**
   * 将赤经赤纬转换为赤道 J2000 单位方向。raHours 会自动跨 0h/24h 回绕。
   */
  static equatorialCoordinateToDirection(raHours: number, decDegrees: number): SkySurveyDirection {
    const normalizedRaHours: number = SkySurveyBackdropMath.wrap(raHours, 24.0);
    const safeDecDegrees: number = SkySurveyBackdropMath.clamp(decDegrees, -90.0, 90.0);
    const raRadians: number = normalizedRaHours * Math.PI / 12.0;
    const decRadians: number = safeDecDegrees * Math.PI / 180.0;
    const decCosine: number = Math.cos(decRadians);
    return {
      x: decCosine * Math.cos(raRadians),
      y: decCosine * Math.sin(raRadians),
      z: Math.sin(decRadians)
    };
  }

  /**
   * 使用 IAU J2000 赤道 -> 银河旋转矩阵把单位方向转换为银河经纬度。
   * 输入即使因上游异常不是单位向量，也会先归一化，避免底图线程出现 NaN。
   */
  static equatorialDirectionToGalactic(directionX: number, directionY: number,
    directionZ: number): SkySurveyGalacticCoordinate {
    const direction: SkySurveyDirection = SkySurveyBackdropMath.normalizeDirection(
      directionX, directionY, directionZ);

    // 标准 IAU J2000 Equatorial -> Galactic 旋转矩阵。
    const galacticX: number = -0.0548755604 * direction.x - 0.8734370902 * direction.y -
      0.4838350155 * direction.z;
    const galacticY: number = 0.4941094279 * direction.x - 0.4448296300 * direction.y +
      0.7469822445 * direction.z;
    const galacticZ: number = -0.8676661490 * direction.x - 0.1980763734 * direction.y +
      0.4559837762 * direction.z;
    const normalizedGalactic: SkySurveyDirection = SkySurveyBackdropMath.normalizeDirection(
      galacticX, galacticY, galacticZ);
    return {
      longitudeDegrees: SkySurveyBackdropMath.wrap(
        Math.atan2(normalizedGalactic.y, normalizedGalactic.x) * 180.0 / Math.PI, 360.0),
      latitudeDegrees: Math.asin(SkySurveyBackdropMath.clamp(normalizedGalactic.z, -1.0, 1.0)) *
        180.0 / Math.PI
    };
  }

  /**
   * 将银河经纬度映射为 2:1 等距柱状图 UV。
   *
   * 原图约定为 l=0 位于水平中心，银河经度向左增加，银河纬度向上增加。
   * 因而 u 必须采用减号；这条约定是防止真实银河底图发生左右镜像的关键。
   */
  static galacticEquirectangularUv(longitudeDegrees: number,
    latitudeDegrees: number): SkySurveyEquirectangularUv {
    const longitude: number = SkySurveyBackdropMath.wrap(longitudeDegrees, 360.0);
    const latitude: number = SkySurveyBackdropMath.clamp(latitudeDegrees, -90.0, 90.0);
    return {
      u: SkySurveyBackdropMath.wrap(0.5 - longitude / 360.0, 1.0),
      v: SkySurveyBackdropMath.clamp(0.5 - latitude / 180.0, 0.0, 1.0)
    };
  }

  /** 赤道 J2000 单位方向到全天摄影底图 UV 的快捷链路。 */
  static equatorialDirectionToEquirectangularUv(directionX: number, directionY: number,
    directionZ: number): SkySurveyEquirectangularUv {
    const galactic: SkySurveyGalacticCoordinate = SkySurveyBackdropMath.equatorialDirectionToGalactic(
      directionX, directionY, directionZ);
    return SkySurveyBackdropMath.galacticEquirectangularUv(
      galactic.longitudeDegrees, galactic.latitudeDegrees);
  }

  /**
   * 反解普通星图当前屏幕像素对应的赤道 J2000 单位方向。
   *
   * 此处与 NormalSkyProjectionService 的立体投影公式严格互逆，避免底图投影、
   * 目录对象和触摸命中使用不同坐标链后产生可见漂移。
   */
  static inverseStereographicScreenDirection(xPixels: number, yPixels: number,
    prepared: NormalSkyPreparedProjection): SkySurveyDirection {
    const screenX: number = SkySurveyBackdropMath.finiteOr(xPixels, prepared.widthPixels / 2.0) -
      prepared.widthPixels / 2.0;
    const screenY: number = SkySurveyBackdropMath.finiteOr(yPixels, prepared.heightPixels / 2.0) -
      prepared.heightPixels / 2.0;
    const unrotatedX: number = screenX * prepared.rotationCosine +
      screenY * prepared.rotationSine;
    const unrotatedY: number = -screenX * prepared.rotationSine +
      screenY * prepared.rotationCosine;
    const pixelScale: number = Math.max(SkySurveyBackdropMath.EPSILON,
      Math.abs(prepared.pixelScale));
    const planeEast: number = -unrotatedX / pixelScale;
    const planeNorth: number = -unrotatedY / pixelScale;
    const radiusSquared: number = planeEast * planeEast + planeNorth * planeNorth;
    const denominator: number = 1.0 + radiusSquared / 4.0;
    const centerFactor: number = (1.0 - radiusSquared / 4.0) / denominator;
    const tangentFactor: number = 1.0 / denominator;
    return SkySurveyBackdropMath.normalizeDirection(
      centerFactor * prepared.centerX + tangentFactor *
        (planeEast * prepared.eastX + planeNorth * prepared.northX),
      centerFactor * prepared.centerY + tangentFactor *
        (planeEast * prepared.eastY + planeNorth * prepared.northY),
      centerFactor * prepared.centerZ + tangentFactor *
        (planeEast * prepared.eastZ + planeNorth * prepared.northZ));
  }

  /** 从普通星图屏幕位置直接取得全天摄影底图 UV。 */
  static screenToEquirectangularUv(xPixels: number, yPixels: number,
    prepared: NormalSkyPreparedProjection): SkySurveyEquirectangularUv {
    const direction: SkySurveyDirection = SkySurveyBackdropMath.inverseStereographicScreenDirection(
      xPixels, yPixels, prepared);
    return SkySurveyBackdropMath.equatorialDirectionToEquirectangularUv(
      direction.x, direction.y, direction.z);
  }

  private static normalizeDirection(x: number, y: number, z: number): SkySurveyDirection {
    const safeX: number = SkySurveyBackdropMath.finiteOr(x, 1.0);
    const safeY: number = SkySurveyBackdropMath.finiteOr(y, 0.0);
    const safeZ: number = SkySurveyBackdropMath.finiteOr(z, 0.0);
    const length: number = Math.sqrt(safeX * safeX + safeY * safeY + safeZ * safeZ);
    if (!Number.isFinite(length) || length < SkySurveyBackdropMath.EPSILON) {
      return { x: 1.0, y: 0.0, z: 0.0 };
    }
    return {
      x: safeX / length,
      y: safeY / length,
      z: safeZ / length
    };
  }

  private static finiteOr(value: number, fallback: number): number {
    return Number.isFinite(value) ? value : fallback;
  }

  private static wrap(value: number, range: number): number {
    const safeValue: number = SkySurveyBackdropMath.finiteOr(value, 0.0);
    const remainder: number = safeValue % range;
    return remainder < 0.0 ? remainder + range : remainder;
  }

  private static clamp(value: number, minimum: number, maximum: number): number {
    const safeValue: number = SkySurveyBackdropMath.finiteOr(value, 0.0);
    return Math.max(minimum, Math.min(maximum, safeValue));
  }
}

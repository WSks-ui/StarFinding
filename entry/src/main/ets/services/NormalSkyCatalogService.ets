import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { EquatorialCoordinate, EquatorialFrame } from '../models/DomainModels';

interface RawSkyLinePoint {
  raHours: number;
  decDegrees: number;
}

interface RawConstellationLines {
  designation: string;
  lines: RawSkyLinePoint[][];
}

interface RawSkyLineMetadata {
  source: string;
  revision: string;
  license: string;
  constellationCount: number;
}

interface RawSkyLineDocument {
  metadata: RawSkyLineMetadata;
  constellations: RawConstellationLines[];
}

export interface ConstellationLineGroup {
  designation: string;
  lines: EquatorialCoordinate[][];
  /** 星座组的保守球面包围帽；用于在投影前排除明确位于视口外的整组线段。 */
  centerDirectionX: number;
  centerDirectionY: number;
  centerDirectionZ: number;
  angularRadiusDegrees: number;
}

export interface ConstellationSphericalBounds {
  centerDirectionX: number;
  centerDirectionY: number;
  centerDirectionZ: number;
  angularRadiusDegrees: number;
}

export interface NormalSkyCatalogMetadata {
  source: string;
  revision: string;
  license: string;
  constellationCount: number;
  lineCount: number;
}

/** 加载固定版本的星座线 rawfile；星体与 Messier 目录继续由各自服务负责。 */
export class NormalSkyCatalogService {
  private static readonly RAW_FILE_NAME: string = 'normal_sky_lines.json';
  private static readonly BOUND_PADDING_DEGREES: number = 2.0;
  private static readonly MAXIMUM_CULLABLE_RADIUS_DEGREES: number = 85.0;
  private groups: ConstellationLineGroup[] = [];
  private metadata: NormalSkyCatalogMetadata | undefined = undefined;
  private loadingPromise: Promise<NormalSkyCatalogMetadata> | undefined = undefined;

  isLoaded(): boolean {
    return this.metadata !== undefined;
  }

  async load(context: common.Context): Promise<NormalSkyCatalogMetadata> {
    if (this.metadata !== undefined) {
      return this.copyMetadata(this.metadata);
    }
    if (this.loadingPromise !== undefined) {
      return this.copyMetadata(await this.loadingPromise);
    }
    this.loadingPromise = this.loadInternal(context);
    try {
      return this.copyMetadata(await this.loadingPromise);
    } finally {
      this.loadingPromise = undefined;
    }
  }

  getLineGroups(): ConstellationLineGroup[] {
    return this.groups;
  }

  getMetadata(): NormalSkyCatalogMetadata | undefined {
    return this.metadata === undefined ? undefined : this.copyMetadata(this.metadata);
  }

  clear(): void {
    this.groups = [];
    this.metadata = undefined;
    this.loadingPromise = undefined;
  }

  private async loadInternal(context: common.Context): Promise<NormalSkyCatalogMetadata> {
    let bytes: Uint8Array;
    try {
      bytes = await context.resourceManager.getRawFileContent(NormalSkyCatalogService.RAW_FILE_NAME);
    } catch (error) {
      throw new Error(`读取离线星座线失败：${error}`);
    }
    let document: RawSkyLineDocument;
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true });
      document = JSON.parse(decoder.decodeToString(bytes)) as RawSkyLineDocument;
      if (document === null || document.metadata === undefined ||
        !Array.isArray(document.constellations)) {
        throw new Error('缺少 metadata 或 constellations');
      }
    } catch (error) {
      throw new Error(`解析离线星座线失败：${error}`);
    }

    const groups: ConstellationLineGroup[] = [];
    let lineCount: number = 0;
    for (let groupIndex: number = 0; groupIndex < document.constellations.length; groupIndex++) {
      const rawGroup: RawConstellationLines = document.constellations[groupIndex];
      if (rawGroup === undefined || typeof rawGroup.designation !== 'string' ||
        !Array.isArray(rawGroup.lines)) {
        continue;
      }
      const lines: EquatorialCoordinate[][] = [];
      for (let lineIndex: number = 0; lineIndex < rawGroup.lines.length; lineIndex++) {
        const rawLine: RawSkyLinePoint[] = rawGroup.lines[lineIndex];
        const line: EquatorialCoordinate[] = [];
        for (let pointIndex: number = 0; pointIndex < rawLine.length; pointIndex++) {
          const point: RawSkyLinePoint = rawLine[pointIndex];
          if (point !== undefined && Number.isFinite(point.raHours) && Number.isFinite(point.decDegrees) &&
            point.raHours >= 0.0 && point.raHours < 24.0 &&
            point.decDegrees >= -90.0 && point.decDegrees <= 90.0) {
            line.push({
              raHours: point.raHours,
              decDegrees: point.decDegrees,
              frame: EquatorialFrame.ICRS_J2000
            });
          }
        }
        if (line.length >= 2) {
          lines.push(line);
          lineCount++;
        }
      }
      const bounds: ConstellationSphericalBounds =
        NormalSkyCatalogService.buildSphericalBounds(lines);
      groups.push({
        designation: rawGroup.designation,
        lines: lines,
        centerDirectionX: bounds.centerDirectionX,
        centerDirectionY: bounds.centerDirectionY,
        centerDirectionZ: bounds.centerDirectionZ,
        angularRadiusDegrees: bounds.angularRadiusDegrees
      });
    }
    if (groups.length !== 88) {
      throw new Error(`星座线应覆盖 88 个星座，实际为 ${groups.length}`);
    }
    this.groups = groups;
    this.metadata = {
      source: document.metadata.source,
      revision: document.metadata.revision,
      license: document.metadata.license,
      constellationCount: groups.length,
      lineCount: lineCount
    };
    return this.metadata;
  }

  /**
   * 以全部星座折线顶点的平均方向建立球面包围帽。
   * 半径超过 85° 时关闭整组裁剪，避免极大或分离星座在宽视场、近天极时发生漏线。
   */
  static buildSphericalBounds(lines: EquatorialCoordinate[][]): ConstellationSphericalBounds {
    let sumX: number = 0.0;
    let sumY: number = 0.0;
    let sumZ: number = 0.0;
    let pointCount: number = 0;
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      const line: EquatorialCoordinate[] = lines[lineIndex];
      for (let pointIndex: number = 0; pointIndex < line.length; pointIndex++) {
        const direction: number[] = NormalSkyCatalogService.coordinateDirection(line[pointIndex]);
        sumX += direction[0];
        sumY += direction[1];
        sumZ += direction[2];
        pointCount++;
      }
    }
    const norm: number = Math.sqrt(sumX * sumX + sumY * sumY + sumZ * sumZ);
    if (pointCount === 0 || norm < 0.000001) {
      return {
        centerDirectionX: 1.0,
        centerDirectionY: 0.0,
        centerDirectionZ: 0.0,
        angularRadiusDegrees: 180.0
      };
    }
    const centerX: number = sumX / norm;
    const centerY: number = sumY / norm;
    const centerZ: number = sumZ / norm;
    let maximumAngleDegrees: number = 0.0;
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      const line: EquatorialCoordinate[] = lines[lineIndex];
      for (let pointIndex: number = 0; pointIndex < line.length; pointIndex++) {
        const direction: number[] = NormalSkyCatalogService.coordinateDirection(line[pointIndex]);
        const dot: number = Math.max(-1.0, Math.min(1.0,
          centerX * direction[0] + centerY * direction[1] + centerZ * direction[2]));
        maximumAngleDegrees = Math.max(maximumAngleDegrees, Math.acos(dot) * 180.0 / Math.PI);
      }
    }
    const paddedRadius: number = Math.min(180.0,
      maximumAngleDegrees + NormalSkyCatalogService.BOUND_PADDING_DEGREES);
    return {
      centerDirectionX: centerX,
      centerDirectionY: centerY,
      centerDirectionZ: centerZ,
      angularRadiusDegrees: paddedRadius >
        NormalSkyCatalogService.MAXIMUM_CULLABLE_RADIUS_DEGREES ? 180.0 : paddedRadius
    };
  }

  private static coordinateDirection(coordinate: EquatorialCoordinate): number[] {
    const rightAscensionRadians: number = coordinate.raHours * Math.PI / 12.0;
    const declinationRadians: number = coordinate.decDegrees * Math.PI / 180.0;
    const declinationCosine: number = Math.cos(declinationRadians);
    return [
      declinationCosine * Math.cos(rightAscensionRadians),
      declinationCosine * Math.sin(rightAscensionRadians),
      Math.sin(declinationRadians)
    ];
  }

  private copyMetadata(metadata: NormalSkyCatalogMetadata): NormalSkyCatalogMetadata {
    return {
      source: metadata.source,
      revision: metadata.revision,
      license: metadata.license,
      constellationCount: metadata.constellationCount,
      lineCount: metadata.lineCount
    };
  }
}

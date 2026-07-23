import { common2D } from '@kit.ArkGraphics2D';
import {
  NormalSkyViewport,
  SkyMapSize
} from '../models/NormalSkyModels';
import {
  NormalSkyPreparedProjection,
  NormalSkyProjectionService
} from './NormalSkyProjectionService';
import {
  SkySurveyBackdropMath,
  SkySurveyDirection
} from './SkySurveyBackdropMath';

export interface SkySurveyMeshFrame {
  meshWidth: number;
  meshHeight: number;
  vertices: Array<number>;
  colors: Array<number>;
  positions: Array<common2D.Point>;
  textureCoordinates: Array<common2D.Point>;
  indices: Array<number>;
  indexCount: number;
  drawPositions: Array<common2D.Point>;
  drawTextureCoordinates: Array<common2D.Point>;
  drawVertexCount: number;
  cornerAngleDegrees: number;
  opaqueAngleDegrees: number;
  clipAngleDegrees: number;
  visibleVertexCount: number;
  visibleTriangleCount: number;
}

/**
 * 将完整银河等距柱状纹理实时投影到普通星图的立体投影视口。
 *
 * 拓扑方向只在构造时计算一次；每个显示帧只更新普通 number 数组中的屏幕坐标与透明度。
 * drawPixelMapMesh 要求纹理坐标均匀分布，因此顶点顺序严格为从上到下、从左到右。
 */
export class SkySurveyMeshProjectionService {
  static readonly DEFAULT_MESH_WIDTH: number = 96;
  static readonly DEFAULT_MESH_HEIGHT: number = 48;

  private static readonly TEXTURE_WIDTH: number = 6000.0;
  private static readonly TEXTURE_HEIGHT: number = 3000.0;
  private static readonly MAXIMUM_CLIP_ANGLE_DEGREES: number = 165.0;
  private static readonly MINIMUM_DENOMINATOR: number = 0.0001;
  private static readonly OPAQUE_WHITE: number = 0xFFFFFFFF;
  private static readonly TRANSPARENT_WHITE: number = 0x00FFFFFF;

  private readonly meshWidth: number;
  private readonly meshHeight: number;
  private readonly directionsX: Float64Array;
  private readonly directionsY: Float64Array;
  private readonly directionsZ: Float64Array;
  private readonly fallbackScreenX: Float64Array;
  private readonly fallbackScreenY: Float64Array;
  private readonly vertices: Array<number>;
  private readonly colors: Array<number>;
  private readonly positions: Array<common2D.Point>;
  private readonly textureCoordinates: Array<common2D.Point>;
  private readonly indices: Array<number>;
  private readonly drawPositions: Array<common2D.Point>;
  private readonly drawTextureCoordinates: Array<common2D.Point>;
  private readonly drawPositionPool: Array<common2D.Point>;
  private readonly drawTextureCoordinatePool: Array<common2D.Point>;
  private readonly maximumIndexCount: number;
  private readonly projectableVertices: Uint8Array;
  private readonly cellDiagonalDegrees: number;

  constructor(meshWidth: number = SkySurveyMeshProjectionService.DEFAULT_MESH_WIDTH,
    meshHeight: number = SkySurveyMeshProjectionService.DEFAULT_MESH_HEIGHT) {
    this.meshWidth = Math.max(2, Math.round(meshWidth));
    this.meshHeight = Math.max(2, Math.round(meshHeight));
    const vertexCount: number = (this.meshWidth + 1) * (this.meshHeight + 1);
    this.directionsX = new Float64Array(vertexCount);
    this.directionsY = new Float64Array(vertexCount);
    this.directionsZ = new Float64Array(vertexCount);
    this.fallbackScreenX = new Float64Array(vertexCount);
    this.fallbackScreenY = new Float64Array(vertexCount);
    this.vertices = new Array<number>(vertexCount * 2);
    this.colors = new Array<number>(vertexCount);
    this.positions = new Array<common2D.Point>(vertexCount);
    this.textureCoordinates = new Array<common2D.Point>(vertexCount);
    this.maximumIndexCount = this.meshWidth * this.meshHeight * 6;
    this.indices = new Array<number>(this.maximumIndexCount);
    this.drawPositions = [];
    this.drawTextureCoordinates = [];
    this.drawPositionPool = new Array<common2D.Point>(this.maximumIndexCount);
    this.drawTextureCoordinatePool = new Array<common2D.Point>(this.maximumIndexCount);
    /*
     * API 23 的部分真机在索引网格数量较大时会只提交前半段三角形，画面表现为阶梯状黑洞。
     * 非索引 TRIANGLES 是同一官方接口支持的路径：这里一次性准备最大容量的 Point 对象，
     * 每帧只覆盖有效前缀，避免连续拖动期间创建上万临时对象。
     */
    for (let index: number = 0; index < this.maximumIndexCount; index++) {
      this.drawPositionPool[index] = { x: 0.0, y: 0.0 };
      this.drawTextureCoordinatePool[index] = { x: 0.0, y: 0.0 };
    }
    this.projectableVertices = new Uint8Array(vertexCount);
    this.cellDiagonalDegrees = Math.sqrt(
      360.0 / this.meshWidth * (360.0 / this.meshWidth) +
      180.0 / this.meshHeight * (180.0 / this.meshHeight));
    this.initializeTopology();
  }

  /**
   * 生成当前视口的网格。返回数组由本服务复用，调用方应立即交给 Drawing Canvas，
   * 不应把它们复制进 @State 或跨线程长期保存。
   */
  project(viewport: NormalSkyViewport, size: SkyMapSize): SkySurveyMeshFrame {
    const prepared: NormalSkyPreparedProjection = NormalSkyProjectionService.prepare(viewport, size);
    const cornerAngleDegrees: number = this.cornerAngleDegrees(prepared);
    const opaqueAngleDegrees: number = Math.min(
      SkySurveyMeshProjectionService.MAXIMUM_CLIP_ANGLE_DEGREES - 1.0,
      cornerAngleDegrees + this.cellDiagonalDegrees);
    const clipAngleDegrees: number = Math.min(
      SkySurveyMeshProjectionService.MAXIMUM_CLIP_ANGLE_DEGREES,
      Math.max(opaqueAngleDegrees + 0.5,
        cornerAngleDegrees + this.cellDiagonalDegrees * 2.0));
    const opaqueDot: number = Math.cos(opaqueAngleDegrees * Math.PI / 180.0);
    const clipDot: number = Math.cos(clipAngleDegrees * Math.PI / 180.0);
    const screenCenterX: number = prepared.widthPixels / 2.0;
    const screenCenterY: number = prepared.heightPixels / 2.0;
    const safeRadius: number = Math.max(prepared.widthPixels, prepared.heightPixels) * 5.0;
    let visibleVertexCount: number = 0;

    for (let index: number = 0; index < this.directionsX.length; index++) {
      const directionX: number = this.directionsX[index];
      const directionY: number = this.directionsY[index];
      const directionZ: number = this.directionsZ[index];
      const centerDot: number = directionX * prepared.centerX +
        directionY * prepared.centerY + directionZ * prepared.centerZ;
      const eastDot: number = directionX * prepared.eastX +
        directionY * prepared.eastY + directionZ * prepared.eastZ;
      const northDot: number = directionX * prepared.northX +
        directionY * prepared.northY + directionZ * prepared.northZ;
      const denominator: number = 1.0 + centerDot;
      let xPixels: number;
      let yPixels: number;
      let alpha: number = 0;

      if (centerDot >= clipDot && denominator > SkySurveyMeshProjectionService.MINIMUM_DENOMINATOR) {
        const planeEast: number = 2.0 * eastDot / denominator;
        const planeNorth: number = 2.0 * northDot / denominator;
        const rawX: number = -planeEast * prepared.pixelScale;
        const rawY: number = -planeNorth * prepared.pixelScale;
        const rotatedX: number = rawX * prepared.rotationCosine -
          rawY * prepared.rotationSine;
        const rotatedY: number = rawX * prepared.rotationSine +
          rawY * prepared.rotationCosine;
        xPixels = screenCenterX + this.clamp(rotatedX, -safeRadius, safeRadius);
        yPixels = screenCenterY + this.clamp(rotatedY, -safeRadius, safeRadius);
        if (centerDot >= opaqueDot) {
          alpha = 255;
        } else {
          const fade: number = this.clamp(
            (centerDot - clipDot) / Math.max(0.000001, opaqueDot - clipDot), 0.0, 1.0);
          alpha = Math.round(fade * 255.0);
        }
        visibleVertexCount++;
        this.projectableVertices[index] = 1;
      } else {
        /*
         * drawPixelMapMesh 不能删除单个背面三角形。裁剪外顶点必须是有限坐标并位于
         * 屏幕外安全圆环；若直接传 Infinity 或把对跖点放到中心，真机会产生贯穿画面的
         * 折叠三角形。fallback 方向在拓扑阶段预计算，精确对跖点也有确定结果。
         */
        let screenDirectionX: number = -(eastDot * prepared.rotationCosine -
          northDot * prepared.rotationSine);
        let screenDirectionY: number = -(eastDot * prepared.rotationSine +
          northDot * prepared.rotationCosine);
        const screenDirectionLength: number = Math.sqrt(
          screenDirectionX * screenDirectionX + screenDirectionY * screenDirectionY);
        if (screenDirectionLength > 0.000001) {
          screenDirectionX /= screenDirectionLength;
          screenDirectionY /= screenDirectionLength;
        } else {
          screenDirectionX = this.fallbackScreenX[index];
          screenDirectionY = this.fallbackScreenY[index];
        }
        xPixels = screenCenterX + screenDirectionX * safeRadius;
        yPixels = screenCenterY + screenDirectionY * safeRadius;
        this.projectableVertices[index] = 0;
      }

      const vertexOffset: number = index * 2;
      this.vertices[vertexOffset] = Number.isFinite(xPixels) ? xPixels : screenCenterX;
      this.vertices[vertexOffset + 1] = Number.isFinite(yPixels) ? yPixels : screenCenterY;
      this.positions[index].x = this.vertices[vertexOffset];
      this.positions[index].y = this.vertices[vertexOffset + 1];
      this.colors[index] = alpha >= 255 ?
        SkySurveyMeshProjectionService.OPAQUE_WHITE :
        (alpha <= 0 ? SkySurveyMeshProjectionService.TRANSPARENT_WHITE :
          alpha * 0x01000000 + 0x00FFFFFF);
    }

    const indexCount: number = this.buildVisibleTriangleIndices();
    this.updateDrawTriangles(indexCount);
    return {
      meshWidth: this.meshWidth,
      meshHeight: this.meshHeight,
      vertices: this.vertices,
      colors: this.colors,
      positions: this.positions,
      textureCoordinates: this.textureCoordinates,
      indices: this.indices,
      indexCount: indexCount,
      drawPositions: this.drawPositions,
      drawTextureCoordinates: this.drawTextureCoordinates,
      drawVertexCount: indexCount,
      cornerAngleDegrees: cornerAngleDegrees,
      opaqueAngleDegrees: opaqueAngleDegrees,
      clipAngleDegrees: clipAngleDegrees,
      visibleVertexCount: visibleVertexCount,
      visibleTriangleCount: indexCount / 3
    };
  }

  private initializeTopology(): void {
    const rowWidth: number = this.meshWidth + 1;
    for (let row: number = 0; row <= this.meshHeight; row++) {
      let firstDirection: SkySurveyDirection | undefined = undefined;
      for (let column: number = 0; column <= this.meshWidth; column++) {
        const index: number = row * rowWidth + column;
        let direction: SkySurveyDirection;
        if (column === this.meshWidth && firstDirection !== undefined) {
          // 最后一列逐位复制第一列，避免 sin(π) 与 sin(-π) 的浮点尾差形成几何细缝。
          direction = firstDirection;
        } else if (row === 0) {
          direction = SkySurveyBackdropMath.galacticDirectionToEquatorial(0.0, 0.0, 1.0);
        } else if (row === this.meshHeight) {
          direction = SkySurveyBackdropMath.galacticDirectionToEquatorial(0.0, 0.0, -1.0);
        } else {
          direction = SkySurveyBackdropMath.galacticEquirectangularDirection(
            column / this.meshWidth, row / this.meshHeight);
        }
        if (column === 0) {
          firstDirection = direction;
        }
        this.directionsX[index] = direction.x;
        this.directionsY[index] = direction.y;
        this.directionsZ[index] = direction.z;
        const fallbackAngle: number = Math.PI * 2.0 *
          (column / this.meshWidth + row / this.meshHeight * 0.125);
        this.fallbackScreenX[index] = Math.cos(fallbackAngle);
        this.fallbackScreenY[index] = Math.sin(fallbackAngle);
        this.vertices[index * 2] = 0.0;
        this.vertices[index * 2 + 1] = 0.0;
        this.colors[index] = SkySurveyMeshProjectionService.TRANSPARENT_WHITE;
        const position: common2D.Point = { x: 0.0, y: 0.0 };
        this.positions[index] = position;
        /*
         * ImageShader 使用 PixelMap 本地像素坐标。最后一列故意取 textureWidth，
         * 配合横向 REPEAT 让 u=1 精确回到 u=0；上下方向不重复，保留两个银河极点。
         */
        const textureCoordinate: common2D.Point = {
          x: SkySurveyMeshProjectionService.TEXTURE_WIDTH * column / this.meshWidth,
          y: SkySurveyMeshProjectionService.TEXTURE_HEIGHT * row / this.meshHeight
        };
        this.textureCoordinates[index] = textureCoordinate;
      }
    }
  }

  /**
   * 只提交投影奇点之前的真实球面三角形。
   *
   * drawPixelMapMesh 会无条件绘制完整规则网格，即使把背面顶点设为透明，也仍会把背面
   * 单元连接成跨越屏幕的折叠三角形。API 23 drawVertices 允许显式索引，这里直接跳过
   * 包含裁剪外顶点的三角形。裁剪角比所有支持布局的屏幕角点多出至少一个网格单元，
   * 因此过滤不会在可见画面内留下孔洞。
   */
  private buildVisibleTriangleIndices(): number {
    const rowWidth: number = this.meshWidth + 1;
    let indexCount: number = 0;
    /*
     * API 23 真机会校验 indices 数组本身，而不只是读取 indexCount 指定的前缀。
     * 上一帧为了满足原生接口已把 length 收缩到有效索引数，因此本帧写入前先恢复最大容量；
     * 填充完成后再收缩到精确长度，既避免尾部空槽触发 “Invalid indices params”，也继续
     * 复用同一个 Array，防止连续拖动时每帧 slice/new 造成 GC 抖动。
     */
    this.indices.length = this.maximumIndexCount;
    for (let row: number = 0; row < this.meshHeight; row++) {
      for (let column: number = 0; column < this.meshWidth; column++) {
        const topLeft: number = row * rowWidth + column;
        const topRight: number = topLeft + 1;
        const bottomLeft: number = topLeft + rowWidth;
        const bottomRight: number = bottomLeft + 1;
        if (this.projectableVertices[topLeft] > 0 &&
          this.projectableVertices[topRight] > 0 &&
          this.projectableVertices[bottomLeft] > 0) {
          this.indices[indexCount++] = topLeft;
          this.indices[indexCount++] = topRight;
          this.indices[indexCount++] = bottomLeft;
        }
        if (this.projectableVertices[topRight] > 0 &&
          this.projectableVertices[bottomRight] > 0 &&
          this.projectableVertices[bottomLeft] > 0) {
          this.indices[indexCount++] = topRight;
          this.indices[indexCount++] = bottomRight;
          this.indices[indexCount++] = bottomLeft;
        }
      }
    }
    this.indices.length = indexCount;
    return indexCount;
  }

  /**
   * 将可见索引展开为非索引三角形。
   *
   * drawVertices 的 indexCount=0、indices=null 路径由 API 23 明确支持。展开后每三个连续顶点
   * 就是一枚独立三角形，不再依赖真机的 uint16 索引转换，也不会把未投影的背面网格重新连接。
   */
  private updateDrawTriangles(indexCount: number): void {
    /*
     * 真机原生层要求 positions.length 与 vertexCount、texs.length 完全一致，不能直接传入
     * 最大容量数组。输出数组只保存对象引用并收缩到有效长度，Point 实例仍由独立对象池持有，
     * 因此下一帧扩容时不会重新创建成千上万个对象。
     */
    this.drawPositions.length = indexCount;
    this.drawTextureCoordinates.length = indexCount;
    for (let drawIndex: number = 0; drawIndex < indexCount; drawIndex++) {
      const sourceIndex: number = this.indices[drawIndex];
      const sourcePosition: common2D.Point = this.positions[sourceIndex];
      const sourceTextureCoordinate: common2D.Point = this.textureCoordinates[sourceIndex];
      const drawPosition: common2D.Point = this.drawPositionPool[drawIndex];
      const drawTextureCoordinate: common2D.Point = this.drawTextureCoordinatePool[drawIndex];
      drawPosition.x = sourcePosition.x;
      drawPosition.y = sourcePosition.y;
      drawTextureCoordinate.x = sourceTextureCoordinate.x;
      drawTextureCoordinate.y = sourceTextureCoordinate.y;
      this.drawPositions[drawIndex] = drawPosition;
      this.drawTextureCoordinates[drawIndex] = drawTextureCoordinate;
    }
  }

  private cornerAngleDegrees(prepared: NormalSkyPreparedProjection): number {
    const halfPlaneX: number = prepared.widthPixels /
      (2.0 * Math.max(0.000001, prepared.pixelScale));
    const halfPlaneY: number = prepared.heightPixels /
      (2.0 * Math.max(0.000001, prepared.pixelScale));
    return 2.0 * Math.atan(Math.sqrt(
      halfPlaneX * halfPlaneX + halfPlaneY * halfPlaneY) / 2.0) * 180.0 / Math.PI;
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

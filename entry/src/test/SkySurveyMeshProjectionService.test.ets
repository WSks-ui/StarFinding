import { describe, expect, it } from '@ohos/hypium';
import { common2D } from '@kit.ArkGraphics2D';
import {
  NormalSkyViewport,
  SkyMapOrientation,
  SkyMapSize
} from '../main/ets/models/NormalSkyModels';
import {
  SkySurveyMeshFrame,
  SkySurveyMeshProjectionService
} from '../main/ets/services/SkySurveyMeshProjectionService';

const SCREENSHOT_VIEWPORT: NormalSkyViewport = {
  centerRaHours: 12.84,
  centerDecDegrees: -71.5,
  fieldOfViewDegrees: 160.0,
  rotationDegrees: 37.0,
  orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
};

function assertFiniteMesh(frame: SkySurveyMeshFrame, size: SkyMapSize): void {
  const vertexCount: number = (frame.meshWidth + 1) * (frame.meshHeight + 1);
  const maximumCoordinate: number = Math.max(size.widthPixels, size.heightPixels) * 6.0;
  expect(frame.vertices.length ===
    vertexCount * 2).assertTrue();
  expect(frame.colors.length === vertexCount).assertTrue();
  expect(frame.positions.length === vertexCount).assertTrue();
  expect(frame.textureCoordinates.length === vertexCount).assertTrue();
  expect(frame.indices.length === frame.indexCount).assertTrue();
  expect(frame.indexCount > 0 && frame.indexCount % 3 === 0).assertTrue();
  expect(frame.drawVertexCount === frame.indexCount).assertTrue();
  expect(frame.drawPositions.length === frame.drawVertexCount).assertTrue();
  expect(frame.drawTextureCoordinates.length === frame.drawVertexCount).assertTrue();
  let finiteVertices: boolean = true;
  for (let index: number = 0; index < frame.vertices.length; index++) {
    if (!Number.isFinite(frame.vertices[index]) ||
      Math.abs(frame.vertices[index]) > maximumCoordinate) {
      finiteVertices = false;
      break;
    }
  }
  expect(finiteVertices).assertTrue();
  let expandedTrianglesValid: boolean = true;
  for (let index: number = 0; index < frame.indices.length; index++) {
    const sourceIndex: number = frame.indices[index];
    if (sourceIndex < 0 || sourceIndex >= vertexCount ||
      frame.drawPositions[index].x !== frame.positions[sourceIndex].x ||
      frame.drawPositions[index].y !== frame.positions[sourceIndex].y ||
      frame.drawTextureCoordinates[index].x !== frame.textureCoordinates[sourceIndex].x ||
      frame.drawTextureCoordinates[index].y !== frame.textureCoordinates[sourceIndex].y) {
      expandedTrianglesValid = false;
      break;
    }
  }
  expect(expandedTrianglesValid).assertTrue();
}

export default function skySurveyMeshProjectionServiceTest(): void {
  describe('全天摄影底图球面网格', () => {
    it('南天极160度视场的全部顶点有限且纹理首末列几何闭合', 0, () => {
      const service: SkySurveyMeshProjectionService = new SkySurveyMeshProjectionService();
      const size: SkyMapSize = { widthPixels: 1024.0, heightPixels: 720.0 };
      const frame: SkySurveyMeshFrame = service.project(SCREENSHOT_VIEWPORT, size);
      assertFiniteMesh(frame, size);
      const rowWidth: number = frame.meshWidth + 1;
      for (let row: number = 0; row <= frame.meshHeight; row++) {
        const firstIndex: number = row * rowWidth;
        const lastIndex: number = firstIndex + frame.meshWidth;
        expect(frame.vertices[firstIndex * 2] === frame.vertices[lastIndex * 2]).assertTrue();
        expect(frame.vertices[firstIndex * 2 + 1] === frame.vertices[lastIndex * 2 + 1]).assertTrue();
        expect(frame.colors[firstIndex] === frame.colors[lastIndex]).assertTrue();
      }
    });

    it('横屏分屏和竖屏都按真实屏幕角点动态扩展裁剪范围', 0, () => {
      const service: SkySurveyMeshProjectionService = new SkySurveyMeshProjectionService();
      const padSize: SkyMapSize = { widthPixels: 1024.0, heightPixels: 720.0 };
      const splitSize: SkyMapSize = { widthPixels: 600.0, heightPixels: 500.0 };
      const portraitSize: SkyMapSize = { widthPixels: 500.0, heightPixels: 900.0 };
      const pad: SkySurveyMeshFrame = service.project(SCREENSHOT_VIEWPORT, padSize);
      const split: SkySurveyMeshFrame = service.project(SCREENSHOT_VIEWPORT, splitSize);
      const portrait: SkySurveyMeshFrame = service.project(SCREENSHOT_VIEWPORT, portraitSize);
      expect(pad.cornerAngleDegrees > 90.0 && pad.cornerAngleDegrees < 93.0).assertTrue();
      expect(split.cornerAngleDegrees > 94.0 && split.cornerAngleDegrees < 97.0).assertTrue();
      expect(portrait.cornerAngleDegrees > 118.0 && portrait.cornerAngleDegrees < 122.0).assertTrue();
      expect(pad.clipAngleDegrees > pad.cornerAngleDegrees).assertTrue();
      expect(split.clipAngleDegrees > split.cornerAngleDegrees).assertTrue();
      expect(portrait.clipAngleDegrees > portrait.cornerAngleDegrees).assertTrue();
      assertFiniteMesh(portrait, portraitSize);
    });

    it('连续拖动旋转复用缓冲且网格不会等待停手后重新生成图片', 0, () => {
      const service: SkySurveyMeshProjectionService = new SkySurveyMeshProjectionService();
      const size: SkyMapSize = { widthPixels: 1024.0, heightPixels: 720.0 };
      const first: SkySurveyMeshFrame = service.project(SCREENSHOT_VIEWPORT, size);
      const firstVertices: Array<number> = first.vertices;
      const firstColors: Array<number> = first.colors;
      const firstIndices: Array<number> = first.indices;
      const firstDrawPositions: Array<common2D.Point> = first.drawPositions;
      const firstDrawTextureCoordinates: Array<common2D.Point> = first.drawTextureCoordinates;
      const centerIndex: number = Math.floor(first.colors.length / 2);
      const firstX: number = first.vertices[centerIndex * 2];
      const firstY: number = first.vertices[centerIndex * 2 + 1];
      const movedViewport: NormalSkyViewport = {
        centerRaHours: 12.90,
        centerDecDegrees: -70.8,
        fieldOfViewDegrees: 154.0,
        rotationDegrees: 42.0,
        orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
      };
      const second: SkySurveyMeshFrame = service.project(movedViewport, size);
      expect(second.vertices === firstVertices).assertTrue();
      expect(second.colors === firstColors).assertTrue();
      expect(second.indices === firstIndices).assertTrue();
      expect(second.drawPositions === firstDrawPositions).assertTrue();
      expect(second.drawTextureCoordinates === firstDrawTextureCoordinates).assertTrue();
      expect(second.indices.length === second.indexCount).assertTrue();
      expect(Number.isFinite(second.vertices[centerIndex * 2]) &&
        Number.isFinite(second.vertices[centerIndex * 2 + 1])).assertTrue();
      expect(Math.abs(second.vertices[centerIndex * 2] - firstX) +
        Math.abs(second.vertices[centerIndex * 2 + 1] - firstY) > 0.01).assertTrue();
    });
  });
}

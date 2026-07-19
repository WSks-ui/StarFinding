import {
  buildLandmarkTensorBuffer,
  buildPalmTensorBuffer
} from '../services/HandImagePreprocessMath';

/**
 * TaskPool 只承担像素复制后的纯 CPU 预处理；MindSpore Model 留在创建它的线程执行，
 * 避免把不可 Sendable 的系统模型对象跨线程传递。
 */
@Concurrent
export function buildPalmTensorTask(yPlaneBuffer: ArrayBuffer,
  yRowStride: number, yPixelStride: number,
  uPlaneBuffer: ArrayBuffer, uRowStride: number, uPixelStride: number,
  vPlaneBuffer: ArrayBuffer, vRowStride: number, vPixelStride: number,
  sourceWidth: number, sourceHeight: number, outputSize: number): ArrayBuffer {
  return buildPalmTensorBuffer(
    yPlaneBuffer, yRowStride, yPixelStride,
    uPlaneBuffer, uRowStride, uPixelStride,
    vPlaneBuffer, vRowStride, vPixelStride,
    sourceWidth, sourceHeight, outputSize);
}

@Concurrent
export function buildLandmarkTensorTask(yPlaneBuffer: ArrayBuffer,
  yRowStride: number, yPixelStride: number,
  uPlaneBuffer: ArrayBuffer, uRowStride: number, uPixelStride: number,
  vPlaneBuffer: ArrayBuffer, vRowStride: number, vPixelStride: number,
  sourceWidth: number, sourceHeight: number, outputSize: number,
  roiCenterX: number, roiCenterY: number, roiWidth: number, roiHeight: number,
  roiRotationRadians: number): ArrayBuffer {
  return buildLandmarkTensorBuffer(
    yPlaneBuffer, yRowStride, yPixelStride,
    uPlaneBuffer, uRowStride, uPixelStride,
    vPlaneBuffer, vRowStride, vPixelStride,
    sourceWidth, sourceHeight, outputSize,
    roiCenterX, roiCenterY, roiWidth, roiHeight, roiRotationRadians);
}

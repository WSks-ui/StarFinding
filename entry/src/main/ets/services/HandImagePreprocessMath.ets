/**
 * 将 CameraKit 的 YUV420 三平面转换为 MediaPipe Lite 模型需要的 NHWC RGB Float32。
 *
 * 该文件保持纯数值实现，既可由 TaskPool Worker 调用，也可由 Hypium 直接验证。
 * 相机平面必须是调用方复制后的自有缓冲，不能在 Image.release() 后继续引用系统缓冲。
 */

function clampByte(value: number): number {
  return Math.max(0.0, Math.min(255.0, value));
}

function samplePlane(buffer: Uint8Array, rowStride: number, pixelStride: number,
  x: number, y: number): number {
  const safeX: number = Math.max(0, Math.floor(x));
  const safeY: number = Math.max(0, Math.floor(y));
  const index: number = safeY * rowStride + safeX * pixelStride;
  if (index < 0 || index >= buffer.length) {
    return 128.0;
  }
  return buffer[index];
}

function samplePlaneBilinear(buffer: Uint8Array, rowStride: number, pixelStride: number,
  x: number, y: number): number {
  const left: number = Math.floor(x);
  const top: number = Math.floor(y);
  const fractionX: number = x - left;
  const fractionY: number = y - top;
  const topLeft: number = samplePlane(buffer, rowStride, pixelStride, left, top);
  const topRight: number = samplePlane(buffer, rowStride, pixelStride, left + 1, top);
  const bottomLeft: number = samplePlane(buffer, rowStride, pixelStride, left, top + 1);
  const bottomRight: number = samplePlane(buffer, rowStride, pixelStride, left + 1, top + 1);
  const topValue: number = topLeft + (topRight - topLeft) * fractionX;
  const bottomValue: number = bottomLeft + (bottomRight - bottomLeft) * fractionX;
  return topValue + (bottomValue - topValue) * fractionY;
}

function writeRgbPixel(output: Float32Array, outputOffset: number,
  yValue: number, uValue: number, vValue: number): void {
  // CameraKit 的 YUV420 默认采用视频范围。最终再截断到 0–255，可同时容忍少量全范围输入。
  const luminance: number = Math.max(0.0, yValue - 16.0);
  const chromaU: number = uValue - 128.0;
  const chromaV: number = vValue - 128.0;
  const red: number = clampByte(1.164 * luminance + 1.596 * chromaV);
  const green: number = clampByte(1.164 * luminance - 0.392 * chromaU - 0.813 * chromaV);
  const blue: number = clampByte(1.164 * luminance + 2.017 * chromaU);
  output[outputOffset] = red / 255.0;
  output[outputOffset + 1] = green / 255.0;
  output[outputOffset + 2] = blue / 255.0;
}

function sampleYuvToRgb(output: Float32Array, outputOffset: number,
  yBuffer: Uint8Array, yRowStride: number, yPixelStride: number,
  uBuffer: Uint8Array, uRowStride: number, uPixelStride: number,
  vBuffer: Uint8Array, vRowStride: number, vPixelStride: number,
  sourceX: number, sourceY: number, sourceWidth: number, sourceHeight: number): void {
  if (sourceX < 0.0 || sourceX > sourceWidth - 1.0 ||
    sourceY < 0.0 || sourceY > sourceHeight - 1.0) {
    output[outputOffset] = 0.0;
    output[outputOffset + 1] = 0.0;
    output[outputOffset + 2] = 0.0;
    return;
  }
  const yValue: number = samplePlaneBilinear(
    yBuffer, yRowStride, yPixelStride, sourceX, sourceY);
  // YUV420 色度分辨率为亮度的一半；rowStride/pixelStride 仍以组件自身缓冲为准。
  const chromaX: number = sourceX / 2.0;
  const chromaY: number = sourceY / 2.0;
  const uValue: number = samplePlaneBilinear(
    uBuffer, uRowStride, uPixelStride, chromaX, chromaY);
  const vValue: number = samplePlaneBilinear(
    vBuffer, vRowStride, vPixelStride, chromaX, chromaY);
  writeRgbPixel(output, outputOffset, yValue, uValue, vValue);
}

export function buildPalmTensorBuffer(yPlaneBuffer: ArrayBuffer,
  yRowStride: number, yPixelStride: number,
  uPlaneBuffer: ArrayBuffer, uRowStride: number, uPixelStride: number,
  vPlaneBuffer: ArrayBuffer, vRowStride: number, vPixelStride: number,
  sourceWidth: number, sourceHeight: number, outputSize: number,
  reusableOutput?: Float32Array): ArrayBuffer {
  /*
   * 相机稳定运行时由分析器传入固定 Float32Array；TaskPool 兼容入口不传该参数，
   * 仍保留原有“返回新 ArrayBuffer”的纯函数行为。这样既不改变模型输入格式，
   * 又避免每个掌心检测帧分配约 432 KiB 的临时张量。
   */
  const expectedLength: number = outputSize * outputSize * 3;
  const output: Float32Array = reusableOutput !== undefined &&
    reusableOutput.length === expectedLength ?
    reusableOutput : new Float32Array(expectedLength);
  if (sourceWidth <= 0 || sourceHeight <= 0 || outputSize <= 0) {
    return output.buffer;
  }
  const yBuffer: Uint8Array = new Uint8Array(yPlaneBuffer);
  const uBuffer: Uint8Array = new Uint8Array(uPlaneBuffer);
  const vBuffer: Uint8Array = new Uint8Array(vPlaneBuffer);
  const scale: number = Math.min(outputSize / sourceWidth, outputSize / sourceHeight);
  const resizedWidth: number = sourceWidth * scale;
  const resizedHeight: number = sourceHeight * scale;
  const left: number = (outputSize - resizedWidth) / 2.0;
  const top: number = (outputSize - resizedHeight) / 2.0;

  for (let outputY: number = 0; outputY < outputSize; outputY++) {
    for (let outputX: number = 0; outputX < outputSize; outputX++) {
      const outputOffset: number = (outputY * outputSize + outputX) * 3;
      const sourceX: number = (outputX - left + 0.5) / scale - 0.5;
      const sourceY: number = (outputY - top + 0.5) / scale - 0.5;
      sampleYuvToRgb(output, outputOffset,
        yBuffer, yRowStride, yPixelStride,
        uBuffer, uRowStride, uPixelStride,
        vBuffer, vRowStride, vPixelStride,
        sourceX, sourceY, sourceWidth, sourceHeight);
    }
  }
  return output.buffer;
}

export function buildLandmarkTensorBuffer(yPlaneBuffer: ArrayBuffer,
  yRowStride: number, yPixelStride: number,
  uPlaneBuffer: ArrayBuffer, uRowStride: number, uPixelStride: number,
  vPlaneBuffer: ArrayBuffer, vRowStride: number, vPixelStride: number,
  sourceWidth: number, sourceHeight: number, outputSize: number,
  roiCenterX: number, roiCenterY: number, roiWidth: number, roiHeight: number,
  roiRotationRadians: number, reusableOutput?: Float32Array): ArrayBuffer {
  /*
   * Landmark 推理占比最高，复用固定输入张量可以减少 GC 抖动；每个像素都会被
   * 覆盖写入，因此不需要在复用前清零。
   */
  const expectedLength: number = outputSize * outputSize * 3;
  const output: Float32Array = reusableOutput !== undefined &&
    reusableOutput.length === expectedLength ?
    reusableOutput : new Float32Array(expectedLength);
  if (sourceWidth <= 0 || sourceHeight <= 0 || outputSize <= 0 ||
    roiWidth <= 0.0 || roiHeight <= 0.0) {
    return output.buffer;
  }
  const yBuffer: Uint8Array = new Uint8Array(yPlaneBuffer);
  const uBuffer: Uint8Array = new Uint8Array(uPlaneBuffer);
  const vBuffer: Uint8Array = new Uint8Array(vPlaneBuffer);
  const cosine: number = Math.cos(roiRotationRadians);
  const sine: number = Math.sin(roiRotationRadians);

  for (let outputY: number = 0; outputY < outputSize; outputY++) {
    for (let outputX: number = 0; outputX < outputSize; outputX++) {
      const localX: number = (outputX + 0.5) / outputSize - 0.5;
      const localY: number = (outputY + 0.5) / outputSize - 0.5;
      const normalizedX: number = roiCenterX +
        cosine * localX * roiWidth - sine * localY * roiHeight;
      const normalizedY: number = roiCenterY +
        sine * localX * roiWidth + cosine * localY * roiHeight;
      const sourceX: number = normalizedX * sourceWidth - 0.5;
      const sourceY: number = normalizedY * sourceHeight - 0.5;
      const outputOffset: number = (outputY * outputSize + outputX) * 3;
      sampleYuvToRgb(output, outputOffset,
        yBuffer, yRowStride, yPixelStride,
        uBuffer, uRowStride, uPixelStride,
        vBuffer, vRowStride, vPixelStride,
        sourceX, sourceY, sourceWidth, sourceHeight);
    }
  }
  return output.buffer;
}

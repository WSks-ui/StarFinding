import { describe, expect, it } from '@ohos/hypium';
import { buildPalmTensorBuffer } from '../main/ets/services/HandImagePreprocessMath';
import {
  HandModelManifest,
  HandModelManifestService,
  HandModelReadinessResult,
  HandTensorSpecification
} from '../main/ets/services/HandModelManifest';
import {
  HandPackedNv21Decoder,
  HandYuvPlaneSet
} from '../main/ets/services/HandLandmarkAnalyzer';
import {
  HandRegionOfInterest,
  MediaPipeHandPipeline,
  PalmDetection
} from '../main/ets/services/MediaPipeHandPipeline';

function tensorSpecification(name: string, shape: number[], elementNum: number): HandTensorSpecification {
  return {
    name: name,
    shape: shape,
    elementNum: elementNum
  };
}

export default function handModelRuntimeTest(): void {
  describe('真实手部模型运行层', () => {
    it('固定清单与两个模型的张量规格一致', 0, () => {
      const manifest: HandModelManifest = HandModelManifestService.manifest();
      expect(manifest.maximumHands).assertEqual(1);
      const palmInput: HandTensorSpecification = tensorSpecification(
        'input_1', [1, 192, 192, 3], 192 * 192 * 3);
      const landmarkInput: HandTensorSpecification = tensorSpecification(
        'input_1', [1, 224, 224, 3], 224 * 224 * 3);
      expect(HandModelManifestService.isExpectedInput(
        palmInput, manifest.palmDetector)).assertTrue();
      expect(HandModelManifestService.isExpectedInput(
        landmarkInput, manifest.handLandmark)).assertTrue();
      expect(HandModelManifestService.isExpectedPalmOutputs([
        tensorSpecification('Identity', [1, 2016, 18], 2016 * 18),
        tensorSpecification('Identity_1', [1, 2016, 1], 2016)
      ])).assertTrue();
      expect(HandModelManifestService.isExpectedLandmarkOutputs([
        tensorSpecification('Identity', [1, 63], 63),
        tensorSpecification('Identity_1', [1, 1], 1),
        tensorSpecification('Identity_2', [1, 1], 1),
        tensorSpecification('Identity_3', [1, 63], 63)
      ])).assertTrue();
    });

    it('缺少资源或张量不匹配时模型状态始终不可用', 0, () => {
      const palmInput: HandTensorSpecification = tensorSpecification(
        'input_1', [1, 192, 192, 3], 192 * 192 * 3);
      const landmarkInput: HandTensorSpecification = tensorSpecification(
        'input_1', [1, 224, 224, 3], 224 * 224 * 3);
      const palmOutputs: HandTensorSpecification[] = [
        tensorSpecification('Identity', [1, 2016, 18], 2016 * 18),
        tensorSpecification('Identity_1', [1, 2016, 1], 2016)
      ];
      const landmarkOutputs: HandTensorSpecification[] = [
        tensorSpecification('Identity', [1, 63], 63),
        tensorSpecification('Identity_1', [1, 1], 1),
        tensorSpecification('Identity_2', [1, 1], 1),
        tensorSpecification('Identity_3', [1, 63], 63)
      ];
      const missing: HandModelReadinessResult = HandModelManifestService.evaluateReadiness(
        false, true, palmInput, landmarkInput, palmOutputs, landmarkOutputs);
      const mismatch: HandModelReadinessResult = HandModelManifestService.evaluateReadiness(
        true, true,
        tensorSpecification('input_1', [1, 128, 128, 3], 128 * 128 * 3),
        landmarkInput, palmOutputs, landmarkOutputs);
      expect(missing.available).assertFalse();
      expect(mismatch.available).assertFalse();
    });

    it('生成官方192输入对应的2016个掌心锚点', 0, () => {
      const pipeline: MediaPipeHandPipeline = new MediaPipeHandPipeline();
      expect(pipeline.getAnchorCount()).assertEqual(2016);
    });

    it('横屏输入的掌心结果会移除上下黑边并生成旋转ROI', 0, () => {
      const pipeline: MediaPipeHandPipeline = new MediaPipeHandPipeline();
      const boxes: Float32Array = new Float32Array(2016 * 18);
      const scores: Float32Array = new Float32Array(2016);
      for (let index: number = 0; index < scores.length; index++) {
        scores[index] = -100.0;
      }
      const selectedIndex: number = (12 * 24 + 12) * 2;
      const offset: number = selectedIndex * 18;
      boxes[offset + 2] = 192.0 * 0.20;
      boxes[offset + 3] = 192.0 * 0.30;
      // 腕点在下、中指掌指关节在上，使生成的手部 ROI 接近正向。
      boxes[offset + 4] = 0.0;
      boxes[offset + 5] = 192.0 * 0.05;
      boxes[offset + 8] = 0.0;
      boxes[offset + 9] = -192.0 * 0.05;
      scores[selectedIndex] = 10.0;
      const detection: PalmDetection | undefined =
        pipeline.decodeBestPalm(boxes, scores, 640, 480);
      expect(detection !== undefined).assertTrue();
      if (detection === undefined) {
        return;
      }
      expect(detection.centerY > 0.50 && detection.centerY < 0.56).assertTrue();
      const roi: HandRegionOfInterest | undefined =
        pipeline.regionOfInterest(detection, 640, 480);
      expect(roi !== undefined).assertTrue();
      if (roi !== undefined) {
        expect(roi.width > detection.width).assertTrue();
        expect(Math.abs(roi.rotationRadians) < 0.001).assertTrue();
      }
    });

    it('关键点模型输出会投影回原始相机坐标并保留世界点', 0, () => {
      const pipeline: MediaPipeHandPipeline = new MediaPipeHandPipeline();
      const landmarks: Float32Array = new Float32Array(63);
      const world: Float32Array = new Float32Array(63);
      for (let index: number = 0; index < 21; index++) {
        landmarks[index * 3] = 112.0;
        landmarks[index * 3 + 1] = 112.0;
        landmarks[index * 3 + 2] = index;
        world[index * 3] = index * 0.001;
        world[index * 3 + 1] = index * -0.001;
        world[index * 3 + 2] = index * 0.0005;
      }
      const decoded = pipeline.decodeLandmarks(landmarks, 0.95, world, {
        centerX: 0.4,
        centerY: 0.6,
        width: 0.3,
        height: 0.4,
        rotationRadians: 0.0
      }, 7, 1000);
      expect(decoded !== undefined).assertTrue();
      if (decoded !== undefined) {
        expect(decoded.points.length).assertEqual(21);
        expect(decoded.worldPoints !== undefined).assertTrue();
        expect(Math.abs(decoded.points[0].x - 0.4) < 0.0001).assertTrue();
        expect(Math.abs(decoded.points[0].y - 0.6) < 0.0001).assertTrue();
        expect(decoded.trackingId).assertEqual(7);
      }
    });

    it('YUV420预处理生成0到1范围的真实RGB张量', 0, () => {
      const yBuffer: ArrayBuffer = new ArrayBuffer(16);
      const uBuffer: ArrayBuffer = new ArrayBuffer(4);
      const vBuffer: ArrayBuffer = new ArrayBuffer(4);
      const yPlane: Uint8Array = new Uint8Array(yBuffer);
      const uPlane: Uint8Array = new Uint8Array(uBuffer);
      const vPlane: Uint8Array = new Uint8Array(vBuffer);
      yPlane.fill(235);
      uPlane.fill(128);
      vPlane.fill(128);
      const buffer: ArrayBuffer = buildPalmTensorBuffer(
        yBuffer, 4, 1,
        uBuffer, 2, 1,
        vBuffer, 2, 1,
        4, 4, 2);
      const rgb: Float32Array = new Float32Array(buffer);
      expect(rgb.length).assertEqual(12);
      expect(rgb[0] > 0.95 && rgb[0] <= 1.0).assertTrue();
      expect(Math.abs(rgb[0] - rgb[1]) < 0.001).assertTrue();
      expect(Math.abs(rgb[1] - rgb[2]) < 0.001).assertTrue();
    });

    it('packed NV21会跳过行填充并按VU顺序拆成三平面', 0, () => {
      const width: number = 4;
      const height: number = 4;
      const rowStride: number = 6;
      const packedBuffer: ArrayBuffer = new ArrayBuffer(rowStride * 6);
      const packed: Uint8Array = new Uint8Array(packedBuffer);
      for (let row: number = 0; row < height; row++) {
        const rowOffset: number = row * rowStride;
        for (let column: number = 0; column < width; column++) {
          packed[rowOffset + column] = row * 10 + column;
        }
        packed[rowOffset + 4] = 250;
        packed[rowOffset + 5] = 251;
      }
      const firstChroma: number = height * rowStride;
      packed[firstChroma] = 150;
      packed[firstChroma + 1] = 100;
      packed[firstChroma + 2] = 160;
      packed[firstChroma + 3] = 110;
      const secondChroma: number = firstChroma + rowStride;
      packed[secondChroma] = 170;
      packed[secondChroma + 1] = 120;
      packed[secondChroma + 2] = 180;
      packed[secondChroma + 3] = 130;

      const planes: HandYuvPlaneSet =
        HandPackedNv21Decoder.decode(packedBuffer, width, height, rowStride);
      const y: Uint8Array = new Uint8Array(planes.yPlane.buffer);
      const u: Uint8Array = new Uint8Array(planes.uPlane.buffer);
      const v: Uint8Array = new Uint8Array(planes.vPlane.buffer);
      expect(y.length).assertEqual(16);
      expect(y[4]).assertEqual(10);
      expect(y[15]).assertEqual(33);
      expect(u.length).assertEqual(4);
      expect(u[0]).assertEqual(100);
      expect(u[3]).assertEqual(130);
      expect(v[0]).assertEqual(150);
      expect(v[3]).assertEqual(180);
      expect(planes.uPlane.rowStride).assertEqual(2);
      expect(planes.uPlane.pixelStride).assertEqual(1);
    });

    it('packed NV21缓冲不足时拒绝生成伪造平面', 0, () => {
      let rejected: boolean = false;
      try {
        HandPackedNv21Decoder.decode(new ArrayBuffer(8), 4, 4, 4);
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}

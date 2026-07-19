import { HandLandmarks, HandPoint } from '../models/DomainModels';

export interface PalmAnchor {
  centerX: number;
  centerY: number;
}

export interface PalmLetterboxTransform {
  paddingLeft: number;
  paddingTop: number;
  contentWidth: number;
  contentHeight: number;
}

export interface PalmDetection {
  score: number;
  centerX: number;
  centerY: number;
  width: number;
  height: number;
  keypoints: HandPoint[];
}

export interface HandRegionOfInterest {
  centerX: number;
  centerY: number;
  width: number;
  height: number;
  rotationRadians: number;
}

/**
 * MediaPipe Hands Lite 两阶段流水线中与模型运行时无关的解码部分。
 *
 * 参数固定来自官方 palm_detection_cpu.pbtxt：
 * 192 输入、2016 anchors、18 个回归量、分数阈值 0.5，以及 2.6 倍手部 ROI。
 */
export class MediaPipeHandPipeline {
  static readonly PALM_INPUT_SIZE: number = 192;
  static readonly LANDMARK_INPUT_SIZE: number = 224;
  static readonly PALM_BOX_COUNT: number = 2016;
  static readonly PALM_COORDINATE_COUNT: number = 18;
  static readonly HAND_LANDMARK_COUNT: number = 21;
  static readonly PALM_SCORE_THRESHOLD: number = 0.5;
  static readonly HAND_PRESENCE_THRESHOLD: number = 0.5;

  private readonly anchors: PalmAnchor[];

  constructor() {
    this.anchors = MediaPipeHandPipeline.createPalmAnchors();
  }

  getAnchorCount(): number {
    return this.anchors.length;
  }

  letterboxTransform(sourceWidth: number, sourceHeight: number): PalmLetterboxTransform {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return {
        paddingLeft: 0.0,
        paddingTop: 0.0,
        contentWidth: 1.0,
        contentHeight: 1.0
      };
    }
    if (sourceWidth >= sourceHeight) {
      const contentHeight: number = sourceHeight / sourceWidth;
      return {
        paddingLeft: 0.0,
        paddingTop: (1.0 - contentHeight) / 2.0,
        contentWidth: 1.0,
        contentHeight: contentHeight
      };
    }
    const contentWidth: number = sourceWidth / sourceHeight;
    return {
      paddingLeft: (1.0 - contentWidth) / 2.0,
      paddingTop: 0.0,
      contentWidth: contentWidth,
      contentHeight: 1.0
    };
  }

  decodeBestPalm(rawBoxes: Float32Array, rawScores: Float32Array,
    sourceWidth: number, sourceHeight: number): PalmDetection | undefined {
    if (rawBoxes.length < MediaPipeHandPipeline.PALM_BOX_COUNT *
      MediaPipeHandPipeline.PALM_COORDINATE_COUNT ||
      rawScores.length < MediaPipeHandPipeline.PALM_BOX_COUNT ||
      this.anchors.length !== MediaPipeHandPipeline.PALM_BOX_COUNT) {
      return undefined;
    }
    let selectedIndex: number = -1;
    let selectedScore: number = MediaPipeHandPipeline.PALM_SCORE_THRESHOLD;
    for (let index: number = 0; index < MediaPipeHandPipeline.PALM_BOX_COUNT; index++) {
      const score: number = this.sigmoid(this.clamp(rawScores[index], -100.0, 100.0));
      if (score > selectedScore) {
        selectedIndex = index;
        selectedScore = score;
      }
    }
    if (selectedIndex < 0) {
      return undefined;
    }

    const transform: PalmLetterboxTransform =
      this.letterboxTransform(sourceWidth, sourceHeight);
    const anchor: PalmAnchor = this.anchors[selectedIndex];
    const offset: number = selectedIndex * MediaPipeHandPipeline.PALM_COORDINATE_COUNT;
    // reverse_output_order=true，因此原始顺序是 x、y、w、h。
    const modelCenterX: number = rawBoxes[offset] /
      MediaPipeHandPipeline.PALM_INPUT_SIZE + anchor.centerX;
    const modelCenterY: number = rawBoxes[offset + 1] /
      MediaPipeHandPipeline.PALM_INPUT_SIZE + anchor.centerY;
    const modelWidth: number = Math.abs(rawBoxes[offset + 2] /
      MediaPipeHandPipeline.PALM_INPUT_SIZE);
    const modelHeight: number = Math.abs(rawBoxes[offset + 3] /
      MediaPipeHandPipeline.PALM_INPUT_SIZE);
    const keypoints: HandPoint[] = [];
    for (let index: number = 0; index < 7; index++) {
      const pointOffset: number = offset + 4 + index * 2;
      const modelX: number = rawBoxes[pointOffset] /
        MediaPipeHandPipeline.PALM_INPUT_SIZE + anchor.centerX;
      const modelY: number = rawBoxes[pointOffset + 1] /
        MediaPipeHandPipeline.PALM_INPUT_SIZE + anchor.centerY;
      keypoints.push({
        x: (modelX - transform.paddingLeft) / transform.contentWidth,
        y: (modelY - transform.paddingTop) / transform.contentHeight,
        confidence: selectedScore
      });
    }
    return {
      score: selectedScore,
      centerX: (modelCenterX - transform.paddingLeft) / transform.contentWidth,
      centerY: (modelCenterY - transform.paddingTop) / transform.contentHeight,
      width: modelWidth / transform.contentWidth,
      height: modelHeight / transform.contentHeight,
      keypoints: keypoints
    };
  }

  regionOfInterest(detection: PalmDetection,
    sourceWidth: number, sourceHeight: number): HandRegionOfInterest | undefined {
    if (sourceWidth <= 0 || sourceHeight <= 0 || detection.keypoints.length < 3 ||
      detection.width <= 0.0 || detection.height <= 0.0) {
      return undefined;
    }
    const wrist: HandPoint = detection.keypoints[0];
    const middleFingerBase: HandPoint = detection.keypoints[2];
    const deltaX: number = (middleFingerBase.x - wrist.x) * sourceWidth;
    const deltaY: number = (middleFingerBase.y - wrist.y) * sourceHeight;
    const rotation: number = this.normalizeRadians(
      Math.PI / 2.0 - Math.atan2(-deltaY, deltaX));

    const widthPixels: number = detection.width * sourceWidth;
    const heightPixels: number = detection.height * sourceHeight;
    const centerXPixels: number = detection.centerX * sourceWidth;
    const centerYPixels: number = detection.centerY * sourceHeight;
    // 官方 RectTransformation：shift_y=-0.5，随后在像素空间取长边正方形并放大 2.6 倍。
    const shiftedCenterX: number = centerXPixels +
      heightPixels * 0.5 * Math.sin(rotation);
    const shiftedCenterY: number = centerYPixels -
      heightPixels * 0.5 * Math.cos(rotation);
    const longSidePixels: number = Math.max(widthPixels, heightPixels) * 2.6;
    if (!Number.isFinite(longSidePixels) || longSidePixels <= 1.0) {
      return undefined;
    }
    return {
      centerX: shiftedCenterX / sourceWidth,
      centerY: shiftedCenterY / sourceHeight,
      width: longSidePixels / sourceWidth,
      height: longSidePixels / sourceHeight,
      rotationRadians: rotation
    };
  }

  /**
   * 根据上一帧21点重建下一帧 ROI。跟踪阶段不重新运行 Palm Detection，
   * 只扩大关键点包围盒并沿掌面方向旋转，避免手部移动后 ROI 逐帧漂出。
   */
  regionOfInterestFromLandmarks(hand: HandLandmarks,
    sourceWidth: number, sourceHeight: number): HandRegionOfInterest | undefined {
    if (sourceWidth <= 0 || sourceHeight <= 0 || hand.points.length < 21) {
      return undefined;
    }
    let minimumX: number = 1.0;
    let maximumX: number = 0.0;
    let minimumY: number = 1.0;
    let maximumY: number = 0.0;
    for (let index: number = 0; index < hand.points.length; index++) {
      const point: HandPoint = hand.points[index];
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
        return undefined;
      }
      minimumX = Math.min(minimumX, point.x);
      maximumX = Math.max(maximumX, point.x);
      minimumY = Math.min(minimumY, point.y);
      maximumY = Math.max(maximumY, point.y);
    }
    const rawWidth: number = Math.max(0.02, maximumX - minimumX);
    const rawHeight: number = Math.max(0.02, maximumY - minimumY);
    const roiWidth: number = Math.min(1.0, rawWidth * 1.5);
    const roiHeight: number = Math.min(1.0, rawHeight * 1.5);
    const wrist: HandPoint = hand.points[0];
    const middleBase: HandPoint = hand.points[9];
    const rotation: number = this.normalizeRadians(
      Math.PI / 2.0 - Math.atan2(
        -(middleBase.y - wrist.y) * sourceHeight,
        (middleBase.x - wrist.x) * sourceWidth));
    return {
      centerX: this.clamp((minimumX + maximumX) / 2.0, roiWidth / 2.0, 1.0 - roiWidth / 2.0),
      centerY: this.clamp((minimumY + maximumY) / 2.0, roiHeight / 2.0, 1.0 - roiHeight / 2.0),
      width: roiWidth,
      height: roiHeight,
      rotationRadians: rotation
    };
  }

  decodeLandmarks(rawLandmarks: Float32Array, handPresenceScore: number,
    rawWorldLandmarks: Float32Array, roi: HandRegionOfInterest,
    trackingId: number, timestampMs: number): HandLandmarks | undefined {
    if (rawLandmarks.length < MediaPipeHandPipeline.HAND_LANDMARK_COUNT * 3 ||
      rawWorldLandmarks.length < MediaPipeHandPipeline.HAND_LANDMARK_COUNT * 3 ||
      handPresenceScore < MediaPipeHandPipeline.HAND_PRESENCE_THRESHOLD) {
      return undefined;
    }
    const confidence: number = this.clamp(handPresenceScore, 0.0, 1.0);
    const points: HandPoint[] = [];
    const worldPoints: HandPoint[] = [];
    const cosine: number = Math.cos(roi.rotationRadians);
    const sine: number = Math.sin(roi.rotationRadians);
    for (let index: number = 0; index < MediaPipeHandPipeline.HAND_LANDMARK_COUNT; index++) {
      const offset: number = index * 3;
      const localX: number = rawLandmarks[offset] /
        MediaPipeHandPipeline.LANDMARK_INPUT_SIZE - 0.5;
      const localY: number = rawLandmarks[offset + 1] /
        MediaPipeHandPipeline.LANDMARK_INPUT_SIZE - 0.5;
      const normalizedZ: number = rawLandmarks[offset + 2] /
        MediaPipeHandPipeline.LANDMARK_INPUT_SIZE / 0.4;
      points.push({
        x: cosine * localX * roi.width - sine * localY * roi.height + roi.centerX,
        y: sine * localX * roi.width + cosine * localY * roi.height + roi.centerY,
        z: normalizedZ * roi.width,
        confidence: confidence
      });

      // 世界关键点单位由模型定义为米；只旋转 XY，不把相对深度伪装成相机绝对距离。
      const worldX: number = rawWorldLandmarks[offset];
      const worldY: number = rawWorldLandmarks[offset + 1];
      worldPoints.push({
        x: cosine * worldX - sine * worldY,
        y: sine * worldX + cosine * worldY,
        z: rawWorldLandmarks[offset + 2],
        confidence: confidence
      });
    }
    const palmFacingConfidence: number = this.palmFacingConfidence(worldPoints);
    return {
      trackingId: trackingId,
      points: points,
      worldPoints: worldPoints,
      confidence: confidence,
      palmConfidence: confidence,
      palmFacingConfidence: palmFacingConfidence,
      timestampMs: timestampMs
    };
  }

  private static createPalmAnchors(): PalmAnchor[] {
    const anchors: PalmAnchor[] = [];
    // 官方 4 层配置中，stride 8 有 2 个 anchor/格，三个 stride 16 层合并为 6 个 anchor/格。
    MediaPipeHandPipeline.appendAnchorGrid(anchors, 24, 24, 2);
    MediaPipeHandPipeline.appendAnchorGrid(anchors, 12, 12, 6);
    return anchors;
  }

  private static appendAnchorGrid(anchors: PalmAnchor[], width: number,
    height: number, anchorsPerCell: number): void {
    for (let y: number = 0; y < height; y++) {
      for (let x: number = 0; x < width; x++) {
        for (let anchorIndex: number = 0; anchorIndex < anchorsPerCell; anchorIndex++) {
          anchors.push({
            centerX: (x + 0.5) / width,
            centerY: (y + 0.5) / height
          });
        }
      }
    }
  }

  private palmFacingConfidence(points: HandPoint[]): number {
    if (points.length < MediaPipeHandPipeline.HAND_LANDMARK_COUNT) {
      return 0.0;
    }
    const wrist: HandPoint = points[0];
    const indexBase: HandPoint = points[5];
    const littleBase: HandPoint = points[17];
    const firstX: number = indexBase.x - wrist.x;
    const firstY: number = indexBase.y - wrist.y;
    const firstZ: number = this.pointZ(indexBase) - this.pointZ(wrist);
    const secondX: number = littleBase.x - wrist.x;
    const secondY: number = littleBase.y - wrist.y;
    const secondZ: number = this.pointZ(littleBase) - this.pointZ(wrist);
    const normalX: number = firstY * secondZ - firstZ * secondY;
    const normalY: number = firstZ * secondX - firstX * secondZ;
    const normalZ: number = firstX * secondY - firstY * secondX;
    const length: number = Math.sqrt(
      normalX * normalX + normalY * normalY + normalZ * normalZ);
    if (length <= 0.000001) {
      return 0.0;
    }
    return this.clamp(Math.abs(normalZ) / length, 0.0, 1.0);
  }

  private pointZ(point: HandPoint): number {
    return point.z === undefined || !Number.isFinite(point.z) ? 0.0 : point.z;
  }

  private sigmoid(value: number): number {
    return 1.0 / (1.0 + Math.exp(-value));
  }

  private normalizeRadians(value: number): number {
    let normalized: number = value;
    while (normalized > Math.PI) {
      normalized -= Math.PI * 2.0;
    }
    while (normalized < -Math.PI) {
      normalized += Math.PI * 2.0;
    }
    return normalized;
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }
}

/**
 * 手部模型清单只描述已经固定并转换完成的离线资产。
 *
 * 运行层会再次检查输入、输出张量规格；文件缺失或张量不匹配时必须保持手势不可用，
 * 不能用空数组或人工关键点伪装成模型已经成功运行。
 */
export interface HandModelArtifact {
  id: string;
  displayName: string;
  rawFileName: string;
  sourceUrl: string;
  sourceLicense: string;
  sourceSha256: string;
  convertedSha256: string;
  converterVersion: string;
  inputWidth: number;
  inputHeight: number;
  inputChannels: number;
}

export interface HandModelManifest {
  manifestVersion: number;
  pipelineName: string;
  pipelineVersion: string;
  maximumHands: number;
  palmDetector: HandModelArtifact;
  handLandmark: HandModelArtifact;
}

export interface HandTensorSpecification {
  name: string;
  shape: number[];
  elementNum: number;
}

export interface HandModelReadinessResult {
  available: boolean;
  message: string;
}

export class HandModelManifestService {
  private static readonly PALM_RAW_FILE: string = 'models/palm_detection_lite.ms';
  private static readonly LANDMARK_RAW_FILE: string = 'models/hand_landmark_lite.ms';

  static manifest(): HandModelManifest {
    return {
      manifestVersion: 1,
      pipelineName: 'MediaPipe Hands Lite + MindSpore Lite',
      pipelineVersion: 'mediapipe-assets-lite/mindspore-lite-2.4.1',
      maximumHands: 1,
      palmDetector: {
        id: 'mediapipe-palm-detection-lite',
        displayName: 'MediaPipe Palm Detection Lite',
        rawFileName: HandModelManifestService.PALM_RAW_FILE,
        sourceUrl: 'https://storage.googleapis.com/mediapipe-assets/palm_detection_lite.tflite',
        sourceLicense: 'Apache-2.0',
        sourceSha256: 'E9A4AADDF90DDA56A87235303CF00E4C2D3FB28725F68FD88772997DAC905C18',
        convertedSha256: 'CB498EDDE8EB8B478EB36580F6D44EAD2D9EC66B9A5FCDBE016805C9978723F8',
        converterVersion: 'MindSpore Lite 2.4.1',
        inputWidth: 192,
        inputHeight: 192,
        inputChannels: 3
      },
      handLandmark: {
        id: 'mediapipe-hand-landmark-lite',
        displayName: 'MediaPipe Hand Landmark Lite',
        rawFileName: HandModelManifestService.LANDMARK_RAW_FILE,
        sourceUrl: 'https://storage.googleapis.com/mediapipe-assets/hand_landmark_lite.tflite',
        sourceLicense: 'Apache-2.0',
        sourceSha256: 'D7FDE8AC11F8CE03F8663775BFC323F4FC9F2A38062B4F4EFA142874EF5B2A48',
        convertedSha256: 'AECF20C97D4DFEBF95B2D587D3EA93C740AC8A0897EC47EB20787EDF25BE6029',
        converterVersion: 'MindSpore Lite 2.4.1',
        inputWidth: 224,
        inputHeight: 224,
        inputChannels: 3
      }
    };
  }

  static isExpectedInput(specification: HandTensorSpecification,
    artifact: HandModelArtifact): boolean {
    if (specification.shape.length !== 4) {
      return false;
    }
    return specification.shape[0] === 1 &&
      specification.shape[1] === artifact.inputHeight &&
      specification.shape[2] === artifact.inputWidth &&
      specification.shape[3] === artifact.inputChannels &&
      specification.elementNum === artifact.inputWidth * artifact.inputHeight *
      artifact.inputChannels;
  }

  static isExpectedPalmOutputs(specifications: HandTensorSpecification[]): boolean {
    let boxOutputFound: boolean = false;
    let scoreOutputFound: boolean = false;
    for (let index: number = 0; index < specifications.length; index++) {
      const elementNum: number = specifications[index].elementNum;
      if (elementNum === 2016 * 18) {
        boxOutputFound = true;
      } else if (elementNum === 2016) {
        scoreOutputFound = true;
      }
    }
    return boxOutputFound && scoreOutputFound;
  }

  static isExpectedLandmarkOutputs(specifications: HandTensorSpecification[]): boolean {
    let sixtyThreeCount: number = 0;
    let scalarCount: number = 0;
    for (let index: number = 0; index < specifications.length; index++) {
      const elementNum: number = specifications[index].elementNum;
      if (elementNum === 63) {
        sixtyThreeCount++;
      } else if (elementNum === 1) {
        scalarCount++;
      }
    }
    return sixtyThreeCount === 2 && scalarCount === 2;
  }

  static evaluateReadiness(palmResourceLoaded: boolean, landmarkResourceLoaded: boolean,
    palmInput: HandTensorSpecification | undefined,
    landmarkInput: HandTensorSpecification | undefined,
    palmOutputs: HandTensorSpecification[],
    landmarkOutputs: HandTensorSpecification[]): HandModelReadinessResult {
    const manifest: HandModelManifest = HandModelManifestService.manifest();
    if (!palmResourceLoaded || !landmarkResourceLoaded) {
      return {
        available: false,
        message: '离线手部模型资源缺失'
      };
    }
    if (palmInput === undefined || landmarkInput === undefined ||
      !HandModelManifestService.isExpectedInput(palmInput, manifest.palmDetector) ||
      !HandModelManifestService.isExpectedInput(landmarkInput, manifest.handLandmark)) {
      return {
        available: false,
        message: '手部模型输入张量规格不匹配'
      };
    }
    if (!HandModelManifestService.isExpectedPalmOutputs(palmOutputs) ||
      !HandModelManifestService.isExpectedLandmarkOutputs(landmarkOutputs)) {
      return {
        available: false,
        message: '手部模型输出张量规格不匹配'
      };
    }
    return {
      available: true,
      message: '离线手部模型已通过张量规格检查'
    };
  }
}

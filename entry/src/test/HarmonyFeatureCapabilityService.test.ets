import { describe, expect, it } from '@ohos/hypium';
import {
  HarmonyCapabilityState,
  HarmonyFeatureProbeInput,
  HarmonyFeatureSnapshot
} from '../main/ets/models/HarmonyFeatureModels';
import {
  HarmonyFeatureCapabilityService
} from '../main/ets/services/HarmonyFeatureCapabilityService';

function createInput(runtimeApiLevel: number): HarmonyFeatureProbeInput {
  return {
    runtimeApiLevel: runtimeApiLevel,
    osFullName: `HarmonyOS API ${runtimeApiLevel}`,
    scanKitDeclared: true,
    liveViewDeclared: true,
    formKitDeclared: true,
    systemShareDeclared: true,
    harmonyShareDeclared: true,
    formExtensionConfigured: false
  };
}

export default function harmonyFeatureCapabilityServiceTest(): void {
  describe('HarmonyFeatureCapabilityService', () => {
    it('API24 真机满足 API23 运行时基线', 0, () => {
      const snapshot: HarmonyFeatureSnapshot =
        HarmonyFeatureCapabilityService.inspectWithInput(createInput(24));
      expect(snapshot.supportsApi23Runtime).assertTrue();
      expect(snapshot.scanKit.state).assertEqual(HarmonyCapabilityState.AVAILABLE);
      expect(snapshot.systemShare.state).assertEqual(HarmonyCapabilityState.AVAILABLE);
    });

    it('实况窗与 Harmony Share 不会仅凭 syscap 误报可用', 0, () => {
      const snapshot: HarmonyFeatureSnapshot =
        HarmonyFeatureCapabilityService.inspectWithInput(createInput(24));
      expect(snapshot.liveView.state).assertEqual(HarmonyCapabilityState.RUNTIME_PROBE_REQUIRED);
      expect(snapshot.liveView.available).assertFalse();
      expect(snapshot.harmonyShare.state).assertEqual(HarmonyCapabilityState.RUNTIME_PROBE_REQUIRED);
      expect(snapshot.harmonyShare.available).assertFalse();
    });

    it('未注册卡片扩展时明确标记构建未配置', 0, () => {
      const snapshot: HarmonyFeatureSnapshot =
        HarmonyFeatureCapabilityService.inspectWithInput(createInput(24));
      expect(snapshot.formKit.state).assertEqual(HarmonyCapabilityState.BUILD_NOT_CONFIGURED);
      expect(snapshot.formKit.available).assertFalse();
    });

    it('系统能力缺失时不开放对应功能', 0, () => {
      const input: HarmonyFeatureProbeInput = createInput(24);
      input.scanKitDeclared = false;
      const snapshot: HarmonyFeatureSnapshot =
        HarmonyFeatureCapabilityService.inspectWithInput(input);
      expect(snapshot.scanKit.state).assertEqual(HarmonyCapabilityState.SYSTEM_CAPABILITY_MISSING);
      expect(snapshot.scanKit.available).assertFalse();
    });

    it('API22 环境保留基础 Kit 并关闭 API23 专属运行时', 0, () => {
      const snapshot: HarmonyFeatureSnapshot =
        HarmonyFeatureCapabilityService.inspectWithInput(createInput(22));
      expect(snapshot.supportsApi23Runtime).assertFalse();
      expect(snapshot.scanKit.available).assertTrue();
      expect(HarmonyFeatureCapabilityService.api23RuntimeCapability(22).available).assertFalse();
    });
  });
}

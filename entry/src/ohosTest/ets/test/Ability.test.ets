import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../../../main/ets/data/CelestialCatalog';

export default function abilityTest(): void {
  describe('StarFinding 真机冒烟测试', () => {
    it('离线天体目录随应用测试包正常加载', 0, () => {
      // 该用例在真机测试 HAP 内运行，用于发现资源打包或模块路径错误，不替代夜间设备验收。
      const coverage = CelestialCatalog.coverage();
      expect(coverage.constellationIndexCount).assertEqual(88);
      expect(coverage.messierIndexCount).assertEqual(110);
    });
  });
}

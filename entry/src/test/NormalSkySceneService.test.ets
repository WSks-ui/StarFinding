import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import { CelestialObject, ObserverState } from '../main/ets/models/DomainModels';
import { DEFAULT_SKY_LAYERS, NormalSkyViewport, SkyMapOrientation } from '../main/ets/models/NormalSkyModels';
import { NormalSkyCatalogService } from '../main/ets/services/NormalSkyCatalogService';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';
import { NormalSkySceneService } from '../main/ets/services/NormalSkySceneService';
import { VisibleStarCatalogService } from '../main/ets/services/VisibleStarCatalogService';

export default function normalSkySceneServiceTest(): void {
  describe('普通星图场景合成', () => {
    it('未加载 HYG 时仍可离线显示和点选 Messier 目标', 0, () => {
      const target: CelestialObject | undefined = CelestialCatalog.getById('messier-31');
      if (target === undefined || target.coordinate === undefined) {
        expect(false).assertTrue();
        return;
      }
      const viewport: NormalSkyViewport = {
        centerRaHours: target.coordinate.raHours,
        centerDecDegrees: target.coordinate.decDegrees,
        fieldOfViewDegrees: 30.0,
        rotationDegrees: 0.0,
        orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
      };
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const scene = service.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: 'messier-31',
        timestampMs: Date.UTC(2026, 6, 15, 12, 0, 0)
      });
      const selected = NormalSkyProjectionService.hitTest(scene.objects, 400.0, 300.0, 18.0);
      expect(selected !== undefined && selected.id === 'messier-31' && selected.selected).assertTrue();
    });

    it('有观测地点时生成地平遮罩和地平线', 0, () => {
      const observer: ObserverState = {
        latitudeDegrees: 34.75,
        longitudeDegrees: 113.62,
        elevationMeters: 100.0,
        timestampMs: Date.UTC(2026, 6, 15, 12, 0, 0)
      };
      const viewport: NormalSkyViewport = NormalSkyProjectionService.homeViewport(
        observer, SkyMapOrientation.HORIZON_ZENITH);
      viewport.fieldOfViewDegrees = 160.0;
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const scene = service.build({
        viewport: viewport,
        size: { widthPixels: 600.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: 'star-vega',
        timestampMs: observer.timestampMs,
        observer: observer
      });
      expect(scene.horizonLines.length > 0).assertTrue();
      expect(scene.horizonMask.length > 0).assertTrue();
    });
  });
}

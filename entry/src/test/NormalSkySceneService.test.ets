import { describe, expect, it } from '@ohos/hypium';
import { CelestialCatalog } from '../main/ets/data/CelestialCatalog';
import {
  CelestialObject,
  EquatorialCoordinate,
  EquatorialFrame,
  ObserverState
} from '../main/ets/models/DomainModels';
import {
  DEFAULT_SKY_LAYERS,
  NormalSkyScene,
  NormalSkyViewport,
  ProjectedSkyObject,
  SkyMapOrientation,
  SkyObjectGlyphKind
} from '../main/ets/models/NormalSkyModels';
import {
  ConstellationSphericalBounds,
  NormalSkyCatalogService
} from '../main/ets/services/NormalSkyCatalogService';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';
import {
  NormalSkySceneCacheStats,
  NormalSkySceneService
} from '../main/ets/services/NormalSkySceneService';
import { EphemerisService } from '../main/ets/services/EphemerisService';
import { VisibleStarCatalogService } from '../main/ets/services/VisibleStarCatalogService';

function findProjected(objects: ProjectedSkyObject[], objectId: string): ProjectedSkyObject | undefined {
  for (let index: number = 0; index < objects.length; index++) {
    if (objects[index].id === objectId) return objects[index];
  }
  return undefined;
}

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
      const interactive: NormalSkyScene = service.build({
        viewport: viewport,
        size: { widthPixels: 600.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: 'star-vega',
        timestampMs: observer.timestampMs + 30000.0,
        observer: observer,
        interactive: true
      });
      expect(interactive.horizonLines.length > 0).assertTrue();
      expect(interactive.horizonMask.length > 0 &&
        interactive.horizonMask.length < scene.horizonMask.length).assertTrue();
      // 交互态只减少标签与遮罩采样，不通过隐藏恒星或目录目标换取帧率。
      expect(interactive.staticObjects.length).assertEqual(scene.staticObjects.length);
      expect(service.getCacheStats().dynamicCatalogCacheHitCount).assertEqual(1);
    });

    it('太阳系目标均映射为确定图符且土星保留星环语义', 0, () => {
      const solarSystem: CelestialObject[] = CelestialCatalog.solarSystem();
      for (let index: number = 0; index < solarSystem.length; index++) {
        const glyph: SkyObjectGlyphKind = NormalSkySceneService.glyphKindFor(solarSystem[index]);
        expect(glyph !== SkyObjectGlyphKind.DEEP_SKY_GENERIC).assertTrue();
      }
      const saturn: CelestialObject | undefined = CelestialCatalog.getById('planet-saturn');
      expect(saturn !== undefined &&
        NormalSkySceneService.glyphKindFor(saturn) === SkyObjectGlyphKind.SATURN).assertTrue();
    });

    it('星座球面包围范围正确处理赤经回绕与近天极', 0, () => {
      const wrapLine: EquatorialCoordinate[] = [
        { raHours: 23.8, decDegrees: 10.0, frame: EquatorialFrame.ICRS_J2000 },
        { raHours: 0.2, decDegrees: 11.0, frame: EquatorialFrame.ICRS_J2000 }
      ];
      const wrapBounds: ConstellationSphericalBounds =
        NormalSkyCatalogService.buildSphericalBounds([wrapLine]);
      expect(wrapBounds.centerDirectionX > 0.9 &&
        Math.abs(wrapBounds.centerDirectionY) < 0.1 &&
        wrapBounds.angularRadiusDegrees < 8.0).assertTrue();

      const poleLine: EquatorialCoordinate[] = [
        { raHours: 0.0, decDegrees: 88.0, frame: EquatorialFrame.ICRS_J2000 },
        { raHours: 6.0, decDegrees: 88.0, frame: EquatorialFrame.ICRS_J2000 },
        { raHours: 12.0, decDegrees: 88.0, frame: EquatorialFrame.ICRS_J2000 },
        { raHours: 18.0, decDegrees: 88.0, frame: EquatorialFrame.ICRS_J2000 }
      ];
      const poleBounds: ConstellationSphericalBounds =
        NormalSkyCatalogService.buildSphericalBounds([poleLine]);
      expect(poleBounds.centerDirectionZ > 0.99 &&
        poleBounds.angularRadiusDegrees < 6.0).assertTrue();
    });

    it('动态目标携带真实外观与亮边屏幕方向', 0, () => {
      const timestampMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const saturn: CelestialObject | undefined = CelestialCatalog.getById('planet-saturn');
      if (saturn === undefined) {
        expect(false).assertTrue();
        return;
      }
      const coordinate = EphemerisService.skyCoordinate(saturn, timestampMs);
      if (coordinate === undefined) {
        expect(false).assertTrue();
        return;
      }
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const scene: NormalSkyScene = service.build({
        viewport: {
          centerRaHours: coordinate.raHours,
          centerDecDegrees: coordinate.decDegrees,
          fieldOfViewDegrees: 30.0,
          rotationDegrees: 31.0,
          orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
        },
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: saturn.id,
        timestampMs: timestampMs
      });
      const projected: ProjectedSkyObject | undefined = findProjected(scene.objects, saturn.id);
      expect(projected !== undefined && projected.appearance !== undefined).assertTrue();
      if (projected === undefined || projected.appearance === undefined) return;
      expect(projected.magnitude !== undefined &&
        Math.abs(projected.magnitude - projected.appearance.magnitude) < 0.0001).assertTrue();
      expect(projected.appearance.ringTiltDegrees !== undefined).assertTrue();
      expect(projected.brightLimbScreenAngleDegrees !== undefined &&
        Number.isFinite(projected.brightLimbScreenAngleDegrees)).assertTrue();
    });

    it('选中动态天体时绘制真实视运动轨迹', 0, () => {
      const timestampMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const mars: CelestialObject | undefined = CelestialCatalog.getById('planet-mars');
      if (mars === undefined) {
        expect(false).assertTrue();
        return;
      }
      const coordinate = EphemerisService.skyCoordinate(mars, timestampMs);
      if (coordinate === undefined) {
        expect(false).assertTrue();
        return;
      }
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const scene = service.build({
        viewport: {
          centerRaHours: coordinate.raHours,
          centerDecDegrees: coordinate.decDegrees,
          fieldOfViewDegrees: 90.0,
          rotationDegrees: 0.0,
          orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
        },
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: mars.id,
        timestampMs: timestampMs
      });
      expect(scene.trajectoryLines.length > 0 && scene.trajectoryLines[0].points.length > 1).assertTrue();
    });

    it('模拟播放复用固定目录层和分桶轨迹且持续刷新动态层', 0, () => {
      const firstAtMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const secondAtMs: number = firstAtMs + 6.0 * 3600000.0;
      const mars: CelestialObject | undefined = CelestialCatalog.getById('planet-mars');
      if (mars === undefined) {
        expect(false).assertTrue();
        return;
      }
      const coordinate = EphemerisService.skyCoordinate(mars, firstAtMs);
      if (coordinate === undefined) {
        expect(false).assertTrue();
        return;
      }
      const viewport: NormalSkyViewport = {
        centerRaHours: coordinate.raHours,
        centerDecDegrees: coordinate.decDegrees,
        fieldOfViewDegrees: 90.0,
        rotationDegrees: 0.0,
        orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
      };
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const first: NormalSkyScene = service.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: mars.id,
        timestampMs: firstAtMs
      });
      const second: NormalSkyScene = service.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: mars.id,
        timestampMs: secondAtMs
      });
      const secondMars: ProjectedSkyObject | undefined = findProjected(second.dynamicObjects, mars.id);
      const stats: NormalSkySceneCacheStats = service.getCacheStats();
      expect(first.staticObjects === second.staticObjects &&
        first.staticRevision === second.staticRevision).assertTrue();
      expect(first.dynamicObjects !== second.dynamicObjects &&
        second.dynamicRevision > first.dynamicRevision).assertTrue();
      expect(secondMars !== undefined && secondMars.appearance !== undefined &&
        secondMars.appearance.timestampMs === secondAtMs).assertTrue();
      expect(stats.staticBuildCount).assertEqual(1);
      expect(stats.staticCacheHitCount).assertEqual(1);
      expect(stats.dynamicBuildCount).assertEqual(2);
      expect(stats.trajectoryBuildCount).assertEqual(1);
      expect(stats.trajectoryCacheHitCount).assertEqual(1);

      service.invalidateForTimeSelection();
      const third: NormalSkyScene = service.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: mars.id,
        timestampMs: secondAtMs
      });
      expect(third.staticRevision > second.staticRevision).assertTrue();
      expect(service.getCacheStats().staticBuildCount).assertEqual(2);
      expect(service.getCacheStats().trajectoryBuildCount).assertEqual(2);
    });

    it('模拟日期变化会更新金星盈亏而不是复用固定图符', 0, () => {
      const firstAtMs: number = Date.UTC(2026, 3, 1, 0, 0, 0);
      const secondAtMs: number = Date.UTC(2026, 6, 15, 0, 0, 0);
      const venus: CelestialObject | undefined = CelestialCatalog.getById('planet-venus');
      if (venus === undefined) {
        expect(false).assertTrue();
        return;
      }
      const firstCoordinate = EphemerisService.skyCoordinate(venus, firstAtMs);
      const secondCoordinate = EphemerisService.skyCoordinate(venus, secondAtMs);
      if (firstCoordinate === undefined || secondCoordinate === undefined) {
        expect(false).assertTrue();
        return;
      }
      const service: NormalSkySceneService = new NormalSkySceneService(
        new VisibleStarCatalogService(), new NormalSkyCatalogService());
      const first: NormalSkyScene = service.build({
        viewport: {
          centerRaHours: firstCoordinate.raHours, centerDecDegrees: firstCoordinate.decDegrees,
          fieldOfViewDegrees: 30.0, rotationDegrees: 0.0,
          orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
        },
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: venus.id,
        timestampMs: firstAtMs
      });
      const second: NormalSkyScene = service.build({
        viewport: {
          centerRaHours: secondCoordinate.raHours, centerDecDegrees: secondCoordinate.decDegrees,
          fieldOfViewDegrees: 30.0, rotationDegrees: 0.0,
          orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
        },
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        layers: DEFAULT_SKY_LAYERS,
        selectedTargetId: venus.id,
        timestampMs: secondAtMs
      });
      const firstVenus: ProjectedSkyObject | undefined = findProjected(first.dynamicObjects, venus.id);
      const secondVenus: ProjectedSkyObject | undefined = findProjected(second.dynamicObjects, venus.id);
      expect(firstVenus !== undefined && firstVenus.appearance !== undefined &&
        secondVenus !== undefined && secondVenus.appearance !== undefined).assertTrue();
      if (firstVenus === undefined || firstVenus.appearance === undefined ||
        secondVenus === undefined || secondVenus.appearance === undefined) return;
      expect(Math.abs(firstVenus.appearance.illuminatedFraction -
        secondVenus.appearance.illuminatedFraction) > 0.2).assertTrue();
      expect(firstVenus.brightLimbScreenAngleDegrees !== undefined &&
        secondVenus.brightLimbScreenAngleDegrees !== undefined).assertTrue();
    });

    it('一百一十个梅西耶目标均映射为深空图符', 0, () => {
      const messier: CelestialObject[] = CelestialCatalog.messierObjects();
      expect(messier.length).assertEqual(110);
      for (let index: number = 0; index < messier.length; index++) {
        const glyph: SkyObjectGlyphKind = NormalSkySceneService.glyphKindFor(messier[index]);
        expect(glyph !== SkyObjectGlyphKind.STAR &&
          glyph !== SkyObjectGlyphKind.CONSTELLATION &&
          glyph !== SkyObjectGlyphKind.SOLAR_SYSTEM_GENERIC).assertTrue();
      }
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import { ObserverState } from '../main/ets/models/DomainModels';
import {
  NormalSkyViewport,
  SkyDirectionKind,
  SkyDirectionMarker,
  SkyMapOrientation,
  SkyOrientationSnapshot
} from '../main/ets/models/NormalSkyModels';
import { NormalSkyOrientationService } from '../main/ets/services/NormalSkyOrientationService';
import { NormalSkyProjectionService } from '../main/ets/services/NormalSkyProjectionService';

function orientationViewport(rotationDegrees: number = 0.0): NormalSkyViewport {
  return {
    centerRaHours: 8.0,
    centerDecDegrees: 25.0,
    fieldOfViewDegrees: 90.0,
    rotationDegrees: rotationDegrees,
    orientation: SkyMapOrientation.EQUATORIAL_NORTH_UP
  };
}

function containsKind(markers: SkyDirectionMarker[], expected: SkyDirectionKind): boolean {
  for (let index: number = 0; index < markers.length; index++) {
    if (markers[index].kind === expected) return true;
  }
  return false;
}

export default function normalSkyOrientationServiceTest(): void {
  describe('普通星图方位快照', () => {
    it('赤道视图默认保持北上东左并生成双天极标记', 0, () => {
      const snapshot: SkyOrientationSnapshot = NormalSkyOrientationService.build({
        viewport: orientationViewport(),
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        directionGuides: true,
        guideInsets: { leftPixels: 90.0, rightPixels: 70.0, topPixels: 100.0, bottomPixels: 80.0 }
      });
      expect(Math.abs(snapshot.northScreenAngleDegrees) < 0.001).assertTrue();
      expect(Math.abs(snapshot.eastScreenAngleDegrees + 90.0) < 0.001).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.NORTH_CELESTIAL_POLE)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.SOUTH_CELESTIAL_POLE)).assertTrue();
      for (let index: number = 0; index < snapshot.markers.length; index++) {
        expect(snapshot.markers[index].xPixels >= 90.0 && snapshot.markers[index].xPixels <= 730.0).assertTrue();
        expect(snapshot.markers[index].yPixels >= 100.0 && snapshot.markers[index].yPixels <= 520.0).assertTrue();
      }
    });

    it('画面旋转后罗盘角度同步变化', 0, () => {
      const snapshot: SkyOrientationSnapshot = NormalSkyOrientationService.build({
        viewport: orientationViewport(37.0),
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        directionGuides: false
      });
      expect(Math.abs(snapshot.northScreenAngleDegrees - 37.0) < 0.001).assertTrue();
      expect(Math.abs(snapshot.eastScreenAngleDegrees + 53.0) < 0.001).assertTrue();
      expect(snapshot.markers.length).assertEqual(0);
    });

    it('地平视图有地点时生成四向和天顶且中心为地平坐标', 0, () => {
      const observer: ObserverState = {
        latitudeDegrees: 34.75,
        longitudeDegrees: 113.62,
        elevationMeters: 100.0,
        timestampMs: Date.UTC(2026, 6, 15, 12, 0, 0)
      };
      const viewport: NormalSkyViewport = NormalSkyProjectionService.homeViewport(
        observer, SkyMapOrientation.HORIZON_ZENITH);
      const snapshot: SkyOrientationSnapshot = NormalSkyOrientationService.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        directionGuides: true,
        observer: observer
      });
      expect(snapshot.centerAzimuthDegrees !== undefined).assertTrue();
      expect(snapshot.centerAltitudeDegrees !== undefined && snapshot.centerAltitudeDegrees > 89.0).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.NORTH)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.EAST)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.SOUTH)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.WEST)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.ZENITH)).assertTrue();
    });

    it('地平视图无地点时不伪造地理方向', 0, () => {
      const viewport: NormalSkyViewport = orientationViewport();
      viewport.orientation = SkyMapOrientation.HORIZON_ZENITH;
      const snapshot: SkyOrientationSnapshot = NormalSkyOrientationService.build({
        viewport: viewport,
        size: { widthPixels: 800.0, heightPixels: 600.0 },
        directionGuides: true
      });
      expect(snapshot.centerAzimuthDegrees === undefined && snapshot.centerAltitudeDegrees === undefined).assertTrue();
      expect(!containsKind(snapshot.markers, SkyDirectionKind.NORTH)).assertTrue();
      expect(!containsKind(snapshot.markers, SkyDirectionKind.ZENITH)).assertTrue();
      expect(containsKind(snapshot.markers, SkyDirectionKind.NORTH_CELESTIAL_POLE)).assertTrue();
    });
  });
}

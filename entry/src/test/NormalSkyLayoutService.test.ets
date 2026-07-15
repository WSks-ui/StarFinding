import { describe, expect, it } from '@ohos/hypium';
import { SkyGuideInsets } from '../main/ets/models/NormalSkyModels';
import {
  NormalSkyCompassLayout,
  NormalSkyLayoutService
} from '../main/ets/services/NormalSkyLayoutService';

export default function normalSkyLayoutServiceTest(): void {
  describe('普通星图响应式浮层布局', () => {
    it('1024乘720 Pad 的罗盘避开右侧控制坞和底部胶囊', 0, () => {
      const insets: SkyGuideInsets = NormalSkyLayoutService.guideInsets({
        viewportWidth: 1024.0,
        viewportHeight: 720.0,
        chromeVisible: true,
        compact: false,
        overlayPanel: 0,
        drawerWidth: 350.0,
        layerPanelOpen: false
      });
      const compass: NormalSkyCompassLayout = NormalSkyLayoutService.compassLayout(
        1024.0, 720.0, insets, false);
      expect(compass.xPixels + compass.sizePixels <= 948.0).assertTrue();
      expect(compass.yPixels + compass.sizePixels <= 632.0).assertTrue();
      expect(compass.sizePixels).assertEqual(64.0);
    });

    it('Pad 图层面板展开时罗盘与面板至少保留八像素间距', 0, () => {
      const insets: SkyGuideInsets = NormalSkyLayoutService.guideInsets({
        viewportWidth: 1024.0,
        viewportHeight: 720.0,
        chromeVisible: true,
        compact: false,
        overlayPanel: 0,
        drawerWidth: 350.0,
        layerPanelOpen: true
      });
      const compass: NormalSkyCompassLayout = NormalSkyLayoutService.compassLayout(
        1024.0, 720.0, insets, false);
      const panelLeft: number = 1024.0 - 278.0 - 8.0;
      expect(compass.xPixels + compass.sizePixels <= panelLeft - 8.0).assertTrue();
      expect(NormalSkyLayoutService.panelRootHeight(720.0, true) <= 474.0).assertTrue();
    });

    it('600乘500 分屏中的图层面板、罗盘和窗口边界互不重叠', 0, () => {
      const insets: SkyGuideInsets = NormalSkyLayoutService.guideInsets({
        viewportWidth: 600.0,
        viewportHeight: 500.0,
        chromeVisible: true,
        compact: true,
        overlayPanel: 0,
        drawerWidth: 576.0,
        layerPanelOpen: true
      });
      const compass: NormalSkyCompassLayout = NormalSkyLayoutService.compassLayout(
        600.0, 500.0, insets, false);
      const panelLeft: number = 600.0 - 278.0 - 8.0;
      expect(compass.xPixels + compass.sizePixels <= panelLeft - 8.0).assertTrue();
      expect(72.0 + NormalSkyLayoutService.panelRootHeight(500.0, true) <= 500.0).assertTrue();
    });

    it('紧凑抽屉打开时保留缩小罗盘并隐藏边缘方向标记', 0, () => {
      const insets: SkyGuideInsets = NormalSkyLayoutService.guideInsets({
        viewportWidth: 600.0,
        viewportHeight: 500.0,
        chromeVisible: true,
        compact: true,
        overlayPanel: 1,
        drawerWidth: 576.0,
        layerPanelOpen: false
      });
      const compass: NormalSkyCompassLayout = NormalSkyLayoutService.compassLayout(
        600.0, 500.0, insets, true);
      expect(compass.xPixels).assertEqual(16.0);
      expect(compass.yPixels + compass.sizePixels <= 150.0).assertTrue();
      expect(compass.sizePixels).assertEqual(48.0);
      expect(NormalSkyLayoutService.showDirectionMarkers(true, 1)).assertFalse();
    });

    it('极窄手机展开图层面板时隐藏无处安放的罗盘', 0, () => {
      expect(NormalSkyLayoutService.showCompass(360.0, true)).assertFalse();
      expect(NormalSkyLayoutService.showCompass(390.0, true)).assertTrue();
      expect(NormalSkyLayoutService.showCompass(360.0, false)).assertTrue();
    });
  });
}

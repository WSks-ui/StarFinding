import { SkyGuideInsets } from '../models/NormalSkyModels';

export interface NormalSkyLayoutQuery {
  viewportWidth: number;
  viewportHeight: number;
  chromeVisible: boolean;
  compact: boolean;
  overlayPanel: number;
  drawerWidth: number;
  layerPanelOpen: boolean;
}

export interface NormalSkyCompassLayout {
  xPixels: number;
  yPixels: number;
  sizePixels: number;
}

/** 普通星图浮层的纯布局计算，便于对 Pad、分屏和手机尺寸做单元测试。 */
export class NormalSkyLayoutService {
  static guideInsets(query: NormalSkyLayoutQuery): SkyGuideInsets {
    if (!query.chromeVisible) {
      return { leftPixels: 24.0, rightPixels: 24.0, topPixels: 24.0, bottomPixels: 24.0 };
    }
    const drawerInset: number = !query.compact && query.overlayPanel > 0 ? query.drawerWidth + 28.0 : 76.0;
    const maximumLayerInset: number = Math.max(96.0, query.viewportWidth - 104.0);
    const layerInset: number = query.layerPanelOpen ? Math.min(286.0, maximumLayerInset) : 76.0;
    return {
      leftPixels: query.compact ? 24.0 : 96.0,
      rightPixels: query.compact ? Math.max(24.0, layerInset) : Math.max(drawerInset, layerInset),
      topPixels: query.compact ? 102.0 : 112.0,
      bottomPixels: query.compact ? 116.0 : 88.0
    };
  }

  static panelHeight(viewportHeight: number): number {
    return Math.min(440.0, Math.max(250.0, viewportHeight - 130.0));
  }

  static panelRootHeight(viewportHeight: number, panelOpen: boolean): number {
    return panelOpen ? NormalSkyLayoutService.panelHeight(viewportHeight) + 34.0 : 310.0;
  }

  static compassLayout(viewportWidth: number, viewportHeight: number, insets: SkyGuideInsets,
    compactDrawerOpen: boolean): NormalSkyCompassLayout {
    if (compactDrawerOpen) {
      return {
        xPixels: 16.0,
        yPixels: Math.max(8.0, insets.topPixels - 6.0),
        sizePixels: 48.0
      };
    }
    const size: number = 64.0;
    const minimumX: number = Math.max(8.0, insets.leftPixels + 4.0);
    const minimumY: number = Math.max(8.0, insets.topPixels + 4.0);
    const desiredX: number = viewportWidth - insets.rightPixels - size - 8.0;
    const desiredY: number = viewportHeight - insets.bottomPixels - size - 8.0;
    return {
      xPixels: Math.max(minimumX, Math.min(desiredX, Math.max(minimumX, viewportWidth - size - 8.0))),
      yPixels: Math.max(minimumY, Math.min(desiredY, Math.max(minimumY, viewportHeight - size - 8.0))),
      sizePixels: size
    };
  }

  static showDirectionMarkers(compact: boolean, overlayPanel: number): boolean {
    return !compact || overlayPanel === 0;
  }

  static showCompass(viewportWidth: number, layerPanelOpen: boolean): boolean {
    return !layerPanelOpen || viewportWidth >= 390.0;
  }
}

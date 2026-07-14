import { curves } from '@kit.ArkUI';

/**
 * 探星全局动效参数。
 *
 * 页面、抽屉和控件必须复用这里的节奏，避免同一层级出现不同速度。姿态传感器、相机帧和
 * 天球投影属于实时数据流，不得套用这些 UI 动画，否则会增加 AR 画面的跟手延迟。
 */
export class MotionTokens {
  static readonly PRESS_MS: number = 100;
  static readonly QUICK_MS: number = 160;
  static readonly STANDARD_MS: number = 220;
  static readonly PAGE_MS: number = 300;
  static readonly EMPHASIZED_MS: number = 380;

  static press(): AnimateParam {
    return { duration: MotionTokens.PRESS_MS, curve: Curve.EaseOut };
  }

  static quick(): AnimateParam {
    return { duration: MotionTokens.QUICK_MS, curve: Curve.EaseOut };
  }

  static standard(): AnimateParam {
    return { duration: MotionTokens.STANDARD_MS, curve: curves.cubicBezierCurve(0.2, 0.0, 0.2, 1.0) };
  }

  static spring(): AnimateParam {
    return { duration: MotionTokens.PAGE_MS, curve: curves.responsiveSpringMotion(0.28, 0.86, 0.18) };
  }

  static page(direction: number): TransitionEffect {
    const enterX: number = direction >= 0 ? 24 : -24;
    const leaveX: number = direction >= 0 ? -12 : 12;
    const appear: TransitionEffect = TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: enterX, y: 0 }));
    const disappear: TransitionEffect = TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: leaveX, y: 0 }));
    return TransitionEffect.asymmetric(appear, disappear).animation({
      duration: MotionTokens.PAGE_MS,
      curve: curves.cubicBezierCurve(0.2, 0.0, 0.2, 1.0)
    });
  }

  static drawer(bottomSheet: boolean): TransitionEffect {
    const offsetX: number = bottomSheet ? 0 : 32;
    const offsetY: number = bottomSheet ? 40 : 0;
    return TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: offsetX, y: offsetY }))
      .animation(MotionTokens.spring());
  }

  static modal(): TransitionEffect {
    return TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: 0, y: 20 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation(MotionTokens.spring());
  }

  static capsule(): TransitionEffect {
    return TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: 0, y: -12 }))
      .animation(MotionTokens.standard());
  }
}

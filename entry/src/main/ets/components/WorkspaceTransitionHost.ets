import { MotionTokens } from '../utils/MotionTokens';

/** 为条件创建的工作区提供一致的进入/退出动画，同时保持业务状态仍由 Index 单点持有。 */
@Component
export struct WorkspaceTransitionHost {
  @Prop motionDirection: number = 1;
  @BuilderParam content: () => void = this.EmptyBuilder;

  @Builder
  private EmptyBuilder() {}

  build() {
    Column() {
      this.content()
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .transition(MotionTokens.page(this.motionDirection))
  }
}

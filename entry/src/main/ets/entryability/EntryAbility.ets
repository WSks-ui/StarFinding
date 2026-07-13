import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 权限、相机和网络服务共享同一个 Ability 上下文，避免页面重建后持有过期资源。
    AppStorage.setOrCreate('uiAbilityContext', this.context);
    try {
      // 天文观测需要避免亮色界面破坏暗视觉；应用内部仍通过语义色区分层级与状态。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(DOMAIN, 'StarFinding', '设置颜色模式失败: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '应用已创建');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '应用已销毁');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '创建主窗口');

    this.configureMainWindow(windowStage).catch((err: Error) => {
      hilog.error(DOMAIN, 'StarFinding', '配置沉浸窗口失败: %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'StarFinding', '加载主界面失败: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'StarFinding', '主界面加载完成');
    });
  }

  private async configureMainWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      // API 22 尚无 API 26 的 ImmersiveMaterial；窗口层只负责透明系统栏，材质由 ArkUI 兼容实现。
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFFFF',
        navigationBarContentColor: '#FFFFFFFF',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: true
      });
    } catch (error) {
      throw new Error(`沉浸窗口配置失败：${error}`);
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '主窗口已销毁');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '应用进入前台');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'StarFinding', '%{public}s', '应用进入后台');
  }
}

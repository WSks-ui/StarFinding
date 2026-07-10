# StarFinding 星空智控

StarFinding 是面向 HarmonyOS 6 平板的 AR 寻星与低成本星空摄影控制系统。应用负责星图交互、OnStepX 赤道仪控制、拍摄任务编排与结果查看；树莓派网关通过 USB 控制 Canon EOS R7，并完成板解析、堆栈和延时视频生成。

## 目录

- `entry/`：HarmonyOS Pad 应用。
- `gateway/`：树莓派相机与图像处理网关。
- `firmware/`：OnStepX MaxESP4 比赛配置和烧录说明。
- `cloud/`：华为云兼容的受约束图像增强服务。
- `docs/`：硬件接线、部署与真机验收记录。

## HarmonyOS 构建

```powershell
$env:DEVECO_HOME='<DevEco Studio 安装目录>'
$env:DEVECO_SDK_HOME=Join-Path $env:DEVECO_HOME 'sdk'
$env:PATH=(Join-Path $env:DEVECO_HOME 'jbr\bin') + ';' + $env:PATH
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default assembleHap --no-daemon
```

未配置签名时可以完成编译和打包检查，但安装真机前必须在 DevEco Studio 中配置调试证书。

本地核心单元测试：

```powershell
$env:DEVECO_HOME='<DevEco Studio 安装目录>'
$env:DEVECO_SDK_HOME=Join-Path $env:DEVECO_HOME 'sdk'
$env:PATH=(Join-Path $env:DEVECO_HOME 'jbr\bin') + ';' + (Join-Path $env:DEVECO_HOME 'tools\node') + ';' + $env:PATH
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default test --no-daemon
```

## 当前闭环

Pad 完成定位、姿态投影和 OnStepX 安全检查后，一键流程会先 GOTO 并等待停止，再逐帧控制 R7。智能长曝光在子曝光之间执行板解析，只对 `0.04°..2°` 的可信偏差进行小幅 GOTO 修正，最终提交本地堆栈；延时模式提交 FFmpeg 制片。华为云增强是本地堆栈后的可选步骤，失败不改变本地任务成功状态。

实现状态和真机证据分别记录在 `docs/implementation-status.md` 与 `docs/real-device-acceptance.md`。模拟网关结果不能填写为真实设备验收。

## 安全约束

自动 GOTO 仅在两轴回零、时间位置同步和软限位检查完成后开放。界面急停会发送 OnStepX `:Td#` 停止跟踪并双发 `:Q#` 停止运动，但它不能替代独立切断电机电源的物理急停。

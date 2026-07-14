# 软件实施状态

更新日期：2026-07-15。

## 已实现并自动验证

- HarmonyOS 6 / API 22 Pad 应用可构建为未签名 HAP；后摄预览、系统定位、姿态传感器、一星校准和 HYG 离线星表已接入 AR 投影。
- 普通星图已改为连续球面立体投影和单 Canvas 渲染，支持跨赤经 `0h`、天极浏览、锚点缩放旋转、搜索飞行、惯性、图层控制与统一命中。
- 离线目录覆盖 8921 颗 HYG 可见恒星、88 星座中心及连线、M1-M110 精确坐标，以及动态太阳、月球和主要行星；详情可直接进入升中落、天气与 18mm 观测规划。
- OnStepX TCP/LX200 客户端实现连接、状态轮询、位置时间同步、原点开关回零、GOTO、恒星/太阳/月球跟踪、停放，以及 `:Td#` 加双发 `:Q#` 软件急停。
- 拍摄流程在 GOTO 前冻结目标和参数，并以取消代次阻止急停后的旧流程重新开启跟踪或触发快门；赤道仪和相机网关急停链路独立执行。
- 相机网关客户端与 FastAPI 的 `/api/v1` 路由、snake_case DTO 和幂等键一致；模拟后端已完成拍摄、板解析、堆栈和延时制片自动测试。
- 智能长曝光按单帧任务执行：每帧结束后可板解析，误差在 `0.04°..2°` 内才执行小幅 GOTO 修正；错解或解析失败只降级，不盲目移动设备。
- 本地堆栈完成后可把结果以 multipart 上传到受约束增强服务；云端不可用时保留本地结果。
- 手势层已具备真实前摄 YUV 帧入口和 21 点解释器。仓库没有经过许可和精度验收的关键点模型，因此当前明确显示不可用，不生成假关键点。

自动验证命令：

```powershell
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default test --no-daemon
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default assembleHap --no-daemon
Push-Location gateway; python -m pytest -q; Pop-Location
Push-Location cloud; python -m pytest -q; Pop-Location
```

当前结果：HarmonyOS 48 个核心、星图与工作流用例通过；网关 9 个用例通过；云端 6 个用例通过。

## 不能由本机替代的真机验收

- DevEco Studio 自动签名、Pad 安装、相机/定位/姿态权限和横屏布局。
- 普通星图在目标 Pad 上连续拖拽/缩放的 55-60 FPS 性能，以及手机真机触控热区和标签遮挡复核。
- Pad 在 `StarScope` 网络中访问 `http://10.42.0.1:8000`，并确认系统允许该局域网明文 HTTP。
- EOS R7 的 USB 枚举、1/10/30 秒 RAW+JPEG、存储卡 CR3 保留、电量字段和长时间稳定性。
- MaxESP4 烧录、AUX3/AUX4 常闭开关的实际电平、回零方向、真实软限位、停放和断线保护。
- 真实夜空 JPEG 的 astrometry.net 解算率、18mm 视场参数、帧间修正方向和堆栈质量。
- 独立物理急停。软件 `:Q#` 绝不能替代切断驱动电源或硬件 EN 的急停回路。
- 华为云 OBS/ModelArts 凭据、网络可达性、模型版本和处理结果的星点保护复核。

## 已知降级

- 本机运行的网关是显式 `mock` 相机与 `mock` 板解析，且本机没有 FFmpeg；只用于接口联调。
- CameraKit 已提供可插拔手势帧源，但没有模型时只保留触控操作。
- 未配置签名时生成 `entry-default-unsigned.hap`，不能直接安装到真机。

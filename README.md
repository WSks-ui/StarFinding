# 探星 StarFinding

> 面向 HarmonyOS 手机与平板的 AR 星图、观测规划与低成本星空摄影系统。

探星以软件体验为核心：即使没有连接赤道仪、相机或网关，用户仍可浏览星图、检索天体、查看升落时间和规划出行；连接开源 OnStepX 谐波赤道仪及 Canon EOS R7 后，应用可将同一套目标选择流程延伸为安全的观测与拍摄任务。

项目面向城市夜空和 18mm 广角镜头的实际场景，优先推荐适合广角呈现的目标与时间窗口。它不是专业天文测量软件，天球计算和 AR 叠加用于观测预览、学习与构图辅助；精确指向仍应由板解析与设备校准闭环确认。

## 核心体验

| 场景 | 可用能力 | 是否依赖外部硬件 |
| --- | --- | --- |
| AR 星图 | 后摄预览上的天穹星图、姿态跟随、一星校准、天体点选与详情 | 否 |
| 普通星图 | 全屏星图、天体检索、目标详情、触控与前摄手势交互 | 否 |
| 观测规划 | 天体升起/中天/落下、暗夜窗口、月相、月距与天气评分 | 否，天气联网时更完整 |
| 智能拍摄 | 仅观测、短子曝光堆栈、延时摄影、任务进度与结果查看 | 是 |
| 设备控制 | 回零、同步、GOTO、跟踪、停放、状态轮询和急停 | 是 |
| 图片后期 | 本地坏帧剔除、配准、堆栈、背景校正与可选云端增强 | 网关为必需，云端为可选 |

## 软件架构

```text
HarmonyOS Pad / Phone
  ├── AR 星图与普通星图
  ├── 离线星表、星历计算、天气与观测规划
  ├── OnStep LX200 控制、拍摄任务与结果展示
  └── 可选连接 StarScope 局域网
          │
Linux 网关（FastAPI）
  ├── libgphoto2 控制 Canon EOS R7
  ├── astrometry.net 板解析
  ├── 本地配准、堆栈与 FFmpeg 延时视频
  └── 可选调用受约束的云端图像增强服务
          │
OnStepX / MaxESP4 ── DIY 谐波赤道仪
```

网关可部署在树莓派或更经济的 Linux 电脑上。比赛主链路使用 R7 的 USB/libgphoto2 控制方式；CCAPI 若后续可用，仅作为相机适配器扩展，不改变 Pad 端操作流程。

## 仓库结构

| 路径 | 说明 |
| --- | --- |
| `entry/` | HarmonyOS 6 应用：全屏星图、AR 天穹、规划、拍摄与设备控制。 |
| `gateway/` | Linux FastAPI 网关：R7 控制、板解析、堆栈、延时视频和 SQLite 任务记录。 |
| `firmware/onstepx-maxesp4/` | OnStepX MaxESP4 的 StarFinding 配置补丁与刷写说明。 |
| `cloud/` | 受约束图像增强服务，采用星点保护策略，不能生成、删除或移动星体。 |
| `docs/` | 网络拓扑、部署说明、实现状态与真机验收记录。 |

## 快速开始

### 1. 准备开发环境

- DevEco Studio，HarmonyOS SDK API 22（HarmonyOS 6）。
- Node、JBR 均使用 DevEco Studio 随附版本。
- 设备调试需要在 DevEco Studio 中配置调试签名证书。

以下命令以 PowerShell 为例。将 `<DevEco Studio 安装目录>` 替换为本机目录，例如 `D:\DevEco Studio`。

### 2. 运行单元测试

```powershell
$env:DEVECO_HOME='<DevEco Studio 安装目录>'
$env:DEVECO_SDK_HOME=Join-Path $env:DEVECO_HOME 'sdk'
$env:JAVA_HOME=Join-Path $env:DEVECO_HOME 'jbr'
$env:PATH=(Join-Path $env:DEVECO_HOME 'jbr\bin') + ';' + (Join-Path $env:DEVECO_HOME 'tools\node') + ';' + $env:PATH
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default test --no-daemon
```

### 3. 构建 HAP

```powershell
$env:DEVECO_HOME='<DevEco Studio 安装目录>'
$env:DEVECO_SDK_HOME=Join-Path $env:DEVECO_HOME 'sdk'
$env:JAVA_HOME=Join-Path $env:DEVECO_HOME 'jbr'
$env:PATH=(Join-Path $env:DEVECO_HOME 'jbr\bin') + ';' + $env:PATH
& (Join-Path $env:DEVECO_HOME 'tools\hvigor\bin\hvigorw.bat') --mode module -p module=entry@default assembleHap --no-daemon
```

未配置签名时，构建会生成未签名 HAP，用于编译和打包检查；安装到真机前必须配置调试或发布签名。

### 4. 以纯软件模式体验

直接在模拟器或真机启动应用即可使用普通星图、AR 预览、天体详情与观测规划。首次进入 AR 星图时，按需授予相机、位置、陀螺仪和加速度计权限；拒绝这些权限不会阻止普通星图和离线规划使用。

## 连接真实设备

完整拍摄链路需要 Pad、Linux 网关和 OnStepX 接入同一 `StarScope` 局域网：

1. 在 OnStepX 启用 Wi-Fi TCP 的 LX200 通道，默认端口为 `9999`。
2. 将 EOS R7 通过 USB 连接到 Linux 网关，并在网关上验证 `gphoto2` 识别与拍摄下载。
3. 将 Pad 连接至相同网络，在设备页发现网关和赤道仪。
4. 先完成原点、位置、时间和软限位检查，再执行同步、GOTO 或拍摄任务。

部署细节请见 [网关说明](gateway/README.md)、[OnStepX 固件说明](firmware/onstepx-maxesp4/README.md)、[网络拓扑](docs/infra/topology.md) 与 [云端部署说明](docs/infra/cloud-deployment.md)。

## 拍摄与后期原则

- 默认采用适合城市光污染和 18mm 镜头的短子曝光堆栈，而不是单张超长曝光。
- 推荐逻辑会综合目标角尺寸、高度角、月相、月距和天气，避免推荐广角无法有效呈现的小目标。
- 本地链路先完成坏帧剔除、星点配准、亮度归一化、堆栈和背景校正。
- 云端增强必须保留原片、堆栈图、AI 结果、模型版本和处理参数；云端不可用时，本地堆栈照常输出。

## 安全边界

自动 GOTO 仅在两轴回零、时间位置同步和软限位检查完成后开放。界面急停会发送 OnStepX `:Td#` 停止跟踪并双发 `:Q#` 停止运动，但它不能替代独立切断电机电源的物理急停。

拍摄、板解析和 AI 结果均应保留原始数据与任务日志。模拟网关或模拟赤道仪的结果不能填写为真实设备验收。

## 进展与验收

- [实现状态](docs/implementation-status.md)
- [真实设备验收记录](docs/real-device-acceptance.md)

## 许可证与第三方声明

第三方组件和许可证信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

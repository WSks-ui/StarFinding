# OnStepX MaxESP4 比赛配置

本目录只保存针对现有开源源码的配置补丁，不包含也不修改 D 盘原始 OnStepX。补丁基于以下文件核对：

- `Config.h` SHA-256：`8E6908A895544489D030EB7060B987960FCA90AEE155CCA1FB01B17FA26D001A`
- `Extended.config.h` SHA-256：`03CFEB332F12E20E29D5AAF5FB5FF8F954DCEEEBF681A451D8EE661155620E4D`
- 固件自报版本：OnStepX `10.24c`，配置版本 `6`

若哈希不一致，先人工比对宏名和引脚图，不要强制应用补丁。

## 补丁内容

- ESP32 使用 `WIFI_STATION` 和 DHCP 接入 `StarScope`，由树莓派 NetworkManager 为其保留 `10.42.0.20`，LX200 TCP 标准通道为 `9999`；
- 关闭经典蓝牙和 Web 管理面，保留 mDNS `starfinding-mount.local`；
- `AUX3/GPIO14` 为轴1回零，`AUX4/GPIO13` 为轴2回零；
- 两轴使用内部上拉的常闭开关，断开时为 `HIGH`；
- 启用严格启动限制，未设置日期/时间前不允许电机动作；
- 将轴1软限位收紧到 `-120..120`，轴2保留 GEM 回零所需的 `-90..90`，并将首次联调速度降为 `0.5 deg/s`。

软限位不是机械参数的替代品。轴1的 `-120..120` 只是首次联调起点，必须在卸载相机、低速、手握急停的条件下测得真实无碰撞范围，再向内留出制动余量。轴2不能机械地改成 `±85°`，因为 GEM 的正常回零坐标位于赤纬 `±90°`；轴2安全范围需要结合所在半球、回零方向和真实结构单独验证。

## 接线

```text
轴1：AUX3 / GPIO14 ---- 常闭触点 ---- GND
轴2：AUX4 / GPIO13 ---- 常闭触点 ---- GND
```

正常未触发时触点闭合，GPIO 读取 `LOW`；到达回零边界后触点打开，内部上拉使 GPIO 读取 `HIGH`。断线也会表现为 `HIGH`，便于在回零测试中暴露故障。

OnStepX 的 `AXISn_SENSE_HOME` 描述的是“位于回零点某一侧时的电平”，机械凸轮/传感器应形成稳定的边界状态。若开关只产生很窄的瞬时脉冲，必须先改造凸轮或换用合适的传感器，不能直接执行自动回零。

注意：

- ESP32 GPIO 只能接 `3.3V` 逻辑，本方案只将 GPIO 与 GND 短接；严禁引入 `5V`、`12V` 或电机电源；
- GPIO13/14 的具体端子仍需用万用表对照 MaxESP4 板卡丝印确认；
- 软件停止和回零开关都不等同于急停。物理急停应使用常闭回路直接切断驱动器电源或硬件 `EN`，并保证断线即停机；
- 首次测试拆下 R7、镜头和所有可能缠绕的线缆。

## 在副本上应用

1. 复制整个 `OnStepXMAXESP4` 到一个新的工作目录，并把原目录压缩归档。
2. 在副本中核对上面的两个 SHA-256。
3. 执行补丁预检和应用：

```powershell
$patch = (Resolve-Path .\firmware\onstepx-maxesp4\StarFinding.Config.patch).Path
Set-Location C:\path\to\OnStepXMAXESP4-copy
git apply --unidiff-zero --check $patch
git apply --unidiff-zero $patch
```

4. 将 `REPLACE_WITH_A_STRONG_PASSWORD` 换成比赛路由密码。真实密码不提交 Git。
5. 若设备曾保存过 Wi-Fi/运行时配置，按源码注释仅临时把 `NV_WIPE` 设为 `ON` 烧录一次，等待初始化完成后立刻改回 `OFF` 再烧录。长期保留 `NV_WIPE ON` 会损耗闪存。

## 烧录与分阶段验收

使用随硬件提供的 Arduino IDE、ESP32 core `2.0.12` 和配套库。板型、Flash 参数、串口与原项目保持一致；不要仅凭本文件猜测板型。烧录前断开电机主电源，只保留控制板 USB 供电。

1. 仅编译，确认没有宏重定义或引脚冲突警告。
2. 烧录后通过 USB 串口发送 `:GVP#`，期望回复 `On-Step#`。
3. 确认控制板接入 `StarScope`，路由器租约表能看到设备；从同网段执行 `Test-NetConnection <IP> -Port 9999`。
4. 仍不接电机，手动按压/释放两只开关，在串口调试或 OnStep 状态中确认“闭合 LOW、打开 HIGH”，并验证轴1/轴2没有接反。
5. 接电机但卸载相机，将 GOTO 基础速度保持 `0.5 deg/s`。从靠近回零点的位置开始，每次只测试一个轴；方向错误立即物理急停并修正配置。
6. 验证断开任一回零开关导线会进入 HIGH 状态，且自动回零不会继续越过该边界。
7. 通过 Pad 下发日期、时间和位置后，再依次测试回零、短距离 GOTO、跟踪、软件停止、物理急停和重新上电恢复。

TCP 验证可使用：

```powershell
$client = [Net.Sockets.TcpClient]::new('<MOUNT_IP>', 9999)
$stream = $client.GetStream()
$bytes = [Text.Encoding]::ASCII.GetBytes(':GVP#')
$stream.Write($bytes, 0, $bytes.Length)
```

## 回滚

1. 物理急停，断开电机电源和相机负载。
2. 将归档的原始 `Config.h`、`Extended.config.h` 恢复到源码副本，或直接使用未改动的归档副本重新编译。
3. 必要时执行一次 `NV_WIPE ON` 烧录以清除新网络/运行时配置，随后恢复 `NV_WIPE OFF` 并再次烧录。
4. USB 串口验证 `:GVP#` 后再恢复电机电源。

比赛现场应同时携带：已验证 HAP、已验证固件二进制、原始固件二进制、两套配置文件、USB 数据线和可直接切断驱动电源的物理急停。

# StarFinding 现场网络与硬件拓扑

```text
                         USB
Canon EOS R7 <--------------------------> Raspberry Pi 5
                                              |
                              AP: StarScope / 10.42.0.1/24 / DHCP
                                              |
                  +---------------------------+-------------------------+
                  |                                                     |
        HarmonyOS 6 Pad                                      OnStepX MaxESP4
        DHCP 动态地址                                         DHCP 保留 10.42.0.20
        网关 10.42.0.1:8000                                  LX200 TCP :9999
        云增强 10.42.0.1:8080                                mDNS: starfinding-mount.local
```

## 固定约定

- 树莓派通过 NetworkManager `ipv4.method shared` 建立唯一 Wi-Fi AP，自身固定为 `10.42.0.1/24`；
- Pad 和 OnStepX 都作为 station 接入，Pad 使用普通 DHCP 动态租约；
- R7 只通过 USB 接树莓派，避免相机热点抢占 Pad 的 Wi-Fi；
- OnStepX 固件保持 DHCP，不硬编码地址；在 NetworkManager 共享网络中按 MAC 保留 `10.42.0.20`；
- Pad 优先使用 `starfinding-mount.local`，mDNS 失败时回退到 `10.42.0.20`；
- TCP `9999` 仅允许 `StarScope` 内网访问，不映射公网；
- FastAPI 网关和增强服务分别使用 `http://10.42.0.1:8000`、`http://10.42.0.1:8080`，以 systemd 或 Docker 自动重启；
- ModelArts/OBS 是可选上行链路，断网时拍摄、原图保存和本地增强仍能完成。

## 现场启动顺序

1. 架设赤道仪，确认机械锁定、配重、线缆余量和物理急停；
2. 启动树莓派并等待 `StarScope` AP、DHCP、相机网关和增强服务健康；
3. 启动 OnStepX，确认获得保留地址 `10.42.0.20` 且 `9999` 可达；
4. 连接 R7 USB，关闭相机自动休眠，设置手动对焦和 RAW+JPEG；
5. Pad 接入 `StarScope`，检查赤道仪、相机和本地增强三项状态；
6. Pad 同步日期、时间、经纬度后才允许回零和 GOTO；
7. 执行回零、短距离空载 GOTO、软件停止、物理急停恢复测试，再安装相机。

## 故障隔离

| 故障 | 应继续工作的能力 | 处理 |
| --- | --- | --- |
| 公网/华为云中断 | 赤道仪、R7、本地堆栈、本地增强 | 显示“已使用本地结果”，稍后可重试云端 |
| OnStepX Wi-Fi 中断 | 相机预览和已拍文件 | 立即停止新拍摄计划，禁止盲目重发 GOTO |
| R7 USB 中断 | 赤道仪停止/停放 | 任务标记失败，不重复触发快门，重连后人工重试 |
| Pad 退出 | 树莓派保存原图与进行中的本地处理 | 重进应用后按 UUID 恢复任务 |
| 回零开关异常 | 不允许自动回零/GOTO | 切断驱动电源，检查常闭回路与 GPIO 电平 |

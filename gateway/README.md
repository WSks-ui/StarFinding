# StarFinding 树莓派相机网关

网关在树莓派 5 上统一管理 EOS R7、板解析、JPEG 堆栈、光污染背景校正和延时视频。Pad 只连接 `StarScope` 局域网并访问一个 HTTP 服务，不需要直接连接相机热点。

## 能力与降级边界

- `gphoto2` 后端通过 USB 控制真实相机，所有调用串行执行；模拟后端会生成带轻微漂移的测试星空和显式标记的 `.mock.cr3` 占位文件。
- `astrometry.net` 后端调用本机 `solve-field`；模拟板解析只用于接口联调，响应中的 `simulated` 永远为 `true`。
- FFmpeg 不做伪降级：未安装时健康检查会显示不可用，延时任务会明确失败；原始 JPEG 和其他处理不受影响。
- 网关本地处理不生成、删除或移动星体。光污染校正只减去大尺度低频背景，原片与结果分别登记和下载。
- 当前真实 R7 的单帧限制为 30 秒。只有本机验证 Bulb 菜单和释放流程后才应开放 31–300 秒；比赛主流程使用 10–30 秒子曝光堆栈。

## 本机开发与模拟联调

需要 Python 3.11+：

```bash
cd gateway
python -m venv .venv
source .venv/bin/activate              # Windows: .venv\Scripts\activate
pip install -e ".[test]"
export STARFINDING_CAMERA_BACKEND=mock  # PowerShell: $env:STARFINDING_CAMERA_BACKEND="mock"
export STARFINDING_PLATE_SOLVER_BACKEND=mock
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

浏览 `http://127.0.0.1:8000/docs` 可直接调试接口。测试命令：

```bash
pytest
```

## 树莓派 5 安装

使用 64 位 Raspberry Pi OS Bookworm，将本目录复制到树莓派后执行：

```bash
chmod +x scripts/install.sh
sudo ./scripts/install.sh
curl http://127.0.0.1:8000/health
```

脚本安装 `gphoto2`、FFmpeg、`astrometry.net`，创建受限的 `starfinding` 系统用户，并把数据保存到 `/var/lib/starfinding-gateway`。修改 `/etc/starfinding-gateway.env` 后执行：

```bash
sudo systemctl restart starfinding-gateway
journalctl -u starfinding-gateway -f
```

真实设备调试建议先停服务，避免两份 gphoto2 同时抢占 USB：

```bash
sudo systemctl stop starfinding-gateway
gphoto2 --auto-detect
gphoto2 --summary
gphoto2 --list-config
sudo systemctl start starfinding-gateway
```

将 R7 设为手动曝光、手动对焦、RAW+JPEG；关闭相机 Wi-Fi 和自动休眠，使用可靠的 USB-C 数据线及独立供电。相机需确认允许“无存储卡释放快门”为关闭，以保证 CR3 留在卡中；网关命令同时使用 `--keep`。

## `StarScope` 局域网

树莓派连接一块支持 AP 模式的 Wi-Fi 适配器后，可用 NetworkManager 建热点。密码应在比赛前改成非默认值：

```bash
sudo nmcli device wifi hotspot ifname wlan0 con-name StarScope ssid StarScope password '替换为至少12位密码'
sudo nmcli connection modify StarScope ipv4.addresses 10.42.0.1/24 ipv4.method shared
sudo nmcli connection modify StarScope connection.autoconnect yes
sudo nmcli connection up StarScope
```

Pad 和 OnStepX 都接入 `StarScope`。建议在 NetworkManager 中为 OnStepX 做 DHCP 地址保留；网关固定访问地址为 `http://10.42.0.1:8000`。防火墙仅放行热点网段：

```bash
sudo apt-get install -y ufw
sudo ufw allow from 10.42.0.0/24 to any port 8000 proto tcp
sudo ufw enable
```

## 主要接口

| 接口 | 用途 |
| --- | --- |
| `GET /health` | 相机、板解析、FFmpeg 与模拟状态 |
| `GET /api/v1/camera/status` | R7 连接状态 |
| `GET /api/v1/camera/capabilities` | ISO、光圈、快门和 Bulb 能力 |
| `GET /api/v1/camera/liveview` | 单帧实时取景 JPEG |
| `POST /api/v1/capture/tasks` | 创建一帧或多子曝光拍摄任务 |
| `POST /api/v1/plate-solve` | 创建板解析任务 |
| `POST /api/v1/stack` | 配准、坏帧剔除、堆栈与光污染校正 |
| `POST /api/v1/timelapse` | 生成 1080p H.264 MP4 |
| `GET /api/v1/tasks/{id}` | 查询任务状态与结果 |
| `POST /api/v1/tasks/{id}/cancel` | 取消排队或运行中的任务 |
| `WS /ws/tasks/{id}` | 订阅任务进度 |
| `POST/GET /api/v1/files` | 上传外部 JPEG/PNG、列出文件 |
| `GET /api/v1/files/{id}` | 下载原片或处理结果 |

会触发快门的请求应带唯一 `Idempotency-Key` 请求头。网络重试时复用同一个值，网关会返回原任务，不会重复执行快门。所有任务状态统一为 `pending/running/succeeded/failed/cancelled`。

## 比赛前真机检查

1. `health.camera.simulated` 必须为 `false`，相机型号应显示 EOS R7。
2. 分别用 1 秒、10 秒、30 秒测试 RAW+JPEG，下载并人工打开 JPEG，同时在 R7 存储卡确认 CR3 存在。
3. 使用实际 18mm 夜空 JPEG 测试 `plate-solve`，核对中心赤经赤纬、视场和旋转角。
4. 连续拍摄至少 20 帧并执行堆栈；拔网线/USB 后确认任务明确失败且重新连接可恢复。
5. 生成 MP4 并在比赛 Pad 播放；保存一份真实任务和文件目录作为阴雨现场回放材料。

# 华为云增强部署说明

## 部署原则

`cloud/` 服务是可信约束层：ModelArts 只产生候选图，服务在本地重新计算星点掩膜并混合原图，随后保存原图、掩膜、结果和哈希。OBS 仅用于可选归档，不作为现场任务成功的前置条件。

## 容器部署

```powershell
Set-Location .\cloud
docker build -t starfinding-enhancement:0.1.0 .
docker run --rm -p 8080:8080 --env-file .env -v starfinding-data:/data starfinding-enhancement:0.1.0
```

比赛树莓派上推荐先使用 `ENHANCEMENT_BACKEND=auto`。没有公网或云配置不完整时自动使用本地后端；若要完全消除外网等待，现场直接设为 `local`。

## ModelArts 契约

将模型部署为实时推理服务，并设置：

- `MODELARTS_ENABLED=true`
- `MODELARTS_ENDPOINT`：实时服务推理 URL
- `MODELARTS_TOKEN`：短期访问令牌，不写入镜像或仓库
- `MODELARTS_AUTH_HEADER`：默认使用华为云 IAM 常见的 `X-Auth-Token`；若前置网关约定不同可调整
- `MODELARTS_TIMEOUT_SECONDS`：现场建议 `10` 到 `20`

请求为 `POST application/octet-stream` 原始图像，并带有 `X-StarFinding-Task-Id` 和 `X-Enhancement-Strength`；响应必须是与输入同尺寸的可解码图像。默认通过 `X-Auth-Token` 发送令牌，且健康接口不会回显令牌。

当前脚手架适合前置一个 API Gateway/FunctionGraph 适配层，把该简单契约转换成具体 ModelArts 服务签名。任何超时、连接错误、无效图片或尺寸不一致都应记录降级原因并转本地算法。

## OBS 环境变量

- `OBS_ENDPOINT`
- `OBS_ACCESS_KEY_ID`
- `OBS_SECRET_ACCESS_KEY`
- `OBS_BUCKET`

这些变量已纳入健康状态检查，但当前版本没有把 OBS 上传放进任务成功路径。接入归档适配器时必须先写本地文件并计算 SHA-256，再异步上传；上传失败只记录告警，不删除本地原图或结果。

## 上线检查

1. `GET /health` 返回 `status=ok`，且不包含令牌、AK、SK；
2. 上传已知测试图，任务最终为 `succeeded`；
3. 下载 `original` 后 SHA-256 与上传文件完全相同；
4. 下载 `star-mask`，确认亮星核心被覆盖，城市光污染背景未大面积误判；
5. 断开公网再上传，任务仍为 `succeeded` 且 `backend_used=local_fallback`；
6. 恢复网络后新任务可使用 ModelArts，历史本地结果不被覆盖；
7. 数据卷容量、日志轮转和比赛前夜的离线备份已确认。

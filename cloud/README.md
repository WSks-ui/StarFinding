# StarFinding 受约束图像增强服务

该服务接收树莓派网关输出的 JPEG/PNG/WebP，保留原始字节，并生成：

- `result.png`：本地或 ModelArts 候选结果经星点保护后的无损图像；
- `star-mask.png`：保护区域，可用于比赛展示算法真实性；
- `metadata.json`：输入/输出 SHA-256、算法版本、后端、降级原因与处理参数。

服务不生成、删除或移动星体。高频星点区域在最终混合时使用原始像素，背景区域才接受降噪和光污染校正。

本地算法避免把整张 R7 原图展开成多份浮点数组，并在单进程内串行处理任务，防止并发的 3250 万像素图像耗尽树莓派内存。部署时保持 Uvicorn 单 worker；横向扩容应让每个实例使用独立任务队列和数据目录。

## 本地运行

```powershell
Set-Location .\cloud
python -m pip install -r requirements-dev.txt
python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

打开 `http://127.0.0.1:8080/docs` 查看交互式接口文档。任务创建示例：

```powershell
curl.exe -F "image=@sample.jpg" -F "strength=0.65" http://127.0.0.1:8080/v1/enhancements
```

使用客户端生成的 UUID 作为幂等键：

```powershell
curl.exe -F "image=@sample.jpg" -F "task_id=7bc41a5c-5d9f-43bb-9877-bca57559a766" http://127.0.0.1:8080/v1/enhancements
```

相同 UUID 和相同原图会返回原任务；相同 UUID 配另一张图返回 `409`。

## 主要接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/health` | 本地、ModelArts、OBS 配置状态（不回显密钥） |
| `POST` | `/v1/enhancements` | 创建异步增强任务 |
| `GET` | `/v1/enhancements/{task_id}` | 查询状态和元数据 |
| `GET` | `/v1/enhancements/{task_id}/original` | 下载未改动原图 |
| `GET` | `/v1/enhancements/{task_id}/result` | 下载增强结果 |
| `GET` | `/v1/enhancements/{task_id}/star-mask` | 下载星点保护掩膜 |

## 后端模式

- `local`：始终使用本地轻量算法，现场无网时推荐；
- `mock`：原样输出，用于联调；
- `auto`：ModelArts 配置完整时优先云端，否则本地；云端超时或返回无效图像也回退本地；
- `modelarts`：请求云端，但仍保留本地回退，避免云服务故障中断拍摄链路。

所有部署变量见 `.env.example`。OBS 变量为后续归档适配器预留；当前版本以本地卷为事实来源，因此 OBS 不可用不会影响原图和本地结果。

## 测试

```powershell
python -m pytest
```

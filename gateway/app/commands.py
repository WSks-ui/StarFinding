from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


class CommandError(RuntimeError):
    """外部工具执行失败，保留可展示给客户端的简短错误信息。"""


@dataclass(frozen=True, slots=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


class CommandRunner:
    """以参数数组执行外部命令，完全不经过 shell。

    相机参数和文件名可能来自 Pad，请勿把它们拼成命令字符串；参数数组可避免
    空格、引号及 shell 元字符被二次解释。所有调用还必须设置有限超时。
    """

    @staticmethod
    def available(binary: str) -> bool:
        return Path(binary).is_file() or shutil.which(binary) is not None

    def run(
        self,
        args: Sequence[str],
        *,
        timeout: float,
        cwd: Path | None = None,
        env: Mapping[str, str] | None = None,
        check: bool = True,
    ) -> CommandResult:
        if not args:
            raise ValueError("外部命令参数不能为空")
        try:
            completed = subprocess.run(
                [str(item) for item in args],
                cwd=str(cwd) if cwd else None,
                env=dict(env) if env else None,
                capture_output=True,
                text=True,
                errors="replace",
                timeout=timeout,
                check=False,
                shell=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CommandError(f"外部工具执行超时（{timeout:.0f} 秒）：{args[0]}") from exc
        except OSError as exc:
            raise CommandError(f"无法启动外部工具 {args[0]}：{exc}") from exc

        result = CommandResult(tuple(str(item) for item in args), completed.returncode, completed.stdout, completed.stderr)
        if check and completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()[-800:]
            raise CommandError(f"外部工具 {args[0]} 执行失败（{completed.returncode}）：{detail}")
        return result

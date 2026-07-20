import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import {
  ObservationPlanningResult,
  ObservationShareKind,
  ObservationSharePayload,
  ObservationShareResult,
  OutingRecommendation,
  PlanningShareInput,
  PlanningWeatherSummary,
  ReplayAssetSource,
  SessionKind,
  SessionStatus,
  TaskReportShareInput,
  WeatherDataStatus,
  WorkflowStage
} from '../models';
import { PlanningSnapshotService } from './PlanningSnapshotService';

const PLAIN_TEXT_UTD: string = 'general.plain-text';

/**
 * 生成并调用系统分享面板。
 *
 * 安全边界：
 * 1. 只接收结构化规划快照或任务会话，不接收任意调试文本。
 * 2. 不读取 DeviceConnectionSettings、网关端点、令牌和日志。
 * 3. 数字孪生报告必须带“模拟素材 · 非现场实拍”，不能冒充现场成品。
 */
export class ObservationShareService {
  static createPlanningPayload(input: PlanningShareInput): ObservationSharePayload {
    if (!PlanningSnapshotService.isConsistent(input.snapshot)) {
      throw new Error('规划快照不一致，已阻止分享旧日期结果');
    }
    const result: ObservationPlanningResult = input.snapshot.result;
    const title: string = `探星观测计划 · ${input.targetName}`;
    const lines: string[] = [];
    lines.push(title);
    lines.push(`${input.designation} · ${ObservationShareService.nightLabel(input.snapshot.dayOffset)}`);
    lines.push(`观测夜：${ObservationShareService.dateTime(input.snapshot.period.startAtMs)} 至 ${
      ObservationShareService.dateTime(input.snapshot.period.endAtMs)}（设备时间）`);
    lines.push(`地点：${input.snapshot.locationSource} · ${
      ObservationShareService.coordinateText(input.snapshot.observerLatitudeDegrees,
        input.snapshot.observerLongitudeDegrees)}`);
    if (input.snapshot.locationProvisional) {
      lines.push('位置状态：最近位置，系统正在后台校正');
    }
    lines.push(`出行建议：${ObservationShareService.recommendationText(result.recommendation)}`);
    lines.push(`天文可观测时段：${ObservationShareService.astronomyWindowText(result)}`);
    lines.push(`推荐拍摄时段：${ObservationShareService.captureWindowText(result)}`);
    lines.push(`评分：天文 ${ObservationShareService.scoreText(result.astronomyScore)} · 天气 ${
      ObservationShareService.scoreText(result.weatherScore)} · 综合 ${
      ObservationShareService.scoreText(result.overallScore)}`);
    lines.push(`月光：${Math.round(result.moonIlluminationPercent)}% · ${result.moonPhaseName}${
      result.moonSeparationDegrees === undefined ? '' :
        ` · 距目标 ${Math.round(result.moonSeparationDegrees)}°`}`);
    lines.push(`天气风险：${ObservationShareService.weatherText(result)}`);
    if (result.warnings.length > 0) {
      lines.push(`提醒：${result.warnings.join('；')}`);
    }
    lines.push('由探星 StarFinding 生成');
    return {
      kind: ObservationShareKind.PLANNING,
      title: title,
      description: '今晚天文观测计划',
      content: lines.join('\n'),
      simulated: false
    };
  }

  static createTaskReportPayload(input: TaskReportShareInput): ObservationSharePayload {
    const simulated: boolean = input.replayManifest !== undefined;
    const session = input.session;
    const title: string = `探星观测报告 · ${session.target.name}`;
    const lines: string[] = [];
    lines.push(title);
    if (simulated) {
      lines.push('数据声明：模拟素材 · 非现场实拍');
    } else {
      lines.push('数据声明：真实任务会话记录');
    }
    lines.push(`${session.target.designation} · ${ObservationShareService.sessionKindText(session.kind)}`);
    lines.push(`状态：${ObservationShareService.sessionStatusText(session.status)}`);
    lines.push(`阶段：${ObservationShareService.workflowStageText(session.stage)}`);
    lines.push(`进度：${Math.round(session.progressPercent)}%`);
    if (session.kind !== SessionKind.OBSERVATION) {
      lines.push(`完成帧数：${session.completedFrames} / ${session.plan.frameCount}`);
      lines.push(`拍摄参数：${session.plan.exposureSeconds}s × ${session.plan.frameCount} · ISO ${
        session.plan.iso} · f/${session.plan.aperture}`);
    }
    lines.push(`开始时间：${ObservationShareService.dateTime(session.startedAtMs)}`);
    if (session.completedAtMs > 0) {
      lines.push(`结束时间：${ObservationShareService.dateTime(session.completedAtMs)}`);
    }
    lines.push(`成品数量：${session.products.length}`);
    if (input.replayManifest !== undefined) {
      lines.push(`演练素材来源：${input.replayManifest.source === ReplayAssetSource.REAL_CAPTURE_REPLAY ?
        '真实设备历史素材 · 非实时' : '模拟素材 · 非现场实拍'}`);
      lines.push(`演练素材文件：${input.replayManifest.files.length}`);
    }
    if (session.warnings.length > 0) {
      lines.push(`提醒：${session.warnings.join('；')}`);
    }
    if (session.errorMessage.length > 0) {
      lines.push(`失败原因：${session.errorMessage}`);
    }
    lines.push('由探星 StarFinding 生成');
    return {
      kind: ObservationShareKind.TASK_REPORT,
      title: title,
      description: simulated ? '数字孪生观测演练报告' : '观测任务报告',
      content: lines.join('\n'),
      simulated: simulated
    };
  }

  static async share(context: common.UIAbilityContext,
    payload: ObservationSharePayload): Promise<ObservationShareResult> {
    try {
      const record: systemShare.SharedRecord = {
        utd: PLAIN_TEXT_UTD,
        title: payload.title,
        description: payload.description,
        content: payload.content
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      };
      await controller.show(context, options);
      return {
        succeeded: true,
        message: '系统分享面板已打开'
      };
    } catch (error) {
      return {
        succeeded: false,
        message: `系统分享不可用：${error}`
      };
    }
  }

  private static nightLabel(dayOffset: number): string {
    return dayOffset === 0 ? '今晚' : '明晚';
  }

  private static coordinateText(latitudeDegrees: number, longitudeDegrees: number): string {
    const latitude: string = `${Math.abs(latitudeDegrees).toFixed(3)}°${
      latitudeDegrees >= 0 ? 'N' : 'S'}`;
    const longitude: string = `${Math.abs(longitudeDegrees).toFixed(3)}°${
      longitudeDegrees >= 0 ? 'E' : 'W'}`;
    return `${latitude}, ${longitude}`;
  }

  private static astronomyWindowText(result: ObservationPlanningResult): string {
    if (result.bestWindow === undefined) return '本夜无可用窗口';
    return `${ObservationShareService.dateTime(result.bestWindow.startAtMs)} 至 ${
      ObservationShareService.dateTime(result.bestWindow.endAtMs)}`;
  }

  private static captureWindowText(result: ObservationPlanningResult): string {
    if (result.recommendedCaptureWindow === undefined) {
      return result.recommendedCaptureUnavailableReason.length > 0 ?
        result.recommendedCaptureUnavailableReason : '暂无推荐';
    }
    const prefix: string = result.recommendedCaptureWindow.astronomyOnly ? '仅按天文条件 · ' : '';
    return `${prefix}${ObservationShareService.dateTime(result.recommendedCaptureWindow.startAtMs)} 至 ${
      ObservationShareService.dateTime(result.recommendedCaptureWindow.endAtMs)}`;
  }

  private static weatherText(result: ObservationPlanningResult): string {
    if (result.weatherStatus === WeatherDataStatus.UNAVAILABLE ||
      result.weatherStatus === WeatherDataStatus.NOT_REQUESTED) {
      return '天气不可用，仅按天文条件';
    }
    const summary: PlanningWeatherSummary | undefined = result.planningWeatherSummary;
    if (summary === undefined) return '预报正在更新';
    const details: string[] = [];
    if (summary.averageCloudCoverPercent !== undefined) {
      details.push(`平均云量 ${Math.round(summary.averageCloudCoverPercent)}%`);
    }
    if (summary.maximumPrecipitationProbabilityPercent !== undefined) {
      details.push(`最高降水概率 ${Math.round(summary.maximumPrecipitationProbabilityPercent)}%`);
    }
    if (summary.maximumWindGustKph !== undefined) {
      details.push(`最大阵风 ${Math.round(summary.maximumWindGustKph)} km/h`);
    }
    return details.length > 0 ? details.join(' · ') : '预报数据不足';
  }

  private static recommendationText(recommendation: OutingRecommendation): string {
    if (recommendation === OutingRecommendation.GOOD) return '值得出行';
    if (recommendation === OutingRecommendation.CAUTION) return '谨慎出行';
    if (recommendation === OutingRecommendation.POOR) return '不建议拍摄';
    if (recommendation === OutingRecommendation.ASTRONOMY_ONLY) return '仅按天文条件判断';
    return '当前不可判断';
  }

  private static scoreText(score: number | undefined): string {
    return score === undefined ? '--' : `${Math.round(score)}`;
  }

  private static sessionKindText(kind: SessionKind): string {
    if (kind === SessionKind.OBSERVATION) return '仅观测';
    if (kind === SessionKind.SMART_LONG_EXPOSURE) return '智能长曝光';
    return '延时摄影';
  }

  private static sessionStatusText(status: SessionStatus): string {
    if (status === SessionStatus.PREPARING) return '准备中';
    if (status === SessionStatus.RUNNING) return '进行中';
    if (status === SessionStatus.WAITING_FOR_USER) return '等待人工继续';
    if (status === SessionStatus.INTERRUPTED) return '已中断';
    if (status === SessionStatus.SUCCEEDED) return '已完成';
    if (status === SessionStatus.FAILED) return '失败';
    return '已取消';
  }

  private static workflowStageText(stage: WorkflowStage): string {
    if (stage === WorkflowStage.SAFETY_CHECK) return '安全检查';
    if (stage === WorkflowStage.CAMERA_PREFLIGHT) return '相机预检';
    if (stage === WorkflowStage.GOTO) return '转向目标';
    if (stage === WorkflowStage.TRACKING) return '跟踪';
    if (stage === WorkflowStage.CAPTURE) return '曝光';
    if (stage === WorkflowStage.PLATE_SOLVE) return '板解析';
    if (stage === WorkflowStage.DRIFT_CORRECTION) return '漂移修正';
    if (stage === WorkflowStage.STACK) return '本地堆栈';
    if (stage === WorkflowStage.TIMELAPSE) return '延时视频';
    if (stage === WorkflowStage.CLOUD_ENHANCEMENT) return '云端增强';
    return '完成';
  }

  private static dateTime(timestampMs: number): string {
    if (timestampMs <= 0) return '--';
    const date: Date = new Date(timestampMs);
    return `${date.getFullYear()}-${ObservationShareService.pad2(date.getMonth() + 1)}-${
      ObservationShareService.pad2(date.getDate())} ${
      ObservationShareService.pad2(date.getHours())}:${ObservationShareService.pad2(date.getMinutes())}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}

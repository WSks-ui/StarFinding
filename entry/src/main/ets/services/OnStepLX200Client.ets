import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  ConnectionState,
  EquatorialFrame,
  MountState,
  MountTargetCoordinate,
  ObserverState,
  TrackingMode
} from '../models/DomainModels';
import { AstronomyService } from './AstronomyService';
import { EphemerisService } from './EphemerisService';

enum LX200ResponseMode {
  HASH_TERMINATED = 'hash',
  SINGLE_CHARACTER = 'single',
  NO_RESPONSE = 'none'
}

type CommandResolve = (response: string) => void;
type CommandReject = (reason: Error) => void;
export type MountStateListener = (state: MountState) => void;

class PendingCommand {
  command: string;
  responseMode: LX200ResponseMode;
  timeoutMs: number;
  resolve: CommandResolve;
  reject: CommandReject;

  constructor(command: string, responseMode: LX200ResponseMode, timeoutMs: number,
    resolve: CommandResolve, reject: CommandReject) {
    this.command = command;
    this.responseMode = responseMode;
    this.timeoutMs = timeoutMs;
    this.resolve = resolve;
    this.reject = reject;
  }
}

/**
 * OnStepX 的 LX200 TCP 客户端。所有命令严格串行，避免 OnStep 的无请求标识协议在并发时串包。
 * 默认连接树莓派 StarScope 局域网内的 OnStepX TCP 9999 端口。
 */
export class OnStepLX200Client {
  static readonly DEFAULT_HOST: string = '10.42.0.20';
  static readonly DEFAULT_PORT: number = 9999;
  // :hC# 会驱动两轴寻找原点开关；:hF# 只把当前位置声明为零位，绝不能用于自动回零按钮。
  static readonly HOME_SEARCH_COMMAND: string = ':hC#';
  // :Q# 只停止 GOTO/导向，不会关闭恒星时跟踪；软件急停必须同时发送 :Td#。
  static readonly EMERGENCY_STOP_COMMAND: string = ':Td#:Q#:Q#';
  static readonly COORDINATE_MODE_QUERY_COMMAND: string = ':GXEE#';
  static readonly MAX_TARGET_AGE_MS: number = 30000;
  static readonly MAX_OBSERVER_SYNC_AGE_MS: number = 120000;
  private tcpSocket: socket.TCPSocket | undefined = undefined;
  private commandQueue: PendingCommand[] = [];
  private activeCommand: PendingCommand | undefined = undefined;
  private receiveBuffer: string = '';
  private timeoutHandle: number = -1;
  private listeners: MountStateListener[] = [];
  private coordinateModeVerified: boolean = false;
  private coordinateModeResponse: string = '';
  private syncedObserver: ObserverState | undefined = undefined;
  private state: MountState = {
    connection: ConnectionState.DISCONNECTED,
    host: '',
    port: 9999,
    rightAscensionHours: 0.0,
    declinationDegrees: 0.0,
    trackingMode: TrackingMode.UNKNOWN,
    slewing: false,
    homed: false,
    parked: false,
    lastError: '',
    updatedAtMs: 0
  };

  getState(): MountState {
    return {
      connection: this.state.connection,
      host: this.state.host,
      port: this.state.port,
      rightAscensionHours: this.state.rightAscensionHours,
      declinationDegrees: this.state.declinationDegrees,
      trackingMode: this.state.trackingMode,
      slewing: this.state.slewing,
      homed: this.state.homed,
      parked: this.state.parked,
      lastError: this.state.lastError,
      updatedAtMs: this.state.updatedAtMs
    };
  }

  subscribe(listener: MountStateListener): void {
    this.listeners.push(listener);
    listener(this.getState());
  }

  unsubscribe(listener: MountStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  isConnected(): boolean {
    return this.state.connection === ConnectionState.CONNECTED;
  }

  isCoordinateModeCompatible(): boolean {
    return this.coordinateModeVerified;
  }

  getCoordinateModeResponse(): string {
    return this.coordinateModeResponse;
  }

  getSyncedObserver(): ObserverState | undefined {
    const observer: ObserverState | undefined = this.syncedObserver;
    if (observer === undefined) return undefined;
    return {
      latitudeDegrees: observer.latitudeDegrees,
      longitudeDegrees: observer.longitudeDegrees,
      elevationMeters: observer.elevationMeters,
      timestampMs: observer.timestampMs
    };
  }

  async connect(host: string = OnStepLX200Client.DEFAULT_HOST,
    port: number = OnStepLX200Client.DEFAULT_PORT, timeoutMs: number = 5000): Promise<void> {
    if (this.tcpSocket !== undefined) {
      await this.disconnect();
    }
    this.setConnectionState(ConnectionState.CONNECTING, '');
    this.state.host = host;
    this.state.port = port;
    const client: socket.TCPSocket = socket.constructTCPSocketInstance();
    this.tcpSocket = client;
    client.on('message', (info: socket.SocketMessageInfo) => {
      this.onSocketMessage(info.message);
    });
    client.on('close', () => {
      this.handleDisconnected('赤道仪连接已关闭');
    });
    client.on('error', (error: BusinessError) => {
      this.handleDisconnected(`赤道仪网络错误：${error.message}`);
    });

    try {
      await client.bind({ address: '0.0.0.0', family: 1, port: 0 });
      await client.connect({
        address: { address: host, family: 1, port: port },
        timeout: timeoutMs
      });
      await client.setExtraOptions({ keepAlive: true, TCPNoDelay: true });
      this.setConnectionState(ConnectionState.CONNECTED, '');
      this.coordinateModeVerified = false;
      this.coordinateModeResponse = '';
      this.syncedObserver = undefined;
      try {
        await this.verifyCoordinateMode();
      } catch (verificationError) {
        // 坐标模式查询失败不应切断状态读取和急停通道，但所有 GOTO/SYNC 会继续保持锁定。
        this.coordinateModeVerified = false;
        this.state.lastError = `无法确认 OnStepX 坐标模式：${verificationError}`;
        this.touchState();
      }
    } catch (error) {
      this.setConnectionState(ConnectionState.ERROR, `${error}`);
      try {
        await client.close();
      } catch (closeError) {
        // 首次连接失败时关闭也可能抛错；原始连接错误更有诊断价值，故不覆盖它。
      }
      this.tcpSocket = undefined;
      throw new Error(`无法连接 OnStepX ${host}:${port}：${error}`);
    }
  }

  async disconnect(): Promise<void> {
    const client: socket.TCPSocket | undefined = this.tcpSocket;
    this.tcpSocket = undefined;
    this.coordinateModeVerified = false;
    this.coordinateModeResponse = '';
    this.syncedObserver = undefined;
    this.rejectAllCommands('赤道仪连接已断开');
    if (client !== undefined) {
      client.off('message');
      client.off('close');
      client.off('error');
      try {
        await client.close();
      } catch (error) {
        // 重复断开或系统已释放 socket 时无需继续向 UI 抛错。
      }
    }
    this.setConnectionState(ConnectionState.DISCONNECTED, '');
  }

  async refreshState(): Promise<MountState> {
    const raText: string = await this.enqueue(':GR#', LX200ResponseMode.HASH_TERMINATED, 2500);
    const decText: string = await this.enqueue(':GD#', LX200ResponseMode.HASH_TERMINATED, 2500);
    const statusText: string = await this.enqueue(':GU#', LX200ResponseMode.HASH_TERMINATED, 2500);
    const ra: number | undefined = OnStepLX200Client.parseRightAscension(raText);
    const dec: number | undefined = OnStepLX200Client.parseDeclination(decText);
    if (ra !== undefined) {
      this.state.rightAscensionHours = ra;
    }
    if (dec !== undefined) {
      this.state.declinationDegrees = dec;
    }
    // OnStepX Status.command.cpp 明确定义：N=当前无 GOTO、h=正在回零、I=正在停放。
    // 状态串还会随配置增加字符，因此这里只判断固件中稳定的核心标志。
    this.state.slewing = !statusText.includes('N') || statusText.includes('h') || statusText.includes('I');
    this.state.parked = statusText.includes('P');
    this.state.homed = statusText.includes('H');
    if (statusText.includes('n')) {
      this.state.trackingMode = TrackingMode.STOPPED;
    } else if (statusText.includes('O')) {
      this.state.trackingMode = TrackingMode.SOLAR;
    } else if (statusText.includes('(')) {
      this.state.trackingMode = TrackingMode.LUNAR;
    } else {
      this.state.trackingMode = TrackingMode.SIDEREAL;
    }
    this.touchState();
    return this.getState();
  }

  async gotoRaDec(coordinate: MountTargetCoordinate): Promise<void> {
    this.validateMotionCoordinate(coordinate);
    const raAccepted: string = await this.enqueue(
      `:Sr${OnStepLX200Client.formatRightAscension(coordinate.raHours)}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (raAccepted !== '1') {
      throw new Error('OnStepX 拒绝赤经参数');
    }
    const decAccepted: string = await this.enqueue(
      `:Sd${OnStepLX200Client.formatDeclination(coordinate.decDegrees)}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (decAccepted !== '1') {
      throw new Error('OnStepX 拒绝赤纬参数');
    }
    const moveResult: string = await this.enqueue(':MS#', LX200ResponseMode.SINGLE_CHARACTER, 5000);
    if (moveResult !== '0') {
      throw new Error(`OnStepX 拒绝 GOTO，状态码 ${moveResult}`);
    }
    this.state.slewing = true;
    this.state.parked = false;
    this.touchState();
  }

  async syncRaDec(coordinate: MountTargetCoordinate): Promise<void> {
    this.validateMotionCoordinate(coordinate);
    const raAccepted: string = await this.enqueue(
      `:Sr${OnStepLX200Client.formatRightAscension(coordinate.raHours)}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 2500);
    const decAccepted: string = await this.enqueue(
      `:Sd${OnStepLX200Client.formatDeclination(coordinate.decDegrees)}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (raAccepted !== '1' || decAccepted !== '1') {
      throw new Error('OnStepX 拒绝同步坐标');
    }
    await this.enqueue(':CM#', LX200ResponseMode.HASH_TERMINATED, 3500);
    this.state.rightAscensionHours = coordinate.raHours;
    this.state.declinationDegrees = coordinate.decDegrees;
    this.touchState();
  }

  async startTracking(mode: TrackingMode = TrackingMode.SIDEREAL): Promise<void> {
    if (mode === TrackingMode.SOLAR) {
      await this.enqueue(':TS#', LX200ResponseMode.NO_RESPONSE, 1000);
    } else if (mode === TrackingMode.LUNAR) {
      await this.enqueue(':TL#', LX200ResponseMode.NO_RESPONSE, 1000);
    } else {
      await this.enqueue(':TQ#', LX200ResponseMode.NO_RESPONSE, 1000);
    }
    const result: string = await this.enqueue(':Te#', LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (result !== '1') {
      throw new Error('OnStepX 未能启动跟踪');
    }
    this.state.trackingMode = mode;
    this.touchState();
  }

  async stopTracking(): Promise<void> {
    const result: string = await this.enqueue(':Td#', LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (result !== '1') {
      throw new Error('OnStepX 未能停止跟踪');
    }
    this.state.trackingMode = TrackingMode.STOPPED;
    this.touchState();
  }

  async home(): Promise<void> {
    await this.enqueue(OnStepLX200Client.HOME_SEARCH_COMMAND, LX200ResponseMode.NO_RESPONSE, 1000);
    this.state.slewing = true;
    this.state.parked = false;
    this.touchState();
  }

  async park(): Promise<void> {
    await this.enqueue(':hP#', LX200ResponseMode.NO_RESPONSE, 1000);
    this.state.slewing = true;
    this.touchState();
  }

  /** 软件急停会抢占命令队列、关闭跟踪并双发停止运动；物理急停仍须独立切断电机电源。 */
  async abort(): Promise<void> {
    const client: socket.TCPSocket | undefined = this.tcpSocket;
    if (client === undefined || !this.isConnected()) {
      throw new Error('赤道仪未连接，无法确认软件急停');
    }
    // 急停不能排在状态轮询或 GOTO 后面。先拒绝当前及待发命令，再直接写入同一 TCP 通道。
    // :Td# 的单字符回包此时没有活动请求承接，会由 onSocketMessage 安全丢弃。
    this.rejectAllCommands('任务已被用户急停');
    try {
      await client.send({ data: OnStepLX200Client.EMERGENCY_STOP_COMMAND, encoding: 'UTF-8' });
    } catch (error) {
      this.state.lastError = `软件急停发送失败：${error}`;
      this.touchState();
      throw new Error(this.state.lastError);
    }
    this.state.slewing = false;
    this.state.trackingMode = TrackingMode.STOPPED;
    this.touchState();
  }

  async setObserver(observer: ObserverState, utcFromLocalOffsetHours: number): Promise<void> {
    const latitude: string = OnStepLX200Client.formatLatitude(observer.latitudeDegrees);
    // LX200 传统协议经度以西经为正，HarmonyOS 定位以东经为正，发送前需反号。
    const westLongitude: number = AstronomyService.normalizeSignedDegrees(-observer.longitudeDegrees);
    const longitude: string = OnStepLX200Client.formatLongitude(westLongitude);
    const latitudeResult: string = await this.enqueue(`:St${latitude}#`, LX200ResponseMode.SINGLE_CHARACTER, 2500);
    const longitudeResult: string = await this.enqueue(`:Sg${longitude}#`, LX200ResponseMode.SINGLE_CHARACTER, 2500);
    if (latitudeResult !== '1' || longitudeResult !== '1') {
      throw new Error('OnStepX 拒绝观测地点参数');
    }
    // JS getTimezoneOffset 与 OnStepX :SG 的定义一致：本地时间加该偏移得到 UTC。
    // 为了构造本地日期时间，需要反向从 UTC 减去此偏移。
    const localTimeMs: number = observer.timestampMs - utcFromLocalOffsetHours * 3600000.0;
    const localDate: Date = new Date(localTimeMs);
    const offset: string = OnStepLX200Client.formatTimezoneOffset(utcFromLocalOffsetHours);
    const timezoneResult: string = await this.enqueue(`:SG${offset}#`, LX200ResponseMode.SINGLE_CHARACTER, 2500);
    const timeResult: string = await this.enqueue(`:SL${OnStepLX200Client.pad2(localDate.getUTCHours())}:${OnStepLX200Client.pad2(localDate.getUTCMinutes())}:${OnStepLX200Client.pad2(localDate.getUTCSeconds())}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 2500);
    const dateResult: string = await this.enqueue(`:SC${OnStepLX200Client.pad2(localDate.getUTCMonth() + 1)}/${OnStepLX200Client.pad2(localDate.getUTCDate())}/${OnStepLX200Client.pad2(localDate.getUTCFullYear() % 100)}#`,
      LX200ResponseMode.SINGLE_CHARACTER, 3500);
    if (timezoneResult !== '1' || timeResult !== '1' || dateResult !== '1') {
      throw new Error('OnStepX 拒绝时区、时间或日期参数');
    }
    this.syncedObserver = {
      latitudeDegrees: observer.latitudeDegrees,
      longitudeDegrees: observer.longitudeDegrees,
      elevationMeters: observer.elevationMeters,
      timestampMs: observer.timestampMs
    };
  }

  /**
   * 固件 MOUNT_COORDS=TOPOCENTRIC 时，OnStepX :GXEE# 固定返回 1。
   * Mount.command.cpp 对 GXEE 设置 supressFrame=true，因此该回包没有 # 终止符。
   */
  async verifyCoordinateMode(): Promise<boolean> {
    const response: string = await this.enqueue(
      OnStepLX200Client.COORDINATE_MODE_QUERY_COMMAND, LX200ResponseMode.SINGLE_CHARACTER, 2500);
    this.coordinateModeResponse = response.trim();
    this.coordinateModeVerified = this.coordinateModeResponse === '1';
    if (!this.coordinateModeVerified) {
      this.state.lastError = `OnStepX 坐标模式返回 ${this.coordinateModeResponse || '空值'}，需要 TOPOCENTRIC(1)`;
      this.touchState();
    }
    return this.coordinateModeVerified;
  }

  async rawCommand(command: string, expectsHashTerminator: boolean = true,
    timeoutMs: number = 2500): Promise<string> {
    if (!command.startsWith(':') || !command.endsWith('#')) {
      throw new Error('LX200 命令必须以冒号开始并以 # 结束');
    }
    if (OnStepLX200Client.isProtectedMotionCommand(command)) {
      throw new Error('运动和坐标同步命令必须通过带站心坐标校验的专用接口发送');
    }
    return this.enqueue(command, expectsHashTerminator ? LX200ResponseMode.HASH_TERMINATED :
      LX200ResponseMode.SINGLE_CHARACTER, timeoutMs);
  }

  private enqueue(command: string, responseMode: LX200ResponseMode, timeoutMs: number): Promise<string> {
    if (!this.isConnected() || this.tcpSocket === undefined) {
      return Promise.reject(new Error('赤道仪尚未连接'));
    }
    return new Promise<string>((resolve: CommandResolve, reject: CommandReject) => {
      this.commandQueue.push(new PendingCommand(command, responseMode, timeoutMs, resolve, reject));
      this.processNextCommand();
    });
  }

  private processNextCommand(): void {
    if (this.activeCommand !== undefined || this.commandQueue.length === 0) {
      return;
    }
    const client: socket.TCPSocket | undefined = this.tcpSocket;
    if (client === undefined || !this.isConnected()) {
      this.rejectAllCommands('赤道仪连接不可用');
      return;
    }
    this.activeCommand = this.commandQueue.shift();
    const active: PendingCommand | undefined = this.activeCommand;
    if (active === undefined) {
      return;
    }
    this.receiveBuffer = '';
    client.send({ data: active.command, encoding: 'UTF-8' }).then(() => {
      if (active.responseMode === LX200ResponseMode.NO_RESPONSE) {
        this.completeActiveCommand('');
        return;
      }
      this.timeoutHandle = setTimeout(() => {
        this.failActiveCommand(`LX200 命令超时：${active.command}`);
      }, active.timeoutMs);
    }).catch((error: BusinessError) => {
      this.failActiveCommand(`LX200 发送失败：${error.message}`);
    });
  }

  private onSocketMessage(buffer: ArrayBuffer): void {
    const bytes: Uint8Array = new Uint8Array(buffer);
    let chunk: string = '';
    for (let index: number = 0; index < bytes.length; index++) {
      chunk += String.fromCharCode(bytes[index]);
    }
    this.receiveBuffer += chunk;
    const active: PendingCommand | undefined = this.activeCommand;
    if (active === undefined) {
      // 未绑定请求的数据可能是上次无响应命令的延迟回包，丢弃以保护后续命令边界。
      this.receiveBuffer = '';
      return;
    }
    if (active.responseMode === LX200ResponseMode.SINGLE_CHARACTER && this.receiveBuffer.length > 0) {
      this.completeActiveCommand(this.receiveBuffer.substring(0, 1));
      return;
    }
    const terminatorIndex: number = this.receiveBuffer.indexOf('#');
    if (active.responseMode === LX200ResponseMode.HASH_TERMINATED && terminatorIndex >= 0) {
      this.completeActiveCommand(this.receiveBuffer.substring(0, terminatorIndex));
    }
  }

  private completeActiveCommand(response: string): void {
    if (this.timeoutHandle >= 0) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = -1;
    }
    const completed: PendingCommand | undefined = this.activeCommand;
    this.activeCommand = undefined;
    this.receiveBuffer = '';
    if (completed !== undefined) {
      completed.resolve(response);
    }
    this.processNextCommand();
  }

  private failActiveCommand(message: string): void {
    if (this.timeoutHandle >= 0) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = -1;
    }
    const failed: PendingCommand | undefined = this.activeCommand;
    this.activeCommand = undefined;
    this.receiveBuffer = '';
    if (failed !== undefined) {
      failed.reject(new Error(message));
    }
    this.state.lastError = message;
    this.touchState();
    this.processNextCommand();
  }

  private rejectQueuedCommands(message: string): void {
    while (this.commandQueue.length > 0) {
      const command: PendingCommand | undefined = this.commandQueue.shift();
      if (command !== undefined) {
        command.reject(new Error(message));
      }
    }
  }

  private rejectAllCommands(message: string): void {
    if (this.timeoutHandle >= 0) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = -1;
    }
    if (this.activeCommand !== undefined) {
      this.activeCommand.reject(new Error(message));
      this.activeCommand = undefined;
    }
    this.rejectQueuedCommands(message);
    this.receiveBuffer = '';
  }

  private handleDisconnected(message: string): void {
    this.tcpSocket = undefined;
    this.coordinateModeVerified = false;
    this.coordinateModeResponse = '';
    this.syncedObserver = undefined;
    this.rejectAllCommands(message);
    this.setConnectionState(ConnectionState.ERROR, message);
  }

  private setConnectionState(connection: ConnectionState, error: string): void {
    this.state.connection = connection;
    this.state.lastError = error;
    this.touchState();
  }

  private touchState(): void {
    this.state.updatedAtMs = Date.now();
    const snapshot: MountState = this.getState();
    for (let index: number = 0; index < this.listeners.length; index++) {
      this.listeners[index](snapshot);
    }
  }

  private validateMotionCoordinate(coordinate: MountTargetCoordinate): void {
    if (!this.coordinateModeVerified) {
      throw new Error('OnStepX 未确认 MOUNT_COORDS=TOPOCENTRIC，GOTO/SYNC 已锁定');
    }
    const observer: ObserverState | undefined = this.syncedObserver;
    if (observer === undefined) {
      throw new Error('尚未把当前地点和真实时间同步到 OnStepX');
    }
    const nowMs: number = Date.now();
    if (Math.abs(nowMs - observer.timestampMs) > OnStepLX200Client.MAX_OBSERVER_SYNC_AGE_MS) {
      throw new Error('OnStepX 地点时间同步已过期，请重新同步后再运动');
    }
    OnStepLX200Client.validateMountTargetCoordinate(
      coordinate, EphemerisService.observerKey(observer), nowMs);
  }

  static validateMountTargetCoordinate(coordinate: MountTargetCoordinate,
    expectedObserverKey: string, nowMs: number): void {
    EphemerisService.requireMountCoordinate(coordinate);
    if (coordinate.frame !== EquatorialFrame.TOPOCENTRIC_OF_DATE ||
      coordinate.raHours < 0.0 || coordinate.raHours >= 24.0 ||
      coordinate.decDegrees < -90.0 || coordinate.decDegrees > 90.0) {
      throw new Error('赤经或赤纬超出有效范围');
    }
    if (coordinate.targetId === 'solar-sun') {
      throw new Error('太阳目标永久禁止普通 GOTO/SYNC');
    }
    if (coordinate.observerKey !== expectedObserverKey) {
      throw new Error('目标坐标的观测地点与已同步地点不一致');
    }
    if (!Number.isFinite(nowMs) ||
      Math.abs(nowMs - coordinate.calculatedAtMs) > OnStepLX200Client.MAX_TARGET_AGE_MS) {
      throw new Error('站心目标坐标已过期，必须按真实时间重新计算');
    }
  }

  private static isProtectedMotionCommand(command: string): boolean {
    return command.startsWith(':Sr') || command.startsWith(':Sd') || command === ':MS#' ||
      command === ':CM#' || command === ':CS#';
  }

  static parseRightAscension(text: string): number | undefined {
    const normalized: string = text.replace('*', ':');
    const parts: string[] = normalized.split(':');
    if (parts.length < 2) {
      return undefined;
    }
    const hours: number = Number(parts[0]);
    const minutes: number = Number(parts[1]);
    const seconds: number = parts.length > 2 ? Number(parts[2]) : 0.0;
    if (!Number.isFinite(hours) || !Number.isFinite(minutes) || !Number.isFinite(seconds)) {
      return undefined;
    }
    return AstronomyService.normalizeHours(hours + minutes / 60.0 + seconds / 3600.0);
  }

  static parseDeclination(text: string): number | undefined {
    const normalized: string = text.replace('*', ':').replace('°', ':');
    const sign: number = normalized.startsWith('-') ? -1.0 : 1.0;
    const unsigned: string = normalized.replace('+', '').replace('-', '');
    const parts: string[] = unsigned.split(':');
    if (parts.length < 2) {
      return undefined;
    }
    const degrees: number = Number(parts[0]);
    const minutes: number = Number(parts[1]);
    const seconds: number = parts.length > 2 ? Number(parts[2]) : 0.0;
    if (!Number.isFinite(degrees) || !Number.isFinite(minutes) || !Number.isFinite(seconds)) {
      return undefined;
    }
    return sign * (degrees + minutes / 60.0 + seconds / 3600.0);
  }

  static formatRightAscension(raHours: number): string {
    const normalized: number = AstronomyService.normalizeHours(raHours);
    const totalSeconds: number = Math.round(normalized * 3600.0) % 86400;
    const hours: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    return `${OnStepLX200Client.pad2(hours)}:${OnStepLX200Client.pad2(minutes)}:${OnStepLX200Client.pad2(seconds)}`;
  }

  static formatDeclination(decDegrees: number): string {
    const sign: string = decDegrees >= 0.0 ? '+' : '-';
    const totalSeconds: number = Math.round(Math.abs(decDegrees) * 3600.0);
    const degrees: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    return `${sign}${OnStepLX200Client.pad2(degrees)}*${OnStepLX200Client.pad2(minutes)}:${OnStepLX200Client.pad2(seconds)}`;
  }

  static formatTimezoneOffset(offsetHours: number): string {
    if (!Number.isFinite(offsetHours) || offsetHours < -13.75 || offsetHours > 12.0) {
      throw new Error('OnStepX 时区偏移必须在 -13:45 到 +12:00 之间');
    }
    const sign: string = offsetHours >= 0 ? '+' : '-';
    const totalMinutes: number = Math.round(Math.abs(offsetHours) * 60.0);
    const hours: number = Math.floor(totalMinutes / 60);
    const minutes: number = totalMinutes % 60;
    return `${sign}${OnStepLX200Client.pad2(hours)}:${OnStepLX200Client.pad2(minutes)}`;
  }

  private static formatLatitude(latitude: number): string {
    const sign: string = latitude >= 0.0 ? '+' : '-';
    const totalMinutes: number = Math.round(Math.abs(latitude) * 60.0);
    return `${sign}${OnStepLX200Client.pad2(Math.floor(totalMinutes / 60))}*${OnStepLX200Client.pad2(totalMinutes % 60)}`;
  }

  private static formatLongitude(longitude: number): string {
    const sign: string = longitude >= 0.0 ? '+' : '-';
    const totalMinutes: number = Math.round(Math.abs(longitude) * 60.0);
    return `${sign}${OnStepLX200Client.pad3(Math.floor(totalMinutes / 60))}*${OnStepLX200Client.pad2(totalMinutes % 60)}`;
  }

  private static pad2(value: number): string {
    return Math.floor(value).toString().padStart(2, '0');
  }

  private static pad3(value: number): string {
    return Math.floor(value).toString().padStart(3, '0');
  }
}

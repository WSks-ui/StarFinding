import {
  DevicePairingConfiguration,
  DevicePairingFailureReason,
  DevicePairingPayload,
  DevicePairingPreview,
  DevicePairingValidationResult
} from '../models/DevicePairingModels';
import { DeviceConnectionSettings } from './DeviceConnectionSettingsStore';

export const STAR_SCOPE_PAIRING_SCHEMA: string = 'starscope-device-v1';
export const STAR_SCOPE_PAIRING_VERSION: string = '1';
export const STAR_SCOPE_PAIRING_PREFIX: string = 'starscope://pair?';
export const STAR_SCOPE_PAIRING_MAX_CODE_LENGTH: number = 8192;
const BASE64URL_ALPHABET: string =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const SHA256_INITIAL_STATE: number[] = [
  0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
  0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
];
const SHA256_ROUND_CONSTANTS: number[] = [
  0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
  0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
  0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
  0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
  0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
  0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
  0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
  0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
  0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
  0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
  0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
  0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
  0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
  0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
  0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
  0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
];

/**
 * StarScope 设备码的纯解析与安全校验服务。
 *
 * 本服务没有 Preferences、Socket、HTTP 或硬件客户端依赖。校验成功只会返回一个
 * 不含 token 的预览；是否持久化必须由页面在用户明确确认后单独执行。
 */
export class DevicePairingService {
  static validateCode(value: string, current: DeviceConnectionSettings,
    nowMs: number): DevicePairingValidationResult {
    const rawValue: string = value.trim();
    if (rawValue.length === 0) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.EMPTY_VALUE, '二维码内容为空');
    }
    if (rawValue.length > STAR_SCOPE_PAIRING_MAX_CODE_LENGTH) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.CODE_TOO_LARGE, '设备码内容过长');
    }
    if (!rawValue.startsWith(STAR_SCOPE_PAIRING_PREFIX)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_SCHEME, '这不是 StarScope 设备码');
    }

    const query: string = rawValue.substring(STAR_SCOPE_PAIRING_PREFIX.length);
    const queryResult: PairingQueryResult = DevicePairingService.parseQuery(query);
    if (!queryResult.success) {
      return DevicePairingService.failure(queryResult.reason, queryResult.message);
    }
    if (queryResult.version !== STAR_SCOPE_PAIRING_VERSION) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.UNSUPPORTED_VERSION, '设备码版本不受支持');
    }

    const decodedJson: StringResult = DevicePairingService.decodePayload(queryResult.data);
    if (!decodedJson.success) {
      return DevicePairingService.failure(decodedJson.reason, decodedJson.message);
    }

    let payload: DevicePairingPayload;
    try {
      payload = JSON.parse(decodedJson.value) as DevicePairingPayload;
    } catch (error) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_JSON, '设备码数据不是有效 JSON');
    }
    return DevicePairingService.validatePayload(payload, current, nowMs);
  }

  /**
   * 生成校验和时必须使用这一固定字段顺序，并排除 checksum 字段。
   * Linux 网关或设备码生成工具若改变顺序，校验将按设计失败。
   */
  static canonicalPayloadJson(payload: DevicePairingPayload): string {
    let json: string = '{';
    json += `"schema":${JSON.stringify(payload.schema)}`;
    json += `,"deviceId":${JSON.stringify(payload.deviceId)}`;
    json += `,"deviceName":${JSON.stringify(payload.deviceName)}`;
    json += `,"mountHost":${JSON.stringify(payload.mountHost)}`;
    json += `,"mountPort":${payload.mountPort.toString()}`;
    json += `,"gatewayHost":${JSON.stringify(payload.gatewayHost)}`;
    json += `,"gatewayPort":${payload.gatewayPort.toString()}`;
    json += `,"issuedAtMs":${payload.issuedAtMs.toString()}`;
    if (payload.expiresAtMs !== undefined) {
      json += `,"expiresAtMs":${payload.expiresAtMs.toString()}`;
    }
    if (payload.token !== undefined) {
      json += `,"token":${JSON.stringify(payload.token)}`;
    }
    json += '}';
    return json;
  }

  static checksumForPayload(payload: DevicePairingPayload): string {
    const bytes: Uint8Array =
      DevicePairingService.utf8Encode(DevicePairingService.canonicalPayloadJson(payload));
    return DevicePairingService.sha256(bytes);
  }

  /**
   * 测试和设备码生成工具使用的编码入口。业务扫码流程不会调用该方法。
   */
  static encodePayload(payload: DevicePairingPayload): string {
    const json: string = JSON.stringify(payload);
    const bytes: Uint8Array = DevicePairingService.utf8Encode(json);
    const data: string = DevicePairingService.base64UrlEncode(bytes);
    return `${STAR_SCOPE_PAIRING_PREFIX}v=${STAR_SCOPE_PAIRING_VERSION}&data=${data}`;
  }

  private static validatePayload(payload: DevicePairingPayload, current: DeviceConnectionSettings,
    nowMs: number): DevicePairingValidationResult {
    if (payload.schema !== STAR_SCOPE_PAIRING_SCHEMA) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_SCHEMA, '设备码类型不受支持');
    }
    const deviceId: string = typeof payload.deviceId === 'string' ? payload.deviceId.trim() : '';
    if (deviceId.length < 1 || deviceId.length > 64 ||
      !/^[A-Za-z0-9._-]+$/.test(deviceId)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_DEVICE_ID, '设备标识无效');
    }
    const deviceName: string = typeof payload.deviceName === 'string' ? payload.deviceName.trim() : '';
    if (deviceName.length < 1 || deviceName.length > 64 ||
      DevicePairingService.containsControlCharacter(deviceName)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_DEVICE_NAME, '设备名称无效');
    }

    const mountHostResult: StringResult = DevicePairingService.validatePrivateIpv4(
      payload.mountHost, '赤道仪地址');
    if (!mountHostResult.success) {
      return DevicePairingService.failure(mountHostResult.reason, mountHostResult.message);
    }
    const gatewayHostResult: StringResult = DevicePairingService.validatePrivateIpv4(
      payload.gatewayHost, '网关地址');
    if (!gatewayHostResult.success) {
      return DevicePairingService.failure(gatewayHostResult.reason, gatewayHostResult.message);
    }
    if (!DevicePairingService.validPort(payload.mountPort) ||
      !DevicePairingService.validPort(payload.gatewayPort)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_PORT, '设备码端口必须在 1 到 65535 之间');
    }
    if (!Number.isSafeInteger(payload.issuedAtMs) || payload.issuedAtMs <= 0) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_TIME, '设备码签发时间无效');
    }
    const expiresAtMs: number = payload.expiresAtMs === undefined ? 0 : payload.expiresAtMs;
    if (payload.expiresAtMs !== undefined &&
      (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= payload.issuedAtMs)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_TIME, '设备码有效期无效');
    }
    if (expiresAtMs > 0 && nowMs > expiresAtMs) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.EXPIRED, '设备码已过期，请重新生成');
    }
    if (payload.token !== undefined &&
      (typeof payload.token !== 'string' || payload.token.length < 1 ||
        payload.token.length > 512 || DevicePairingService.containsControlCharacter(payload.token))) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_TOKEN, '设备码令牌格式无效');
    }
    if (typeof payload.checksum !== 'string' || !/^[A-Fa-f0-9]{64}$/.test(payload.checksum)) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_CHECKSUM, '设备码校验和格式无效');
    }
    const expectedChecksum: string = DevicePairingService.checksumForPayload(payload);
    if (expectedChecksum !== payload.checksum.toUpperCase()) {
      return DevicePairingService.failure(
        DevicePairingFailureReason.INVALID_CHECKSUM, '设备码校验失败，配置可能已被修改');
    }

    const configuration: DevicePairingConfiguration = new DevicePairingConfiguration(
      mountHostResult.value, payload.mountPort, gatewayHostResult.value, payload.gatewayPort);
    const mountChanged: boolean = current.mountHost !== configuration.mountHost ||
      current.mountPort !== configuration.mountPort;
    const gatewayChanged: boolean = current.gatewayHost !== configuration.gatewayHost ||
      current.gatewayPort !== configuration.gatewayPort;
    const preview: DevicePairingPreview = new DevicePairingPreview(
      deviceId,
      deviceName,
      configuration,
      mountChanged,
      gatewayChanged,
      payload.issuedAtMs,
      expiresAtMs,
      payload.token !== undefined);
    return new DevicePairingValidationResult(
      true, DevicePairingFailureReason.NONE, '设备码校验通过，请确认后保存', preview);
  }

  private static parseQuery(query: string): PairingQueryResult {
    if (query.length === 0 || query.indexOf('#') >= 0) {
      return new PairingQueryResult(false, '', '',
        DevicePairingFailureReason.INVALID_QUERY, '设备码参数无效');
    }
    const parts: string[] = query.split('&');
    let version: string = '';
    let data: string = '';
    for (let index: number = 0; index < parts.length; index++) {
      const part: string = parts[index];
      const separator: number = part.indexOf('=');
      if (separator <= 0) {
        return new PairingQueryResult(false, '', '',
          DevicePairingFailureReason.INVALID_QUERY, '设备码参数格式无效');
      }
      const key: string = part.substring(0, separator);
      const parameterValue: string = part.substring(separator + 1);
      if (key === 'v') {
        if (version.length > 0) {
          return new PairingQueryResult(false, '', '',
            DevicePairingFailureReason.INVALID_QUERY, '设备码版本参数重复');
        }
        version = parameterValue;
      } else if (key === 'data') {
        if (data.length > 0) {
          return new PairingQueryResult(false, '', '',
            DevicePairingFailureReason.INVALID_QUERY, '设备码数据参数重复');
        }
        data = parameterValue;
      } else {
        return new PairingQueryResult(false, '', '',
          DevicePairingFailureReason.INVALID_QUERY, '设备码包含未知参数');
      }
    }
    if (version.length === 0 || data.length === 0) {
      return new PairingQueryResult(false, '', '',
        DevicePairingFailureReason.INVALID_QUERY, '设备码缺少版本或数据');
    }
    return new PairingQueryResult(
      true, version, data, DevicePairingFailureReason.NONE, '');
  }

  private static decodePayload(data: string): StringResult {
    if (!/^[A-Za-z0-9_-]+={0,2}$/.test(data)) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_BASE64URL, '设备码 Base64URL 数据无效');
    }
    let bytes: Uint8Array;
    try {
      bytes = DevicePairingService.base64UrlDecode(data);
    } catch (error) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_BASE64URL, '设备码 Base64URL 解码失败');
    }
    try {
      return new StringResult(true, DevicePairingService.utf8Decode(bytes),
        DevicePairingFailureReason.NONE, '');
    } catch (error) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_UTF8, '设备码不是有效 UTF-8 文本');
    }
  }

  private static validatePrivateIpv4(value: string, label: string): StringResult {
    if (typeof value !== 'string') {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_HOST, `${label}必须是私有局域网 IPv4`);
    }
    const host: string = value.trim();
    if (host.length < 7 || host.length > 15 ||
      host.indexOf('/') >= 0 || host.indexOf(':') >= 0 ||
      host.indexOf('?') >= 0 || host.indexOf('#') >= 0) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_HOST, `${label}必须是私有局域网 IPv4`);
    }
    const segments: string[] = host.split('.');
    if (segments.length !== 4) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_HOST, `${label}必须是私有局域网 IPv4`);
    }
    const octets: number[] = [];
    for (let index: number = 0; index < segments.length; index++) {
      const segment: string = segments[index];
      if (!/^[0-9]{1,3}$/.test(segment)) {
        return new StringResult(false, '',
          DevicePairingFailureReason.INVALID_HOST, `${label}包含无效字符`);
      }
      const octet: number = Number(segment);
      if (!Number.isInteger(octet) || octet < 0 || octet > 255) {
        return new StringResult(false, '',
          DevicePairingFailureReason.INVALID_HOST, `${label}超出 IPv4 范围`);
      }
      octets.push(octet);
    }
    const privateAddress: boolean = octets[0] === 10 ||
      (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] === 192 && octets[1] === 168);
    if (!privateAddress) {
      return new StringResult(false, '',
        DevicePairingFailureReason.INVALID_HOST, `${label}不是私有局域网地址`);
    }
    return new StringResult(true,
      `${octets[0]}.${octets[1]}.${octets[2]}.${octets[3]}`,
      DevicePairingFailureReason.NONE, '');
  }

  private static validPort(value: number): boolean {
    return Number.isInteger(value) && value >= 1 && value <= 65535;
  }

  private static containsControlCharacter(value: string): boolean {
    return /[\u0000-\u001F\u007F]/.test(value);
  }

  /**
   * 设备码使用无换行、无填充的 RFC 4648 Base64URL。这里采用纯 ArkTS 实现，
   * 避免桌面 Hypium 运行器与真机 Base64Helper 行为不一致，同时保持完全离线。
   */
  private static base64UrlEncode(bytes: Uint8Array): string {
    let result: string = '';
    for (let index: number = 0; index < bytes.length; index += 3) {
      const first: number = bytes[index];
      const secondAvailable: boolean = index + 1 < bytes.length;
      const thirdAvailable: boolean = index + 2 < bytes.length;
      const second: number = secondAvailable ? bytes[index + 1] : 0;
      const third: number = thirdAvailable ? bytes[index + 2] : 0;
      result += BASE64URL_ALPHABET.charAt(first >> 2);
      result += BASE64URL_ALPHABET.charAt(((first & 3) << 4) | (second >> 4));
      if (secondAvailable) {
        result += BASE64URL_ALPHABET.charAt(((second & 15) << 2) | (third >> 6));
      }
      if (thirdAvailable) {
        result += BASE64URL_ALPHABET.charAt(third & 63);
      }
    }
    return result;
  }

  private static base64UrlDecode(value: string): Uint8Array {
    let data: string = value;
    while (data.endsWith('=')) {
      data = data.substring(0, data.length - 1);
    }
    if (data.length === 0 || data.length % 4 === 1) {
      throw new Error('Base64URL 长度无效');
    }
    const outputLength: number = Math.floor(data.length * 6 / 8);
    const output: Uint8Array = new Uint8Array(outputLength);
    let outputIndex: number = 0;
    for (let index: number = 0; index < data.length; index += 4) {
      const first: number = DevicePairingService.base64UrlValue(data.charAt(index));
      const second: number = DevicePairingService.base64UrlValue(data.charAt(index + 1));
      const thirdAvailable: boolean = index + 2 < data.length;
      const fourthAvailable: boolean = index + 3 < data.length;
      const third: number = thirdAvailable ?
        DevicePairingService.base64UrlValue(data.charAt(index + 2)) : 0;
      const fourth: number = fourthAvailable ?
        DevicePairingService.base64UrlValue(data.charAt(index + 3)) : 0;
      if (outputIndex < output.length) {
        output[outputIndex] = (first << 2) | (second >> 4);
        outputIndex++;
      }
      if (thirdAvailable && outputIndex < output.length) {
        output[outputIndex] = ((second & 15) << 4) | (third >> 2);
        outputIndex++;
      }
      if (fourthAvailable && outputIndex < output.length) {
        output[outputIndex] = ((third & 3) << 6) | fourth;
        outputIndex++;
      }
    }
    return output;
  }

  private static base64UrlValue(character: string): number {
    const value: number = BASE64URL_ALPHABET.indexOf(character);
    if (value < 0) {
      throw new Error('Base64URL 字符无效');
    }
    return value;
  }

  /**
   * 纯 ArkTS UTF-8 编解码用于设备码协议。除真机外，桌面 Hypium 运行器对部分
   * 系统 util 实现只提供空桩；协议核心若依赖空桩，会造成测试通过情况与真机不一致。
   */
  private static utf8Encode(value: string): Uint8Array {
    const bytes: number[] = [];
    for (let index: number = 0; index < value.length; index++) {
      let codePoint: number = value.charCodeAt(index);
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
        if (index + 1 >= value.length) {
          throw new Error('UTF-16 高代理项缺少配对');
        }
        const low: number = value.charCodeAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
          throw new Error('UTF-16 代理项无效');
        }
        codePoint = 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00);
        index++;
      } else if (codePoint >= 0xDC00 && codePoint <= 0xDFFF) {
        throw new Error('UTF-16 低代理项缺少配对');
      }

      if (codePoint <= 0x7F) {
        bytes.push(codePoint);
      } else if (codePoint <= 0x7FF) {
        bytes.push(0xC0 | (codePoint >> 6));
        bytes.push(0x80 | (codePoint & 0x3F));
      } else if (codePoint <= 0xFFFF) {
        bytes.push(0xE0 | (codePoint >> 12));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
        bytes.push(0x80 | (codePoint & 0x3F));
      } else {
        bytes.push(0xF0 | (codePoint >> 18));
        bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
        bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
        bytes.push(0x80 | (codePoint & 0x3F));
      }
    }
    const result: Uint8Array = new Uint8Array(bytes.length);
    for (let index: number = 0; index < bytes.length; index++) {
      result[index] = bytes[index];
    }
    return result;
  }

  private static utf8Decode(bytes: Uint8Array): string {
    let result: string = '';
    let index: number = 0;
    while (index < bytes.length) {
      const first: number = bytes[index];
      let codePoint: number = 0;
      let width: number = 0;
      if (first <= 0x7F) {
        codePoint = first;
        width = 1;
      } else if (first >= 0xC2 && first <= 0xDF) {
        DevicePairingService.requireUtf8Continuation(bytes, index, 1);
        codePoint = ((first & 0x1F) << 6) | (bytes[index + 1] & 0x3F);
        width = 2;
      } else if (first >= 0xE0 && first <= 0xEF) {
        DevicePairingService.requireUtf8Continuation(bytes, index, 2);
        const second: number = bytes[index + 1];
        if ((first === 0xE0 && second < 0xA0) ||
          (first === 0xED && second > 0x9F)) {
          throw new Error('UTF-8 三字节序列无效');
        }
        codePoint = ((first & 0x0F) << 12) |
          ((second & 0x3F) << 6) |
          (bytes[index + 2] & 0x3F);
        width = 3;
      } else if (first >= 0xF0 && first <= 0xF4) {
        DevicePairingService.requireUtf8Continuation(bytes, index, 3);
        const second: number = bytes[index + 1];
        if ((first === 0xF0 && second < 0x90) ||
          (first === 0xF4 && second > 0x8F)) {
          throw new Error('UTF-8 四字节序列无效');
        }
        codePoint = ((first & 0x07) << 18) |
          ((second & 0x3F) << 12) |
          ((bytes[index + 2] & 0x3F) << 6) |
          (bytes[index + 3] & 0x3F);
        width = 4;
      } else {
        throw new Error('UTF-8 起始字节无效');
      }

      if (codePoint <= 0xFFFF) {
        result += String.fromCharCode(codePoint);
      } else {
        const adjusted: number = codePoint - 0x10000;
        result += String.fromCharCode(0xD800 + (adjusted >> 10));
        result += String.fromCharCode(0xDC00 + (adjusted & 0x3FF));
      }
      index += width;
    }
    return result;
  }

  private static requireUtf8Continuation(bytes: Uint8Array,
    start: number, count: number): void {
    if (start + count >= bytes.length) {
      throw new Error('UTF-8 序列被截断');
    }
    for (let offset: number = 1; offset <= count; offset++) {
      if ((bytes[start + offset] & 0xC0) !== 0x80) {
        throw new Error('UTF-8 连续字节无效');
      }
    }
  }

  /**
   * 纯 ArkTS SHA-256。设备码最大 8 KiB，使用同步计算不会影响 UI，同时能让桌面
   * Hypium 与真机执行完全相同的安全校验，避免系统加密模块空桩造成假失败。
   */
  private static sha256(bytes: Uint8Array): string {
    const bitLength: number = bytes.length * 8;
    const paddedLength: number = Math.ceil((bytes.length + 9) / 64) * 64;
    const padded: Uint8Array = new Uint8Array(paddedLength);
    padded.set(bytes);
    padded[bytes.length] = 0x80;
    const highLength: number = Math.floor(bitLength / 0x100000000);
    const lowLength: number = bitLength >>> 0;
    const lengthOffset: number = paddedLength - 8;
    padded[lengthOffset] = (highLength >>> 24) & 0xFF;
    padded[lengthOffset + 1] = (highLength >>> 16) & 0xFF;
    padded[lengthOffset + 2] = (highLength >>> 8) & 0xFF;
    padded[lengthOffset + 3] = highLength & 0xFF;
    padded[lengthOffset + 4] = (lowLength >>> 24) & 0xFF;
    padded[lengthOffset + 5] = (lowLength >>> 16) & 0xFF;
    padded[lengthOffset + 6] = (lowLength >>> 8) & 0xFF;
    padded[lengthOffset + 7] = lowLength & 0xFF;

    const state: Uint32Array = new Uint32Array(8);
    for (let index: number = 0; index < SHA256_INITIAL_STATE.length; index++) {
      state[index] = SHA256_INITIAL_STATE[index];
    }
    const schedule: Uint32Array = new Uint32Array(64);
    for (let blockOffset: number = 0; blockOffset < padded.length; blockOffset += 64) {
      for (let index: number = 0; index < 16; index++) {
        const offset: number = blockOffset + index * 4;
        schedule[index] = ((padded[offset] << 24) |
          (padded[offset + 1] << 16) |
          (padded[offset + 2] << 8) |
          padded[offset + 3]) >>> 0;
      }
      for (let index: number = 16; index < 64; index++) {
        const previous15: number = schedule[index - 15];
        const previous2: number = schedule[index - 2];
        const smallSigma0: number =
          (DevicePairingService.rotateRight(previous15, 7) ^
            DevicePairingService.rotateRight(previous15, 18) ^
            (previous15 >>> 3)) >>> 0;
        const smallSigma1: number =
          (DevicePairingService.rotateRight(previous2, 17) ^
            DevicePairingService.rotateRight(previous2, 19) ^
            (previous2 >>> 10)) >>> 0;
        schedule[index] =
          (schedule[index - 16] + smallSigma0 +
            schedule[index - 7] + smallSigma1) >>> 0;
      }

      let a: number = state[0];
      let b: number = state[1];
      let c: number = state[2];
      let d: number = state[3];
      let e: number = state[4];
      let f: number = state[5];
      let g: number = state[6];
      let h: number = state[7];
      for (let index: number = 0; index < 64; index++) {
        const bigSigma1: number =
          (DevicePairingService.rotateRight(e, 6) ^
            DevicePairingService.rotateRight(e, 11) ^
            DevicePairingService.rotateRight(e, 25)) >>> 0;
        const choose: number = ((e & f) ^ ((~e) & g)) >>> 0;
        const temporary1: number =
          (h + bigSigma1 + choose + SHA256_ROUND_CONSTANTS[index] + schedule[index]) >>> 0;
        const bigSigma0: number =
          (DevicePairingService.rotateRight(a, 2) ^
            DevicePairingService.rotateRight(a, 13) ^
            DevicePairingService.rotateRight(a, 22)) >>> 0;
        const majority: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
        const temporary2: number = (bigSigma0 + majority) >>> 0;
        h = g;
        g = f;
        f = e;
        e = (d + temporary1) >>> 0;
        d = c;
        c = b;
        b = a;
        a = (temporary1 + temporary2) >>> 0;
      }
      state[0] = (state[0] + a) >>> 0;
      state[1] = (state[1] + b) >>> 0;
      state[2] = (state[2] + c) >>> 0;
      state[3] = (state[3] + d) >>> 0;
      state[4] = (state[4] + e) >>> 0;
      state[5] = (state[5] + f) >>> 0;
      state[6] = (state[6] + g) >>> 0;
      state[7] = (state[7] + h) >>> 0;
    }

    let result: string = '';
    for (let index: number = 0; index < state.length; index++) {
      result += DevicePairingService.hex32(state[index]);
    }
    return result.toUpperCase();
  }

  private static rotateRight(value: number, count: number): number {
    return ((value >>> count) | (value << (32 - count))) >>> 0;
  }

  private static hex32(value: number): string {
    let result: string = (value >>> 0).toString(16);
    while (result.length < 8) {
      result = `0${result}`;
    }
    return result;
  }

  private static failure(reason: DevicePairingFailureReason,
    message: string): DevicePairingValidationResult {
    return new DevicePairingValidationResult(false, reason, message, undefined);
  }
}

class PairingQueryResult {
  success: boolean;
  version: string;
  data: string;
  reason: DevicePairingFailureReason;
  message: string;

  constructor(success: boolean, version: string, data: string,
    reason: DevicePairingFailureReason, message: string) {
    this.success = success;
    this.version = version;
    this.data = data;
    this.reason = reason;
    this.message = message;
  }
}

class StringResult {
  success: boolean;
  value: string;
  reason: DevicePairingFailureReason;
  message: string;

  constructor(success: boolean, value: string,
    reason: DevicePairingFailureReason, message: string) {
    this.success = success;
    this.value = value;
    this.reason = reason;
    this.message = message;
  }
}

import { describe, expect, it } from '@ohos/hypium';
import {
  DevicePairingFailureReason,
  DevicePairingPayload,
  DevicePairingValidationResult
} from '../main/ets/models/DevicePairingModels';
import {
  DeviceConnectionSettings
} from '../main/ets/services/DeviceConnectionSettingsStore';
import {
  DevicePairingService,
  STAR_SCOPE_PAIRING_SCHEMA
} from '../main/ets/services/DevicePairingService';

const TEST_NOW_MS: number = 1784548800000;
const TEST_TOKEN: string = 'private-token-must-never-enter-preview';

function currentSettings(): DeviceConnectionSettings {
  return new DeviceConnectionSettings('192.168.137.20', 9999, '192.168.137.10', 8000);
}

function validPayload(): DevicePairingPayload {
  const payload: DevicePairingPayload = {
    schema: STAR_SCOPE_PAIRING_SCHEMA,
    deviceId: 'starscope-demo-01',
    deviceName: 'StarScope 演示设备',
    mountHost: '192.168.137.30',
    mountPort: 9999,
    gatewayHost: '192.168.137.11',
    gatewayPort: 8000,
    issuedAtMs: TEST_NOW_MS - 60000,
    expiresAtMs: TEST_NOW_MS + 3600000,
    token: TEST_TOKEN,
    checksum: ''
  };
  payload.checksum = DevicePairingService.checksumForPayload(payload);
  return payload;
}

function validCode(): string {
  return DevicePairingService.encodePayload(validPayload());
}

export default function devicePairingServiceTest(): void {
  describe('StarScope 设备码安全校验', () => {
    it('正确设备码生成不含令牌的配置预览', 0, () => {
      const result: DevicePairingValidationResult =
        DevicePairingService.validateCode(validCode(), currentSettings(), TEST_NOW_MS);
      expect(result.success).assertTrue();
      expect(result.reason).assertEqual(DevicePairingFailureReason.NONE);
      expect(result.preview === undefined).assertFalse();
      if (result.preview !== undefined) {
        expect(result.preview.configuration.mountHost).assertEqual('192.168.137.30');
        expect(result.preview.configuration.gatewayPort).assertEqual(8000);
        expect(result.preview.mountChanged).assertTrue();
        expect(result.preview.tokenIncluded).assertTrue();
        expect(JSON.stringify(result.preview).indexOf(TEST_TOKEN)).assertEqual(-1);
      }
    });

    it('拒绝错误协议和版本', 0, () => {
      const wrongScheme: DevicePairingValidationResult =
        DevicePairingService.validateCode(
          validCode().replace('starscope://', 'https://'), currentSettings(), TEST_NOW_MS);
      const wrongVersion: DevicePairingValidationResult =
        DevicePairingService.validateCode(
          validCode().replace('pair?v=1&', 'pair?v=2&'), currentSettings(), TEST_NOW_MS);
      expect(wrongScheme.reason).assertEqual(DevicePairingFailureReason.INVALID_SCHEME);
      expect(wrongVersion.reason).assertEqual(DevicePairingFailureReason.UNSUPPORTED_VERSION);
    });

    it('拒绝损坏的 Base64URL 和 JSON', 0, () => {
      const brokenBase64: DevicePairingValidationResult =
        DevicePairingService.validateCode(
          'starscope://pair?v=1&data=%%%', currentSettings(), TEST_NOW_MS);
      const brokenJson: DevicePairingValidationResult =
        DevicePairingService.validateCode(
          'starscope://pair?v=1&data=e2ludmFsaWQ=', currentSettings(), TEST_NOW_MS);
      expect(brokenBase64.reason).assertEqual(DevicePairingFailureReason.INVALID_BASE64URL);
      expect(brokenJson.reason).assertEqual(DevicePairingFailureReason.INVALID_JSON);
    });

    it('拒绝不兼容的数据 schema', 0, () => {
      const payload: DevicePairingPayload = validPayload();
      payload.schema = 'starscope-device-v2';
      payload.checksum = DevicePairingService.checksumForPayload(payload);
      const result: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(payload), currentSettings(), TEST_NOW_MS);
      expect(result.reason).assertEqual(DevicePairingFailureReason.INVALID_SCHEMA);
    });

    it('拒绝公网 IP 和 URL 注入', 0, () => {
      const publicPayload: DevicePairingPayload = validPayload();
      publicPayload.mountHost = '8.8.8.8';
      publicPayload.checksum = DevicePairingService.checksumForPayload(publicPayload);
      const publicResult: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(publicPayload), currentSettings(), TEST_NOW_MS);

      const urlPayload: DevicePairingPayload = validPayload();
      urlPayload.gatewayHost = 'http://192.168.137.11';
      urlPayload.checksum = DevicePairingService.checksumForPayload(urlPayload);
      const urlResult: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(urlPayload), currentSettings(), TEST_NOW_MS);
      expect(publicResult.reason).assertEqual(DevicePairingFailureReason.INVALID_HOST);
      expect(urlResult.reason).assertEqual(DevicePairingFailureReason.INVALID_HOST);
    });

    it('拒绝越界端口', 0, () => {
      const payload: DevicePairingPayload = validPayload();
      payload.mountPort = 65536;
      payload.checksum = DevicePairingService.checksumForPayload(payload);
      const result: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(payload), currentSettings(), TEST_NOW_MS);
      expect(result.reason).assertEqual(DevicePairingFailureReason.INVALID_PORT);
    });

    it('拒绝过期设备码', 0, () => {
      const payload: DevicePairingPayload = validPayload();
      payload.expiresAtMs = TEST_NOW_MS - 1;
      payload.checksum = DevicePairingService.checksumForPayload(payload);
      const result: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(payload), currentSettings(), TEST_NOW_MS);
      expect(result.reason).assertEqual(DevicePairingFailureReason.EXPIRED);
    });

    it('拒绝校验和不匹配的篡改内容', 0, () => {
      const payload: DevicePairingPayload = validPayload();
      const originalChecksum: string = payload.checksum;
      payload.gatewayPort = 9000;
      payload.checksum = originalChecksum;
      const result: DevicePairingValidationResult = DevicePairingService.validateCode(
        DevicePairingService.encodePayload(payload), currentSettings(), TEST_NOW_MS);
      expect(result.reason).assertEqual(DevicePairingFailureReason.INVALID_CHECKSUM);
    });

    it('失败解析不会改变调用方当前配置', 0, () => {
      const current: DeviceConnectionSettings = currentSettings();
      DevicePairingService.validateCode(
        'starscope://pair?v=1&data=bad!', current, TEST_NOW_MS);
      expect(current.mountHost).assertEqual('192.168.137.20');
      expect(current.gatewayHost).assertEqual('192.168.137.10');
    });
  });
}

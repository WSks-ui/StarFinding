import { describe, expect, it } from '@ohos/hypium';
import {
  DEVICE_CONNECTION_SCHEMA_VERSION,
  DeviceConnectionSettings,
  DeviceConnectionSettingsStore
} from '../main/ets/services/DeviceConnectionSettingsStore';

export default function deviceConnectionSettingsStoreTest(): void {
  describe('设备网络地址配置', () => {
    it('可校验并规范化 Windows 热点 IPv4 地址', 0, () => {
      const settings: DeviceConnectionSettings = DeviceConnectionSettingsStore.createFromText(
        '192.168.137.020', '9999', '192.168.137.10', '8000');
      expect(settings.mountHost).assertEqual('192.168.137.20');
      expect(settings.mountPort).assertEqual(9999);
      expect(settings.gatewayHost).assertEqual('192.168.137.10');
      expect(settings.gatewayPort).assertEqual(8000);
    });

    it('拒绝无法用于现场 TCP 连接的地址和端口', 0, () => {
      let invalidHostRejected: boolean = false;
      let invalidPortRejected: boolean = false;
      try {
        DeviceConnectionSettingsStore.createFromText('192.168.137.300', '9999',
          '192.168.137.10', '8000');
      } catch (error) {
        invalidHostRejected = true;
      }
      try {
        DeviceConnectionSettingsStore.createFromText('192.168.137.20', '0',
          '192.168.137.10', '8000');
      } catch (error) {
        invalidPortRejected = true;
      }
      expect(invalidHostRejected).assertTrue();
      expect(invalidPortRejected).assertTrue();
    });

    it('损坏或版本不兼容的存储内容安全回退到默认拓扑', 0, () => {
      const malformed: DeviceConnectionSettings = DeviceConnectionSettingsStore.decode('{invalid');
      expect(malformed.mountHost).assertEqual('10.42.0.20');
      const incompatible: DeviceConnectionSettings = DeviceConnectionSettingsStore.decode(JSON.stringify({
        version: DEVICE_CONNECTION_SCHEMA_VERSION + 1,
        mountHost: '192.168.137.20',
        mountPort: 9999,
        gatewayHost: '192.168.137.10',
        gatewayPort: 8000
      }));
      expect(incompatible.gatewayHost).assertEqual('10.42.0.1');
    });
  });
}

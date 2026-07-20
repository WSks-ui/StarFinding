import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import {
  DevicePairingScanResult,
  DevicePairingScanState
} from '../models/DevicePairingModels';

/**
 * Scan Kit 的最小包装层。
 *
 * 扫码界面必须在 ArkUI 页面上下文调用。该类只取得二维码原文，不解析、不保存配置，
 * 也不会发起任何网络或硬件操作。
 */
export class DevicePairingScanner {
  async scan(context: common.Context): Promise<DevicePairingScanResult> {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    try {
      const result: scanBarcode.ScanResult =
        await scanBarcode.startScanForResult(context, options);
      if (result.scanType !== scanCore.ScanType.QR_CODE ||
        result.originalValue.trim().length === 0) {
        return new DevicePairingScanResult(
          DevicePairingScanState.FAILED, '', '未识别到有效二维码');
      }
      return new DevicePairingScanResult(
        DevicePairingScanState.SUCCESS, result.originalValue, '');
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      if (businessError.code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
        return new DevicePairingScanResult(
          DevicePairingScanState.CANCELLED, '', '已取消扫码');
      }
      return new DevicePairingScanResult(
        DevicePairingScanState.FAILED, '', 'Scan Kit 扫描失败，请使用手动地址配置');
    }
  }
}

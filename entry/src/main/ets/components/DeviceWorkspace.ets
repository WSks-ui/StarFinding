import {
  ConnectionState,
  DevicePairingPreview,
  HarmonyCapabilityReason,
  HarmonyCapabilityState,
  HarmonyFeatureCapability,
  HarmonyFeatureSnapshot,
  ObservationRunMode
} from '../models';
import {
  DeviceReadinessService,
  MountReadinessInput,
  MountReadinessStage
} from '../services/DeviceReadinessService';
import { MotionTokens } from '../utils/MotionTokens';

interface DeviceStatusLine {
  key: string;
  name: ResourceStr;
  detail: ResourceStr;
  state: ResourceStr;
  color: ResourceColor;
}

@Component
export struct DeviceWorkspace {
  @Prop compact: boolean = false;
  @Prop pageMargin: number = 18;
  @Prop runMode: ObservationRunMode = ObservationRunMode.REAL;
  @Prop digitalTwinPlaying: boolean = false;
  @Prop digitalTwinPhaseText: string = '';
  @Prop digitalTwinSourceText: string = '';
  @Prop mountConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop gatewayServiceConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop cameraConnection: ConnectionState = ConnectionState.DISCONNECTED;
  @Prop mountDetail: string = '';
  @Prop gatewayDetail: string = '';
  @Prop connectionSettingsOpen: boolean = false;
  @Prop connectionSettingsLocked: boolean = false;
  @Prop mountHostInput: string = '';
  @Prop mountPortInput: string = '';
  @Prop gatewayHostInput: string = '';
  @Prop gatewayPortInput: string = '';
  @Prop scanKitAvailable: boolean = false;
  @Prop pairingBusy: boolean = false;
  @Prop pairingPreview: DevicePairingPreview | undefined = undefined;
  @Prop harmonyFeatures: HarmonyFeatureSnapshot | undefined = undefined;
  @Prop mountHomed: boolean = false;
  @Prop coordinateModeCompatible: boolean = false;
  @Prop tracking: boolean = false;
  @Prop locationSynced: boolean = false;
  @Prop observerAvailable: boolean = false;
  @Prop simulatedTimeActive: boolean = false;
  @Prop locationText: string = '等待定位';
  @Prop mountRaHours: number = 0;
  @Prop mountDecDegrees: number = 0;
  @Prop mountSlewing: boolean = false;
  @Prop mountUpdatedAtMs: number = 0;
  @Prop gatewayUpdatedAtMs: number = 0;
  @Prop deviceMessage: string = '';
  @Prop emergencyMessage: string = '';
  @State private pressedAction: string = '';
  @State private harmonyDiagnosticsOpen: boolean = false;

  onToggleMount: () => void = (): void => {};
  onToggleGateway: () => void = (): void => {};
  onEnterSimulation: () => void = (): void => {};
  onExitSimulation: () => void = (): void => {};
  onToggleSimulationPlayback: () => void = (): void => {};
  onRestartSimulation: () => void = (): void => {};
  onToggleConnectionSettings: () => void = (): void => {};
  onMountHostChange: (value: string) => void = (_value: string): void => {};
  onMountPortChange: (value: string) => void = (_value: string): void => {};
  onGatewayHostChange: (value: string) => void = (_value: string): void => {};
  onGatewayPortChange: (value: string) => void = (_value: string): void => {};
  onSaveConnectionSettings: () => void = (): void => {};
  onRestoreConnectionDefaults: () => void = (): void => {};
  onScanDeviceCode: () => void = (): void => {};
  onConfirmPairing: () => void = (): void => {};
  onCancelPairing: () => void = (): void => {};
  onRefreshHarmonyFeatures: () => void = (): void => {};
  onHomeMount: () => void = (): void => {};
  onSyncObserver: () => void = (): void => {};
  onToggleTracking: () => void = (): void => {};
  onParkMount: () => void = (): void => {};

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          this.RunModePanel()
          this.ConnectionSection()
          this.OperationFeedback()
          this.ReadinessPanel()
          this.DevicePanels()
        }
        .width('100%')
        .padding({ left: this.pageMargin, right: this.pageMargin, top: 16, bottom: 28 })
      }
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    // 主窗口使用沉浸式全屏，系统导航条会覆盖页面底部。由外层容器保留安全区，
    // 让内层 Scroll 的测量高度不包含系统导航条占用的 32vp。
    .padding({ bottom: 32 })
  }

  @Builder
  private RunModePanel() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text($r('app.string.digital_twin_mode_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text(this.simulationActive() ? $r('app.string.digital_twin_mode_simulation_detail') :
            $r('app.string.digital_twin_mode_real_detail'))
            .fontSize(11)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(2)
        }.layoutWeight(1)
        Row() {
          Button($r('app.string.digital_twin_mode_real'))
            .height(36)
            .padding({ left: 13, right: 13 })
            .fontSize(11)
            .fontColor(!this.simulationActive() ? $r('app.color.app_on_brand') :
              $r('app.color.app_text_secondary'))
            .backgroundColor(!this.simulationActive() ? $r('app.color.app_brand') : 'transparent')
            .borderRadius(18)
            .onClick(this.onExitSimulation)
          Button($r('app.string.digital_twin_mode_simulation'))
            .height(36)
            .padding({ left: 13, right: 13 })
            .fontSize(11)
            .fontColor(this.simulationActive() ? $r('app.color.app_on_brand') :
              $r('app.color.app_text_secondary'))
            .backgroundColor(this.simulationActive() ? $r('app.color.app_brand') : 'transparent')
            .borderRadius(18)
            .onClick(this.onEnterSimulation)
        }
        .padding(3)
        .backgroundColor($r('app.color.app_surface_secondary'))
        .borderRadius(21)
      }.width('100%')

      if (this.simulationActive()) {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(this.digitalTwinPhaseText.length > 0 ? this.digitalTwinPhaseText :
              $r('app.string.digital_twin_waiting'))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_brand'))
            Text(this.digitalTwinSourceText.length > 0 ? this.digitalTwinSourceText :
              $r('app.string.digital_twin_source_simulated'))
              .fontSize(10)
              .fontColor($r('app.color.app_warning'))
          }.layoutWeight(1)
          Button(this.digitalTwinPlaying ? $r('app.string.digital_twin_pause') :
            $r('app.string.digital_twin_play'))
            .height(38)
            .padding({ left: 14, right: 14 })
            .fontSize(11)
            .fontColor($r('app.color.app_on_brand'))
            .backgroundColor($r('app.color.app_brand'))
            .borderRadius(19)
            .onClick(this.onToggleSimulationPlayback)
          Button($r('app.string.digital_twin_restart'))
            .height(38)
            .padding({ left: 14, right: 14 })
            .fontSize(11)
            .fontColor($r('app.color.app_text_primary'))
            .backgroundColor($r('app.color.app_surface_secondary'))
            .borderRadius(19)
            .onClick(this.onRestartSimulation)
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.app_surface_primary'))
        .borderRadius($r('app.float.corner_small'))

        Text($r('app.string.digital_twin_safety_note'))
          .fontSize(10)
          .lineHeight(16)
          .fontColor($r('app.color.app_warning'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_background_secondary'))
    .border({ width: 1, color: this.simulationActive() ?
      $r('app.color.app_brand') : $r('app.color.app_divider') })
    .borderRadius($r('app.float.corner_card'))
  }

  @Builder
  private ConnectionSection() {
    Column({ space: 12 }) {
      this.ConnectionSettingsPanel()
      if (this.compact) {
        Column({ space: 12 }) {
          this.ConnectionPanel($r('app.string.device_mount_title'), this.mountSubtitle(),
            this.mountConnection, this.mountUpdatedAtMs, this.mountActionText(), this.onToggleMount)
          this.ConnectionPanel($r('app.string.device_gateway_title'), this.gatewaySubtitle(),
            this.gatewayServiceConnection, this.gatewayUpdatedAtMs, this.gatewayActionText(), this.onToggleGateway)
        }.width('100%')
      } else {
        Row({ space: 12 }) {
          Column() {
            this.ConnectionPanel($r('app.string.device_mount_title'), this.mountSubtitle(),
              this.mountConnection, this.mountUpdatedAtMs, this.mountActionText(), this.onToggleMount)
          }.layoutWeight(1)
          Column() {
            this.ConnectionPanel($r('app.string.device_gateway_title'), this.gatewaySubtitle(),
              this.gatewayServiceConnection, this.gatewayUpdatedAtMs, this.gatewayActionText(), this.onToggleGateway)
          }.layoutWeight(1)
        }.width('100%')
      }
    }.width('100%')
  }

  @Builder
  private ConnectionSettingsPanel() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text($r('app.string.device_network_settings_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text($r('app.string.device_network_settings_detail'))
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(2)
        }.layoutWeight(1)
        Button(this.connectionSettingsOpen ? $r('app.string.device_network_settings_hide') :
          $r('app.string.device_network_settings_edit'))
          .height(36)
          .padding({ left: 14, right: 14 })
          .fontSize(12)
          .fontColor($r('app.color.app_brand'))
          .backgroundColor($r('app.color.app_surface_secondary'))
          .border({ width: 1, color: $r('app.color.app_divider') })
          .borderRadius(18)
          .enabled(!this.connectionSettingsLocked)
          .onClick(this.onToggleConnectionSettings)
      }.width('100%').alignItems(VerticalAlign.Top)

      Row({ space: 10 }) {
        Button(this.pairingBusy ? $r('app.string.device_pairing_scanning') :
          $r('app.string.device_pairing_scan'))
          .layoutWeight(1)
          .height(42)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.scanKitAvailable ? $r('app.color.app_on_brand') :
            $r('app.color.app_text_tertiary'))
          .backgroundColor(this.scanKitAvailable ? $r('app.color.app_brand') :
            $r('app.color.app_surface_secondary'))
          .borderRadius(21)
          .enabled(this.scanKitAvailable && !this.pairingBusy && !this.connectionSettingsLocked &&
            !this.simulationActive())
          .onClick(this.onScanDeviceCode)
        Button($r('app.string.harmony_diagnostics_title'))
          .layoutWeight(1)
          .height(42)
          .fontSize(13)
          .fontColor($r('app.color.app_brand'))
          .backgroundColor($r('app.color.app_surface_secondary'))
          .border({ width: 1, color: $r('app.color.app_divider') })
          .borderRadius(21)
          .onClick(() => {
            this.harmonyDiagnosticsOpen = !this.harmonyDiagnosticsOpen;
            if (this.harmonyDiagnosticsOpen) {
              this.onRefreshHarmonyFeatures();
            }
          })
      }.width('100%')

      if (!this.scanKitAvailable) {
        Text($r('app.string.device_pairing_scan_unavailable'))
          .fontSize(11)
          .fontColor($r('app.color.app_warning'))
          .width('100%')
      }

      if (this.pairingPreview !== undefined) {
        this.PairingPreviewCard(this.pairingPreview)
      }

      if (this.harmonyDiagnosticsOpen) {
        this.HarmonyDiagnosticsPanel()
      }

      if (this.connectionSettingsOpen) {
        Column({ space: 10 }) {
          if (this.compact) {
            Column({ space: 10 }) {
              this.EndpointInput($r('app.string.device_network_mount_ip'), this.mountHostInput,
                $r('app.string.device_network_ip_placeholder'), false, this.onMountHostChange)
              this.EndpointInput($r('app.string.device_network_mount_port'), this.mountPortInput,
                $r('app.string.device_network_port_placeholder'), true, this.onMountPortChange)
              this.EndpointInput($r('app.string.device_network_gateway_ip'), this.gatewayHostInput,
                $r('app.string.device_network_ip_placeholder'), false, this.onGatewayHostChange)
              this.EndpointInput($r('app.string.device_network_gateway_port'), this.gatewayPortInput,
                $r('app.string.device_network_port_placeholder'), true, this.onGatewayPortChange)
            }.width('100%')
          } else {
            Row({ space: 10 }) {
              Column({ space: 10 }) {
                this.EndpointInput($r('app.string.device_network_mount_ip'), this.mountHostInput,
                  $r('app.string.device_network_ip_placeholder'), false, this.onMountHostChange)
                this.EndpointInput($r('app.string.device_network_mount_port'), this.mountPortInput,
                  $r('app.string.device_network_port_placeholder'), true, this.onMountPortChange)
              }.layoutWeight(1)
              Column({ space: 10 }) {
                this.EndpointInput($r('app.string.device_network_gateway_ip'), this.gatewayHostInput,
                  $r('app.string.device_network_ip_placeholder'), false, this.onGatewayHostChange)
                this.EndpointInput($r('app.string.device_network_gateway_port'), this.gatewayPortInput,
                  $r('app.string.device_network_port_placeholder'), true, this.onGatewayPortChange)
              }.layoutWeight(1)
            }.width('100%')
          }
          Text(this.connectionSettingsLocked ? $r('app.string.device_network_settings_locked') :
            $r('app.string.device_network_settings_safe_note'))
            .fontSize(11)
            .fontColor(this.connectionSettingsLocked ? $r('app.color.app_warning') :
              $r('app.color.app_text_tertiary'))
            .width('100%')
          Row({ space: 10 }) {
            Button($r('app.string.device_network_restore_default'))
              .layoutWeight(1)
              .height(42)
              .fontSize(13)
              .fontColor($r('app.color.app_text_primary'))
              .backgroundColor($r('app.color.app_surface_secondary'))
              .border({ width: 1, color: $r('app.color.app_divider') })
              .borderRadius(21)
              .enabled(!this.connectionSettingsLocked)
              .onClick(this.onRestoreConnectionDefaults)
            Button($r('app.string.device_network_save_apply'))
              .layoutWeight(1)
              .height(42)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_on_brand'))
              .backgroundColor($r('app.color.app_brand'))
              .borderRadius(21)
              .enabled(!this.connectionSettingsLocked)
              .onClick(this.onSaveConnectionSettings)
          }.width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.app_surface_secondary'))
        .borderRadius($r('app.float.corner_small'))
        .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_background_secondary'))
    .border({ width: 1, color: $r('app.color.app_divider') })
    .borderRadius($r('app.float.corner_card'))
    .animation(MotionTokens.standard())
  }

  @Builder
  private PairingPreviewCard(preview: DevicePairingPreview) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(38)
            .height(38)
            .fill($r('app.color.app_surface_tertiary'))
          SymbolGlyph($r('sys.symbol.qrcode'))
            .fontSize(20)
            .fontColor([$r('app.color.app_brand')])
        }
        Column({ space: 3 }) {
          Text($r('app.string.device_pairing_preview_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text(preview.deviceName)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1)
        Text($r('app.string.device_pairing_verified'))
          .fontSize(11)
          .fontColor($r('app.color.app_success'))
      }.width('100%')

      this.PairingEndpointLine(
        $r('app.string.device_pairing_mount_endpoint'),
        `${preview.configuration.mountHost}:${preview.configuration.mountPort}`,
        preview.mountChanged)
      this.PairingEndpointLine(
        $r('app.string.device_pairing_gateway_endpoint'),
        `${preview.configuration.gatewayHost}:${preview.configuration.gatewayPort}`,
        preview.gatewayChanged)

      if (preview.tokenIncluded) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(14)
            .fontColor([$r('app.color.app_text_tertiary')])
          Text($r('app.string.device_pairing_token_hidden'))
            .fontSize(11)
            .fontColor($r('app.color.app_text_tertiary'))
            .layoutWeight(1)
        }.width('100%')
      }

      Text($r('app.string.device_pairing_confirm_note'))
        .fontSize(11)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')

      Row({ space: 10 }) {
        Button($r('app.string.device_pairing_cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.app_text_primary'))
          .backgroundColor($r('app.color.app_background_primary'))
          .border({ width: 1, color: $r('app.color.app_divider') })
          .borderRadius(20)
          .enabled(!this.pairingBusy)
          .onClick(this.onCancelPairing)
        Button($r('app.string.device_pairing_confirm'))
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_on_brand'))
          .backgroundColor($r('app.color.app_brand'))
          .borderRadius(20)
          .enabled(!this.pairingBusy && !this.connectionSettingsLocked)
          .onClick(this.onConfirmPairing)
      }.width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_surface_secondary'))
    .border({ width: 1, color: $r('app.color.app_brand') })
    .borderRadius($r('app.float.corner_small'))
    .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
  }

  @Builder
  private PairingEndpointLine(label: ResourceStr, value: string, changed: boolean) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.app_text_secondary'))
        .width(this.compact ? 86 : 112)
      Text(value)
        .fontSize(12)
        .fontColor($r('app.color.app_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(changed ? $r('app.string.device_pairing_will_update') :
        $r('app.string.device_pairing_unchanged'))
        .fontSize(10)
        .fontColor(changed ? $r('app.color.app_brand') : $r('app.color.app_text_tertiary'))
    }.width('100%')
  }

  @Builder
  private HarmonyDiagnosticsPanel() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text($r('app.string.harmony_diagnostics_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
          Text(this.harmonyRuntimeDescription())
            .fontSize(11)
            .fontColor($r('app.color.app_text_secondary'))
        }.layoutWeight(1)
        Button($r('app.string.harmony_diagnostics_refresh'))
          .height(32)
          .padding({ left: 12, right: 12 })
          .fontSize(11)
          .fontColor($r('app.color.app_brand'))
          .backgroundColor($r('app.color.app_background_primary'))
          .borderRadius(16)
          .onClick(this.onRefreshHarmonyFeatures)
      }.width('100%')

      if (this.harmonyFeatures !== undefined) {
        this.HarmonyCapabilityLine($r('app.string.harmony_feature_scan_kit'),
          this.harmonyFeatures.scanKit)
        this.HarmonyCapabilityLine($r('app.string.harmony_feature_live_view'),
          this.harmonyFeatures.liveView)
        this.HarmonyCapabilityLine($r('app.string.harmony_feature_form_kit'),
          this.harmonyFeatures.formKit)
        this.HarmonyCapabilityLine($r('app.string.harmony_feature_system_share'),
          this.harmonyFeatures.systemShare)
        this.HarmonyCapabilityLine($r('app.string.harmony_feature_harmony_share'),
          this.harmonyFeatures.harmonyShare)
      }

      Text($r('app.string.harmony_diagnostics_truth_note'))
        .fontSize(10)
        .fontColor($r('app.color.app_text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.app_surface_secondary'))
    .border({ width: 1, color: $r('app.color.app_divider') })
    .borderRadius($r('app.float.corner_small'))
    .transition(TransitionEffect.OPACITY.animation(MotionTokens.standard()))
  }

  @Builder
  private HarmonyCapabilityLine(label: ResourceStr, capability: HarmonyFeatureCapability) {
    Row({ space: 10 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.harmonyCapabilityColor(capability))
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.app_text_primary'))
        .width(this.compact ? 96 : 130)
      Text(this.harmonyCapabilityText(capability))
        .fontSize(11)
        .fontColor(this.harmonyCapabilityColor(capability))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(2)
    }
    .width('100%')
    .constraintSize({ minHeight: 34 })
  }

  @Builder
  private EndpointInput(label: ResourceStr, value: string, placeholder: ResourceStr,
    numeric: boolean, onChange: (value: string) => void) {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.app_text_secondary'))
      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor($r('app.color.app_text_primary'))
        .placeholderColor($r('app.color.app_text_tertiary'))
        .backgroundColor($r('app.color.app_background_primary'))
        .border({ width: 1, color: $r('app.color.app_divider') })
        .borderRadius($r('app.float.corner_small'))
        .type(numeric ? InputType.Number : InputType.Normal)
        .enabled(!this.connectionSettingsLocked)
        .onChange(onChange)
    }.width('100%')
  }

  @Builder
  private ConnectionPanel(title: ResourceStr, subtitle: ResourceStr, state: ConnectionState,
    updatedAtMs: number, actionLabel: ResourceStr, action: () => void) {
    Row({ space: 12 }) {
      if (state === ConnectionState.CONNECTING) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color($r('app.color.app_warning'))
          .transition(TransitionEffect.OPACITY.animation(MotionTokens.quick()))
      } else {
        Circle().width(12).height(12).fill(this.connectionColor(state))
          .transition(TransitionEffect.OPACITY.animation(MotionTokens.quick()))
      }
      Column({ space: 4 }) {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .width('100%')
          .maxLines(1)
        Text(subtitle)
          .fontSize(12)
          .fontColor($r('app.color.app_text_secondary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1)
      Column({ space: 6 }) {
        Text(this.connectionText(state))
          .fontSize(12)
          .fontColor(this.connectionColor(state))
          .maxLines(1)
        if (updatedAtMs > 0) {
          Text(this.formatUpdatedAt(updatedAtMs))
            .fontSize(10)
            .fontColor($r('app.color.app_text_tertiary'))
        }
        Button(actionLabel)
          .height(44)
          .constraintSize({ minWidth: 96 })
          .padding({ left: 16, right: 16 })
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_on_brand'))
          .backgroundColor($r('app.color.app_brand'))
          .borderRadius(22)
          .enabled(state !== ConnectionState.CONNECTING && !this.simulationActive())
          .onClick(action)
      }.alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .constraintSize({ minHeight: 108 })
    .padding({ left: 18, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.app_background_secondary'))
    .border({ width: 1, color: $r('app.color.app_divider') })
    .borderRadius($r('app.float.corner_card'))
    .animation(MotionTokens.standard())
  }

  @Builder
  private OperationFeedback() {
    Row({ space: 12 }) {
      Circle()
        .width(9)
        .height(9)
        .fill(this.emergencyMessage.length > 0 ?
          $r('app.color.app_error') : (this.deviceMessage.length > 0 ?
            $r('app.color.app_brand') : $r('app.color.app_text_tertiary')))
      Column({ space: 3 }) {
        Text($r('app.string.device_operation_feedback'))
          .fontSize(11)
          .fontColor($r('app.color.app_text_tertiary'))
        Text(this.feedbackText())
          .fontSize(13)
          .fontColor(this.emergencyMessage.length > 0 ?
            $r('app.color.app_error') : $r('app.color.app_text_primary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 58 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_small'))
    .border({ width: 1, color: this.emergencyMessage.length > 0 ?
      $r('app.color.app_error') : $r('app.color.app_divider') })
  }

  @Builder
  private ReadinessPanel() {
    Column({ space: 14 }) {
      this.PanelTitle($r('app.string.device_workflow_title'),
        this.readinessStage() === MountReadinessStage.BLOCKED ?
          $r('app.string.device_step_blocked_detail') : $r('app.string.device_workflow_subtitle'))
      if (this.compact) {
        Column({ space: 10 }) {
          this.WorkflowStep(0, $r('app.string.device_step_connect'),
            $r('app.string.device_step_connect_detail'))
          this.WorkflowStep(1, $r('app.string.device_step_home'),
            $r('app.string.device_step_home_detail'))
          this.WorkflowStep(2, $r('app.string.device_step_sync'),
            $r('app.string.device_step_sync_detail'))
          this.WorkflowStep(3, $r('app.string.device_step_ready'),
            $r('app.string.device_step_ready_detail'))
        }.width('100%')
      } else {
        Row({ space: 10 }) {
          Column() {
            this.WorkflowStep(0, $r('app.string.device_step_connect'),
              $r('app.string.device_step_connect_detail'))
          }.layoutWeight(1)
          Rect().width(20).height(1).fill($r('app.color.app_divider'))
          Column() {
            this.WorkflowStep(1, $r('app.string.device_step_home'),
              $r('app.string.device_step_home_detail'))
          }.layoutWeight(1)
          Rect().width(20).height(1).fill($r('app.color.app_divider'))
          Column() {
            this.WorkflowStep(2, $r('app.string.device_step_sync'),
              $r('app.string.device_step_sync_detail'))
          }.layoutWeight(1)
          Rect().width(20).height(1).fill($r('app.color.app_divider'))
          Column() {
            this.WorkflowStep(3, $r('app.string.device_step_ready'),
              $r('app.string.device_step_ready_detail'))
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: this.readinessStage() === MountReadinessStage.BLOCKED ?
      $r('app.color.app_error') : $r('app.color.app_divider') })
  }

  @Builder
  private WorkflowStep(index: number, title: ResourceStr, detail: ResourceStr) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(32)
          .height(32)
          .fill(this.workflowStepColor(index))
        if (this.workflowStepComplete(index)) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([$r('app.color.app_on_brand')])
        } else {
          Text((index + 1).toString())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.workflowStepActive(index) ?
              $r('app.color.app_on_brand') : $r('app.color.app_text_secondary'))
        }
      }.width(32).height(32)
      Column({ space: 2 }) {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.workflowStepActive(index) || this.workflowStepComplete(index) ?
            $r('app.color.app_text_primary') : $r('app.color.app_text_secondary'))
          .maxLines(1)
        Text(detail)
          .fontSize(10)
          .fontColor($r('app.color.app_text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: 40 })
  }

  @Builder
  private DevicePanels() {
    if (this.compact) {
      Column({ space: 12 }) {
        this.MountOperationsPanel()
        this.TelemetryPanel()
      }.width('100%')
    } else {
      Row({ space: 12 }) {
        Column() {
          this.MountOperationsPanel()
        }.layoutWeight(1)
        Column() {
          this.TelemetryPanel()
        }.width(340)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      // 左列检查项明显高于右列离线遥测卡。显式保留双栏高度，避免 layoutWeight
      // 只按右列约 360vp 计算滚动范围，导致物理急停等末尾检查项无法滚入安全区。
      .constraintSize({ minHeight: 520 })
    }
  }

  @Builder
  private MountOperationsPanel() {
    Column({ space: 14 }) {
      this.PanelTitle($r('app.string.device_mount_operations'),
        $r('app.string.device_mount_operations_note'))
      if (this.compact) {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            this.ActionButton('home', $r('sys.symbol.house'), $r('app.string.device_action_home'),
              this.canHome(), this.onHomeMount)
            this.ActionButton('sync', $r('sys.symbol.scope'), $r('app.string.device_action_sync'),
              this.canSync(), this.onSyncObserver)
          }.width('100%')
          Row({ space: 10 }) {
            this.ActionButton('tracking', $r('sys.symbol.play_circle'), this.tracking ?
              $r('app.string.device_action_tracking_stop') : $r('app.string.device_action_tracking_start'),
              this.canTrack(), this.onToggleTracking)
            this.ActionButton('park', $r('sys.symbol.pause_circle'), $r('app.string.device_action_park'),
              this.canPark(), this.onParkMount)
          }.width('100%')
        }.width('100%')
      } else {
        Row({ space: 10 }) {
          this.ActionButton('home', $r('sys.symbol.house'), $r('app.string.device_action_home'),
            this.canHome(), this.onHomeMount)
          this.ActionButton('sync', $r('sys.symbol.scope'), $r('app.string.device_action_sync'),
            this.canSync(), this.onSyncObserver)
          this.ActionButton('tracking', $r('sys.symbol.play_circle'), this.tracking ?
            $r('app.string.device_action_tracking_stop') : $r('app.string.device_action_tracking_start'),
            this.canTrack(), this.onToggleTracking)
          this.ActionButton('park', $r('sys.symbol.pause_circle'), $r('app.string.device_action_park'),
            this.canPark(), this.onParkMount)
        }.width('100%')
      }

      Text($r('app.string.device_system_checks'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')
      Column() {
        ForEach(this.deviceLines(), (line: DeviceStatusLine) => {
          Row({ space: 10 }) {
            Circle().width(8).height(8).fill(line.color)
            Text(line.name)
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
              .width(this.compact ? 92 : 108)
              .maxLines(1)
            Text(line.detail)
              .fontSize(12)
              .fontColor($r('app.color.app_text_primary'))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(line.state)
              .fontSize(11)
              .fontColor(line.color)
              .maxLines(1)
          }
          .width('100%')
          .constraintSize({ minHeight: 44 })
          .border({ width: { bottom: 1 }, color: $r('app.color.app_divider') })
        }, (line: DeviceStatusLine) => line.key)
      }.width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private TelemetryPanel() {
    Column({ space: 14 }) {
      this.PanelTitle($r('app.string.device_telemetry_title'), $r('app.string.device_telemetry_note'))
      if (DeviceReadinessService.telemetryAvailable(this.mountConnection, this.mountUpdatedAtMs)) {
        this.TelemetryLine($r('app.string.device_telemetry_ra'), this.formatRa(this.mountRaHours))
        this.TelemetryLine($r('app.string.device_telemetry_dec'), this.formatDec(this.mountDecDegrees))
        this.TelemetryLine($r('app.string.device_telemetry_motion'), this.mountSlewing ?
          $r('app.string.device_value_slewing') : $r('app.string.device_value_stationary'))
        this.TelemetryLine($r('app.string.device_telemetry_location'), this.locationSynced ?
          $r('app.string.device_status_synced') : $r('app.string.device_status_waiting_sync'))
        this.TelemetryLine($r('app.string.device_telemetry_coordinate'), this.coordinateModeCompatible ?
          $r('app.string.device_status_topocentric') : $r('app.string.device_value_motion_locked'))
        this.TelemetryLine($r('app.string.device_telemetry_tracking'), this.tracking ?
          $r('app.string.device_value_sidereal') : $r('app.string.device_value_tracking_stopped'))
        this.TelemetryLine($r('app.string.device_telemetry_safety'), this.mountHomed ?
          $r('app.string.device_value_soft_limit_ready') : $r('app.string.device_value_waiting_home'))
        this.TelemetryLine($r('app.string.device_telemetry_updated'),
          this.formatUpdatedAt(this.mountUpdatedAtMs))
      } else {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.scope'))
            .fontSize(36)
            .fontColor([$r('app.color.app_text_tertiary')])
          Text($r('app.string.device_telemetry_offline'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_secondary'))
          Text($r('app.string.device_telemetry_offline_detail'))
            .fontSize(12)
            .fontColor($r('app.color.app_text_tertiary'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
        }
        .width('100%')
        .constraintSize({ minHeight: 230 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 360 })
    .padding(20)
    .backgroundColor($r('app.color.app_background_secondary'))
    .borderRadius($r('app.float.corner_card'))
    .border({ width: 1, color: $r('app.color.app_divider') })
  }

  @Builder
  private PanelTitle(title: ResourceStr, subtitle: ResourceStr) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .width('100%')
      Text(subtitle)
        .fontSize(12)
        .fontColor($r('app.color.app_text_secondary'))
        .width('100%')
        .maxLines(2)
    }.width('100%')
  }

  @Builder
  private ActionButton(actionId: string, icon: Resource, label: ResourceStr,
    enabled: boolean, action: () => void) {
    Column({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(25)
        .fontColor([enabled ? $r('app.color.app_brand') : $r('app.color.app_text_tertiary')])
      Text(label)
        .fontSize(12)
        .fontColor(enabled ? $r('app.color.app_text_primary') : $r('app.color.app_text_tertiary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .layoutWeight(1)
    .height(88)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.app_surface_secondary'))
    .borderRadius($r('app.float.corner_small'))
    .opacity(enabled ? 1 : 0.58)
    .scale({
      x: this.pressedAction === actionId ? 0.96 : 1,
      y: this.pressedAction === actionId ? 0.96 : 1
    })
    .animation(MotionTokens.quick())
    .onTouch((event: TouchEvent) => {
      if (!enabled) return;
      if (event.type === TouchType.Down) {
        this.pressedAction = actionId;
      } else if (this.pressedAction === actionId) {
        this.pressedAction = '';
      }
    })
    .onClick(() => {
      if (enabled) action();
    })
  }

  @Builder
  private TelemetryLine(label: ResourceStr, value: ResourceStr) {
    Row({ space: 12 }) {
      Text(label).fontSize(13).fontColor($r('app.color.app_text_secondary'))
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.app_text_primary'))
        .textAlign(TextAlign.End)
        .maxLines(1)
    }
    .width('100%')
    .height(32)
  }

  private readinessInput(): MountReadinessInput {
    return {
      connection: this.mountConnection,
      coordinateModeCompatible: this.coordinateModeCompatible,
      mountHomed: this.mountHomed,
      locationSynced: this.locationSynced,
      observerAvailable: this.observerAvailable,
      simulatedTimeActive: this.simulatedTimeActive
    };
  }

  private readinessStage(): MountReadinessStage {
    if (this.simulationActive()) return MountReadinessStage.READY;
    return DeviceReadinessService.stage(this.readinessInput());
  }

  private workflowStepComplete(index: number): boolean {
    if (this.simulationActive()) {
      if (index === 0) {
        return this.mountConnection === ConnectionState.SIMULATED &&
          this.gatewayServiceConnection === ConnectionState.SIMULATED;
      }
      if (index === 1) return this.mountHomed;
      if (index === 2) return this.locationSynced;
      return this.tracking;
    }
    const input: MountReadinessInput = this.readinessInput();
    if (index === 0) {
      return DeviceReadinessService.connectionReady(input) && input.coordinateModeCompatible;
    }
    if (index === 1) return DeviceReadinessService.homeReady(input);
    if (index === 2) return DeviceReadinessService.syncReady(input);
    return DeviceReadinessService.fullyReady(input);
  }

  private workflowStepActive(index: number): boolean {
    const stage: MountReadinessStage = this.readinessStage();
    if (index === 0) return stage === MountReadinessStage.CONNECT || stage === MountReadinessStage.BLOCKED;
    if (index === 1) return stage === MountReadinessStage.HOME;
    if (index === 2) return stage === MountReadinessStage.SYNC;
    return stage === MountReadinessStage.READY;
  }

  private workflowStepColor(index: number): ResourceColor {
    if (this.workflowStepComplete(index)) return $r('app.color.app_success');
    if (this.workflowStepActive(index)) {
      return this.readinessStage() === MountReadinessStage.BLOCKED ?
        $r('app.color.app_error') : $r('app.color.app_brand');
    }
    return $r('app.color.app_surface_tertiary');
  }

  private canHome(): boolean {
    if (this.simulationActive()) return false;
    return this.mountConnection === ConnectionState.CONNECTED && this.coordinateModeCompatible;
  }

  private canSync(): boolean {
    if (this.simulationActive()) return false;
    return this.mountConnection === ConnectionState.CONNECTED && this.coordinateModeCompatible &&
      this.observerAvailable && !this.simulatedTimeActive;
  }

  private canTrack(): boolean {
    if (this.simulationActive()) return false;
    return this.mountConnection === ConnectionState.CONNECTED && this.coordinateModeCompatible &&
      this.mountHomed && this.locationSynced;
  }

  private canPark(): boolean {
    if (this.simulationActive()) return false;
    return this.mountConnection === ConnectionState.CONNECTED && this.mountHomed;
  }

  private feedbackText(): ResourceStr {
    if (this.emergencyMessage.length > 0) return this.emergencyMessage;
    if (this.deviceMessage.length > 0) return this.deviceMessage;
    return $r('app.string.device_operation_idle');
  }

  private gatewaySubtitle(): ResourceStr {
    return this.gatewayDetail.length > 0 ? this.gatewayDetail : $r('app.string.device_gateway_endpoint');
  }

  private mountSubtitle(): ResourceStr {
    return this.mountDetail.length > 0 ? this.mountDetail : $r('app.string.device_mount_endpoint');
  }

  private mountActionText(): ResourceStr {
    if (this.mountConnection === ConnectionState.CONNECTED) return $r('app.string.device_disconnect');
    if (this.mountConnection === ConnectionState.ERROR) return $r('app.string.device_reconnect');
    return $r('app.string.device_connect_self_test');
  }

  private gatewayActionText(): ResourceStr {
    if (this.gatewayServiceConnection === ConnectionState.CONNECTED) {
      return $r('app.string.device_stop_monitoring');
    }
    if (this.gatewayServiceConnection === ConnectionState.ERROR) return $r('app.string.device_recheck');
    return $r('app.string.device_check_gateway');
  }

  private connectionText(state: ConnectionState): ResourceStr {
    if (state === ConnectionState.CONNECTED) return $r('app.string.device_state_connected');
    if (state === ConnectionState.CONNECTING) return $r('app.string.device_state_connecting');
    if (state === ConnectionState.ERROR) return $r('app.string.device_state_error');
    if (state === ConnectionState.SIMULATED) return $r('app.string.device_state_simulated');
    return $r('app.string.device_state_disconnected');
  }

  private connectionColor(state: ConnectionState): ResourceColor {
    if (state === ConnectionState.CONNECTED) return $r('app.color.app_success');
    if (state === ConnectionState.CONNECTING) return $r('app.color.app_warning');
    if (state === ConnectionState.ERROR) return $r('app.color.app_error');
    if (state === ConnectionState.SIMULATED) return $r('app.color.app_brand');
    return $r('app.color.app_text_tertiary');
  }

  private deviceLines(): DeviceStatusLine[] {
    return [
      this.networkLine(),
      this.coordinateLine(),
      this.homeLine(),
      this.locationLine(),
      this.cameraLine(),
      {
        key: 'emergency',
        name: $r('app.string.device_check_emergency'),
        detail: $r('app.string.device_detail_emergency'),
        state: $r('app.string.device_status_manual_confirm'),
        color: $r('app.color.app_error')
      }
    ];
  }

  private networkLine(): DeviceStatusLine {
    return {
      key: 'network',
      name: $r('app.string.device_check_network'),
      detail: this.mountSubtitle(),
      state: this.connectionText(this.mountConnection),
      color: this.connectionColor(this.mountConnection)
    };
  }

  private coordinateLine(): DeviceStatusLine {
    if (this.simulationActive()) {
      return {
        key: 'coordinate',
        name: $r('app.string.device_check_coordinate'),
        detail: $r('app.string.digital_twin_check_scripted'),
        state: this.coordinateModeCompatible ? $r('app.string.device_status_topocentric') :
          $r('app.string.device_status_unchecked'),
        color: this.coordinateModeCompatible ? $r('app.color.app_brand') :
          $r('app.color.app_text_tertiary')
      };
    }
    if (this.mountConnection !== ConnectionState.CONNECTED) {
      return {
        key: 'coordinate',
        name: $r('app.string.device_check_coordinate'),
        detail: $r('app.string.device_detail_coordinate'),
        state: $r('app.string.device_status_unchecked'),
        color: $r('app.color.app_text_tertiary')
      };
    }
    return {
      key: 'coordinate',
      name: $r('app.string.device_check_coordinate'),
      detail: $r('app.string.device_detail_coordinate'),
      state: this.coordinateModeCompatible ?
        $r('app.string.device_status_topocentric') : $r('app.string.device_status_incompatible'),
      color: this.coordinateModeCompatible ? $r('app.color.app_success') : $r('app.color.app_error')
    };
  }

  private homeLine(): DeviceStatusLine {
    const connected: boolean = this.mountConnection === ConnectionState.CONNECTED ||
      (this.simulationActive() && this.mountConnection === ConnectionState.SIMULATED);
    return {
      key: 'home',
      name: $r('app.string.device_check_home'),
      detail: $r('app.string.device_detail_home'),
      state: !connected ? $r('app.string.device_status_unconfirmed') :
        (this.mountHomed ? $r('app.string.device_status_homed') : $r('app.string.device_status_waiting_home')),
      color: !connected ? $r('app.color.app_text_tertiary') :
        (this.mountHomed ? $r('app.color.app_success') : $r('app.color.app_warning'))
    };
  }

  private locationLine(): DeviceStatusLine {
    if (this.simulationActive()) {
      return {
        key: 'location',
        name: $r('app.string.device_check_location'),
        detail: $r('app.string.digital_twin_check_scripted'),
        state: this.locationSynced ? $r('app.string.device_status_synced') :
          $r('app.string.device_status_waiting_sync'),
        color: this.locationSynced ? $r('app.color.app_brand') :
          $r('app.color.app_text_tertiary')
      };
    }
    return {
      key: 'location',
      name: $r('app.string.device_check_location'),
      detail: this.locationText,
      state: !this.observerAvailable ? $r('app.string.device_status_location_unavailable') :
        (this.locationSynced ?
          $r('app.string.device_status_synced') : $r('app.string.device_status_waiting_sync')),
      color: this.locationSynced ? $r('app.color.app_success') :
        (this.observerAvailable ? $r('app.color.app_warning') : $r('app.color.app_text_tertiary'))
    };
  }

  private cameraLine(): DeviceStatusLine {
    if (this.simulationActive()) {
      return {
        key: 'camera',
        name: $r('app.string.device_check_camera'),
        detail: this.gatewayDetail,
        state: $r('app.string.device_status_simulated_camera'),
        color: $r('app.color.app_brand')
      };
    }
    if (this.gatewayServiceConnection !== ConnectionState.CONNECTED) {
      return {
        key: 'camera',
        name: $r('app.string.device_check_camera'),
        detail: $r('app.string.device_detail_camera'),
        state: this.gatewayServiceConnection === ConnectionState.ERROR ?
          $r('app.string.device_state_error') : $r('app.string.device_status_unchecked'),
        color: this.gatewayServiceConnection === ConnectionState.ERROR ?
          $r('app.color.app_error') : $r('app.color.app_text_tertiary')
      };
    }
    let state: ResourceStr = $r('app.string.device_status_camera_missing');
    let color: ResourceColor = $r('app.color.app_warning');
    if (this.cameraConnection === ConnectionState.CONNECTED) {
      state = $r('app.string.device_status_real_camera');
      color = $r('app.color.app_success');
    } else if (this.cameraConnection === ConnectionState.SIMULATED) {
      state = $r('app.string.device_status_simulated_camera');
      color = $r('app.color.app_warning');
    }
    return {
      key: 'camera',
      name: $r('app.string.device_check_camera'),
      detail: this.gatewayDetail.length > 0 ? this.gatewayDetail : $r('app.string.device_detail_camera'),
      state: state,
      color: color
    };
  }

  private formatRa(raHours: number): string {
    const normalized: number = ((raHours % 24) + 24) % 24;
    const totalSeconds: number = Math.round(normalized * 3600.0);
    const hours: number = Math.floor(totalSeconds / 3600) % 24;
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    return `${this.pad2(hours)}h ${this.pad2(minutes)}m ${this.pad2(seconds)}s`;
  }

  private formatDec(decDegrees: number): string {
    const sign: string = decDegrees >= 0 ? '+' : '-';
    const absolute: number = Math.abs(decDegrees);
    const degrees: number = Math.floor(absolute);
    const minutes: number = Math.floor((absolute - degrees) * 60.0);
    const seconds: number = Math.round((((absolute - degrees) * 60.0) - minutes) * 60.0);
    return `${sign}${degrees.toString()}° ${this.pad2(minutes)}′ ${this.pad2(seconds)}″`;
  }

  private formatUpdatedAt(timestampMs: number): string {
    const date: Date = new Date(timestampMs);
    return `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}:${this.pad2(date.getSeconds())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }

  private harmonyRuntimeDescription(): string {
    const snapshot: HarmonyFeatureSnapshot | undefined = this.harmonyFeatures;
    if (snapshot === undefined) {
      return '正在读取系统能力';
    }
    return `API ${snapshot.runtimeApiLevel} · ${snapshot.osFullName}`;
  }

  private harmonyCapabilityText(capability: HarmonyFeatureCapability): ResourceStr {
    if (capability.state === HarmonyCapabilityState.AVAILABLE) {
      return $r('app.string.harmony_status_available');
    }
    if (capability.state === HarmonyCapabilityState.RUNTIME_PROBE_REQUIRED) {
      return capability.reason === HarmonyCapabilityReason.LIVE_VIEW_RIGHT_AND_SWITCH_REQUIRED ?
        $r('app.string.harmony_status_right_probe') :
        $r('app.string.harmony_status_device_probe');
    }
    if (capability.state === HarmonyCapabilityState.BUILD_NOT_CONFIGURED) {
      return $r('app.string.harmony_status_not_configured');
    }
    if (capability.state === HarmonyCapabilityState.API_LEVEL_TOO_LOW) {
      return $r('app.string.harmony_status_api_too_low');
    }
    return $r('app.string.harmony_status_unsupported');
  }

  private harmonyCapabilityColor(capability: HarmonyFeatureCapability): ResourceColor {
    if (capability.state === HarmonyCapabilityState.AVAILABLE) {
      return $r('app.color.app_success');
    }
    if (capability.state === HarmonyCapabilityState.RUNTIME_PROBE_REQUIRED) {
      return $r('app.color.app_warning');
    }
    return $r('app.color.app_text_tertiary');
  }

  private simulationActive(): boolean {
    return this.runMode === ObservationRunMode.SIMULATION;
  }
}

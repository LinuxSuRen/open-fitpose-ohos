import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { CameraController } from '../camera/CameraController';
import { PoseSocket, WsState } from '../net/PoseSocket';
import { Keypoint, PoseResult, SocketEvent } from '../model/Protocol';
import { Tips } from '../util/Tips';

const DOMAIN = 0x0803;
const TAG = 'fitpose.Index';

const STATE_TEXT: Record<string, string> = {
  'idle': '未连接',
  'connecting': '连接中…',
  'open': '已连接',
  'backoff': '重连中…',
};

/** COCO 17 点骨架连线（下标对，见服务端 docs/protocol.md）。 */
const EDGES: number[][] = [
  [5, 6], [5, 7], [7, 9], [6, 8], [8, 10],
  [5, 11], [6, 12], [11, 12],
  [11, 13], [13, 15], [12, 14], [14, 16],
];

const SCORE_GATE = 0.3;

@Entry
@Component
struct Index {
  @State statusText: string = '未连接';
  @State connectButtonText: string = '连接';
  @State tipsText: string = '';
  @State squatCount: number = 0;
  @State pushupCount: number = 0;
  @State jackCount: number = 0;
  @State serverUrl: string = 'ws://192.168.1.10:8080/api/v1/ws/pose';
  @State token: string = '';
  @State cameraHint: string = '正在申请相机权限…';
  private keypoints: Keypoint[] = [];

  private xComponentController: XComponentController = new XComponentController();
  private canvasCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private camera: CameraController | null = null;
  private socket: PoseSocket = new PoseSocket(
    (ev: SocketEvent) => {
      this.onSocketEvent(ev);
    },
    (s: WsState) => {
      this.onSocketState(s);
    },
  );

  aboutToAppear(): void {
    this.requestCamera();
  }

  aboutToDisappear(): void {
    this.socket.disconnect();
    this.camera?.stop();
  }

  private requestCamera(): void {
    const ctx = this.getUIAbilityContext();    const atManager = abilityAccessCtrl.createAtManager();
    const perms: Array<Permissions> = ['ohos.permission.CAMERA'];
    atManager.requestPermissionsFromUser(ctx, perms).then((result) => {
      const status = result.authResults[0];
      if (status === 0) {
        this.cameraHint = '';
      } else {
        this.cameraHint = '无法访问摄像头，请在系统设置中授权后重试';
      }
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'request camera permission failed: %{public}s', err.message);
      this.cameraHint = '相机权限申请失败';
    });
  }

  private getUIAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  build() {
    Column() {
      // 顶栏：标题 + 连接状态
      Row() {
        Text('FitPose').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E8EDF4')
        Blank()
        Text(this.statusText).fontSize(12).fontColor('#8A97A8')
      }
      .width('100%')
      .padding(12)

      // 预览 + 骨架叠加
      Stack() {
        XComponent({
          id: 'fitpose_preview',
          type: XComponentType.SURFACE,
          controller: this.xComponentController,
        })
          .onLoad(() => {
            const surfaceId = this.xComponentController.getXComponentSurfaceId();
            const rect = this.xComponentController.getXComponentSurfaceRect();
            const ctx = this.getUIAbilityContext();
            this.camera = new CameraController(
              ctx,
              (b64: string) => {
                this.socket.sendFrame(b64);
              },
              (msg: string) => {
                this.cameraHint = msg;
              },
            );
            this.camera.init(surfaceId, rect.surfaceWidth, rect.surfaceHeight).catch((err: Error) => {
              hilog.error(DOMAIN, TAG, 'camera init failed: %{public}s', err.message);
              this.cameraHint = `相机初始化失败：${err.message}`;
            });
          })
          .width('100%')
          .height('100%')
        Canvas(this.canvasCtx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.redrawOverlay();
          })
        if (this.cameraHint.length > 0) {
          Text(this.cameraHint).fontSize(14).fontColor('#8A97A8')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#05070A')

      // 计数行
      Row() {
        Column() {
          Text(`${this.squatCount}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#4FC3F7')
          Text('深蹲').fontSize(12).fontColor('#8A97A8')
        }.layoutWeight(1)
        Column() {
          Text(`${this.pushupCount}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#4FC3F7')
          Text('俯卧撑').fontSize(12).fontColor('#8A97A8')
        }.layoutWeight(1)
        Column() {
          Text(`${this.jackCount}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#4FC3F7')
          Text('开合跳').fontSize(12).fontColor('#8A97A8')
        }.layoutWeight(1)
      }
      .width('100%')
      .padding(12)

      // 姿态提示
      Text(this.tipsText)
        .fontSize(13)
        .fontColor('#FFB74D')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .minLines(1)

      // 连接配置
      Column() {
        TextInput({ text: this.serverUrl, placeholder: '服务地址 ws://IP:8080/api/v1/ws/pose' })
          .fontSize(13)
          .fontColor('#E8EDF4')
          .placeholderColor('#5A6778')
          .onChange((v: string) => {
            this.serverUrl = v;
          })
        TextInput({ text: this.token, placeholder: '访问令牌（可选）' })
          .fontSize(13)
          .fontColor('#E8EDF4')
          .placeholderColor('#5A6778')
          .type(InputType.Password)
          .onChange((v: string) => {
            this.token = v;
          })
        Button(this.connectButtonText)
          .width('100%')
          .margin({ top: 8 })
          .backgroundColor('#4FC3F7')
          .fontColor('#06222E')
          .onClick(() => {
            this.toggleConnect();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#10141A')
  }

  // ---- 连接 ----

  private toggleConnect(): void {
    if (this.connectButtonText === '断开') {
      this.socket.disconnect();
      return;
    }
    if (this.serverUrl.length === 0) {
      this.statusText = '请输入服务地址';
      return;
    }
    this.socket.connect(this.serverUrl, this.token);
  }

  private onSocketState(s: WsState): void {
    this.statusText = STATE_TEXT[s];
    this.connectButtonText = (s === 'open' || s === 'connecting') ? '断开' : '连接';
    if (s === 'idle') {
      this.keypoints = [];
      this.redrawOverlay();
    }
  }

  private onSocketEvent(ev: SocketEvent): void {
    if (ev.kind === 'welcome') {
      this.statusText = `已连接（${ev.provider ?? ''}）`;
      return;
    }
    if (ev.kind === 'error') {
      this.tipsText = Tips.errorText(ev.code ?? '');
      return;
    }
    if (ev.kind === 'pose' && ev.result !== undefined) {
      this.renderPose(ev.result);
    }
  }

  private renderPose(result: PoseResult): void {
    this.keypoints = result.keypoints;
    this.tipsText = Tips.format(result.tips);
    this.redrawOverlay();
    const an = result.analysis;
    if (an !== null && an !== undefined) {
      this.squatCount = an.squat.count;
      this.pushupCount = an.pushup.count;
      this.jackCount = an.jumpingJack.count;
    }
  }

  // ---- 骨架绘制 ----

  private redrawOverlay(): void {
    const ctx = this.canvasCtx;
    const w = ctx.width;
    const h = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    if (this.keypoints.length === 0) {
      return;
    }
    ctx.strokeStyle = '#E64FC3F7';
    ctx.lineWidth = 4;
    for (const edge of EDGES) {
      const a = this.keypoints[edge[0]];
      const b = this.keypoints[edge[1]];
      if (a === undefined || b === undefined) {
        continue;
      }
      if (a.score < SCORE_GATE || b.score < SCORE_GATE) {
        continue;
      }
      ctx.beginPath();
      ctx.moveTo(a.x * w, a.y * h);
      ctx.lineTo(b.x * w, b.y * h);
      ctx.stroke();
    }
    ctx.fillStyle = '#F081C784';
    for (const kp of this.keypoints) {
      if (kp.score < SCORE_GATE) {
        continue;
      }
      ctx.beginPath();
      ctx.arc(kp.x * w, kp.y * h, 5, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}

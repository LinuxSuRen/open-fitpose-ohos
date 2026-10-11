import camera from '@ohos.multimedia.camera';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';

const DOMAIN = 0x0803;
const TAG = 'fitpose.Camera';

/** 拍照采集间隔（毫秒）。当前实现基于拍照流，速率受限于拍照管线。 */
export const CAPTURE_INTERVAL_MS = 600;

/**
 * 相机控制器：XComponent 预览 + 周期拍照取帧。
 *
 * 说明：ArkTS 侧暂无法直接读取预览 YUV 流（需 C++ NativeImage），
 * v1 采用拍照流周期取帧，帧率有限；预览帧直读列入路线图。
 */
export class CameraController {
  private context: common.UIAbilityContext;
  private onFrame: (jpegBase64: string) => void;
  private onError: (msg: string) => void;

  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private receiver: image.ImageReceiver | null = null;
  private captureTimer: number = -1;
  private busy: boolean = false;

  constructor(
    context: common.UIAbilityContext,
    onFrame: (jpegBase64: string) => void,
    onError: (msg: string) => void,
  ) {
    this.context = context;
    this.onFrame = onFrame;
    this.onError = onError;
  }

  /** 初始化相机会话：preview 绑定 XComponent surface，photo 绑定 ImageReceiver。 */
  async init(surfaceId: string, surfaceWidth: number, surfaceHeight: number): Promise<void> {
    const manager = camera.getCameraManager(this.context);
    const devices = manager.getSupportedCameras();
    if (devices.length === 0) {
      this.onError('未找到可用摄像头');
      return;
    }

    this.cameraInput = manager.createCameraInput(devices[0]);
    await this.cameraInput.open();

    const capability = manager.getSupportedOutputCapability(devices[0]);
    const previewProfile = this.pickPreviewProfile(capability.previewProfiles, surfaceWidth, surfaceHeight);
    const photoProfile = this.pickPhotoProfile(capability.photoProfiles);
    if (previewProfile === null || photoProfile === null) {
      this.onError('相机不支持所需输出规格');
      return;
    }

    this.previewOutput = manager.createPreviewOutput(previewProfile, surfaceId);

    this.receiver = image.createImageReceiver(
      photoProfile.size.width, photoProfile.size.height, image.ImageFormat.JPEG, 8);
    const photoSurfaceId = await this.receiver.getReceivingSurfaceId();
    this.photoOutput = manager.createPhotoOutput(photoProfile, photoSurfaceId);
    this.receiver.on('imageArrival', () => {
      this.readLatest();
    });

    const session = manager.createSession(camera.SceneMode.NORMAL_PHOTO);
    session.beginConfig();
    session.addInput(this.cameraInput);
    session.addOutput(this.previewOutput);
    session.addOutput(this.photoOutput);
    await session.commitConfig();
    await session.start();

    this.captureTimer = setInterval(() => {
      this.captureOnce();
    }, CAPTURE_INTERVAL_MS);
    hilog.info(DOMAIN, TAG, 'camera session started');
  }

  stop(): void {
    if (this.captureTimer >= 0) {
      clearInterval(this.captureTimer);
      this.captureTimer = -1;
    }
    this.receiver?.off('imageArrival');
    this.photoOutput?.release();
    this.previewOutput?.release();
    this.cameraInput?.close();
    this.photoOutput = null;
    this.previewOutput = null;
    this.cameraInput = null;
    hilog.info(DOMAIN, TAG, 'camera stopped');
  }

  private captureOnce(): void {
    const output = this.photoOutput;
    if (output === null || this.busy) {
      return;
    }
    output.capture().catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'capture failed: %{public}s', err.message);
    });
  }

  private readLatest(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.receiver?.readLatestImage((err, img) => {
      if (err || img === undefined) {
        this.busy = false;
        return;
      }
      img.getComponent(image.ComponentType.JPEG).then((component) => {
        const base64 = this.toBase64(component.buffer);
        img.release();
        this.busy = false;
        if (base64.length > 0) {
          this.onFrame(base64);
        }
      }).catch((_err: Error) => {
        img.release();
        this.busy = false;
      });
    });
  }

  private toBase64(buffer: ArrayBuffer): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(buffer), util.Type.BASIC);
  }

  private pickPreviewProfile(
    profiles: Array<camera.Profile>,
    surfaceWidth: number,
    surfaceHeight: number,
  ): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    let best: camera.Profile = profiles[0];
    let bestScore = Number.MAX_VALUE;
    const surfaceRatio = surfaceWidth / Math.max(1, surfaceHeight);
    for (const p of profiles) {
      const ratio = p.size.width / Math.max(1, p.size.height);
      // 越接近 surface 比例、分辨率越接近 720p 越好
      const score = Math.abs(ratio - surfaceRatio) + Math.abs(p.size.width - 1280) / 10000;
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return best;
  }

  private pickPhotoProfile(profiles: Array<camera.Profile>): camera.Profile | null {
    if (profiles.length === 0) {
      return null;
    }
    // 选分辨率最小的档位，降低上行带宽
    let best: camera.Profile = profiles[0];
    for (const p of profiles) {
      if (p.size.width * p.size.height < best.size.width * best.size.height) {
        best = p;
      }
    }
    return best;
  }
}

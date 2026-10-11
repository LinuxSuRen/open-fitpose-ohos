import webSocket from '@ohos.net.webSocket';
import hilog from '@ohos.hilog';
import {
  SocketEvent,
  parseServerMessage,
  buildHelloMessage,
  buildFrameMessage,
} from '../model/Protocol';

const DOMAIN = 0x0803;
const TAG = 'fitpose.PoseSocket';

export type WsState = 'idle' | 'connecting' | 'open' | 'backoff';

/**
 * FitPose WebSocket 客户端：
 * - 指数退避自动重连（1s 起步、上限 8s）
 * - 未连接期间只保留最新一帧（服务端按最新帧处理，不积压）
 */
export class PoseSocket {
  private ws: webSocket.WebSocket | null = null;
  private url: string = '';
  private token: string = '';
  private wanted: boolean = false;
  private retry: number = 0;
  private seq: number = 0;
  private reconnectTimer: number = -1;
  private pendingFrame: string | null = null;
  private onEvent: (e: SocketEvent) => void;
  private onState: (s: WsState) => void;

  constructor(onEvent: (e: SocketEvent) => void, onState: (s: WsState) => void) {
    this.onEvent = onEvent;
    this.onState = onState;
  }

  connect(url: string, token: string): void {
    this.url = url;
    this.token = token;
    this.wanted = true;
    this.retry = 0;
    this.open();
  }

  disconnect(): void {
    this.wanted = false;
    this.cancelReconnect();
    this.closeSocket();
    this.onState('idle');
  }

  /** 发送一帧 base64 JPEG；未连接时仅缓存最新一帧。 */
  sendFrame(jpegBase64: string): void {
    const ws = this.ws;
    if (ws === null) {
      this.pendingFrame = jpegBase64;
      return;
    }
    this.pendingFrame = null;
    this.seq += 1;
    ws.send(buildFrameMessage(this.seq, jpegBase64), (err) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'send frame failed');
      }
    });
  }

  private open(): void {
    if (!this.wanted) {
      return;
    }
    this.onState('connecting');
    this.closeSocket();

    const ws = webSocket.createWebSocket();
    this.ws = ws;

    ws.on('open', () => {
      this.retry = 0;
      this.onState('open');
      ws.send(buildHelloMessage(), () => {
      });
      if (this.pendingFrame !== null) {
        this.sendFrame(this.pendingFrame);
      }
    });

    ws.on('message', (_err, value) => {
      if (typeof value !== 'string') {
        return;
      }
      const event = parseServerMessage(value);
      if (event !== null) {
        this.onEvent(event);
      }
    });

    ws.on('close', () => {
      this.scheduleReconnect();
    });

    ws.on('error', (_err) => {
      hilog.warn(DOMAIN, TAG, 'ws error');
    });

    const fullUrl = this.token.length > 0
      ? `${this.url}${this.url.includes('?') ? '&' : '?'}token=${this.token}`
      : this.url;
    const header: Record<string, string> = {};
    if (this.token.length > 0) {
      header['Authorization'] = `Bearer ${this.token}`;
    }
    const options: webSocket.WebSocketRequestOptions = { header: header };
    ws.connect(fullUrl, options).catch((_err: Error) => {
      hilog.warn(DOMAIN, TAG, 'connect failed');
      this.scheduleReconnect();
    });
  }

  private scheduleReconnect(): void {
    this.ws = null;
    if (!this.wanted) {
      return;
    }
    this.cancelReconnect();
    const delay = Math.min(1000 * Math.pow(2, this.retry), 8000);
    this.retry += 1;
    this.onState('backoff');
    this.reconnectTimer = setTimeout(() => {
      this.open();
    }, delay);
  }

  private cancelReconnect(): void {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private closeSocket(): void {
    const ws = this.ws;
    if (ws !== null) {
      ws.off('open');
      ws.off('message');
      ws.off('close');
      ws.off('error');
      ws.close();
      this.ws = null;
    }
  }
}
